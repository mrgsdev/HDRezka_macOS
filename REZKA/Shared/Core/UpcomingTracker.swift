import AppKit
import WidgetKit

/// Keeps the "Скоро выйдет" widget current. The widget can't reach the site, so the app looks up the
/// air dates of the series in "Продолжить просмотр" and leaves it a ready list in the shared folder.
/// Runs at launch, when the app comes forward and every few hours while it is open.
@MainActor
final class UpcomingTracker {
    static let shared = UpcomingTracker()

    /// The most recent series of "Продолжить просмотр" that are looked at; the list keeps far more.
    private static let seriesLimit = 20
    /// How many rows the widget gets. It shows a few and counts the rest as "+N", so the list must be whole:
    /// cut short, reminders went missing and the count came out too low.
    private static let itemLimit = 60
    private static let refreshInterval: TimeInterval = 3 * 3600
    /// A series page is fetched again after this long...
    private static let scheduleMaxAge: TimeInterval = 6 * 3600
    /// ...or sooner while an episode is due and the site doesn't have it yet.
    private static let dueScheduleMaxAge: TimeInterval = 3600
    /// An episode counts as new for this many days after it airs.
    private static let releasedDays = 3
    /// An episode the site is late with is shown for this many days after its air date.
    private static let lateDays = 7
    /// How often the page of a title in "Напомнить о выходе" is looked at until it comes out.
    private static let reminderMaxAge: TimeInterval = 3 * 3600
    private static let cacheKey = "upcoming.schedules.v2"
    /// Leaves the first seconds after launch to the home screen's own requests.
    private static let launchDelay: Duration = .seconds(20)

    private struct Schedule: Codable {
        struct Episode: Codable {
            let season: String?
            let episode: String?
            let airDay: String
            let isReleased: Bool
            let isWatched: Bool
        }

        let postId: String
        /// The title page's own poster: larger than the cover in "Продолжить просмотр".
        let posterURL: URL?
        let fetchedAt: Date
        let episodes: [Episode]
    }

    private var schedules: [String: Schedule]
    private var lastRun: Date?
    /// True for the first seconds after launch, when the app coming forward must not start a look yet.
    private var isWaitingForLaunch = true
    private var running: Task<Void, Never>?
    private var timer: Timer?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode([String: Schedule].self, from: data) {
            schedules = decoded
        } else {
            schedules = [:]
        }
    }

    /// Called once at launch: the first look waits a little, then repeats while the app is open.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
            Task { @MainActor in UpcomingTracker.shared.refreshIfDue() }
        }
        Task {
            try? await Task.sleep(for: Self.launchDelay)
            isWaitingForLaunch = false
            refreshIfDue()
        }
    }

    /// Looks again when the last look is old enough; otherwise only redraws the list, so an episode
    /// just watched stops showing as new.
    func refreshIfDue() {
        guard !isWaitingForLaunch else { return }
        if let lastRun, Date().timeIntervalSince(lastRun) < Self.refreshInterval {
            publish()
        } else {
            refresh()
        }
    }

    /// Looks at "Продолжить просмотр" now, e.g. right after signing in.
    func refresh() {
        guard running == nil else { return }
        running = Task {
            await run()
            running = nil
        }
    }

    /// After "Напомнить о выходе" was turned on or off, or a reminded title's page was looked at.
    func remindersChanged() {
        // Before the first look after launch there's nothing to add to; that look puts the titles in.
        guard lastRun != nil else { return }
        publish()
        Task {
            // Only fetches what's missing: deleting is left to the regular look, which knows the whole list.
            // Two passes both deleting raced each other and threw away the posters the other had just saved.
            await savePosters(removingUnused: false)
            publish()
        }
    }

    /// After signing out: the widget says to sign in and keeps nothing of the account.
    func signedOut() {
        running?.cancel()
        running = nil
        lastRun = nil
        schedules = [:]
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        write(UpcomingSnapshot(state: .signedOut, language: AppLanguage.interface, updatedAt: Date(), items: []))
        removePosters(keeping: [])
    }

    // MARK: Looking up

    /// The series being watched, from the last look at "Продолжить просмотр".
    private var series: [MediaItem] = []

    private func run() async {
        guard AuthSession.shared.isLoggedIn else {
            signedOut()
            return
        }
        let items: [MediaItem]
        do {
            items = try await RezkaClient.shared.continueWatching()
        } catch {
            // Offline or the mirror is down: the widget keeps the last list and dates still move on.
            return
        }
        // Films say only the year or the dub here; series say "2 сезон 5 серия".
        series = Array(items.filter { $0.subtitle.contains("серия") || $0.subtitle.contains("сезон") }.prefix(Self.seriesLimit))

        // One page at a time: the site stalls bursts, and this is never urgent.
        for item in series where isStale(schedules[item.path]) {
            guard !Task.isCancelled else { return }
            guard let details = try? await RezkaClient.shared.details(path: item.path) else { continue }
            AgeBook.remember(details, path: item.path)
            schedules[item.path] = Schedule(
                postId: details.postId,
                posterURL: details.posterURL,
                fetchedAt: Date(),
                episodes: details.schedule.flatMap(\.episodes).compactMap { episode in
                    guard let day = SiteDate.day(from: episode.date) else { return nil }
                    return Schedule.Episode(season: episode.seasonNumber, episode: episode.episodeNumber, airDay: day,
                                            isReleased: episode.isReleased, isWatched: episode.isWatched)
                }
            )
        }
        guard !Task.isCancelled else { return }

        // Titles in "Напомнить о выходе": their pages, every few hours until they come out.
        for reminder in ReleaseReminders.shared.reminders.values
        where reminder.availableSince == nil && Date().timeIntervalSince(reminder.checkedAt) > Self.reminderMaxAge {
            guard !Task.isCancelled else { return }
            guard let details = try? await RezkaClient.shared.details(path: reminder.path) else { continue }
            AgeBook.remember(details, path: reminder.path)
            ReleaseReminders.shared.update(details, path: reminder.path)
        }
        guard !Task.isCancelled else { return }
        dropFinishedReminders()

        let kept = Set(series.map(\.path))
        schedules = schedules.filter { kept.contains($0.key) }
        if let data = try? JSONEncoder().encode(schedules) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
        lastRun = Date()
        await savePosters(removingUnused: true)
        publish()
    }

    /// A title that came out leaves after a few days, or as soon as it was played here.
    private func dropFinishedReminders() {
        let finished = ReleaseReminders.shared.reminders.values.filter { reminder in
            guard let since = reminder.availableSince else { return false }
            let played = WatchProgressStore.shared.last(postId: reminder.postId).map { $0.updatedAt > since } ?? false
            return played || Date().timeIntervalSince(since) > Double(Self.releasedDays) * 86400
        }
        ReleaseReminders.shared.drop(finished.map(\.path))
    }

    private func isStale(_ schedule: Schedule?) -> Bool {
        guard let schedule else { return true }
        let today = SiteDate.day(Date())
        let isDue = schedule.episodes.contains { !$0.isReleased && $0.airDay <= today }
        let maxAge = isDue ? Self.dueScheduleMaxAge : Self.scheduleMaxAge
        return Date().timeIntervalSince(schedule.fetchedAt) > maxAge
    }

    // MARK: The widget's list

    /// Picks one row per series and hands the list to the widget.
    private func publish() {
        guard AuthSession.shared.isLoggedIn, lastRun != nil else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let newSince = SiteDate.day(Calendar.current.date(byAdding: .day, value: -Self.releasedDays, to: today) ?? today)
        let lateSince = SiteDate.day(Calendar.current.date(byAdding: .day, value: -Self.lateDays, to: today) ?? today)
        let todayString = SiteDate.day(today)

        var rows: [UpcomingSnapshot.Item] = []
        for item in series where ParentalControl.shared.allows(item) {
            guard let schedule = schedules[item.path] else { continue }
            let episodes = schedule.episodes.sorted { ($0.airDay, Self.number($0.season), Self.number($0.episode)) < ($1.airDay, Self.number($1.season), Self.number($1.episode)) }
            // The earliest of the new ones: the episode to watch next, also when a whole season came out at once.
            let new = episodes.first {
                $0.isReleased && $0.airDay >= newSince && $0.airDay <= todayString && !$0.isWatched && !isPlayed($0, postId: schedule.postId)
            }
            let late = episodes.first { !$0.isReleased && $0.airDay >= lateSince && $0.airDay < todayString }
            let next = episodes.first { !$0.isReleased && $0.airDay >= todayString }
            let pick: (Schedule.Episode, UpcomingSnapshot.Item.Status)? =
                new.map { ($0, .released) } ?? late.map { ($0, .late) } ?? next.map { ($0, .upcoming) }
            guard case let (episode, status)? = pick else { continue }
            rows.append(UpcomingSnapshot.Item(
                path: item.path, title: item.title, season: episode.season, episode: episode.episode,
                airDay: episode.airDay, status: status, poster: posterName(schedule.postId)
            ))
        }

        // Titles from "Напомнить о выходе": by their release date, "Ждём" without one, "Вышел" once out.
        let shown = Set(rows.map(\.path))
        for reminder in ReleaseReminders.shared.reminders.values where !shown.contains(reminder.path) {
            let item = MediaItem(path: reminder.path, title: reminder.title, subtitle: "", posterURL: reminder.posterURL,
                                 kind: reminder.kind, badge: nil)
            guard ParentalControl.shared.allows(item) else { continue }
            let status: UpcomingSnapshot.Item.Status
            let day: String
            if let since = reminder.availableSince {
                (status, day) = (.released, SiteDate.day(since))
            } else if let release = reminder.releaseDay, release >= todayString {
                (status, day) = (.upcoming, release)
            } else {
                (status, day) = (.awaited, reminder.releaseDay ?? "")
            }
            rows.append(UpcomingSnapshot.Item(
                path: reminder.path, title: reminder.title, season: nil, episode: nil,
                airDay: day, status: status, poster: posterName(reminder.postId), kind: reminder.kind.rawValue
            ))
        }

        // New episodes first, newest on top; then the late ones and the coming ones by date; the awaited last.
        let rank: [UpcomingSnapshot.Item.Status: Int] = [.released: 0, .late: 1, .upcoming: 2, .awaited: 3]
        rows.sort {
            if $0.status != $1.status { return rank[$0.status, default: 2] < rank[$1.status, default: 2] }
            switch $0.status {
            case .released: return $0.airDay > $1.airDay
            case .awaited: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            case .late, .upcoming: return $0.airDay < $1.airDay
            }
        }
        write(UpcomingSnapshot(state: .ready, language: AppLanguage.interface, updatedAt: lastRun ?? Date(),
                               items: Array(rows.prefix(Self.itemLimit))))
    }

    /// Whether this episode was started in REZKA on this Mac.
    private func isPlayed(_ episode: Schedule.Episode, postId: String) -> Bool {
        WatchProgressStore.shared.entry(postId: postId, seasonId: episode.season, episodeId: episode.episode) != nil
    }

    private func write(_ snapshot: UpcomingSnapshot) {
        let previous = SharedContainer.readSnapshot()
        // Rewriting the same list would only make the widget redraw for nothing.
        if let previous, previous.state == snapshot.state, previous.items == snapshot.items,
           previous.language == snapshot.language, Date().timeIntervalSince(previous.updatedAt) < 3600 { return }
        try? SharedContainer.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedContainer.upcomingWidgetKind)
    }

    // MARK: Posters

    private func posterName(_ postId: String) -> String? {
        guard let folder = SharedContainer.postersURL else { return nil }
        let name = Self.posterFile(postId)
        return FileManager.default.fileExists(atPath: folder.appending(path: name).path) ? name : nil
    }

    /// Small copies of the posters, made once per title: the widget can't load images from the web.
    /// `removingUnused` also deletes the ones no longer in the list.
    private func savePosters(removingUnused: Bool) async {
        guard let folder = SharedContainer.postersURL else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var names: Set<String> = []
        for item in series {
            guard let schedule = schedules[item.path], let url = schedule.posterURL ?? item.posterURL else { continue }
            let file = folder.appending(path: Self.posterFile(schedule.postId))
            names.insert(file.lastPathComponent)
            await savePoster(from: url, to: file)
        }
        for reminder in ReleaseReminders.shared.reminders.values {
            guard let url = reminder.posterURL else { continue }
            let file = folder.appending(path: Self.posterFile(reminder.postId))
            names.insert(file.lastPathComponent)
            await savePoster(from: url, to: file)
        }
        if removingUnused { removePosters(keeping: names) }
    }

    private func savePoster(from url: URL, to file: URL) async {
        guard !FileManager.default.fileExists(atPath: file.path),
              let response = try? await URLSession.shared.data(from: url),
              let thumbnail = Self.thumbnail(response.0) else { return }
        try? thumbnail.write(to: file, options: .atomic)
    }

    private func removePosters(keeping names: Set<String>) {
        guard let folder = SharedContainer.postersURL,
              let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for file in files where !names.contains(file) {
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
    }

    private static func posterFile(_ postId: String) -> String {
        "\(postId)-510.jpg"
    }

    /// A JPEG at most 510 pixels high: the small widget fills itself with the poster on a Retina screen.
    private static func thumbnail(_ data: Data) -> Data? {
        guard let image = NSImage(data: data), let source = image.representations.first,
              source.pixelsHigh > 0 else { return nil }
        let height = min(510, source.pixelsHigh)
        let width = max(1, source.pixelsWide * height / source.pixelsHigh)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    private static func number(_ text: String?) -> Int {
        text.flatMap(Int.init) ?? 0
    }
}

/// Dates as the site writes them, and calendar days as "2026-11-21".
enum SiteDate {
    private static let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    /// "26 февраля 2026", "12 ноября 2014 года" → "2026-02-26"; nil when the text names no day.
    static func day(from text: String) -> String? {
        guard let match = text.firstMatch(of: /(\d{1,2})\s+(\p{L}+)\s+(\d{4})/),
              let day = Int(match.1), let year = Int(match.3),
              let month = months.firstIndex(of: String(match.2).lowercased()) else { return nil }
        return String(format: "%04d-%02d-%02d", year, month + 1, day)
    }

    /// The calendar day of `date` in the current time zone.
    static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
