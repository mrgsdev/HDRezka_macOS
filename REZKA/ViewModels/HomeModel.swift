import Foundation
import Observation

@MainActor
@Observable
final class HomeModel {
    struct Shelf: Identifiable {
        let title: String
        let items: [MediaItem]
        var id: String { title }
        var isContinue: Bool { title == HomeModel.continueTitle }
    }

    private(set) var shelves: [Shelf] = []
    private(set) var isLoading = false
    private(set) var error: Error?
    var removalError: String?
    /// Bumped per load so a superseded or cancelled load never overwrites a newer result.
    private var generation = 0
    /// What the current load has brought so far, by shelf title.
    @ObservationIgnored private var loaded: [String: [MediaItem]] = [:]
    @ObservationIgnored private var firstError: Error?

    private enum Source {
        /// The site's home page slider of recently added titles and episodes.
        case newest
        case catalog(CatalogSection?, CatalogFilter)

        func items() async throws -> [MediaItem] {
            switch self {
            case .newest: try await RezkaClient.shared.newest()
            case let .catalog(section, filter): try await RezkaClient.shared.catalog(section, filter: filter).items
            }
        }
    }

    nonisolated static let continueTitle = "Продолжить просмотр"
    private static let sources: [(String, Source)] = [
        ("Новые фильмы, сериалы, мультфильмы и аниме", .newest),
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

        // Shelves appear as they arrive; RezkaClient limits how many requests run at once.
        // Each result goes through `receive` on the model: collected in locals captured by the group's
        // closure instead, results got lost in optimized (Release) builds and the home stayed empty.
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.receive(Self.continueTitle, load: current) { try await RezkaClient.shared.continueWatching() }
            }
            for (title, source) in Self.sources {
                group.addTask {
                    await self.receive(title, load: current) { try await source.items() }
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
            shelves = ([Self.continueTitle] + Self.sources.map(\.0)).compactMap { title in
                loaded[title].flatMap { $0.isEmpty ? nil : Shelf(title: title, items: $0) }
            }
        case let .failure(error) where !error.isCancellation && title != Self.continueTitle:
            firstError = firstError ?? error
        default:
            break
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
