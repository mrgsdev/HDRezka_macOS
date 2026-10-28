import Foundation
import Observation

/// The site's per-section menu (genres, studios), read from a listing page and kept for the session.
@MainActor
@Observable
final class SiteMenu {
    static let shared = SiteMenu()

    private(set) var menus: [CatalogSection: SectionMenu] = [:]
    private var isLoading = false

    func update(_ menus: [CatalogSection: SectionMenu]) {
        self.menus = menus
    }

    /// Fetches the menu if no listing brought it yet. On failure the catalog simply shows no genre picker.
    func loadIfNeeded() async {
        guard menus.isEmpty, !isLoading else { return }
        isLoading = true
        if let menus = try? await RezkaClient.shared.sectionMenus(), !menus.isEmpty {
            self.menus = menus
        }
        isLoading = false
    }
}
