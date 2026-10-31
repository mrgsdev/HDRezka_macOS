import Foundation
import Observation

/// What has been watched in REZKA on this Mac, for «Итоги»: seconds of video by day and title, and
/// what each title is. Counted in the player as the video plays, so it covers only this app here;
/// at 2× an hour of watching counts as two hours of film. Kept in the app's own settings only.
@MainActor
@Observable
final class WatchStats {
    struct Title: Codable, Hashable {
        var name: String
        var kind: MediaKind
        var genres: [String]
        var posterURL: URL?
        /// The title page on the site, so «Итоги» can open it.
        var path: String?
    }

    static let shared = WatchStats()

    /// Seconds watched, by day ("2026-10-31") and then by title id.
    private(set) var days: [String: [String: Double]]
    private(set) var titles: [String: Title]

    private static let daysKey = "watchStats.days.v2"
    private static let titlesKey = "watchStats.titles.v2"
    /// The first version also took in this Mac's saved positions, which held test plays too.
    private static let droppedKeys = ["watchStats.days.v1", "watchStats.titles.v1", "watchStats.backfilled"]
    private var lastPersist = Date.distantPast

    private init() {
        let defaults = UserDefaults.standard
        Self.droppedKeys.forEach(defaults.removeObject(forKey:))
        days = defaults.data(forKey: Self.daysKey).flatMap { try? JSONDecoder().decode([String: [String: Double]].self, from: $0) } ?? [:]
        titles = defaults.data(forKey: Self.titlesKey).flatMap { try? JSONDecoder().decode([String: Title].self, from: $0) } ?? [:]
    }

    /// Adds what just played. The title's details come with it when the player knows them.
    func add(_ seconds: Double, postId: String, title: Title?, on date: Date = Date()) {
        guard seconds > 0 else { return }
        days[Self.dayKey(date), default: [:]][postId, default: 0] += seconds
        if let title { titles[postId] = title }
        if Date().timeIntervalSince(lastPersist) > 30 { persist() }
    }

    func persist() {
        lastPersist = Date()
        if let data = try? JSONEncoder().encode(days) { UserDefaults.standard.set(data, forKey: Self.daysKey) }
        if let data = try? JSONEncoder().encode(titles) { UserDefaults.standard.set(data, forKey: Self.titlesKey) }
    }

    // MARK: Days

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(_ date: Date) -> String { dayFormat.string(from: date) }
    static func date(ofDay key: String) -> Date? { dayFormat.date(from: key) }
}
