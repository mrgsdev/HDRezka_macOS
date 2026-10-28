import Foundation
import Observation

@MainActor
@Observable
final class CollectionsModel {
    private(set) var items: [MediaCollection] = []
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var hasMore = true
    private var page = 0

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        error = nil
        do {
            let result = try await RezkaClient.shared.collections(page: page + 1)
            page += 1
            let known = Set(items.map(\.id))
            items += result.items.filter { !known.contains($0.id) }
            hasMore = result.hasMore
        } catch where !error.isCancellation {
            self.error = error
            AuthSession.shared.handle(error)
        } catch {}
        isLoading = false
    }
}
