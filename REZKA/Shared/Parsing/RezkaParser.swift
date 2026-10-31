import Foundation
import SwiftSoup

/// Turns HDrezka HTML into models. All selectors live here so layout changes are fixed in one place.
enum RezkaParser {
    // MARK: Listings

    static func items(in root: Element, base: URL) throws -> [MediaItem] {
        try root.select(".b-content__inline_item").array().compactMap { try item(from: $0, base: base) }
    }

    static func page(in doc: Document, base: URL) throws -> Page<MediaItem> {
        let container = try doc.select(".b-content__inline_items").first() ?? doc
        let items = try items(in: container, base: base)
        let next = try doc.select(".b-navigation__next").first()
        let hasMore = next?.parent()?.tagName() == "a"
        return Page(items: items, hasMore: hasMore && !items.isEmpty)
    }

    private static func item(from element: Element, base: URL) throws -> MediaItem? {
        let link = try element.select(".b-content__inline_item-link a").first()
        let href = try element.attr("data-url").nonEmpty ?? link?.attr("href") ?? ""
        guard let path = sitePath(href, base: base) else { return nil }

        let cover = try element.select(".b-content__inline_item-cover").first()
        let classes = try cover?.select(".cat").first()?.className().split(separator: " ").map(String.init) ?? []
        let poster = try cover?.select("img").first()?.attr("src")

        return MediaItem(
            path: path,
            title: try link?.text() ?? "",
            subtitle: try element.select(".b-content__inline_item-link div").first()?.text() ?? "",
            posterURL: absoluteURL(poster, base: base),
            kind: MediaKind(cssClasses: classes),
            badge: try cover?.select(".info").first()?.text().nonEmpty
        )
    }

    // MARK: Menu & collections

    /// Genres and studio collections per section from the site's top menu, present on every page.
    static func sectionMenus(in doc: Document) throws -> [CatalogSection: SectionMenu] {
        var menus: [CatalogSection: SectionMenu] = [:]
        for item in try doc.select("#topnav-menu > li.b-topnav__item").array() {
            guard let href = try item.select("a.b-topnav__item-link").first()?.attr("href"),
                  let path = listingPath(href),
                  let section = CatalogSection(rawValue: String(path.dropLast())) else { continue }
            // The "hot" entry on the right is "Лучшие новинки", which the catalog offers as its own sort.
            let genres = try item.select(".b-topnav__sub ul.left a").array().compactMap { link in
                try listingPath(link.attr("href")).map { Listing(title: try link.text(), path: $0) }
            }
            let studios = try item.select(".b-topnav__sub ul.right li:not(.hot) a").array().compactMap { link in
                try listingPath(link.attr("href")).flatMap { path in
                    try link.attr("title").nonEmpty.map { Listing(title: $0, path: path) }
                }
            }
            var seen = Set<String>()
            menus[section] = SectionMenu(genres: genres.filter { seen.insert($0.path).inserted }, studios: studios)
        }
        return menus
    }

    static func collections(in doc: Document, base: URL) throws -> Page<MediaCollection> {
        let items = try doc.select(".b-content__collections_item").array().compactMap { element -> MediaCollection? in
            let href = try element.attr("data-url").nonEmpty ?? element.select("a.title").first()?.attr("href") ?? ""
            guard let path = listingPath(href) else { return nil }
            return MediaCollection(
                listing: Listing(title: try element.select(".title").first()?.text() ?? "", path: path),
                coverURL: absoluteURL(try element.select("img.cover").first()?.attr("src"), base: base),
                count: Int(try element.select(".num").first()?.text() ?? "")
            )
        }
        let next = try doc.select(".b-navigation__next").first()
        return Page(items: items, hasMore: next?.parent()?.tagName() == "a" && !items.isEmpty)
    }

    private static func franchise(in doc: Document, base: URL) throws -> Franchise? {
        let items = try doc.select(".b-post__partcontent_item").array()
        guard !items.isEmpty else { return nil }
        let parts = try items.map { item in
            let href = try item.attr("data-url").nonEmpty ?? item.select(".title a").first()?.attr("href")
            let rating = try item.select(".rating").first()?.text().nonEmpty
            return FranchisePart(
                number: try item.select(".num").first()?.text() ?? "",
                title: try item.select(".title").first()?.text() ?? "",
                year: try item.select(".year").first()?.text() ?? "",
                rating: rating == "—" ? nil : rating,
                path: item.hasClass("current") ? nil : href.flatMap { sitePath($0, base: base) }
            )
        }
        let title = try doc.select(".b-post__franchise_link_title").first()?.text().nonEmpty ?? String(localized: "Все части франшизы")
        return Franchise(title: title, parts: parts)
    }

    /// The "даты выхода серий" tables: the latest season first, then the older ones the site folds away.
    private static func schedule(in doc: Document) throws -> [ScheduleSeason] {
        try doc.select(".b-post__schedule_block").array().compactMap { block in
            let episodes = try block.select("tr").array().compactMap { row -> ScheduleEpisode? in
                // The "загрузить еще серии" row has no .td-1; the hidden rows it reveals are already here.
                guard let number = try row.select(".td-1").first() else { return nil }
                let names = try row.select(".td-2").first()
                let label = try number.text()
                let numbers = label.matches(of: /\d+/).map { String($0.output) }
                return ScheduleEpisode(
                    id: try number.attr("data-id").nonEmpty ?? label,
                    label: numbers.count == 2
                        ? String(localized: "\(numbers[1]) серия")
                        : label.range(of: "сезон ").map { String(label[$0.upperBound...]) } ?? label,
                    seasonNumber: numbers.count == 2 ? numbers[0] : nil,
                    episodeNumber: numbers.count == 2 ? numbers[1] : nil,
                    title: try names?.select("b").first()?.text() ?? "",
                    originalTitle: try names?.select("span").first()?.text().nonEmpty,
                    date: try row.select(".td-4").first()?.text() ?? "",
                    isReleased: try !row.select(".exists-episode").isEmpty(),
                    isWatched: try !row.select(".watch-episode-action.watched").isEmpty()
                )
            }
            guard !episodes.isEmpty else { return nil }
            // "Игры Биста - даты выхода серий 2 сезона" → "2 сезон", like the older blocks are titled.
            let title = try block.select(".b-post__schedule_block_title .title").first()?.text() ?? ""
            let season = title.firstMatch(of: /(\d+) сезона?$/).map { String(localized: "\(String($0.1)) сезон") } ?? title
            return ScheduleSeason(title: season, episodes: episodes)
        }
    }

    /// Links in the details row "Из серии", which point to collections.
    private static func collectionLinks(in doc: Document) throws -> [Listing] {
        try infoRow("Из серии", in: doc)?.select("a").array().compactMap { link in
            try listingPath(link.attr("href")).map { Listing(title: try link.text(), path: $0) }
        } ?? []
    }

    /// The details row "Входит в списки": links to best-of lists, each followed by "(10 место)".
    private static func rankings(in doc: Document) throws -> [RankedListing] {
        try infoRow("Входит в списки", in: doc)?.select("a").array().compactMap { link in
            guard let path = listingPath(try link.attr("href")) else { return nil }
            let place = (link.nextSibling() as? TextNode)?.text().filter(\.isNumber)
            // A ranked list has no "Последние"/"Популярные" of its own.
            return RankedListing(listing: Listing(title: try link.text(), path: path, isSortable: false), place: place.flatMap { Int($0) })
        } ?? []
    }

    /// The people in a details row, "Режиссер" or "В ролях актеры", each with a link and a small photo.
    private static func people(_ title: String, in doc: Document, base: URL) throws -> [PersonLink] {
        try infoRow(title, in: doc)?.select(".person-name-item").array().compactMap { item in
            let link = try item.select("a").first()
            let name = try (link ?? item).text()
            guard !name.isEmpty else { return nil }
            let path = try link.flatMap { listingPath(try $0.attr("href")) }
            return PersonLink(
                id: try item.attr("data-id").nonEmpty ?? path ?? name,
                name: name,
                path: path,
                photoURL: absoluteURL(try item.attr("data-photo"), base: base)
            )
        } ?? []
    }

    /// A person's page: `.t1`/`.t2` names, a photo, the info table, and a `.b-person__career` block per role.
    static func person(in doc: Document, base: URL) throws -> PersonDetails {
        let cover = try doc.select(".b-post__infotable_left .b-sidecover").first()
        let largePhoto = try cover?.select("a").first()?.attr("href")
        let photo = try cover?.select("img").first()?.attr("src")
        let info = try doc.select(".b-post__infotable_right_inner tr").array().compactMap { row -> InfoRow? in
            let cells = try row.select("td").array()
            guard cells.count == 2 else { return nil }
            let title = try cells[0].text().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            let value = try cells[1].text()
            return title.isEmpty || value.isEmpty ? nil : InfoRow(title: title, value: value)
        }
        let careers = try doc.select(".b-person__career").array().compactMap { section -> PersonDetails.Career? in
            let items = try items(in: section, base: base)
            guard !items.isEmpty else { return nil }
            return PersonDetails.Career(
                title: try section.select("h2").first()?.text().nonEmpty ?? String(localized: "Фильмография"),
                stats: try section.select(".b-person__career_stats").first()?.text().nonEmpty,
                items: items
            )
        }
        return PersonDetails(
            name: try doc.select(".b-post__title .t1").first()?.text().nonEmpty ?? doc.select(".b-post__title").text(),
            originalName: try doc.select(".b-post__title .t2").first()?.text().nonEmpty,
            photoURL: absoluteURL(largePhoto?.hasImageExtension == true ? largePhoto : photo, base: base),
            info: info,
            careers: careers
        )
    }

    private static func infoRow(_ title: String, in doc: Document) throws -> Element? {
        try doc.select(".b-post__info tr").array().first { try $0.select("td").first()?.text().hasPrefix(title) == true }
    }

    /// `https://rezka.fi/films/drama/` or `/films/drama/` → `films/drama/`, the form `Listing.path` uses.
    static func listingPath(_ href: String) -> String? {
        guard let components = URLComponents(string: href), components.path.count > 1 else { return nil }
        let path = String(components.path.drop { $0 == "/" })
        return path.hasSuffix("/") ? path : path + "/"
    }

    // MARK: Continue watching

    static func continueWatching(in doc: Document, base: URL) throws -> [MediaItem] {
        try doc.select(".b-videosaves__list_item[id^=videosave]").array().compactMap { row in
            guard let link = try row.select(".td.title a").first(),
                  let path = sitePath(try link.attr("href"), base: base) else { return nil }
            let info = try row.select(".td.info").first()?.text() ?? ""
            let year = try row.select(".td.title small").first()?.text() ?? ""
            let removeId = try row.select(".i-sprt.delete").first()?.attr("data-id").nonEmpty
                ?? row.id().components(separatedBy: "-").last?.nonEmpty
            return MediaItem(
                path: path,
                title: try link.text(),
                subtitle: info.isEmpty ? year : info,
                posterURL: absoluteURL(try link.attr("data-cover_url"), base: base),
                kind: .unknown,
                badge: nil,
                continueId: removeId
            )
        }
    }

    // MARK: Bookmarks

    static func bookmarkFolders(in doc: Document) throws -> [BookmarkFolder] {
        try doc.select(".b-favorites_content__cats_list_item").array().compactMap { element in
            let id = try element.attr("data-cat_id")
            guard !id.isEmpty else { return nil }
            let name = try element.select(".name").first()?.text() ?? element.text()
            let count = try Int(element.select(".num-holder").first()?.text().filter(\.isNumber) ?? "")
            return BookmarkFolder(id: id, name: name, count: count)
        }
    }

    // MARK: Details

    static func details(in doc: Document, path: String, base: URL) throws -> MediaDetails {
        let html = try doc.html()
        let seriesArgs = initArguments(in: html, function: "initCDNSeriesEvents")
        let movieArgs = initArguments(in: html, function: "initCDNMoviesEvents")

        let postId = try [
            doc.select("#post_id").first()?.attr("value"),
            doc.select("[data-post_id]").first()?.attr("data-post_id"),
            (seriesArgs ?? movieArgs)?.first,
            idFromPath(path),
        ].compactMap { $0?.nonEmpty }.first
        guard let postId else { throw RezkaError.parsing("post id") }

        let info = try infoRows(in: doc)
        let hasEpisodeTabs = try !doc.select("#simple-episodes-tabs").isEmpty()
        let isSeries = seriesArgs != nil || hasEpisodeTabs

        var translators = try doc.select("#translators-list .b-translator__item").array().map { element in
            Translator(
                id: try element.attr("data-translator_id"),
                name: try dubName(element.attr("title").nonEmpty ?? element.text(), flag: element.select("img").first()),
                isCamrip: try element.attr("data-camrip").nonEmpty ?? "0",
                isAds: try element.attr("data-ads").nonEmpty ?? "0",
                isDirector: try element.attr("data-director").nonEmpty ?? "0",
                isPremium: element.hasClass("b-prem_translator")
            )
        }.filter { !$0.id.isEmpty }

        let activeTranslatorId = try doc.select("#translators-list .b-translator__item.active").first()?.attr("data-translator_id").nonEmpty
            ?? (seriesArgs ?? movieArgs).flatMap { $0.count > 1 ? $0[1] : nil }

        if translators.isEmpty, let id = activeTranslatorId {
            let name = info.first { $0.title.hasPrefix("В переводе") }?.value ?? String(localized: "По умолчанию")
            var single = Translator(id: id, name: name)
            if let args = movieArgs, args.count >= 5 {
                single.isCamrip = args[2]
                single.isAds = args[3]
                single.isDirector = args[4]
            }
            translators = [single]
        }

        let bookmarks = try bookmarkFolders(onDetails: doc)
        let posterHref = try doc.select(".b-sidecover a").first()?.attr("href")
        let posterSrc = try doc.select(".b-sidecover img").first()?.attr("src")

        return MediaDetails(
            postId: postId,
            path: path,
            title: try doc.select(".b-post__title h1").first()?.text().nonEmpty ?? doc.select(".b-post__title").text(),
            originalTitle: try doc.select(".b-post__origtitle").first()?.text() ?? "",
            posterURL: absoluteURL(posterHref?.hasImageExtension == true ? posterHref : posterSrc, base: base),
            description: try doc.select(".b-post__description_text").first()?.text() ?? "",
            info: info,
            favs: try doc.select("#ctrl_favs").first()?.attr("value") ?? "",
            isSeries: isSeries,
            translators: translators,
            activeTranslatorId: activeTranslatorId,
            seasons: isSeries ? try seasons(in: doc) : [],
            related: try doc.select(".b-sidelist").first().map { try items(in: $0, base: base) } ?? [],
            bookmarkFolders: bookmarks?.folders,
            bookmarkedIn: bookmarks?.checked ?? [],
            commentsCount: try Int(doc.select("#comments-list-button em").first()?.text() ?? "") ?? 0,
            collections: try collectionLinks(in: doc),
            rankings: try rankings(in: doc),
            directors: try people("Режиссер", in: doc, base: base),
            cast: try people("В ролях", in: doc, base: base),
            franchise: try franchise(in: doc, base: base),
            schedule: try schedule(in: doc),
            // Nothing to play: no dub list and no player config, only the site's status and maybe a trailer.
            upcomingStatus: translators.isEmpty
                ? try doc.select(".b-post__go_status").first()?.text().nonEmpty ?? String(localized: "Ожидается")
                : nil,
            restriction: try doc.select(".b-player__restricted__block_message").first()?.ownText()
                .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            siteRating: try siteRating(in: doc),
            dubPopularity: try dubPopularity(in: doc)
        )
    }

    /// A dub's name with its language when a flag marks it, e.g. "HDrezka Studio (Украинский)".
    private static func dubName(_ text: String, flag: Element?) throws -> String {
        var name = text.trimmingCharacters(in: .whitespaces)
        if let language = try flag?.attr("title").nonEmpty ?? flag?.attr("alt").nonEmpty,
           !name.localizedCaseInsensitiveContains(language) {
            name += " (\(language))"
        }
        return name
    }

    /// "Не можешь выбрать озвучку?" next to the dub list: its tooltip is an HTML table of the dubs
    /// with the share of viewers watching each.
    private static func dubPopularity(in doc: Document) throws -> DubPopularity? {
        guard let hint = try doc.select(".b-rgstats__help").first() else { return nil }
        let table = try SwiftSoup.parseBodyFragment(try hint.attr("title"))
        let entries = try table.select(".b-rgstats__list_item .inner").array().compactMap { row -> DubPopularity.Entry? in
            guard let title = try row.select(".title").first(),
                  let percent = Double(try row.select(".count").text()
                    .filter { $0.isNumber || $0 == "," || $0 == "." }
                    .replacingOccurrences(of: ",", with: "."))
            else { return nil }
            return DubPopularity.Entry(name: try dubName(title.text(), flag: title.select("img").first()), percent: percent)
        }
        guard !entries.isEmpty else { return nil }
        return DubPopularity(
            title: try table.select(".b-rgstats__title").first()?.text().nonEmpty ?? String(localized: "Популярность озвучек"),
            entries: entries,
            note: try table.select(".b-rgstats__info").first()?.text() ?? ""
        )
    }

    /// "Никнейм" on the profile settings page: a label followed by a plain `div` with the name.
    static func accountName(in doc: Document) throws -> String? {
        for group in try doc.select(".b-profile_input-group").array()
        where try group.select("label").first()?.text() == "Никнейм" {
            // `select` would match the group itself, which is a `div` too.
            return try group.children().array().first { $0.tagName() == "div" }?.text().nonEmpty
        }
        return nil
    }

    /// "Оцени фильм: ★★★★★ 8.62 (4836)" under the title. The 1–10 links are there only until the account votes.
    private static func siteRating(in doc: Document) throws -> SiteRating? {
        guard let block = try doc.select(".b-post__rating").first(),
              let value = Double(try block.select(".num").first()?.text().replacingOccurrences(of: ",", with: ".") ?? "")
        else { return nil }
        return SiteRating(
            value: value,
            votes: Int(try block.select(".votes span").first()?.text().filter(\.isNumber) ?? "") ?? 0,
            canVote: try !block.select(".b-post__rating_wrapper a[onclick*=rate]").isEmpty()
        )
    }

    /// The account's bookmark folders from a details page and those holding the title;
    /// nil when the page has no bookmark controls (logged out).
    private static func bookmarkFolders(onDetails doc: Document) throws -> (folders: [BookmarkFolder], checked: Set<String>)? {
        guard try doc.select("#user-favorites-holder").first() != nil else { return nil }
        var folders: [BookmarkFolder] = []
        var checked = Set<String>()
        for row in try doc.select("#user-favorites-list .hd-label-row").array() {
            guard let input = try row.select("input").first() else { continue }
            let id = try input.attr("value")
            guard !id.isEmpty else { continue }
            let label = try row.select("label").first()
            let name = try label?.ownText().nonEmpty ?? label?.text() ?? id
            let count = try Int(row.select("small b").first()?.text() ?? "")
            folders.append(BookmarkFolder(id: id, name: name, count: count))
            if input.hasAttr("checked") { checked.insert(id) }
        }
        return (folders, checked)
    }

    // MARK: Comments

    /// Comments from `ajax/get_comments/`. Tree items come in reading order, each before its replies,
    /// so walking them in document order flattens the tree.
    static func comments(in root: Element) throws -> [Comment] {
        try root.select(".comments-tree-item").array().compactMap { item in
            let id = try item.attr("data-id")
            guard !id.isEmpty, let text = try item.select(".text").first() else { return nil }
            let like = try item.select(".b-comment__like_it").first()
            return Comment(
                id: id,
                author: try item.select(".name").first()?.text() ?? "",
                date: try item.select(".date").first()?.text().replacingOccurrences(of: "оставлен ", with: "") ?? "",
                parts: try commentParts(text),
                likes: Int(try like?.attr("data-likes_num") ?? "") ?? 0,
                isLiked: like?.hasClass("disabled") ?? false,
                canLike: like.map { !$0.hasClass("self-disabled") && !$0.hasClass("guest") } ?? false,
                depth: Int(try item.attr("data-indent")) ?? 0
            )
        }
    }

    /// Whether the comments page navigator links to the page after `page`.
    static func hasPage(after page: Int, in navigator: Element) throws -> Bool {
        let next = String(page + 1)
        return try navigator.select("a").array().contains { link in
            try link.text().trimmingCharacters(in: .whitespaces) == next || link.select(".b-navigation__next").first() != nil
        }
    }

    /// Comment text with line breaks kept and `.text_spoiler` blocks marked as spoilers.
    private static func commentParts(_ text: Element) throws -> [Comment.Part] {
        var parts: [Comment.Part] = []
        func append(_ string: String, spoiler: Bool) {
            if let last = parts.last, last.isSpoiler == spoiler {
                parts[parts.count - 1] = Comment.Part(text: last.text + string, isSpoiler: spoiler)
            } else {
                parts.append(Comment.Part(text: string, isSpoiler: spoiler))
            }
        }
        func walk(_ node: Node, spoiler: Bool) throws {
            if let textNode = node as? TextNode {
                append(textNode.getWholeText(), spoiler: spoiler)
            } else if let element = node as? Element {
                // The "спойлер" caption above a hidden block; the app draws its own.
                guard !element.hasClass("title_spoiler") else { return }
                if element.tagName() == "br" {
                    append("\n", spoiler: spoiler)
                    return
                }
                let isBlock = ["div", "p"].contains(element.tagName())
                if isBlock { append("\n", spoiler: spoiler) }
                for child in element.getChildNodes() {
                    try walk(child, spoiler: spoiler || element.hasClass("text_spoiler"))
                }
                if isBlock { append("\n", spoiler: spoiler) }
            }
        }
        for child in text.getChildNodes() {
            try walk(child, spoiler: false)
        }
        let cleaned = parts.map { Comment.Part(text: tidy($0.text), isSpoiler: $0.isSpoiler) }
        return trimEnds(cleaned.filter { !$0.text.isEmpty })
    }

    /// Collapses the page's indentation: spaces within lines, blank runs to one empty line.
    private static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: "[ \t\u{00A0}]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }

    private static func trimEnds(_ parts: [Comment.Part]) -> [Comment.Part] {
        var parts = parts
        if let first = parts.first {
            parts[0] = Comment.Part(text: String(first.text.drop { $0.isWhitespace }), isSpoiler: first.isSpoiler)
        }
        if let last = parts.last {
            let trimmed = String(last.text.reversed().drop { $0.isWhitespace }.reversed())
            parts[parts.count - 1] = Comment.Part(text: trimmed, isSpoiler: last.isSpoiler)
        }
        return parts.filter { !$0.text.isEmpty }
    }

    static func seasons(in root: Element) throws -> [Season] {
        var order: [String] = []
        var episodesBySeason: [String: [Episode]] = [:]
        for element in try root.select(".b-simple_episode__item").array() {
            let seasonId = try element.attr("data-season_id")
            let episodeId = try element.attr("data-episode_id")
            guard !seasonId.isEmpty, !episodeId.isEmpty else { continue }
            if episodesBySeason[seasonId] == nil { order.append(seasonId) }
            // The site's usual "Серия 3" follows the interface language; a name of its own stays.
            let text = try element.text()
            let title = text.isEmpty || text == "Серия \(episodeId)" ? String(localized: "Серия \(episodeId)") : text
            episodesBySeason[seasonId, default: []].append(Episode(id: episodeId, seasonId: seasonId, title: title))
        }

        var titles: [String: String] = [:]
        var seasonOrder: [String] = []
        for element in try root.select(".b-simple_season__item").array() {
            let id = try element.attr("data-tab_id")
            guard !id.isEmpty else { continue }
            titles[id] = try element.text()
            seasonOrder.append(id)
        }
        if seasonOrder.isEmpty { seasonOrder = order }

        return seasonOrder.compactMap { id in
            guard let episodes = episodesBySeason[id], !episodes.isEmpty else { return nil }
            let title = titles[id].flatMap { $0 == "Сезон \(id)" ? nil : $0 } ?? String(localized: "Сезон \(id)")
            return Season(id: id, title: title, episodes: episodes)
        }
    }

    private static func infoRows(in doc: Document) throws -> [InfoRow] {
        var rows: [InfoRow] = []
        for row in try doc.select(".b-post__info tr").array() {
            let cells = try row.select("td")
            if cells.size() == 2 {
                let title = try cells.get(0).text().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                let value = try cells.get(1).text()
                if !title.isEmpty, !value.isEmpty { rows.append(InfoRow(title: title, value: value)) }
            } else if let holder = try row.select(".persons-list-holder").first() {
                let names = try holder.select(".person-name-item").array().map { try $0.text() }.filter { !$0.isEmpty }
                if !names.isEmpty {
                    rows.append(InfoRow(title: "В ролях", value: names.prefix(12).joined(separator: ", ")))
                }
            }
        }
        return rows
    }

    /// Arguments of `sof.tv.initCDNSeriesEvents(postId, translatorId, ...)` up to the JSON config.
    static func initArguments(in html: String, function: String) -> [String]? {
        guard let start = html.range(of: function + "(") else { return nil }
        let tail = html[start.upperBound...].prefix { $0 != "{" && $0 != ")" }
        let args = tail.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }
        return args.isEmpty ? nil : args
    }

    // MARK: Helpers

    static func sitePath(_ href: String, base: URL) -> String? {
        guard !href.isEmpty, let url = URL(string: href, relativeTo: base) else { return nil }
        let path = url.path
        return path.isEmpty || path == "/" ? nil : path
    }

    static func absoluteURL(_ string: String?, base: URL) -> URL? {
        guard let string = string?.nonEmpty else { return nil }
        if string.hasPrefix("//") { return URL(string: "https:" + string) }
        return URL(string: string, relativeTo: base)?.absoluteURL
    }

    /// `/films/drama/12345-name-2020.html` → `12345`, the site's post id.
    static func idFromPath(_ path: String) -> String? {
        let last = path.split(separator: "/").last ?? ""
        let digits = last.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    fileprivate var hasImageExtension: Bool {
        let lower = lowercased()
        return [".jpg", ".jpeg", ".png", ".webp"].contains { lower.hasSuffix($0) }
    }
}
