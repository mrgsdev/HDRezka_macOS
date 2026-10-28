import Foundation
import Observation

@MainActor
@Observable
final class BookmarksModel {
    private(set) var folders: [BookmarkFolder] = []
    var selectedFolderId: String?
    private(set) var isLoadingFolders = false
    private(set) var foldersError: Error?
    var actionError: String?
    /// Set when bookmarks changed elsewhere (a details page); the screen reloads when shown again.
    var isStale = false
    let loader = PagedLoader()

    var selectedFolder: BookmarkFolder? {
        folders.first { $0.id == selectedFolderId }
    }

    func loadFolders() async {
        isLoadingFolders = true
        foldersError = nil
        do {
            folders = try await RezkaClient.shared.bookmarkFolders()
            if selectedFolder == nil { selectedFolderId = folders.first?.id }
        } catch where !error.isCancellation {
            foldersError = error
            AuthSession.shared.handle(error)
        } catch {}
        isLoadingFolders = false
    }

    func showSelectedFolder(force: Bool = false) async {
        guard let folder = selectedFolderId else {
            loader.clear()
            return
        }
        guard force || loader.key != folder else { return }
        loader.reset(key: folder) { page in
            try await RezkaClient.shared.bookmarks(folder: folder, page: page)
        }
        await loader.loadMore()
    }

    func reload() async {
        await loadFolders()
        await showSelectedFolder(force: true)
    }

    // MARK: Folders

    func createFolder(named name: String) async {
        guard let name = name.nonEmpty else { return }
        do {
            let folder = try await RezkaClient.shared.createBookmarkFolder(name: name)
            // Reload so the folder lands where the site sorts it.
            await loadFolders()
            if !folders.contains(where: { $0.id == folder.id }) { folders.insert(folder, at: 0) }
            selectedFolderId = folder.id
        } catch {
            report(error)
        }
    }

    func renameSelectedFolder(to name: String) async {
        guard let folder = selectedFolder, let name = name.nonEmpty, name != folder.name else { return }
        do {
            try await RezkaClient.shared.renameBookmarkFolder(id: folder.id, name: name)
            update(folder.id) { BookmarkFolder(id: $0.id, name: name, count: $0.count) }
        } catch {
            report(error)
        }
    }

    func deleteSelectedFolder() async {
        guard let folder = selectedFolder else { return }
        do {
            try await RezkaClient.shared.deleteBookmarkFolder(id: folder.id)
            folders.removeAll { $0.id == folder.id }
            selectedFolderId = folders.first?.id
        } catch {
            report(error)
        }
    }

    // MARK: Titles

    func remove(_ item: MediaItem) async {
        guard let folder = selectedFolder, let postId = RezkaParser.idFromPath(item.path) else { return }
        do {
            try await RezkaClient.shared.removeBookmark(postId: postId, folder: folder.id)
            loader.remove(id: item.id)
            update(folder.id) { BookmarkFolder(id: $0.id, name: $0.name, count: $0.count.map { max($0 - 1, 0) }) }
        } catch {
            report(error)
        }
    }

    func move(_ item: MediaItem, to target: BookmarkFolder) async {
        guard let folder = selectedFolder, let postId = RezkaParser.idFromPath(item.path) else { return }
        do {
            try await RezkaClient.shared.moveBookmark(postId: postId, from: folder.id, to: target.id)
            loader.remove(id: item.id)
            // Counts change on both sides; a title already in the target is not duplicated, so ask the site.
            folders = (try? await RezkaClient.shared.bookmarkFolders()) ?? folders
        } catch {
            report(error)
        }
    }

    private func update(_ id: String, _ change: (BookmarkFolder) -> BookmarkFolder) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index] = change(folders[index])
    }

    private func report(_ error: Error) {
        guard !error.isCancellation else { return }
        actionError = error.localizedDescription
        AuthSession.shared.handle(error)
    }
}
