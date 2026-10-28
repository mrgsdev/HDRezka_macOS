import Foundation
import Observation

/// Loads numbered pages of media items and appends them, dropping duplicates.
@MainActor
@Observable
final class PagedLoader {
    private(set) var items: [MediaItem] = []
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var hasMore = false
    /// Identifies what is loaded (filter, query, folder) so views can skip reloading on re-appear.
    private(set) var key: String?

    private var page = 0
    private var generation = 0
    private var fetch: ((Int) async throws -> Page<MediaItem>)?

    func reset(key: String, fetch: @escaping (Int) async throws -> Page<MediaItem>) {
        self.key = key
        self.fetch = fetch
        generation += 1
        items = []
        page = 0
        hasMore = true
        error = nil
        isLoading = false
    }

    func clear() {
        key = nil
        fetch = nil
        generation += 1
        items = []
        hasMore = false
        error = nil
        isLoading = false
    }

    /// Drops an item removed on the site without reloading, so focus stays where it was.
    func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    func loadMore() async {
        guard let fetch, hasMore, !isLoading else { return }
        let current = generation
        isLoading = true
        error = nil
        do {
            let result = try await fetch(page + 1)
            guard current == generation else { return }
            page += 1
            let known = Set(items.map(\.id))
            items += result.items.filter { !known.contains($0.id) }
            hasMore = result.hasMore
        } catch {
            guard current == generation else { return }
            if !error.isCancellation {
                self.error = error
                AuthSession.shared.handle(error)
            }
        }
        isLoading = false
    }
}

extension Error {
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
