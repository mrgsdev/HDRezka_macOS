import Foundation
import Observation

/// Titles the site is still waiting for that the viewer asked about: "Напомнить о выходе" on the title's
/// page. Kept only on this Mac. `UpcomingTracker` looks at their pages and shows them in the widget, first
/// with the release date or "Ждём", then as "Вышел" for a few days once the page has something to play.
@MainActor
@Observable
final class ReleaseReminders {
    static let shared = ReleaseReminders()

    struct Reminder: Codable, Hashable {
        /// Site path of the title's page, the key everywhere.
        let path: String
        let postId: String
        var title: String
        var kind: MediaKind
        var posterURL: URL?
        /// "2026-12-12" from the page's "Дата выхода", when it names a day.
        var releaseDay: String?
        /// When the page was first seen with something to play.
        var availableSince: Date?
        var checkedAt: Date
    }

    private(set) var reminders: [String: Reminder]

    private static let key = "releaseReminders.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: Reminder].self, from: data) {
            reminders = decoded
        } else {
            reminders = [:]
        }
    }

    func contains(_ path: String) -> Bool {
        reminders[path] != nil
    }

    func add(_ details: MediaDetails, item: MediaItem) {
        let kind = item.kind == .unknown ? (details.isSeries ? .series : .film) : item.kind
        reminders[item.path] = Reminder(path: item.path, postId: details.postId, title: details.title, kind: kind,
                                        posterURL: details.posterURL, releaseDay: nil, availableSince: nil, checkedAt: Date())
        update(details, path: item.path)
        UpcomingTracker.shared.remindersChanged()
    }

    func remove(_ path: String) {
        guard reminders.removeValue(forKey: path) != nil else { return }
        save()
        UpcomingTracker.shared.remindersChanged()
    }

    /// Lets go of titles that came out and were seen; the tracker redraws the widget itself.
    func drop(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        for path in paths { reminders.removeValue(forKey: path) }
        save()
    }

    /// Takes what a fresh look at the page says: the release date, and whether it can be played now.
    func update(_ details: MediaDetails, path: String) {
        guard var reminder = reminders[path] else { return }
        reminder.title = details.title
        reminder.posterURL = details.posterURL ?? reminder.posterURL
        reminder.releaseDay = details.info("Дата выхода").flatMap(SiteDate.day(from:))
        if details.upcomingStatus == nil, reminder.availableSince == nil {
            reminder.availableSince = Date()
        }
        reminder.checkedAt = Date()
        reminders[path] = reminder
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
