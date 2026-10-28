import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var loader = PagedLoader()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if loader.key == nil {
                    EmptyStateView(text: "Введите название фильма, сериала или мультфильма", icon: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    MediaGrid(items: loader.items) { await loader.loadMore() }
                    PagedFooter(loader: loader, emptyText: "По запросу «\(loader.key ?? "")» ничего не найдено")
                }
            }
            .padding(28)
        }
        .navigationTitle("Поиск")
        .searchable(text: $query, placement: .toolbar, prompt: "Фильмы, сериалы, мультфильмы")
        .searchFocused($isSearchFocused)
        .onAppear { isSearchFocused = true }
        .onChange(of: Router.shared.searchRequests) { isSearchFocused = true }
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else {
                loader.clear()
                return
            }
            guard text != loader.key else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            loader.reset(key: text) { page in
                try await RezkaClient.shared.search(text, page: page)
            }
            await loader.loadMore()
        }
    }
}
