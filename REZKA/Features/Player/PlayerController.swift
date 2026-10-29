import AVFoundation
import Foundation
import Observation

/// Plays one title in the player window: picks the stream and quality, shows WebVTT subtitles,
/// resumes where the viewer stopped, moves on to the next episode and syncs the position with the site.
/// Same rules as the Apple TV player.
@MainActor
@Observable
final class PlayerController {
    static let speedOptions: [Float] = [1, 1.25, 1.5, 1.75, 2]

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
    /// Closes the window; set by the view.
    var onClose: (() -> Void)?

    @ObservationIgnored private var cues: [SubtitleCue] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var waitingObservation: NSKeyValueObservation?
    @ObservationIgnored private var bufferingTask: Task<Void, Never>?
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
        load(startAt: request.startPosition)
    }

    // MARK: Titles

    var episodeLabel: String? {
        guard let seasonId = request.seasonId, let episodeId = request.episodeId else { return nil }
        let season = request.seasons.first { $0.id == seasonId }
        let episode = season?.episodes.first { $0.id == episodeId }
        return [season?.title ?? String(localized: "Сезон \(seasonId)"), episode?.title ?? String(localized: "Серия \(episodeId)"), request.translator.name].joined(separator: " · ")
    }

    var subtitleLine: String {
        episodeLabel ?? request.translator.name
    }

    // MARK: Loading

    private func load(startAt: Double?) {
        loadTask?.cancel()
        isLoading = true
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
        case .failed:
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
        QualityPreference.current = option.label
        play(option, at: currentPosition)
    }

    /// `defaultRate` is what `play()` resumes at, so the speed survives pausing and the next episode.
    func setSpeed(_ rate: Float) {
        speed = rate
        player.defaultRate = rate
        if player.rate != 0 { player.rate = rate }
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
        waitingObservation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        statusObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
