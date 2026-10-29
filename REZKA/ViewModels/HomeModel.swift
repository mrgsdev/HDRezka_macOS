import Foundation
import Observation

/// What the "Новые фильмы, сериалы, мультфильмы и аниме" shelf shows: the words of its title pick
/// one section, as on the site. The raw values are the site's own ids for its slider.
enum NewestSection: Int, CaseIterable {
    case all = 0
    case films = 1
    case series = 2
    case cartoons = 3
    case anime = 82

    var word: String {
        switch self {
        case .all: String(localized: "все новинки")
        case .films: String(localized: "фильмы")
        case .series: String(localized: "сериалы")
        case .cartoons: String(localized: "мультфильмы")
        case .anime: String(localized: "аниме")
        }
    }

    private static let key = "newestSection"

    /// Kept between launches, as the site keeps it in a cookie.
    static var saved: NewestSection {
        get { NewestSection(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .all }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

@MainActor
@Observable
final class HomeModel {
    struct Shelf: Identifiable {
        let title: String
        let items: [MediaItem]
        var id: String { title }
        var isContinue: Bool { title == HomeModel.continueTitle }
        var isNewest: Bool { title == HomeModel.newestTitle }
    }

    private(set) var shelves: [Shelf] = []
    private(set) var isLoading = false
    private(set) var error: Error?
    var removalError: String?
    private(set) var newestSection = NewestSection.saved
    private(set) var isLoadingNewest = false
    /// Bumped per load so a superseded or cancelled load never overwrites a newer result.
    private var generation = 0
    /// What the current load has brought so far, by shelf title.
    @ObservationIgnored private var loaded: [String: [MediaItem]] = [:]
    @ObservationIgnored private var firstError: Error?

    private enum Source {
        /// The site's home page slider of recently added titles and episodes.
        case newest
        case catalog(CatalogSection?, CatalogFilter)

        func items(newest section: NewestSection) async throws -> [MediaItem] {
            switch self {
            case .newest: try await RezkaClient.shared.newest(section: section.rawValue)
            case let .catalog(section, filter): try await RezkaClient.shared.catalog(section, filter: filter).items
            }
        }
    }

    nonisolated static let continueTitle = "Продолжить просмотр"
    nonisolated static let newestTitle = "Новые фильмы, сериалы, мультфильмы и аниме"
    private static let sources: [(String, Source)] = [
        (newestTitle, .newest),
        ("Новинки", .catalog(nil, .last)),
        ("Популярные фильмы", .catalog(.films, .popular)),
        ("Популярные сериалы", .catalog(.series, .popular)),
        ("Сейчас смотрят", .catalog(.films, .watching)),
        ("Мультфильмы", .catalog(.cartoons, .popular)),
        ("Аниме", .catalog(.animation, .popular)),
    ]

    func loadIfNeeded() async {
        if shelves.isEmpty { await load() }
    }

    func load() async {
        // SwiftUI may start and immediately cancel this task on first layout; don't send that burst.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }

        generation += 1
        let current = generation
        isLoading = true
        error = nil
        loaded = [:]
        firstError = nil
        let newest = newestSection

        // Shelves appear as they arrive; RezkaClient limits how many requests run at once.
        // Each result goes through `receive` on the model: collected in locals captured by the group's
        // closure instead, results got lost in optimized (Release) builds and the home stayed empty.
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.receive(Self.continueTitle, load: current) { try await RezkaClient.shared.continueWatching() }
            }
            for (title, source) in Self.sources {
                group.addTask {
                    await self.receive(title, load: current) { try await source.items(newest: newest) }
                }
            }
        }

        guard current == generation, !Task.isCancelled else { return }
        if shelves.isEmpty, let firstError {
            error = firstError
            AuthSession.shared.handle(firstError)
        }
        isLoading = false
    }

    /// Fetches one shelf and puts it in place, keeping the shelves in their fixed order.
    private func receive(_ title: String, load: Int, _ fetch: @Sendable () async throws -> [MediaItem]) async {
        let result: Result<[MediaItem], Error>
        do { result = .success(try await fetch()) } catch { result = .failure(error) }
        guard load == generation, !Task.isCancelled else { return }
        switch result {
        case let .success(items):
            loaded[title] = items
            arrangeShelves()
        case let .failure(error) where !error.isCancellation && title != Self.continueTitle:
            firstError = firstError ?? error
        default:
            break
        }
    }

    /// The loaded shelves in their fixed order. An empty shelf is left out, except "Новые …":
    /// its title is where the section is picked, so it has to stay to pick another.
    private func arrangeShelves() {
        shelves = ([Self.continueTitle] + Self.sources.map(\.0)).compactMap { title in
            loaded[title].flatMap { $0.isEmpty && title != Self.newestTitle ? nil : Shelf(title: title, items: $0) }
        }
    }

    /// Shows one section in the "Новые …" shelf, or all of them again; only that shelf reloads.
    func showNewest(_ section: NewestSection) async {
        guard section != newestSection, !isLoadingNewest else { return }
        let previous = newestSection
        newestSection = section
        isLoadingNewest = true
        defer { isLoadingNewest = false }
        do {
            loaded[Self.newestTitle] = try await RezkaClient.shared.newest(section: section.rawValue)
            NewestSection.saved = section
            arrangeShelves()
        } catch {
            newestSection = previous
            if !error.isCancellation { AuthSession.shared.handle(error) }
        }
    }

    /// Re-reads only "continue watching", e.g. after the player closed.
    func refreshContinue() async {
        guard !shelves.isEmpty, let items = try? await RezkaClient.shared.continueWatching() else { return }
        setContinue(items)
    }

    func removeFromContinue(_ item: MediaItem) async {
        guard let id = item.continueId else { return }
        do {
            try await RezkaClient.shared.removeFromContinue(id: id)
            let remaining = shelves.first(where: \.isContinue)?.items.filter { $0.id != item.id } ?? []
            setContinue(remaining)
            // Without this the details screen would still offer to resume the title.
            if let postId = RezkaParser.idFromPath(item.path) {
                WatchProgressStore.shared.remove(postId: postId)
            }
        } catch {
            removalError = error.localizedDescription
            AuthSession.shared.handle(error)
        }
    }

    private func setContinue(_ items: [MediaItem]) {
        shelves.removeAll(where: \.isContinue)
        if !items.isEmpty {
            shelves.insert(Shelf(title: Self.continueTitle, items: items), at: 0)
        }
    }
}
