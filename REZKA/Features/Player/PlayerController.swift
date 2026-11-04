import AVFoundation
import Foundation
import Observation
import os

/// Plays one title in the player window: picks the stream and quality, shows WebVTT subtitles,
/// resumes where the viewer stopped, moves on to the next episode and syncs the position with the site.
/// Same rules as the Apple TV player.
@MainActor
@Observable
final class PlayerController {
    /// Offered both in the toolbar and in the player's own menu (» in its controls).
    static let speedOptions: [Float] = [0.5, 1, 1.25, 1.5, 1.75, 2]

    private(set) var request: PlaybackRequest
    let player = AVPlayer()
    private(set) var stream: StreamInfo?
    private(set) var quality: StreamQuality?
    private(set) var subtitle: SubtitleTrack?
    private(set) var subtitleText: String?
    private(set) var isLoading = true
    private(set) var speed: Float = 1
    var errorMessage: String?
    /// The sum of the latest run of ← → jumps, shown over the video for a moment; nil hides it.
    private(set) var seekHint: Double?
    /// Playback has waited for data for more than a moment, e.g. after a jump to a part not loaded yet.
    private(set) var isBuffering = false
    /// How much of the video has loaded, in whole percent; nil until its length is known.
    /// The system controls don't show it.
    private(set) var loadedPercent: Int?
    /// What is left of the episode or film at the current speed, and the clock time it ends; nil until
    /// the video is ready, and for a teaser clip.
    private(set) var timeLeft: TimeLeft?
    /// The picture froze while the sound went on, and the video is loading again from where it stopped.
    private(set) var isRecovering = false
    /// The frozen picture, kept over the video while it loads again: the reload shows the film's first
    /// frame for a moment before it jumps back to where the picture stopped. Nil otherwise.
    private(set) var recoveryStill: CGImage?
    /// A few reloads in a row didn't bring the picture back: the note over the video says so until
    /// closed, another quality or the next episode.
    private(set) var showsRecoveryNote = false

    struct TimeLeft: Equatable {
        /// Real minutes left, rounded up: the last seconds still show one minute.
        let minutes: Int
        /// To the minute, so the toolbar changes once a minute, not with every tick.
        let endsAt: Date

        /// "12 мин", "1 ч 50 мин".
        var leftText: String {
            Duration.seconds(minutes * 60)
                .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(AppLanguage.locale))
        }

        /// "23:40", or "11:40 PM" in English.
        var endText: String {
            endsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.locale))
        }
    }
    /// Closes the window; set by the view.
    var onClose: (() -> Void)?

    @ObservationIgnored private var cues: [SubtitleCue] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var loadedObservation: NSKeyValueObservation?
    @ObservationIgnored private var waitingObservation: NSKeyValueObservation?
    @ObservationIgnored private var speedObservation: NSKeyValueObservation?
    @ObservationIgnored private var bufferingTask: Task<Void, Never>?
    /// Moves «закончится в» on while paused, when the time observer is quiet.
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var subtitleTask: Task<Void, Never>?
    @ObservationIgnored private var remoteSaveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var usingFallback = false
    @ObservationIgnored private var lastLocalSave = Date.distantPast
    @ObservationIgnored private var lastRemoteSave = Date()
    @ObservationIgnored private var isStarted = false
    /// Where a jump in flight is headed, so quick presses add up instead of starting from the old time.
    @ObservationIgnored private var seekTarget: Double?
    @ObservationIgnored private var seekHintTask: Task<Void, Never>?
    @ObservationIgnored private var isTornDown = false
    @ObservationIgnored private let watchdog = FrozenVideoWatchdog()
    /// When the picture was last brought back, to stop after a few tries in a row.
    @ObservationIgnored private var recoveries: [Date] = []
    /// Checks that found a new frame since the latest reload. A few in a row mean the picture runs again;
    /// one alone may be the last frame before the place the reload went to, shown after the jump.
    @ObservationIgnored private var framesSinceReload = 0
    /// No more reloads until another quality or episode: the server is too slow for now.
    @ObservationIgnored private var recoveryGaveUp = false
    /// Whether the window is on screen. Hidden or minimized, the frames aren't checked: nobody sees a
    /// frozen picture, and the system may not draw any while the sound plays on.
    @ObservationIgnored private var isVideoVisible = true

    private static let log = Logger(subsystem: "com.mrgsdev.hdrezkamac", category: "player")
    /// Tries within this many seconds count as in a row.
    private static let recoveryWindow: TimeInterval = 120
    private static let maxRecoveries = 3
    /// The last tick's position, to count what played since for «Итоги».
    @ObservationIgnored private var lastTickTime: Double?
    /// The achievements have heard that this episode or film played to the end.
    @ObservationIgnored private var finishNoted = false

    init(request: PlaybackRequest) {
        self.request = request
    }

    /// Loads the stream and starts playback; called once the window appears. Not done in `init`:
    /// SwiftUI may build the view, and so a controller, more than once, and every extra one
    /// would play the episode in the background — the sound doubled.
    func start() {
        guard !isStarted, !isTornDown else { return }
        isStarted = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        waitingObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.timeControlChanged() }
            }
        }
        // The player's own menu sets the speed straight on the player; the toolbar has to follow.
        speedObservation = player.observe(\.defaultRate, options: [.new]) { [weak self] player, _ in
            let rate = player.defaultRate
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, rate > 0, rate != self.speed else { return }
                    self.speed = rate
                    self.updateTimeLeft()
                }
            }
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { return }
                self.updateTimeLeft()
            }
        }
        load(startAt: request.startPosition)
        AchievementTracker.shared.noteStart()
    }

    // MARK: Titles

    var episodeLabel: String? {
        guard let seasonId = request.seasonId, let episodeId = request.episodeId else { return nil }
        let season = request.seasons.first { $0.id == seasonId }
        let episode = season?.episodes.first { $0.id == episodeId }
        return [season?.title ?? String(localized: "Сезон \(seasonId)"), episode?.title ?? String(localized: "Серия \(episodeId)"), request.translator.name].joined(separator: " · ")
    }

    /// The episode and dub. How much has loaded is in the toolbar, with the time left.
    var subtitleLine: String {
        episodeLabel ?? request.translator.name
    }

    /// "45 %" until all of the video has loaded; nil once it has.
    var loadedShare: String? {
        guard let loadedPercent, loadedPercent < 100 else { return nil }
        return (Double(loadedPercent) / 100).formatted(.percent.locale(AppLanguage.locale))
    }

    /// «Серия загружена на 45 %», in full for the time-left menu.
    var loadedLine: String? {
        guard let share = loadedShare else { return nil }
        if request.episodeId != nil { return String(localized: "Серия загружена на \(share)") }
        return switch request.kind {
        case .cartoon: String(localized: "Мультфильм загружен на \(share)")
        case .anime: String(localized: "Аниме загружено на \(share)")
        default: String(localized: "Фильм загружен на \(share)")
        }
    }

    // MARK: Loading

    private func load(startAt: Double?) {
        loadTask?.cancel()
        finishNoted = false
        isLoading = true
        timeLeft = nil
        resetRecovery()
        cues = []
        subtitleText = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await RezkaClient.shared.stream(
                    postId: request.postId,
                    translator: request.translator,
                    seasonId: request.seasonId,
                    episodeId: request.episodeId,
                    favs: request.favs
                )
                try Task.checkCancellation()
                guard let quality = QualityPreference.pick(from: stream.qualities, allowPremium: AuthSession.shared.isPremium) else {
                    throw RezkaError.noStreams
                }
                self.stream = stream
                play(quality, at: startAt ?? savedPosition())
                restoreSubtitle()
            } catch is CancellationError {
            } catch {
                isLoading = false
                AuthSession.shared.handle(error)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func play(_ quality: StreamQuality, at position: Double, fallback: Bool = false) {
        self.quality = quality
        usingFallback = fallback
        pendingSeek = position > 1 ? position : nil

        let item = AVPlayerItem(url: fallback ? (quality.fallbackURL ?? quality.url) : quality.url)
        loadedPercent = nil
        watchdog.attach(to: item)
        observe(item)
        player.replaceCurrentItem(with: item)
        player.defaultRate = speed
        player.play()
    }

    private func observe(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.statusChanged(item) }
            }
        }
        loadedObservation = item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateLoaded() }
            }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidFinish() }
        }
    }

    private func statusChanged(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            isLoading = false
            if let pendingSeek {
                self.pendingSeek = nil
                player.seek(to: CMTime(seconds: pendingSeek, preferredTimescale: 600))
            }
            updateTimeLeft()
        case .failed:
            endRecovery()
            if !usingFallback, let quality, quality.fallbackURL != nil {
                play(quality, at: pendingSeek ?? currentPosition, fallback: true)
            } else {
                isLoading = false
                errorMessage = (item.error ?? RezkaError.noStreams).localizedDescription
            }
        default:
            break
        }
    }

    /// All loaded stretches together: after a jump ahead there are several.
    private func updateLoaded() {
        let duration = currentDuration
        guard duration > 0, let item = player.currentItem else { return }
        let seconds = item.loadedTimeRanges.map(\.timeRangeValue.duration.seconds)
            .filter { $0.isFinite && $0 > 0 }
            .reduce(0, +)
        // The last fraction of a second is often never reported as loaded.
        let percent = seconds >= duration - 1 ? 100 : min(Int(seconds / duration * 100), 99)
        if percent != loadedPercent { loadedPercent = percent }
    }

    private func itemDidFinish() {
        guard !isPreviewClip else {
            // A premium-quality teaser ended: keep the episode unwatched.
            onClose?()
            return
        }
        recordProgress(force: true, finished: true)
        if nextEpisode != nil {
            playNext()
        } else {
            onClose?()
        }
    }

    // MARK: Jumps

    /// ← and → in the player: moves by `seconds` within the episode and adds the run up on screen.
    func seek(by seconds: Double) {
        guard player.currentItem?.status == .readyToPlay, pendingSeek == nil else { return }
        watchdog.reset()
        let end = currentDuration > 0 ? currentDuration - 1 : .greatestFiniteMagnitude
        let target = min(max((seekTarget ?? currentPosition) + seconds, 0), end)
        seekTarget = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in
                if self?.seekTarget == target { self?.seekTarget = nil }
            }
        }

        seekHint = (seekHint ?? 0) + seconds
        seekHintTask?.cancel()
        seekHintTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.seekHint = nil
        }
    }

    // MARK: Buffering

    /// Shows the loading badge once playback has waited half a second for data: after a jump to a part
    /// not loaded yet the video otherwise just looks frozen. Shorter waits show nothing.
    private func timeControlChanged() {
        guard !isTornDown else { return }
        // Paused, waiting or started again, possibly after a jump on the timeline: the frames start over.
        watchdog.reset()
        guard player.timeControlStatus == .waitingToPlayAtSpecifiedRate, player.currentItem != nil else {
            bufferingTask?.cancel()
            bufferingTask = nil
            isBuffering = false
            return
        }
        guard bufferingTask == nil else { return }
        bufferingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.isBuffering = true
        }
    }

    // MARK: Menus

    var sortedQualities: [StreamQuality] {
        (stream?.qualities ?? []).sorted { $0.rank > $1.rank }
    }

    func switchQuality(_ option: StreamQuality) {
        guard option != quality else { return }
        resetRecovery()
        QualityPreference.current = option.label
        play(option, at: currentPosition)
    }

    /// `defaultRate` is what `play()` resumes at, so the speed survives pausing and the next episode.
    func setSpeed(_ rate: Float) {
        speed = rate
        player.defaultRate = rate
        if player.rate != 0 { player.rate = rate }
        updateTimeLeft()
    }

    static func speedLabel(_ rate: Float) -> String {
        rate == 1 ? String(localized: "Обычная") : rate.formatted(.number.locale(AppLanguage.locale)) + "×"
    }

    private func restoreSubtitle() {
        let track = SubtitlePreference.current.flatMap { label in stream?.subtitles.first { $0.label == label } }
        selectSubtitle(track, remember: false)
    }

    func selectSubtitle(_ track: SubtitleTrack?, remember: Bool = true) {
        subtitle = track
        cues = []
        subtitleText = nil
        if remember { SubtitlePreference.current = track?.label }

        subtitleTask?.cancel()
        guard let track else { return }
        subtitleTask = Task { [weak self] in
            guard let text = try? await RezkaClient.shared.downloadText(track.url) else { return }
            let cues = WebVTT.parse(text)
            guard let self, !Task.isCancelled, subtitle == track else { return }
            self.cues = cues
        }
    }

    // MARK: Progress

    private var currentPosition: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    private var currentDuration: Double {
        let seconds = player.currentItem?.duration.seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    private func tick(_ time: Double) {
        if !cues.isEmpty {
            let text = WebVTT.text(at: time, in: cues)
            if text != subtitleText { subtitleText = text }
        }
        if Date().timeIntervalSince(lastLocalSave) > 5 { recordProgress() }
        countWatched(upTo: time)
        updateTimeLeft()
        watchFrames()
    }

    // MARK: Frozen picture

    /// Checks the frames while the video plays; see `FrozenVideoWatchdog`. Paused, waiting for data,
    /// mid-jump or loading, there is nothing to check and the count starts over.
    private func watchFrames() {
        guard FrozenVideoRecovery.isEnabled, isVideoVisible, !recoveryGaveUp, !isTornDown, !isLoading, !isPreviewClip,
              pendingSeek == nil, seekTarget == nil,
              player.timeControlStatus == .playing, player.currentItem?.status == .readyToPlay
        else {
            watchdog.reset()
            return
        }
        switch watchdog.check() {
        case .frame:
            // Back once frames keep coming, wherever the reload landed: the jump may have gone to the
            // keyframe a few seconds before the place asked for.
            if isRecovering {
                framesSinceReload += 1
                if framesSinceReload >= 3 { endRecovery() }
            }
        case .waiting:
            break
        case let .frozen(stoppedAt):
            recover(stoppedAt: stoppedAt)
        }
    }

    /// The picture froze while the sound went on: loads the video again, in this window, from where the
    /// picture stopped, so the seconds heard over the still are seen too. Speed, dub and subtitles stay.
    /// The second try in a row goes to the other server when the site gave two; after three within two
    /// minutes it stops and says so, rather than reloading over and over.
    private func recover(stoppedAt: Double?) {
        guard let quality else { return }
        let position = stoppedAt ?? max(currentPosition - FrozenVideoWatchdog.threshold * Double(speed), 0)
        // Some files end their picture a moment before the sound: nothing to bring back there.
        guard currentDuration - position > FrozenVideoWatchdog.threshold * Double(speed) + 2 else { return }
        let now = Date()
        recoveries = recoveries.filter { now.timeIntervalSince($0) < Self.recoveryWindow } + [now]
        guard recoveries.count <= Self.maxRecoveries else {
            Self.log.error("Picture frozen at \(position, privacy: .public) s again after \(Self.maxRecoveries) reloads; giving up")
            endRecovery()
            recoveryGaveUp = true
            showsRecoveryNote = true
            return
        }
        let fallback = recoveries.count >= 2 && quality.fallbackURL != nil ? !usingFallback : usingFallback
        Self.log.notice("Picture frozen at \(position, privacy: .public) s; reloading, try \(self.recoveries.count), \(fallback ? "fallback" : "main", privacy: .public) server")
        // The same still for every try in a row: it is what the viewer last saw.
        if recoveryStill == nil { recoveryStill = watchdog.stillImage() }
        isRecovering = true
        framesSinceReload = 0
        play(quality, at: position, fallback: fallback)
    }

    /// From the player view, as the window comes on screen or leaves it. Back on screen, the count starts
    /// over: the frames may take a moment.
    func setVideoVisible(_ visible: Bool) {
        guard visible != isVideoVisible else { return }
        isVideoVisible = visible
        watchdog.reset()
    }

    /// The note over the video after reloads didn't help, closed by its button. No reloads start again
    /// until another quality or episode.
    func dismissRecoveryNote() {
        showsRecoveryNote = false
    }

    private func endRecovery() {
        isRecovering = false
        recoveryStill = nil
    }

    private func resetRecovery() {
        endRecovery()
        showsRecoveryNote = false
        recoveryGaveUp = false
        recoveries = []
    }

    /// The rest of the video divided by the speed: at 2× an hour left takes half an hour. Paused, it is
    /// what is left once playback resumes, so the end moves on with the clock.
    private func updateTimeLeft() {
        // Kept as it was while the video reloads: the new item has no length yet.
        guard !isRecovering else { return }
        let duration = currentDuration
        // Mid-jump, from where the arrows are taking it rather than where the picture still is.
        let position = seekTarget ?? pendingSeek ?? currentPosition
        let left = max(duration - position, 0) / Double(max(speed, 0.1))
        guard !isTornDown, !isLoading, duration > 0, !isPreviewClip, left >= 1 else {
            if timeLeft != nil { timeLeft = nil }
            return
        }
        let end = Date().addingTimeInterval(left).timeIntervalSinceReferenceDate
        let value = TimeLeft(
            minutes: Int((left / 60).rounded(.up)),
            endsAt: Date(timeIntervalSinceReferenceDate: (end / 60).rounded(.down) * 60)
        )
        if value != timeLeft { timeLeft = value }
    }

    /// Adds the video that played since the last tick; a jump or a pause adds nothing.
    private func countWatched(upTo time: Double) {
        defer { lastTickTime = time }
        guard let last = lastTickTime, player.timeControlStatus == .playing, pendingSeek == nil, !isPreviewClip else { return }
        let played = time - last
        guard played > 0, played < 1.5 * Double(max(player.rate, 1)) else { return }
        WatchStats.shared.add(played, postId: request.postId, title: WatchStats.Title(
            name: request.title,
            kind: request.kind ?? .unknown,
            genres: request.genres ?? WatchStats.shared.titles[request.postId]?.genres ?? [],
            posterURL: request.posterURL,
            path: request.path ?? WatchStats.shared.titles[request.postId]?.path,
            countries: request.countries ?? WatchStats.shared.titles[request.postId]?.countries,
            year: request.year ?? WatchStats.shared.titles[request.postId]?.year
        ), dub: request.translator.name)
    }

    private func savedPosition() -> Double {
        guard let entry = WatchProgressStore.shared.entry(postId: request.postId, seasonId: request.seasonId, episodeId: request.episodeId),
              !entry.isFinished, entry.position > 15 else { return 0 }
        return max(entry.position - 3, 0)
    }

    /// Clips under 3 minutes are teasers (e.g. premium quality on a free account), not the episode.
    private var isPreviewClip: Bool {
        currentDuration > 0 && currentDuration < 180
    }

    private func recordProgress(force: Bool = false, finished: Bool = false) {
        let duration = currentDuration
        guard duration > 0, pendingSeek == nil, !isPreviewClip else { return }
        let position = finished ? duration : currentPosition
        guard position > 0 else { return }
        lastLocalSave = Date()

        WatchProgressStore.shared.update(.init(
            postId: request.postId,
            translatorId: request.translator.id,
            seasonId: request.seasonId,
            episodeId: request.episodeId,
            position: position,
            duration: duration,
            updatedAt: Date()
        ), persistNow: force)
        // As far as «finished» goes for saved positions: the credits need not run out.
        if position >= duration * 0.92, !finishNoted {
            finishNoted = true
            AchievementTracker.shared.noteFinished(request)
        }
        AchievementTracker.shared.noteWatching()

        if force || Date().timeIntervalSince(lastRemoteSave) > 60 {
            lastRemoteSave = Date()
            let request = request
            remoteSaveTask = Task {
                await RezkaClient.shared.saveProgress(
                    postId: request.postId,
                    translatorId: request.translator.id,
                    seasonId: request.seasonId,
                    episodeId: request.episodeId,
                    position: position,
                    duration: duration
                )
            }
        }
    }

    // MARK: Episodes

    var nextEpisode: Episode? {
        guard let seasonId = request.seasonId, let episodeId = request.episodeId else { return nil }
        let all = request.seasons.flatMap(\.episodes)
        guard let index = all.firstIndex(where: { $0.seasonId == seasonId && $0.id == episodeId }), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    func playNext() {
        guard let next = nextEpisode else { return }
        recordProgress(force: true)
        request.seasonId = next.seasonId
        request.episodeId = next.id
        player.pause()
        load(startAt: nil)
    }

    // MARK: Teardown

    /// Saves the final position and stops playback when the window closes.
    func finish() {
        guard !isTornDown else { return }
        isTornDown = true
        recordProgress(force: true)
        // Once the final position reaches the site, let "continue watching" refresh.
        let save = remoteSaveTask
        Task {
            await save?.value
            NotificationCenter.default.post(name: .watchHistoryChanged, object: nil)
        }
        loadTask?.cancel()
        subtitleTask?.cancel()
        seekHintTask?.cancel()
        bufferingTask?.cancel()
        clockTask?.cancel()
        waitingObservation = nil
        speedObservation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        statusObservation = nil
        loadedObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
