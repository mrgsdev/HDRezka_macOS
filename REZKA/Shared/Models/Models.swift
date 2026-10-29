import Foundation

enum MediaKind: String, Codable, Hashable {
    case film, series, cartoon, anime, unknown

    init(cssClasses: [String]) {
        if cssClasses.contains("films") { self = .film }
        else if cssClasses.contains("series") { self = .series }
        else if cssClasses.contains("cartoons") { self = .cartoon }
        else if cssClasses.contains("animation") { self = .anime }
        else { self = .unknown }
    }

    var title: String? {
        switch self {
        case .film: String(localized: "Фильм")
        case .series: String(localized: "Сериал")
        case .cartoon: String(localized: "Мультфильм")
        case .anime: String(localized: "Аниме")
        case .unknown: nil
        }
    }
}

/// An item of any listing (catalog, search, bookmarks, continue watching).
struct MediaItem: Identifiable, Hashable, Codable {
    /// Site-relative path of the details page, e.g. `/films/drama/12345-name-2020.html`.
    let path: String
    let title: String
    let subtitle: String
    let posterURL: URL?
    let kind: MediaKind
    /// Short badge from the cover, e.g. "2 сезон, 8 серия".
    let badge: String?
    /// Id of the entry in the site's "continue watching" list, used to remove it.
    var continueId: String? = nil

    var id: String { path }
}

/// A list of titles on the site: a genre or studio inside a section, a collection, best-of or announcements.
struct Listing: Identifiable, Hashable {
    let title: String
    /// Site path without the page part, e.g. `films/drama/` or `collections/834-filmy-netflix/`.
    let path: String
    /// Whether the site's sort options ("Популярные", "В ожидании"…) apply to it.
    var isSortable = true

    var id: String { path }

    static let announcements = Listing(title: String(localized: "Анонсы"), path: "announce/", isSortable: false)
}

/// What the site's top menu offers inside a section.
struct SectionMenu: Hashable {
    let genres: [Listing]
    /// Studio collections the menu shows as logos (Netflix, HBO…).
    let studios: [Listing]
}

struct Franchise: Hashable {
    /// E.g. «Все части фильма "Пила"».
    let title: String
    let parts: [FranchisePart]
}

struct FranchisePart: Identifiable, Hashable {
    /// The part's number in the franchise, counted from the first.
    let number: String
    let title: String
    /// E.g. "2024 год".
    let year: String
    /// Kinopoisk rating, nil when the site shows a dash.
    let rating: String?
    /// Site path of its details page; nil for the title being viewed.
    let path: String?

    var id: String { "\(number)|\(title)" }
    var isCurrent: Bool { path == nil }
}

struct ScheduleSeason: Identifiable, Hashable {
    /// E.g. "2 сезон".
    let title: String
    let episodes: [ScheduleEpisode]

    var id: String { title }
}

struct ScheduleEpisode: Identifiable, Hashable {
    /// The site's id of the row, also used to toggle "просмотрено".
    let id: String
    /// E.g. "10 серия".
    let label: String
    /// Season and episode numbers from "2 сезон 10 серия", to match the player's episode list.
    let seasonNumber: String?
    let episodeNumber: String?
    let title: String
    let originalTitle: String?
    /// Air date as the site writes it, e.g. "26 февраля 2026".
    let date: String
    /// Whether the episode is already on the site.
    let isReleased: Bool
    /// Marked "просмотрено" in the account.
    let isWatched: Bool
}

/// A card on the site's collections page.
struct MediaCollection: Identifiable, Hashable {
    let listing: Listing
    let coverURL: URL?
    /// Number of titles in it, as the card shows.
    let count: Int?

    var id: String { listing.id }
}

struct Page<T> {
    let items: [T]
    let hasMore: Bool
}

struct Translator: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    var isCamrip = "0"
    var isAds = "0"
    var isDirector = "0"
    var isPremium = false
}

struct Episode: Identifiable, Hashable, Codable {
    let id: String
    let seasonId: String
    let title: String
}

struct Season: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let episodes: [Episode]
}

struct InfoRow: Hashable {
    let title: String
    let value: String
}

struct MediaDetails {
    let postId: String
    let path: String
    let title: String
    let originalTitle: String
    let posterURL: URL?
    let description: String
    let info: [InfoRow]
    let favs: String
    let isSeries: Bool
    let translators: [Translator]
    let activeTranslatorId: String?
    /// Seasons embedded in the page for the active translator.
    let seasons: [Season]
    let related: [MediaItem]
    /// The account's bookmark folders; nil when the page offers no bookmarks (logged out).
    let bookmarkFolders: [BookmarkFolder]?
    /// Ids of the folders that hold this title.
    let bookmarkedIn: Set<String>
    /// "Отзывы (N)" on the page; the comments themselves load separately.
    let commentsCount: Int
    /// The collections in the "Из серии" row, e.g. "Сериалы Amazon".
    let collections: [Listing]
    /// "Входит в списки": the site's best-of lists that rank the title.
    let rankings: [RankedListing]
    /// "Режиссер" and "В ролях актеры", with links to their pages.
    let directors: [PersonLink]
    let cast: [PersonLink]
    /// Other films and series of the same franchise, as the site lists them (newest first).
    let franchise: Franchise?
    /// Episode release dates by season, latest season first; empty for films.
    let schedule: [ScheduleSeason]
    /// The site's note for a title that cannot be played yet, e.g. "Ожидаем фильм в хорошем качестве...";
    /// nil when it has something to watch.
    let upcomingStatus: String?
    /// The viewers' rating on the site itself; nil when the page has none.
    let siteRating: SiteRating?
    /// "Не можешь выбрать озвучку?": which dubs viewers pick; nil when the page has no such hint.
    let dubPopularity: DubPopularity?

    func info(_ title: String) -> String? {
        info.first { $0.title.hasPrefix(title) }?.value
    }
}

/// Someone in a title's cast or crew; `path` leads to their page, e.g. `person/3775-gari-oldman/`.
struct PersonLink: Identifiable, Hashable {
    let id: String
    let name: String
    /// nil for a name the site doesn't link to a page.
    let path: String?
    let photoURL: URL?
}

/// A person's page: the info table and their titles, a list per role ("Актер", "Режиссер"…).
struct PersonDetails {
    struct Career: Identifiable {
        let title: String
        /// "В базе 6 фильмов и 13 сериалов".
        let stats: String?
        let items: [MediaItem]

        var id: String { title }
    }

    let name: String
    let originalName: String?
    let photoURL: URL?
    /// "Карьера", "Дата рождения", "Место рождения", "Рост"…
    let info: [InfoRow]
    let careers: [Career]
}

/// A best-of list that ranks a title, e.g. "Лучшие сериалы триллеры 2022 года", 10th place.
struct RankedListing: Identifiable, Hashable {
    let listing: Listing
    let place: Int?

    var id: String { listing.id }
}

/// The share of the site's viewers watching a title in each dub, most popular first.
struct DubPopularity: Hashable {
    struct Entry: Hashable, Identifiable {
        /// Named like `Translator.name`, flag included, so the two can be matched.
        let name: String
        let percent: Double

        var id: String { name }
    }

    /// "Популярность озвучек для данного сериала".
    let title: String
    let entries: [Entry]
    /// The site's footnote on how the numbers are made.
    let note: String
}

/// The site's own rating of a title: the average of its viewers' votes from 1 to 10.
struct SiteRating: Hashable {
    let value: Double
    let votes: Int
    /// The page still offers its 1–10 links: this account has not voted for the title.
    let canVote: Bool
}

struct StreamQuality: Identifiable, Hashable {
    let label: String
    let url: URL
    let fallbackURL: URL?
    /// Premium-only quality: without HDrezka Premium the site serves a ~1 minute teaser instead.
    var isPremium = false

    var id: String { label }

    /// Higher is better; used to pick the default quality.
    var rank: Int {
        let digits = Int(label.prefix { $0.isNumber }) ?? 0
        return digits * 10 + (label.localizedCaseInsensitiveContains("ultra") ? 5 : 0)
    }
}

struct SubtitleTrack: Identifiable, Hashable {
    let label: String
    let url: URL
    let language: String?

    var id: String { label }
}

struct StreamInfo {
    let qualities: [StreamQuality]
    let subtitles: [SubtitleTrack]
    let defaultSubtitle: String?
}

/// A comment under a title. The site's reply tree is flattened in reading order, with `depth` for indentation.
struct Comment: Identifiable, Hashable {
    struct Part: Hashable {
        let text: String
        /// Hidden behind "спойлер" until the viewer asks to see it.
        let isSpoiler: Bool
    }

    let id: String
    let author: String
    let date: String
    let parts: [Part]
    var likes: Int
    /// The account's own like, which the site lets it take back.
    var isLiked: Bool
    /// False on the account's own comments: the site doesn't let them be liked.
    let canLike: Bool
    /// 0 for a comment on the title, 1 and more for replies.
    let depth: Int

    var hasSpoiler: Bool { parts.contains(where: \.isSpoiler) }
}

struct BookmarkFolder: Identifiable, Hashable {
    let id: String
    let name: String
    let count: Int?
}
