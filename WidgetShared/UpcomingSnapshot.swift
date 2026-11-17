import Foundation

/// What the "Скоро выйдет" widget shows. The app writes it into the folder it shares with the widget:
/// the widget never reaches the site itself, it only draws the app's last look.
struct UpcomingSnapshot: Codable {
    enum State: String, Codable {
        case ready
        /// Nobody is signed in, so there is no "Продолжить просмотр" to look at.
        case signedOut
    }

    struct Item: Codable, Hashable, Identifiable {
        enum Status: String, Codable {
            /// On the site in the last few days and not watched yet.
            case released
            /// The air date has passed, but the site has no episode yet.
            case late
            /// Airs today or later.
            case upcoming
            /// A title from "Напомнить о выходе" with no release date, or one already past: the site is
            /// still waiting for it.
            case awaited
        }

        /// Site path of the title's page, e.g. `/series/drama/12345-name-2024.html`.
        let path: String
        let title: String
        let season: String?
        let episode: String?
        /// The site's air date as a calendar day, "2026-11-21"; empty for an awaited title without one.
        let airDay: String
        let status: Status
        /// File name of the poster thumbnail in `SharedContainer.postersURL`.
        let poster: String?
        /// For a whole title from "Напомнить о выходе": "film", "series", "cartoon", "anime" or "show".
        /// nil for an episode of a series being watched.
        var kind: String? = nil

        var id: String { path }
        var isTitle: Bool { kind != nil }

        /// The air day as a date at the start of that day in the current time zone.
        var airDate: Date? {
            let parts = airDay.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
    }

    var state: State
    /// The app's interface language, "ru" or "en", so the widget speaks the same one.
    var language: String
    var updatedAt: Date
    var items: [Item]
}

/// The folder the app and its widget share.
enum SharedContainer {
    static let groupIdentifier = "Y2Y34S7QM3.com.mrgsdev.hdrezkamac"
    static let upcomingWidgetKind = "Upcoming"

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    static var postersURL: URL? {
        url?.appending(path: "Posters", directoryHint: .isDirectory)
    }

    private static var snapshotURL: URL? {
        url?.appending(path: "upcoming.json")
    }

    static func readSnapshot() -> UpcomingSnapshot? {
        guard let snapshotURL, let data = try? Data(contentsOf: snapshotURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UpcomingSnapshot.self, from: data)
    }

    static func write(_ snapshot: UpcomingSnapshot) throws {
        guard let url, let snapshotURL else { return }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
    }
}

/// Links into the app, `hdrezkamac://title?path=…&title=…`: the widget opens a title's page with them.
enum AppLink {
    static let scheme = "hdrezkamac"

    static func title(path: String, title: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "title"
        components.queryItems = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "title", value: title)]
        return components.url
    }

    /// The title a link points to, or nil for anything else.
    static func parseTitle(_ url: URL) -> (path: String, title: String)? {
        guard url.scheme == scheme, url.host() == "title",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let path = items.first(where: { $0.name == "path" })?.value, path.hasPrefix("/")
        else { return nil }
        return (path, items.first(where: { $0.name == "title" })?.value ?? "")
    }
}
