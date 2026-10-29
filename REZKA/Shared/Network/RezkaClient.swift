import Foundation
import OSLog
import SwiftSoup

enum CatalogSection: String, CaseIterable, Identifiable, Hashable {
    case films, series, cartoons, animation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .films: String(localized: "Фильмы")
        case .series: String(localized: "Сериалы")
        case .cartoons: String(localized: "Мультфильмы")
        case .animation: String(localized: "Аниме")
        }
    }

    var systemImage: String {
        switch self {
        case .films: "film"
        case .series: "tv"
        case .cartoons: "sparkles.tv"
        case .animation: "wand.and.stars"
        }
    }
}

extension CatalogSection {
    /// `films/best/drama/2026/`: the site's best-rated list, optionally for one genre and year.
    func bestPath(genre: Listing?, year: Int?) -> String {
        var path = "\(rawValue)/best/"
        if let genre = genre?.path.split(separator: "/").last { path += "\(genre)/" }
        if let year { path += "\(year)/" }
        return path
    }
}

enum CatalogFilter: String, CaseIterable, Identifiable, Hashable {
    case last, popular, watching, soon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last: String(localized: "Последние")
        case .popular: String(localized: "Популярные")
        case .watching: String(localized: "Сейчас смотрят")
        case .soon: String(localized: "В ожидании")
        }
    }
}

/// HTTP client for the HDrezka website. Uses the shared cookie jar for the logged-in session.
final class RezkaClient {
    static let shared = RezkaClient()

    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private let session: URLSession

    var baseURL: URL { Mirror.current }

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept-Language": "ru-RU,ru;q=0.9,en;q=0.8",
        ]
        session = URLSession(configuration: configuration)
    }

    // MARK: Account

    var isLoggedIn: Bool {
        let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        func has(_ name: String) -> Bool {
            cookies.contains { $0.name == name && !$0.value.isEmpty && $0.value != "deleted" }
        }
        return has("dle_user_id") && has("dle_password")
    }

    func login(email: String, password: String) async throws {
        let json = try await postJSON("ajax/login/", form: [
            "login_name": email,
            "login_password": password,
            "login_not_save": "0",
        ], timestamped: false)
        guard json["success"] as? Bool == true else {
            if let logged = json["logged_email"] as? String, !logged.isEmpty, isLoggedIn {
                CookieVault.save()
                return
            }
            throw siteError(json, fallback: "Не удалось войти. Проверьте email и пароль.")
        }
        CookieVault.save()
    }

    func logout() async {
        _ = try? await string(url("logout/"))
        CookieVault.clear()
    }

    // MARK: Listings

    func catalog(_ section: CatalogSection?, filter: CatalogFilter = .last, page: Int = 1) async throws -> Page<MediaItem> {
        try await listing(section.map { "\($0.rawValue)/" } ?? "new/", filter: filter, page: page)
    }

    /// Any list of titles by its site path. The first one loaded also fills `SiteMenu` from the page's top menu.
    func listing(_ path: String, filter: CatalogFilter? = nil, page: Int = 1) async throws -> Page<MediaItem> {
        var path = path
        if page > 1 { path += "page/\(page)/" }
        let doc: Document
        do {
            doc = try await document(url(path, query: filter.map { [URLQueryItem(name: "filter", value: $0.rawValue)] } ?? []))
        } catch RezkaError.badStatus(let code) where code == 404 {
            // An empty list comes back as a normal page with status 404, e.g. "Последние" in a collection
            // of titles that are all still "В ожидании".
            return Page(items: [], hasMore: false)
        }
        if await SiteMenu.shared.menus.isEmpty, let menus = try? RezkaParser.sectionMenus(in: doc), !menus.isEmpty {
            await SiteMenu.shared.update(menus)
        }
        return try RezkaParser.page(in: doc, base: baseURL)
    }

    /// Reads the top menu from a section page, for when no listing has brought it yet.
    func sectionMenus() async throws -> [CatalogSection: SectionMenu] {
        try RezkaParser.sectionMenus(in: try await document(url("films/")))
    }

    func collections(page: Int = 1) async throws -> Page<MediaCollection> {
        let doc = try await document(url(page > 1 ? "collections/page/\(page)/" : "collections/"))
        return try RezkaParser.collections(in: doc, base: baseURL)
    }

    /// The home page's "Новые фильмы, сериалы, мультфильмы и аниме" slider: recently added titles and episodes.
    /// `section` 0 mixes all sections; 1, 2, 3 and 82 are films, series, cartoons and anime,
    /// the ids behind the words of the slider's title.
    func newest(section: Int = 0) async throws -> [MediaItem] {
        let html = String(decoding: try await post("engine/ajax/get_newest_slider_content.php", form: ["id": String(section)], timestamped: false), as: UTF8.self)
        if html.contains("loginForm") { throw RezkaError.loginRequired }
        return try RezkaParser.items(in: SwiftSoup.parseBodyFragment(html), base: baseURL)
    }

    func search(_ query: String, page: Int = 1) async throws -> Page<MediaItem> {
        var items = [
            URLQueryItem(name: "do", value: "search"),
            URLQueryItem(name: "subaction", value: "search"),
            URLQueryItem(name: "q", value: query),
        ]
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        let doc = try await document(url("search/", query: items))
        return try RezkaParser.page(in: doc, base: baseURL)
    }

    func continueWatching() async throws -> [MediaItem] {
        let doc = try await document(url("continue/"))
        return try RezkaParser.continueWatching(in: doc, base: baseURL)
    }

    func bookmarkFolders() async throws -> [BookmarkFolder] {
        let doc = try await document(url("favorites/"))
        return try RezkaParser.bookmarkFolders(in: doc)
    }

    func bookmarks(folder: String, page: Int = 1) async throws -> Page<MediaItem> {
        var path = "favorites/\(folder)/"
        if page > 1 { path += "page/\(page)/" }
        let doc = try await document(url(path))
        return try RezkaParser.page(in: doc, base: baseURL)
    }

    // MARK: Bookmark editing

    func createBookmarkFolder(name: String) async throws -> BookmarkFolder {
        let json = try await favorites(["name": name, "action": "add_cat"], fallback: "Не удалось создать папку.")
        let id = (json["id"] as? Int).map(String.init) ?? (json["id"] as? String) ?? ""
        guard !id.isEmpty, id != "0" else { throw RezkaError.parsing(String(localized: "id новой папки")) }
        return BookmarkFolder(id: id, name: (json["name"] as? String)?.nonEmpty ?? name, count: 0)
    }

    func renameBookmarkFolder(id: String, name: String) async throws {
        try await favorites(["cat_id": id, "name": name, "action": "change_cat_name"], fallback: "Не удалось переименовать папку.")
    }

    /// Deletes the folder together with the bookmarks in it.
    func deleteBookmarkFolder(id: String) async throws {
        try await favorites(["cat_id": id, "action": "remove_cat"], fallback: "Не удалось удалить папку.")
    }

    /// The site toggles membership with this action, so call it only for a title not in the folder.
    func addBookmark(postId: String, folder: String) async throws {
        try await favorites(["post_id": postId, "cat_id": folder, "action": "add_post"], fallback: "Не удалось добавить в закладки.")
    }

    func removeBookmark(postId: String, folder: String) async throws {
        try await favorites(["items[]": postId, "cat_id": folder, "action": "remove_items"], fallback: "Не удалось убрать из закладок.")
    }

    func moveBookmark(postId: String, from: String, to: String) async throws {
        try await favorites(["items[]": postId, "from_cat_id": from, "to_cat_id": to, "action": "change_items_cat"],
                            fallback: "Не удалось перенести закладку.")
    }

    @discardableResult
    private func favorites(_ form: [String: String], fallback: String.LocalizationValue) async throws -> [String: Any] {
        let json = try await postJSON("ajax/favorites/", form: form, timestamped: false)
        guard json["success"] as? Bool == true else { throw siteError(json, fallback: fallback) }
        return json
    }

    // MARK: Details & streams

    func details(path: String) async throws -> MediaDetails {
        let doc = try await document(url(path))
        return try RezkaParser.details(in: doc, path: path, base: baseURL)
    }

    /// One page of comments under a title, newest threads first, as the site shows them.
    func comments(postId: String, page: Int = 1) async throws -> Page<Comment> {
        var request = URLRequest(url: url("ajax/get_comments/", query: [
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "news_id", value: postId),
            URLQueryItem(name: "cstart", value: String(page)),
            URLQueryItem(name: "type", value: "0"),
            URLQueryItem(name: "comment_id", value: "0"),
            URLQueryItem(name: "skin", value: "hdrezka"),
        ]))
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        let data = try await perform(request)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if String(decoding: data, as: UTF8.self).contains("loginForm") { throw RezkaError.loginRequired }
            throw RezkaError.parsing(String(localized: "отзывы"))
        }
        let comments = try RezkaParser.comments(in: SwiftSoup.parseBodyFragment(json["comments"] as? String ?? ""))
        let navigator = try SwiftSoup.parseBodyFragment(json["navigation"] as? String ?? "")
        let hasMore = try RezkaParser.hasPage(after: page, in: navigator)
        return Page(items: comments, hasMore: !comments.isEmpty && hasMore)
    }

    func seasons(postId: String, translatorId: String, favs: String) async throws -> [Season] {
        let json = try await postJSON("ajax/get_cdn_series/", form: [
            "id": postId,
            "translator_id": translatorId,
            "favs": favs,
            "action": "get_episodes",
        ])
        guard json["success"] as? Bool == true else { throw siteError(json, fallback: "Не удалось загрузить серии.") }
        let html = [json["seasons"] as? String, json["episodes"] as? String].compactMap { $0 }.joined()
        let fragment = try SwiftSoup.parseBodyFragment(html)
        return try RezkaParser.seasons(in: fragment)
    }

    func stream(postId: String, translator: Translator, seasonId: String?, episodeId: String?, favs: String) async throws -> StreamInfo {
        var form = ["id": postId, "translator_id": translator.id, "favs": favs]
        if let seasonId, let episodeId {
            form["season"] = seasonId
            form["episode"] = episodeId
            form["action"] = "get_stream"
        } else {
            form["is_camrip"] = translator.isCamrip
            form["is_ads"] = translator.isAds
            form["is_director"] = translator.isDirector
            form["action"] = "get_movie"
        }
        let json = try await postJSON("ajax/get_cdn_series/", form: form)
        guard json["success"] as? Bool == true else { throw siteError(json, fallback: "Не удалось получить ссылку на видео.") }
        guard let encoded = json["url"] as? String, !encoded.isEmpty else { throw RezkaError.noStreams }
        guard let decoded = StreamDecoder.decode(encoded) else { throw RezkaError.parsing(String(localized: "ссылка на видео")) }

        let qualities = StreamDecoder.qualities(from: decoded)
        guard !qualities.isEmpty else { throw RezkaError.noStreams }
        return StreamInfo(
            qualities: qualities,
            subtitles: StreamDecoder.subtitles(from: json["subtitle"] as? String, languages: json["subtitle_lns"] as? [String: Any]),
            defaultSubtitle: json["subtitle_def"] as? String
        )
    }

    /// Syncs the playback position with the site's "continue watching" list. Errors are ignored.
    func saveProgress(postId: String, translatorId: String, seasonId: String?, episodeId: String?, position: Double, duration: Double) async {
        // Launch argument `-disableRemoteProgress YES` keeps test playback out of the account history.
        guard isLoggedIn, duration > 0, !UserDefaults.standard.bool(forKey: "disableRemoteProgress") else { return }
        _ = try? await postJSON("ajax/send_save/", form: [
            "post_id": postId,
            "translator_id": translatorId,
            "season": seasonId ?? "0",
            "episode": episodeId ?? "0",
            "current_time": String(Int(position)),
            "duration": String(Int(duration)),
        ])
    }

    /// Flips the "просмотрено" mark of an episode in the site's air-date table; the site only toggles,
    /// so call it for an episode whose current mark is known.
    func toggleEpisodeWatched(id: String) async throws {
        let json = try await postJSON("engine/ajax/schedule_watched.php", form: ["id": id], timestamped: false)
        guard json["success"] as? Bool == true else {
            if json["message"] as? String == "need_auth" { throw RezkaError.loginRequired }
            throw siteError(json, fallback: "Не удалось изменить отметку «просмотрено».")
        }
    }

    /// A person's page with their titles by role; `path` as in `PersonLink`.
    func person(path: String) async throws -> PersonDetails {
        try RezkaParser.person(in: try await document(url(path)), base: baseURL)
    }

    /// The account's nickname, from the profile settings page.
    func accountName() async throws -> String? {
        try RezkaParser.accountName(in: try await document(url("settings/")))
    }

    /// Votes for a title from 1 to 10, as the stars on a details page do, and returns the new average.
    /// The site takes one vote per account.
    func rate(postId: String, value: Int) async throws -> SiteRating {
        var request = URLRequest(url: url("engine/ajax/rating.php", query: [
            URLQueryItem(name: "news_id", value: postId),
            URLQueryItem(name: "go_rate", value: String(value)),
            URLQueryItem(name: "skin", value: "hdrezka"),
        ]))
        // The vote is a GET, so keep it out of the cache and never resend it.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        let data = try await perform(request, retryingTimeout: false)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if String(decoding: data, as: UTF8.self).contains("loginForm") { throw RezkaError.loginRequired }
            throw RezkaError.parsing(String(localized: "оценка"))
        }
        guard json["success"] as? Bool == true else {
            throw siteError(json, fallback: "Сайт не принял оценку. Возможно, вы уже оценивали этот тайтл.")
        }
        // Numbers come back as strings or as numbers.
        let field = { (key: String) in (json[key] as? NSNumber)?.stringValue ?? json[key] as? String ?? "" }
        return SiteRating(
            value: Double(field("num").replacingOccurrences(of: ",", with: ".")) ?? 0,
            votes: Int(field("votes").filter(\.isNumber)) ?? 0,
            canVote: false
        )
    }

    /// Puts the account's like on a comment, or takes it back if it is there: the site toggles it.
    /// Returns the new number of likes and whether the comment is liked now.
    func toggleCommentLike(id: String) async throws -> (likes: Int, isLiked: Bool) {
        var request = URLRequest(url: url("engine/ajax/comments_like.php", query: [URLQueryItem(name: "id", value: id)]))
        // A GET that changes state, like the vote: never from the cache, never resent.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        let data = try await perform(request, retryingTimeout: false)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if String(decoding: data, as: UTF8.self).contains("loginForm") { throw RezkaError.loginRequired }
            throw RezkaError.parsing(String(localized: "лайк"))
        }
        guard json["success"] as? Bool == true, let likes = (json["count"] as? NSNumber)?.intValue else {
            throw siteError(json, fallback: "Сайт не принял лайк.")
        }
        // "plus" for a like put, "minus" for one taken back.
        return (likes, json["type"] as? String != "minus")
    }

    /// Removes an entry from the site's "continue watching" list.
    func removeFromContinue(id: String) async throws {
        let json = try await postJSON("engine/ajax/cdn_saves_remove.php", form: ["id": id], timestamped: false)
        guard json["success"] as? Bool == true else {
            throw siteError(json, fallback: "Не удалось убрать из «Продолжить просмотр».")
        }
    }

    func downloadText(_ url: URL) async throws -> String {
        try await string(url)
    }

    // MARK: Transport

    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    private func document(_ url: URL) async throws -> Document {
        let html = try await string(url)
        let doc = try SwiftSoup.parse(html, baseURL.absoluteString)
        let isLoginWall = try doc.select("#loginForm").first() != nil && doc.select(".b-content__main, #main").isEmpty()
        if try isLoginWall || doc.title().contains("Вход на HDrezka") {
            throw RezkaError.loginRequired
        }
        // Premium accounts show the remaining days in the header.
        let isPremium = try !doc.select(".b-tophead-premuser").isEmpty()
        await MainActor.run { AuthSession.shared.updatePremium(isPremium) }
        return doc
    }

    private func string(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        return String(decoding: try await perform(request), as: UTF8.self)
    }

    /// Sends the request through the concurrency gate, retrying a GET once after a timeout unless
    /// `retryingTimeout` is off. The site stalls bursts of parallel requests, so at most `gate.limit` run at a time.
    private func perform(_ request: URLRequest, retryingTimeout: Bool = true) async throws -> Data {
        await gate.acquire()
        do {
            let data: Data
            do {
                data = try await attempt(request)
            } catch let error as URLError where retryingTimeout && (request.httpMethod ?? "GET") == "GET" && [.timedOut, .networkConnectionLost].contains(error.code) {
                data = try await attempt(request)
            }
            await gate.release()
            return data
        } catch {
            await gate.release()
            throw error
        }
    }

    /// One request, logging path, status, size and timing (never cookies or bodies).
    private func attempt(_ request: URLRequest) async throws -> Data {
        let started = Date()
        let label = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        func elapsed() -> String { String(format: "%.1fs", Date().timeIntervalSince(started)) }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            Self.log.notice("\(label, privacy: .public) -> \(status) \(data.count / 1024)KB \(elapsed(), privacy: .public)")
            #if DEBUG
            Self.dump(data, for: request)
            #endif
            try validate(response)
            return data
        } catch {
            Self.log.error("\(label, privacy: .public) failed after \(elapsed(), privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private let gate = RequestGate(limit: 3)
    private static let log = Logger(subsystem: "com.mrgsdev.hdrezkamac", category: "http")

    #if DEBUG
    /// With launch argument `-dumpHTTP YES`, saves response bodies to Caches/http-debug
    /// so parsing can be checked against real pages.
    private static func dump(_ data: Data, for request: URLRequest) {
        guard UserDefaults.standard.bool(forKey: "dumpHTTP"), let url = request.url, !url.path.contains("login") else { return }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "http-debug")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = String((url.path + "_" + (url.query() ?? "")).map { $0.isLetter || $0.isNumber ? $0 : "_" }.prefix(80))
        let stamp = Int(Date().timeIntervalSince1970 * 1000) % 10_000_000
        try? data.write(to: directory.appending(path: "\(stamp)-\(name).txt"))
    }
    #endif

    private func post(_ path: String, form: [String: String], timestamped: Bool = true) async throws -> Data {
        let query = timestamped ? [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970 * 1000)))] : []
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = Data(Self.formEncode(form).utf8)
        return try await perform(request)
    }

    private func postJSON(_ path: String, form: [String: String], timestamped: Bool = true) async throws -> [String: Any] {
        let data = try await post(path, form: form, timestamped: timestamped)
        guard let json = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? [String: Any] else {
            if String(decoding: data, as: UTF8.self).contains("loginForm") { throw RezkaError.loginRequired }
            throw RezkaError.parsing(String(localized: "JSON \(path)"))
        }
        return json
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw RezkaError.loginRequired }
        guard (200..<400).contains(http.statusCode) else { throw RezkaError.badStatus(http.statusCode) }
    }

    /// The site's own message (Russian), or `fallback` in the interface language.
    private func siteError(_ json: [String: Any], fallback: String.LocalizationValue) -> RezkaError {
        let message = (json["message"] as? String)?
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let message, message.localizedCaseInsensitiveContains("авториз") { return .loginRequired }
        return .site(message?.nonEmpty ?? String(localized: fallback))
    }

    private static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        func encode(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        }
        return form.map { key, value in "\(encode(key))=\(encode(value))" }.joined(separator: "&")
    }
}

extension Notification.Name {
    /// Posted when playback progress may have changed the site's "continue watching" list.
    static let watchHistoryChanged = Notification.Name("watchHistoryChanged")
    /// Posted when bookmarks were changed outside the bookmarks screen, e.g. on a details page.
    static let bookmarksChanged = Notification.Name("bookmarksChanged")
}
