import Foundation
import Observation

enum SidebarItem: Hashable {
    case home, search, roulette, collections, bookmarks, stats
    case section(CatalogSection)
}

/// The selected sidebar section, shared with the menu bar commands.
@MainActor
@Observable
final class Router {
    static let shared = Router()

    var selection: SidebarItem? = .home
    /// The tour of the app: once after signing in, then from Help.
    var showsOnboarding = false
    /// Bumped by ⌘F so the search field takes focus even when search is already open.
    private(set) var searchRequests = 0
    /// A title to open from outside, e.g. the widget; the library window pushes it onto Home and clears it.
    var pendingTitle: MediaItem?

    func focusSearch() {
        selection = .search
        searchRequests += 1
    }

    func open(_ item: MediaItem) {
        selection = .home
        pendingTitle = item
    }
}
