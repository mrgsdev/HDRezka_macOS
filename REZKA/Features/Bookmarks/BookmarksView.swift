import SwiftUI

struct BookmarksView: View {
    private enum Editor {
        case create, rename
    }

    let model: BookmarksModel

    @State private var editor: Editor?
    @State private var folderName = ""
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !model.folders.isEmpty {
                    folderBar
                }
                MediaGrid(items: model.loader.items, onReachEnd: { await model.loader.loadMore() }, actions: actions(for:))
                if model.selectedFolderId != nil {
                    PagedFooter(loader: model.loader, emptyText: "В этой папке пока пусто. Добавляйте сюда фильмы и сериалы кнопкой «В закладки» в их карточке.")
                }
            }
            .padding(28)
        }
        .overlay {
            if model.folders.isEmpty {
                if model.isLoadingFolders {
                    ProgressView()
                } else if let error = model.foldersError {
                    ErrorStateView(error: error) { await model.loadFolders() }
                } else {
                    VStack(spacing: 8) {
                        EmptyStateView(text: "Закладок пока нет. Создайте папку и добавляйте в неё фильмы и сериалы кнопкой «В закладки» в их карточке.",
                                       icon: "bookmark")
                        Button("Создать папку") { startEditing(.create) }
                    }
                }
            }
        }
        .navigationTitle("Закладки")
        .navigationSubtitle(model.selectedFolder?.name ?? "")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    startEditing(.create)
                } label: {
                    Label("Новая папка", systemImage: "folder.badge.plus")
                }
                .help("Новая папка")
                if let folder = model.selectedFolder {
                    Menu {
                        Button {
                            startEditing(.rename, name: folder.name)
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Удалить папку", systemImage: "trash")
                        }
                    } label: {
                        Label("Папка", systemImage: "ellipsis.circle")
                    }
                    .help("Переименовать или удалить папку «\(folder.name)»")
                }
            }
        }
        .task {
            if model.folders.isEmpty { await model.loadFolders() }
        }
        .task(id: model.selectedFolderId) {
            await model.showSelectedFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarksChanged)) { _ in
            model.isStale = true
        }
        .onAppear {
            guard model.isStale else { return }
            model.isStale = false
            Task { await model.reload() }
        }
        .alert(editor == .rename ? "Переименовать папку" : "Новая папка", isPresented: Binding(
            get: { editor != nil },
            set: { if !$0 { editor = nil } }
        )) {
            TextField("Название", text: $folderName)
            Button(editor == .rename ? "Сохранить" : "Создать") {
                // The alert resets `editor` as it closes, so read it now.
                let mode = editor, name = folderName
                Task {
                    if mode == .rename {
                        await model.renameSelectedFolder(to: name)
                    } else {
                        await model.createFolder(named: name)
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Удалить папку «\(model.selectedFolder?.name ?? "")»?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) { Task { await model.deleteSelectedFolder() } }
        } message: {
            if let count = model.selectedFolder?.count, count > 0 {
                Text("Закладки в ней (\(count)) тоже удалятся.")
            }
        }
        .alert("Не получилось", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.folders) { folder in
                    let isSelected = folder.id == model.selectedFolderId
                    Button {
                        model.selectedFolderId = folder.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(folder.name)
                            if let count = folder.count {
                                Text("\(count)").foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                            }
                        }
                        .foregroundStyle(isSelected ? Color.white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.accentColor : Brand.panel, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Right-click menu on a poster: remove it from the folder or move it to another one.
    private func actions(for item: MediaItem) -> [CardAction] {
        guard let folder = model.selectedFolder else { return [] }
        let remove = CardAction(title: "Убрать из «\(folder.name)»", systemImage: "trash", isDestructive: true) {
            Task { await model.remove(item) }
        }
        let moves = model.folders.filter { $0.id != folder.id }.map { target in
            CardAction(title: "Перенести в «\(target.name)»", systemImage: "folder") {
                Task { await model.move(item, to: target) }
            }
        }
        return [remove] + moves
    }

    private func startEditing(_ mode: Editor, name: String = "") {
        folderName = name
        editor = mode
    }
}
