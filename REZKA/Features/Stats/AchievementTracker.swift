import Foundation
import Observation

/// Earns the achievements in «Итоги» from what is watched in REZKA on this Mac. Saved positions are
/// pruned and «Итоги» keep only time, so it keeps its own ledger of the films and episodes watched to
/// the end, roulette spins and the franchises seen; the rest comes from «Итоги» and the yearly goal.
/// Kept in the app's settings, like «Итоги».
@MainActor
@Observable
final class AchievementTracker {
    static let shared = AchievementTracker()

    struct Progress: Equatable {
        let current: Int
        let target: Int

        var isDone: Bool { current >= target }
    }

    /// When each achievement was earned, by id.
    private(set) var earned: [String: Date]
    /// How far along the counted ones are, by id.
    private(set) var progress: [String: Progress] = [:]

    private var ledger: Ledger
    /// Nothing was kept before: what is already known counts without a banner for each.
    @ObservationIgnored private let isFirstRun: Bool
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var lastTimeCheck = Date.distantPast
    /// Air days of the episodes of series opened this session, by `key(_:_:_:)`.
    @ObservationIgnored private var airDays: [String: String] = [:]

    private static let earnedKey = "achievements.earned"
    private static let ledgerKey = "achievements.ledger"
    /// Origin tags the site files among genres.
    private static let notGenres: Set<String> = ["Зарубежные", "Русские", "Украинские"]

    private struct Ledger: Codable {
        /// Titles without episodes by post id: when first watched to the end.
        var films: [String: Date] = [:]
        /// Episodes by `key(_:_:_:)`: when first watched to the end.
        var episodes: [String: Date] = [:]
        var spins = 0
        /// Roulette picks by post id: their IMDb rating once their page gave it, 0 until then.
        var picks: [String: Double] = [:]
        /// The post ids of each franchise's parts.
        var franchises: [[String]] = []
        /// Titles in all bookmark folders, as last seen.
        var bookmarks = 0
    }

    private init() {
        let defaults = UserDefaults.standard
        earned = defaults.data(forKey: Self.earnedKey).flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        let saved = defaults.data(forKey: Self.ledgerKey).flatMap { try? JSONDecoder().decode(Ledger.self, from: $0) }
        ledger = saved ?? Ledger()
        isFirstRun = saved == nil
    }

    /// At launch, or with the first event if a player window opens first. The first time, what saved
    /// positions already know counts, without a banner for each.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        if isFirstRun {
            for entry in WatchProgressStore.shared.finishedEntries() {
                if let seasonId = entry.seasonId, let episodeId = entry.episodeId {
                    ledger.episodes[Self.key(entry.postId, seasonId, episodeId)] = entry.updatedAt
                } else {
                    ledger.films[entry.postId] = entry.updatedAt
                }
            }
            save()
        }
        evaluate(announce: !isFirstRun)
    }

    // MARK: Events

    /// A film or an episode has just played to the end.
    func noteFinished(_ request: PlaybackRequest, at date: Date = Date()) {
        start()
        if let seasonId = request.seasonId, let episodeId = request.episodeId {
            let key = Self.key(request.postId, seasonId, episodeId)
            if ledger.episodes[key] == nil { ledger.episodes[key] = date }
            noteEpisode(of: request, seasonId: seasonId, episodeId: episodeId, at: date)
        } else {
            if ledger.films[request.postId] == nil { ledger.films[request.postId] = date }
            if let rating = ledger.picks[request.postId] {
                award("fate")
                if rating >= 8 { award("jackpot") }
            }
        }
        save()
        evaluate(announce: true)
    }

    private func noteEpisode(of request: PlaybackRequest, seasonId: String, episodeId: String, at date: Date) {
        if let season = request.seasons.first(where: { $0.id == seasonId }), !season.episodes.isEmpty,
           season.episodes.allSatisfy({ ledger.episodes[Self.key(request.postId, $0.seasonId, $0.id)] != nil }) {
            award("season")
        }
        if let last = request.seasons.last?.episodes.last, last.seasonId == seasonId, last.id == episodeId {
            award("finale")
            if request.seasons.count >= 10 { award("long-run") }
        }
        if airDays[Self.key(request.postId, seasonId, episodeId)] == WatchStats.dayKey(date) {
            award("same-day")
        }
    }

    /// Playback has started: the early bird is up before seven.
    func noteStart(at date: Date = Date()) {
        start()
        if (4..<7).contains(Calendar.current.component(.hour, from: date)) { award("early-bird") }
    }

    /// As the video plays: New Year's night, and once a minute what time alone earns.
    func noteWatching(at date: Date = Date()) {
        start()
        let parts = Calendar.current.dateComponents([.month, .day, .hour], from: date)
        if let month = parts.month, let day = parts.day, let hour = parts.hour,
           (month == 12 && day == 31 && hour >= 21) || (month == 1 && day == 1 && hour < 5) {
            award("new-year")
        }
        guard date.timeIntervalSince(lastTimeCheck) > 60 else { return }
        lastTimeCheck = date
        evaluate(announce: true)
    }

    /// A title page has loaded: its franchise, its episodes' air days, and the IMDb rating of a roulette pick.
    func noteDetails(_ details: MediaDetails) {
        start()
        var changed = false
        if let franchise = details.franchise {
            let ids = franchise.parts.compactMap { $0.path == nil ? details.postId : $0.path.flatMap(RezkaParser.idFromPath) }
            if ids.count >= 2, !ledger.franchises.contains(where: { Set($0) == Set(ids) }) {
                ledger.franchises.append(ids)
                changed = true
            }
        }
        if ledger.picks[details.postId] == 0, let rating = details.info("Рейтинги").flatMap(RezkaParser.imdbRating(in:)) {
            ledger.picks[details.postId] = rating
            changed = true
        }
        for episode in details.schedule.flatMap(\.episodes) {
            guard let season = episode.seasonNumber, let number = episode.episodeNumber, let day = Self.dayKey(siteDate: episode.date) else { continue }
            airDays[Self.key(details.postId, season, number)] = day
        }
        if changed {
            save()
            evaluate(announce: true)
        }
    }

    /// The roulette has picked a title.
    func noteSpin(postId: String?) {
        start()
        ledger.spins += 1
        if let postId, ledger.picks[postId] == nil { ledger.picks[postId] = 0 }
        save()
        evaluate(announce: true)
    }

    /// The bookmark folders have loaded with their sizes.
    func noteBookmarks(total: Int) {
        start()
        guard total != ledger.bookmarks else { return }
        ledger.bookmarks = total
        save()
        evaluate(announce: true)
    }

    /// A vote has gone to the site.
    func noteRated() {
        start()
        award("critic")
    }

    // MARK: Rules

    /// Works out what the ledger, «Итоги» and the yearly goal add up to, and awards what they reach.
    func evaluate(announce: Bool) {
        let measured = measure()
        progress = measured
        for (id, value) in measured where value.isDone {
            award(id, announce: announce)
        }
    }

    private func measure() -> [String: Progress] {
        var result: [String: Progress] = [:]
        func set(_ id: String, _ current: Int, _ target: Int) {
            result[id] = Progress(current: current, target: target)
        }
        let stats = WatchStats.shared
        let calendar = Calendar.current

        // Time.
        let secondsByDay = stats.days.compactMapValues { $0.values.reduce(0, +) }
        let hours = Int(secondsByDay.values.reduce(0, +) / 3600)
        set("first-hour", hours, 1)
        for target in [10, 50, 100, 250, 500, 1000] { set("hours-\(target)", hours, target) }

        // Films.
        let films = Array(ledger.films.keys)
        set("premiere", films.count, 1)
        for target in [10, 25, 50, 100, 250] { set("films-\(target)", films.count, target) }
        if ledger.films.values.contains(where: { (3..<6).contains(calendar.component(.hour, from: $0)) }) { set("night-owl", 1, 1) }

        // Episodes.
        let episodes = ledger.episodes
        let series = Set(episodes.keys.map(Self.postId(ofKey:)))
        set("pilot", episodes.count, 1)
        set("episodes-100", episodes.count, 100)
        set("episodes-500", episodes.count, 500)
        set("otaku", episodes.keys.filter { stats.titles[Self.postId(ofKey: $0)]?.kind == .anime }.count, 100)
        var byDay: [String: [String: Int]] = [:]
        for (key, date) in episodes { byDay[WatchStats.dayKey(date), default: [:]][Self.postId(ofKey: key), default: 0] += 1 }
        set("hooked", byDay.values.flatMap(\.values).max() ?? 0, 3)
        set("marathon", byDay.values.map { $0.values.reduce(0, +) }.max() ?? 0, 10)

        // Genres, countries and years of the films.
        let titles = films.compactMap { stats.titles[$0] }
        set("omnivore", Set(titles.flatMap(\.genres)).subtracting(Self.notGenres).count, 10)
        set("comedies", titles.filter { $0.genres.contains("Комедии") }.count, 20)
        set("horrors", titles.filter { $0.genres.contains("Ужасы") }.count, 10)
        set("detective", titles.filter { $0.genres.contains("Детективы") || $0.genres.contains("Триллеры") }.count, 15)
        set("cartoons", titles.filter { $0.kind == .cartoon }.count, 25)
        let countries = Set(titles.flatMap { $0.countries ?? [] })
        set("countries-10", countries.count, 10)
        set("countries-25", countries.count, 25)
        set("ussr", titles.filter { $0.countries?.contains("СССР") == true }.count, 10)
        set("korea", Set(films).union(series).filter { stats.titles[$0]?.countries?.contains("Корея Южная") == true }.count, 10)
        let years = titles.compactMap(\.year)
        set("decades", Set(years.map { $0 / 10 }).count, 6)
        if years.contains(where: { $0 < 1960 }) { set("retro", 1, 1) }

        // Habits: days with at least five minutes of watching.
        let days = Set(secondsByDay.filter { $0.value >= 300 }.keys)
        var best = 0
        for key in days {
            guard let date = WatchStats.date(ofDay: key),
                  let before = calendar.date(byAdding: .day, value: -1, to: date),
                  !days.contains(WatchStats.dayKey(before)) else { continue }
            var length = 1
            var next = date
            while let following = calendar.date(byAdding: .day, value: 1, to: next), days.contains(WatchStats.dayKey(following)) {
                length += 1
                next = following
            }
            best = max(best, length)
        }
        set("week-streak", best, 7)
        set("month-streak", best, 30)
        let weekend = secondsByDay.compactMap { key, seconds -> Double? in
            guard let date = WatchStats.date(ofDay: key), calendar.component(.weekday, from: date) == 7,
                  let sunday = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            return seconds + (secondsByDay[WatchStats.dayKey(sunday)] ?? 0)
        }.max() ?? 0
        set("weekend", Int(weekend / 3600), 5)
        if let first = secondsByDay.keys.compactMap(WatchStats.date(ofDay:)).min() {
            set("anniversary", calendar.dateComponents([.day], from: first, to: Date()).day ?? 0, 365)
        }

        // The roulette, bookmarks, votes.
        set("spins", ledger.spins, 10)
        set("collector", ledger.bookmarks, 10)
        if !(UserDefaults.standard.dictionary(forKey: "myRatings") ?? [:]).isEmpty { set("critic", 1, 1) }

        // The yearly goal, counted as its card in «Итоги» counts it.
        let goals = WatchGoal.all
        if !goals.isEmpty { set("goal-set", 1, 1) }
        for (year, target) in goals {
            guard let year = Int(year), target > 0,
                  let interval = calendar.dateInterval(of: .year, for: calendar.date(from: DateComponents(year: year)) ?? Date())
            else { continue }
            let finished = WatchProgressStore.shared.finishedFilms(in: interval).map(\.updatedAt).sorted()
            guard finished.count >= target else { continue }
            set("goal-done", 1, 1)
            if let october = calendar.date(from: DateComponents(year: year, month: 10, day: 1)), finished[target - 1] < october {
                set("goal-early", 1, 1)
            }
        }

        // A franchise with every part watched: films to the end, series at least an episode.
        if ledger.franchises.contains(where: { $0.allSatisfy { ledger.films[$0] != nil || series.contains($0) } }) {
            set("franchise", 1, 1)
        }
        return result
    }

    private func award(_ id: String, announce: Bool = true) {
        guard earned[id] == nil, let achievement = Achievement.all.first(where: { $0.id == id }) else { return }
        earned[id] = Date()
        if let data = try? JSONEncoder().encode(earned) { UserDefaults.standard.set(data, forKey: Self.earnedKey) }
        if announce { AchievementBanner.show(achievement) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(ledger) { UserDefaults.standard.set(data, forKey: Self.ledgerKey) }
    }

    // MARK: Keys

    private static func key(_ postId: String, _ seasonId: String, _ episodeId: String) -> String {
        "\(postId)|\(seasonId)|\(episodeId)"
    }

    private static func postId(ofKey key: String) -> String {
        String(key.prefix { $0 != "|" })
    }

    private static let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    /// "26 февраля 2026", as the site writes air dates → "2026-02-26".
    private static func dayKey(siteDate: String) -> String? {
        guard let match = siteDate.firstMatch(of: /(\d{1,2})\s+(\p{L}+)\s+(\d{4})/),
              let day = Int(match.1), let year = Int(match.3),
              let month = months.firstIndex(of: String(match.2).lowercased()) else { return nil }
        return String(format: "%04d-%02d-%02d", year, month + 1, day)
    }
}
