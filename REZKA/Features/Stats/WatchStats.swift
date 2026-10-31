import Foundation
import Observation

/// What has been watched in REZKA on this Mac, for «Итоги»: seconds of video by day and title, and
/// what each title is. Counted in the player as the video plays, so it covers only this app here;
/// at 2× an hour of watching counts as two hours of film.
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

    private static let daysKey = "watchStats.days.v1"
    private static let titlesKey = "watchStats.titles.v1"
    private static let backfilledKey = "watchStats.backfilled"
    private var lastPersist = Date.distantPast

    private init() {
        let defaults = UserDefaults.standard
        days = defaults.data(forKey: Self.daysKey).flatMap { try? JSONDecoder().decode([String: [String: Double]].self, from: $0) } ?? [:]
        titles = defaults.data(forKey: Self.titlesKey).flatMap { try? JSONDecoder().decode([String: Title].self, from: $0) } ?? [:]
        if !defaults.bool(forKey: Self.backfilledKey) {
            backfill()
            defaults.set(true, forKey: Self.backfilledKey)
        }
    }

    /// Adds what just played. The title's details come with it when the player knows them.
    func add(_ seconds: Double, postId: String, title: Title?, on date: Date = Date()) {
        guard seconds > 0 else { return }
        days[Self.dayKey(date), default: [:]][postId, default: 0] += seconds
        if let title { titles[postId] = title }
        if Date().timeIntervalSince(lastPersist) > 30 { persist() }
    }

    /// Names a title counted before its details were known, e.g. one from this Mac's earlier history.
    func remember(_ details: MediaDetails, kind: MediaKind) {
        guard titles[details.postId] == nil, days.values.contains(where: { $0[details.postId] != nil }) else { return }
        titles[details.postId] = Title(
            name: details.title,
            kind: kind,
            genres: details.info("Жанр")?.components(separatedBy: ", ") ?? [],
            posterURL: details.posterURL,
            path: details.path
        )
        persist()
    }

    /// Looks for titles counted without details in the account's «Продолжить просмотр», whose links
    /// carry the title id, and reads their pages.
    func resolveUnknown() async {
        let unknown = Set(days.values.flatMap(\.keys)).subtracting(titles.keys)
        guard !unknown.isEmpty, let history = try? await RezkaClient.shared.continueWatching() else { return }
        for item in history {
            guard let id = Self.postId(inPath: item.path), unknown.contains(id),
                  let details = try? await RezkaClient.shared.details(path: item.path) else { continue }
            remember(details, kind: details.isSeries ? .series : .film)
        }
    }

    /// `/series/thriller/47752-medlennye-loshadi-2022.html` → `47752`.
    static func postId(inPath path: String) -> String? {
        path.split(separator: "/").last?.firstMatch(of: /^(\d+)-/).map { String($0.1) }
    }

    func persist() {
        lastPersist = Date()
        if let data = try? JSONEncoder().encode(days) { UserDefaults.standard.set(data, forKey: Self.daysKey) }
        if let data = try? JSONEncoder().encode(titles) { UserDefaults.standard.set(data, forKey: Self.titlesKey) }
    }

    /// Before counting began, this Mac already kept how far each film and episode got and when:
    /// that much goes in once, on the day it was last played.
    private func backfill() {
        for entry in WatchProgressStore.shared.allEntries where entry.duration > 0 {
            let seconds = entry.isFinished ? entry.duration : min(entry.position, entry.duration)
            days[Self.dayKey(entry.updatedAt), default: [:]][entry.postId, default: 0] += seconds
        }
        persist()
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
