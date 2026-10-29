import SwiftUI

/// Sidebar with the site's sections and a navigation stack per section, like the tvOS tab sidebar.
struct MainView: View {
    @State private var router = Router.shared
    // Kept here so switching sections does not reload these screens.
    @State private var home = HomeModel()
    @State private var collections = CollectionsModel()
    @State private var bookmarks = BookmarksModel()
    @State private var paths: [SidebarItem: NavigationPath] = [:]

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(selection: $router.selection) {
                Section {
                    row(.home, "Главная", "house")
                    row(.search, "Поиск", "magnifyingglass")
                }
                Section("Каталог") {
                    ForEach(CatalogSection.allCases) { section in
                        row(.section(section), LocalizedStringKey(section.title), section.systemImage)
                    }
                }
                Section("Моё") {
                    row(.collections, "Подборки", "square.stack")
                    row(.bookmarks, "Закладки", "bookmark")
                }
            }
            .safeAreaInset(edge: .top) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .safeAreaInset(edge: .bottom) {
                SettingsLink {
                    Label("Настройки", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            let item = router.selection ?? .home
            NavigationStack(path: path(for: item)) {
                content(for: item)
                    .mediaDestinations()
            }
            .id(item)
            .background(Brand.background)
        }
    }

    private func row(_ item: SidebarItem, _ title: LocalizedStringKey, _ icon: String) -> some View {
        Label(title, systemImage: icon).tag(item)
    }

    private func path(for item: SidebarItem) -> Binding<NavigationPath> {
        Binding(
            get: { paths[item] ?? NavigationPath() },
            set: { paths[item] = $0 }
        )
    }

    @ViewBuilder
    private func content(for item: SidebarItem) -> some View {
        switch item {
        case .home:
            HomeView(model: home)
        case .search:
            SearchView()
        case let .section(section):
            CatalogView(section: section)
        case .collections:
            CollectionsView(model: collections)
        case .bookmarks:
            BookmarksView(model: bookmarks)
        }
    }
}
