import AppKit
import Foundation
import Observation
import SwiftUI

/// "Что посмотреть?": a reel of posters from the site's lists that spins and stops on a random title,
/// or shows one at once. Filtered as on Kinopoisk's random film page: genres and countries, any of
/// those picked, and a span of years.
@MainActor
@Observable
final class RouletteModel {
    enum Phase {
        case idle, loading, spinning, done
    }

    /// A run of the reel from one position to another, eased out so it slows down to a stop.
    struct Spin {
        let from: Double
        let to: Double
        let start: Date
        let duration: TimeInterval

        func position(at date: Date) -> Double {
            let progress = min(max(date.timeIntervalSince(start) / duration, 0), 1)
            return from + (to - from) * (1 - pow(1 - progress, 4))
        }
    }

    var section: CatalogSection = .films {
        // Each section has its own genres on the site.
        didSet { if section != oldValue { genres = []; reset() } }
    }
    /// Genres from the site's menu; none takes the whole section.
    var genres: Set<Listing> = [] {
        didSet { if genres != oldValue { reset() } }
    }
    var countries: Set<String> = [] {
        didSet { if countries != oldValue { reset() } }
    }
    var years = RouletteModel.allYears {
        didSet { if years != oldValue { reset() } }
    }

    static let allYears = 1920...Calendar.current.component(.year, from: Date())
    /// The countries Kinopoisk offers, as the site names them.
    static let countryOptions = [
        "Россия", "США", "СССР", "Великобритания", "Германия", "Франция", "Италия", "Испания", "Япония",
        "Корея Южная", "Китай", "Индия", "Канада", "Австралия", "Мексика", "Швеция", "Дания", "Бельгия",
        "Гонконг", "Турция",
    ]

    var hasFilters: Bool { !genres.isEmpty || !countries.isEmpty || years != Self.allYears }

    /// The posters on the reel, left to right; the reel only grows while it spins.
    private(set) var reel: [MediaItem] = []
    /// Where the reel stands, as an index into `reel` under the middle.
    private(set) var position: Double = 0
    private(set) var spin: Spin?
    private(set) var phase = Phase.idle
    /// The title the reel stopped on, loading its details for the description and the watch button.
    private(set) var pick: DetailsModel?
    /// The pick's poster colour for the glow behind the middle card, once the reel has stopped on it.
    private(set) var glow: Color?
    private(set) var error: Error?

    /// Titles to draw from, shuffled, for the current filters.
    @ObservationIgnored private var pool: [MediaItem] = []
    @ObservationIgnored private var poolKey: String?
    /// Picks of this session, so a roll does not land on one of them again while there are others.
    @ObservationIgnored private var picked: Set<String> = []
    @ObservationIgnored private var spinTask: Task<Void, Never>?
    /// Worked out while the reel spins and shown when it stops, so the glow does not give the pick away.
    @ObservationIgnored private var pickColor: Color?
    /// Bumped by every load, so a slow one for filters changed since does not land.
    @ObservationIgnored private var loadID = 0

    /// Not what anyone means by a film to watch tonight, unless they pick that very genre.
    private static let offTopic = ["Концерт", "Документальн", "Стендап", "Короткометраж"]

    static let spinDuration: TimeInterval = 4.5

    var key: String {
        [section.rawValue, genres.map(\.path).sorted().joined(separator: ","), countries.sorted().joined(separator: ","),
         "\(years.lowerBound)-\(years.upperBound)"].joined(separator: "|")
    }

    var isBusy: Bool { phase == .loading || phase == .spinning }

    /// Fills the reel for the current filters so it stands ready before the first roll.
    func prepare() async {
        guard poolKey != key else { return }
        loadID += 1
        let load = loadID, key = key
        phase = .loading
        error = nil
        do {
            let items = try await loadPool()
            guard load == loadID else { return }
            pool = items
            poolKey = key
            reel = Array(pool.prefix(12))
            position = Double(min(5, reel.count - 1))
            phase = .idle
        } catch {
            guard load == loadID else { return }
            if !error.isCancellation { self.error = error }
            phase = .idle
        }
    }

    func resetFilters() {
        genres = []
        countries = []
        years = Self.allYears
    }

    /// Picks a random title: with the reel spinning to it, or straight away.
    func roll(animated: Bool) async {
        guard !isBusy else { return }
        if poolKey != key || pool.isEmpty {
            await prepare()
            guard !pool.isEmpty else { return }
        }

        // Keep the cards in view where they are, then lay new ones after them; the pick lands well ahead,
        // so the reel has room to speed up and slow down.
        let current = Int(position.rounded())
        let kept = Array(reel[max(0, current - 6)...min(reel.count - 1, current + 6)])
        let start = current - max(0, current - 6)
        let distance = animated ? Int.random(in: 28...36) : 1
        var fresh: [MediaItem] = []
        while fresh.count < distance + 8 {
            var batch = pool.shuffled()
            // No poster twice in a row where two shuffles meet.
            if batch.count > 1, batch.first?.id == fresh.last?.id { batch.swapAt(0, batch.count - 1) }
            fresh += batch
        }
        let target = kept.count + distance - 1
        let unseen = pool.filter { !picked.contains($0.id) }
        let choice = (unseen.isEmpty ? pool : unseen).randomElement() ?? fresh[distance - 1]
        fresh[distance - 1] = choice
        picked.insert(choice.id)

        reel = kept + fresh
        position = Double(start)
        withAnimation(.easeInOut(duration: 0.4)) { glow = nil }
        pickColor = nil
        error = nil
        let details = DetailsModel(item: choice)
        pick = details
        Task { await details.load() }
        Task { [weak self] in
            let color = await PosterColor.glow(for: choice.posterURL)
            guard let self, pick === details else { return }
            pickColor = color
            if phase == .done { showGlow() }
        }

        guard animated else {
            position = Double(target)
            phase = .done
            showGlow()
            return
        }
        phase = .spinning
        spin = Spin(from: position, to: Double(target), start: Date(), duration: Self.spinDuration)
        spinTask?.cancel()
        spinTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.spinDuration))
            guard let self, !Task.isCancelled else { return }
            position = Double(target)
            spin = nil
            withAnimation(.easeOut(duration: 0.3)) { self.phase = .done }
            showGlow()
        }
    }

    private func showGlow() {
        guard let pickColor else { return }
        withAnimation(.easeInOut(duration: 0.8)) { glow = pickColor }
    }

    /// Forgets the titles drawn for the old filters; the reel stays until the new ones come.
    private func reset() {
        spinTask?.cancel()
        spin = nil
        pool = []
        poolKey = nil
        pick = nil
        glow = nil
        error = nil
        phase = .idle
    }

    /// One list to draw from and what it already guarantees about its titles.
    private struct Source {
        let path: String
        var filter: CatalogFilter?
        let page: Int
        /// A country's own list: its titles may name another country first.
        var isCountry = false
        /// A genre's own list: its titles may name another genre first.
        var isGenre = false
    }

    /// Lists until there are enough titles that fit: countries' lists when countries are picked, in turn
    /// with the best of a picked genre for a random year of the span, and its popular. The site's lists
    /// take one genre and one year at a time, so the rest is checked on each title.
    private func loadPool() async throws -> [MediaItem] {
        var found: [MediaItem] = []
        var seen: Set<String> = []
        for attempt in 0..<8 where found.count < 30 {
            let source = source(for: attempt)
            let items = (try? await RezkaClient.shared.listing(source.path, filter: source.filter, page: source.page).items) ?? []
            try Task.checkCancellation()
            // A few from each list, so one year or one genre does not fill the whole reel.
            let fitting = items.shuffled().filter { seen.insert($0.id).inserted && fits($0, from: source) }
            found += fitting.prefix(8)
        }
        guard !found.isEmpty else {
            throw RezkaError.site(String(localized: "Под эти фильтры ничего не нашлось. Попробуйте расширить годы или выбрать другие жанры."))
        }
        return found.shuffled()
    }

    private func source(for attempt: Int) -> Source {
        if let country = countries.randomElement(), attempt.isMultiple(of: 2) {
            return Source(path: "country/\(country)/", filter: Bool.random() ? .popular : nil, page: Int.random(in: 1...3), isCountry: true)
        }
        let genre = genres.randomElement()
        if attempt % 3 == 2 {
            return Source(path: genre?.path ?? "\(section.rawValue)/", filter: .popular, page: Int.random(in: 1...3), isGenre: genre != nil)
        }
        let narrowed = years != Self.allYears
        let year = narrowed ? Int.random(in: years) : nil
        return Source(path: section.bestPath(genre: genre, year: year), page: Int.random(in: 1...(narrowed ? 2 : 5)), isGenre: genre != nil)
    }

    /// Whether a title from a list fits the filters, judged by its card line: "2014, США, Фантастика".
    private func fits(_ item: MediaItem, from source: Source) -> Bool {
        guard item.posterURL != nil else { return false }
        if item.kind != .unknown, item.kind != section.kind { return false }
        let parts = item.subtitle.components(separatedBy: ", ")
        if years != Self.allYears {
            guard let year = item.subtitle.firstMatch(of: /\d{4}/).flatMap({ Int($0.output) }), years.contains(year) else { return false }
        }
        if !countries.isEmpty, !source.isCountry, !countries.contains(where: { parts.contains($0) }) { return false }
        if !genres.isEmpty, !source.isGenre {
            let titles = genres.map { $0.title.lowercased() }
            guard parts.contains(where: { titles.contains($0.lowercased()) }) else { return false }
        }
        let asked = genres.map(\.title)
        if Self.offTopic.contains(where: { word in item.subtitle.contains(word) && !asked.contains { $0.contains(word) } }) { return false }
        return true
    }
}

extension CatalogSection {
    /// What the site's cards in this section are.
    var kind: MediaKind {
        switch self {
        case .films: .film
        case .series: .series
        case .cartoons: .cartoon
        case .animation: .anime
        }
    }
}

/// The colour a poster gives off: its average, made brighter and more saturated, since the plain
/// average of a picture is usually a muddy brown.
enum PosterColor {
    static func glow(for url: URL?) async -> Color? {
        guard let url else { return nil }
        let image: NSImage
        if let cached = PosterCache.image(for: url) {
            image = cached
        } else {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let decoded = NSImage(data: data) else { return nil }
            image = decoded
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let average = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(1, saturation * 1.6 + 0.2), brightness: min(1, max(0.6, brightness * 1.6)))
    }
}
