import Foundation
import Observation

@MainActor
@Observable
final class DetailsModel {
    enum State {
        case loading
        case loaded(MediaDetails)
        case failed(Error)
    }

    let item: MediaItem
    private(set) var state: State = .loading
    private(set) var translator: Translator?
    private(set) var seasons: [Season] = []
    var selectedSeasonId: String?
    /// Every dub's seasons by translator id, filled in the background for the dub menu.
    private(set) var seasonsByTranslator: [String: [Season]] = [:]
    private(set) var isLoadingEpisodes = false
    private(set) var episodesError: Error?
    /// The account's bookmark folders; nil hides the bookmark button (logged out).
    private(set) var bookmarkFolders: [BookmarkFolder]?
    private(set) var bookmarkedIn: Set<String> = []
    /// Shown in a "Не получилось" alert: a failed bookmark, watched-mark change, vote or like.
    var actionError: String?
    /// Schedule ids of the episodes marked "просмотрено" in the account.
    private(set) var watchedEpisodes: Set<String> = []
    private(set) var comments: [Comment] = []
    private(set) var hasMoreComments = false
    private(set) var isLoadingComments = false
    private(set) var commentsError: Error?
    private var commentsPage = 0
    /// Comments whose like is on its way to the site.
    private(set) var likingComments: Set<String> = []
    /// The site's rating of the title; changes once the account votes.
    private(set) var siteRating: SiteRating?
    /// The vote sent from this Mac, if any: after voting the site no longer says which one it was.
    private(set) var myRating: Int?
    private(set) var isRating = false

    init(item: MediaItem) {
        self.item = item
    }

    var details: MediaDetails? {
        if case let .loaded(details) = state { details } else { nil }
    }

    var selectedSeason: Season? {
        seasons.first { $0.id == selectedSeasonId } ?? seasons.first
    }

    func loadIfNeeded() async {
        if details == nil { await load() }
    }

    func load() async {
        state = .loading
        do {
            let details = try await RezkaClient.shared.details(path: item.path)
            let last = WatchProgressStore.shared.last(postId: details.postId)
            // Without Premium, premium dubs play only a teaser, so default to a free one.
            let playable = AuthSession.shared.isPremium ? details.translators : details.translators.filter { !$0.isPremium }
            let pool = playable.isEmpty ? details.translators : playable
            let chosen = pool.first { $0.id == last?.translatorId }
                ?? pool.first { $0.id == details.activeTranslatorId }
                ?? pool.first
            translator = chosen
            bookmarkFolders = details.bookmarkFolders
            bookmarkedIn = details.bookmarkedIn
            watchedEpisodes = Set(details.schedule.flatMap(\.episodes).filter(\.isWatched).map(\.id))
            siteRating = details.siteRating
            myRating = Self.myRatings[details.postId]
            state = .loaded(details)

            if details.isSeries, let chosen {
                if let active = details.activeTranslatorId, !details.seasons.isEmpty {
                    seasonsByTranslator[active] = details.seasons
                }
                if chosen.id == details.activeTranslatorId, !details.seasons.isEmpty {
                    apply(details.seasons, postId: details.postId)
                } else {
                    await loadSeasons(details, chosen)
                }
            }
            // After the episodes, so the play button is not kept waiting on the site.
            if details.commentsCount > 0 { await loadMoreComments() }
            if details.isSeries, details.translators.count > 1 { await loadAllSeasons(details) }
        } catch where !error.isCancellation {
            state = .failed(error)
            AuthSession.shared.handle(error)
        } catch {}
    }

    func select(_ translator: Translator) async {
        guard let details, translator != self.translator else { return }
        self.translator = translator
        guard details.isSeries else { return }
        if let seasons = seasonsByTranslator[translator.id] {
            episodesError = nil
            apply(seasons, postId: details.postId)
        } else {
            await loadSeasons(details, translator)
        }
    }

    private func loadSeasons(_ details: MediaDetails, _ translator: Translator) async {
        isLoadingEpisodes = true
        episodesError = nil
        do {
            let seasons = try await RezkaClient.shared.seasons(postId: details.postId, translatorId: translator.id, favs: details.favs)
            seasonsByTranslator[translator.id] = seasons
            guard translator == self.translator else { return }
            apply(seasons, postId: details.postId)
        } catch where !error.isCancellation {
            episodesError = error
            AuthSession.shared.handle(error)
        } catch {}
        isLoadingEpisodes = false
    }

    private func apply(_ seasons: [Season], postId: String) {
        self.seasons = seasons
        let lastSeason = WatchProgressStore.shared.last(postId: postId)?.seasonId
        selectedSeasonId = seasons.first { $0.id == lastSeason }?.id ?? seasons.first?.id
    }

    /// One dub at a time, so the menu hint never holds up the player's requests.
    /// A dub that fails stays unknown: it only loses its hint.
    private func loadAllSeasons(_ details: MediaDetails) async {
        for translator in details.translators where seasonsByTranslator[translator.id] == nil {
            guard !Task.isCancelled else { return }
            guard let seasons = try? await RezkaClient.shared.seasons(postId: details.postId, translatorId: translator.id, favs: details.favs)
            else { continue }
            seasonsByTranslator[translator.id] = seasons
        }
    }

    // MARK: Dub menu

    /// "сезоны 1–12, 15" once the dubs are known to differ; nil while they all look the same.
    func seasonsHint(for translator: Translator) -> String? {
        guard let seasons = seasonsByTranslator[translator.id],
              Set(seasonsByTranslator.values.map { $0.map(\.id) }).count > 1
        else { return nil }
        return Self.seasonsLabel(seasons)
    }

    /// The dubs with and without the season on screen, once every dub's seasons are in
    /// and some lack it; nil otherwise, for one flat list.
    var translatorsBySelectedSeason: (season: Season, with: [Translator], without: [Translator])? {
        guard let details, let season = selectedSeason,
              details.translators.allSatisfy({ seasonsByTranslator[$0.id] != nil })
        else { return nil }
        let has = { (translator: Translator) in
            self.seasonsByTranslator[translator.id]?.contains { $0.id == season.id } == true
        }
        let without = details.translators.filter { !has($0) }
        return without.isEmpty ? nil : (season, details.translators.filter(has), without)
    }

    /// Runs of numbers collapsed: "сезоны 1–12, 15", or "сезон 5" for one.
    private static func seasonsLabel(_ seasons: [Season]) -> String {
        let numbers = seasons.compactMap { Int($0.id) }.sorted()
        guard let first = numbers.first, numbers.count == seasons.count else { return String(localized: "сезонов: \(seasons.count)") }
        if numbers.count == 1 { return String(localized: "сезон \(first)") }
        var runs: [String] = []
        var (start, end) = (first, first)
        for number in numbers.dropFirst() {
            if number == end + 1 {
                end = number
                continue
            }
            runs.append(start == end ? "\(start)" : "\(start)–\(end)")
            (start, end) = (number, number)
        }
        runs.append(start == end ? "\(start)" : "\(start)–\(end)")
        return String(localized: "сезоны \(runs.joined(separator: ", "))")
    }

    // MARK: Comments

    func loadMoreComments() async {
        guard let details, !isLoadingComments, commentsPage == 0 || hasMoreComments else { return }
        isLoadingComments = true
        commentsError = nil
        do {
            let page = try await RezkaClient.shared.comments(postId: details.postId, page: commentsPage + 1)
            // A thread can straddle pages; keep the first copy of a comment.
            let known = Set(comments.map(\.id))
            comments += page.items.filter { !known.contains($0.id) }
            hasMoreComments = page.hasMore
            commentsPage += 1
        } catch where !error.isCancellation {
            commentsError = error
            AuthSession.shared.handle(error)
        } catch {}
        isLoadingComments = false
    }

    /// Likes a comment or takes the like back, then shows the count the site returns.
    func toggleLike(_ comment: Comment) async {
        guard comment.canLike, !likingComments.contains(comment.id) else { return }
        likingComments.insert(comment.id)
        defer { likingComments.remove(comment.id) }
        do {
            let result = try await RezkaClient.shared.toggleCommentLike(id: comment.id)
            guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
            comments[index].likes = result.likes
            comments[index].isLiked = result.isLiked
        } catch {
            report(error)
        }
    }

    // MARK: Watched marks

    /// The schedule row for a player episode, matched by season and episode number.
    func scheduleEpisode(for episode: Episode) -> ScheduleEpisode? {
        details?.schedule.lazy.flatMap(\.episodes).first {
            $0.seasonNumber == episode.seasonId && $0.episodeNumber == episode.id
        }
    }

    func toggleWatched(_ episode: ScheduleEpisode) async {
        do {
            try await RezkaClient.shared.toggleEpisodeWatched(id: episode.id)
            if watchedEpisodes.contains(episode.id) {
                watchedEpisodes.remove(episode.id)
            } else {
                watchedEpisodes.insert(episode.id)
            }
        } catch {
            report(error)
        }
    }

    // MARK: Bookmarks

    func toggleBookmark(in folder: BookmarkFolder) async {
        guard let details else { return }
        do {
            if bookmarkedIn.contains(folder.id) {
                try await RezkaClient.shared.removeBookmark(postId: details.postId, folder: folder.id)
                bookmarkedIn.remove(folder.id)
            } else {
                try await RezkaClient.shared.addBookmark(postId: details.postId, folder: folder.id)
                bookmarkedIn.insert(folder.id)
            }
            NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
        } catch {
            report(error)
        }
    }

    /// Creates a folder and puts the title in it, like the site's "new folder" on a details page.
    func createBookmarkFolder(named name: String) async {
        guard let details, let name = name.nonEmpty else { return }
        do {
            let folder = try await RezkaClient.shared.createBookmarkFolder(name: name)
            bookmarkFolders = [folder] + (bookmarkFolders ?? [])
            NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
            try await RezkaClient.shared.addBookmark(postId: details.postId, folder: folder.id)
            bookmarkedIn.insert(folder.id)
        } catch {
            report(error)
        }
    }

    // MARK: Rating

    /// Votes for the title from 1 to 10. The site takes one vote per account and never changes it.
    func rate(_ value: Int) async {
        guard let details, !isRating else { return }
        isRating = true
        defer { isRating = false }
        do {
            siteRating = try await RezkaClient.shared.rate(postId: details.postId, value: value)
            myRating = value
            Self.myRatings[details.postId] = value
        } catch {
            report(error)
        }
    }

    /// Votes sent from this Mac by post id.
    private static var myRatings: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: "myRatings") as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "myRatings") }
    }

    private func report(_ error: Error) {
        guard !error.isCancellation else { return }
        actionError = error.localizedDescription
        AuthSession.shared.handle(error)
    }

    // MARK: Playback

    /// The episode the main button should play: the next unfinished one after the last watched.
    func resumeEpisode(progress: WatchProgressStore) -> (episode: Episode, entry: WatchProgressStore.Entry?)? {
        guard let details else { return nil }
        let all = seasons.flatMap(\.episodes)
        guard let first = all.first else { return nil }
        guard let last = progress.last(postId: details.postId),
              let index = all.firstIndex(where: { $0.seasonId == last.seasonId && $0.id == last.episodeId })
        else { return (first, nil) }
        if last.isFinished, index + 1 < all.count {
            return (all[index + 1], nil)
        }
        return (all[index], last)
    }

    func play(episode: Episode? = nil, from position: Double? = nil) {
        guard let details, let translator else { return }
        PlayerPresenter.present(PlaybackRequest(
            postId: details.postId,
            title: details.title,
            posterURL: details.posterURL ?? item.posterURL,
            favs: details.favs,
            translator: translator,
            seasons: seasons,
            seasonId: episode?.seasonId,
            episodeId: episode?.id,
            startPosition: position,
            genres: details.info("Жанр")?.components(separatedBy: ", "),
            kind: item.kind == .unknown ? (details.isSeries ? .series : .film) : item.kind,
            path: details.path
        ))
    }
}
