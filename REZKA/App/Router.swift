import Foundation
import Observation

enum SidebarItem: Hashable {
    case home, search, roulette, collections, bookmarks
    case section(CatalogSection)
}

/// The selected sidebar section, shared with the menu bar commands.
@MainActor
@Observable
final class Router {
    static let shared = Router()

    var selection: SidebarItem? = .home
    /// Bumped by ⌘F so the search field takes focus even when search is already open.
    private(set) var searchRequests = 0

    func focusSearch() {
        selection = .search
        searchRequests += 1
    }
}
