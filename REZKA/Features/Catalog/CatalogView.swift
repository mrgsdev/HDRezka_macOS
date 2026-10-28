import SwiftUI

struct CatalogView: View {
    enum Sort: Hashable {
        case filter(CatalogFilter)
        /// The site's best-rated list, optionally for one year.
        case best

        var title: String {
            switch self {
            case let .filter(filter): filter.title
            case .best: "Лучшие"
            }
        }
    }

    let section: CatalogSection

    /// A genre or studio from the site's menu; nil shows the whole section.
    @State private var genre: Listing?
    @State private var sort: Sort = .filter(.last)
    /// nil is "за всё время".
    @State private var bestYear: Int?
    @State private var loader = PagedLoader()

    private static let years = Array((1896...Calendar.current.component(.year, from: Date()) + 1).reversed())

    private var menu: SectionMenu? { SiteMenu.shared.menus[section] }

    /// Studios are collections on the site, so they have no best-of list.
    private var isStudio: Bool {
        genre.map { menu?.studios.contains($0) == true } ?? false
    }

    private var sorts: [Sort] {
        CatalogFilter.allCases.map(Sort.filter) + (isStudio ? [] : [.best])
    }

    private var key: String {
        "\(genre?.path ?? section.rawValue)|\(sort)|\(bestYear ?? 0)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MediaGrid(items: loader.items) { await loader.loadMore() }
                PagedFooter(loader: loader, emptyText: "Здесь пока ничего нет — попробуйте другую сортировку")
            }
            .padding(28)
        }
        .navigationTitle(genre?.title ?? section.title)
        .navigationSubtitle(genre == nil ? sort.title : "\(section.title) · \(sort.title)")
        .toolbar {
            ToolbarItemGroup {
                if let menu {
                    genreMenu(menu)
                }
                Picker("Сортировка", selection: $sort) {
                    ForEach(sorts, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if sort == .best {
                    yearMenu
                }
            }
        }
        .task { await SiteMenu.shared.loadIfNeeded() }
        .onChange(of: genre) {
            if isStudio, sort == .best { sort = .filter(.last) }
        }
        .task(id: key) {
            guard loader.key != key || (loader.items.isEmpty && loader.error == nil) else { return }
            let section = section, genre = genre, sort = sort, year = bestYear
            loader.reset(key: key) { page in
                switch sort {
                case let .filter(filter):
                    try await RezkaClient.shared.listing(genre?.path ?? "\(section.rawValue)/", filter: filter, page: page)
                case .best:
                    try await RezkaClient.shared.listing(section.bestPath(genre: genre, year: year), page: page)
                }
            }
            await loader.loadMore()
        }
    }

    private func genreMenu(_ menu: SectionMenu) -> some View {
        Menu {
            Button {
                genre = nil
            } label: {
                choice("Все жанры", isOn: genre == nil)
            }
            Section("Жанры") {
                ForEach(menu.genres) { item in
                    Button {
                        genre = item
                    } label: {
                        choice(item.title, isOn: genre == item)
                    }
                }
            }
            if !menu.studios.isEmpty {
                Section("Студии") {
                    ForEach(menu.studios) { item in
                        Button {
                            genre = item
                        } label: {
                            choice(item.title, isOn: genre == item)
                        }
                    }
                }
            }
        } label: {
            Label(genre?.title ?? "Все жанры", systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.titleAndIcon)
        }
        // A toolbar shows only icons by default; the chosen genre has to be readable.
        .fixedSize()
        .help("Жанр или студия")
    }

    private var yearMenu: some View {
        Menu {
            Button {
                bestYear = nil
            } label: {
                choice("За всё время", isOn: bestYear == nil)
            }
            ForEach(Self.years, id: \.self) { year in
                Button {
                    bestYear = year
                } label: {
                    choice(String(year), isOn: bestYear == year)
                }
            }
        } label: {
            Label(bestYear.map(String.init) ?? "За всё время", systemImage: "calendar")
                .labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .help("Год")
    }

    @ViewBuilder
    private func choice(_ title: String, isOn: Bool) -> some View {
        if isOn {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

/// Any list from the site by path: a collection from the collections tab or a details page, or announcements.
struct ListingView: View {
    let listing: Listing

    @State private var filter: CatalogFilter = .last
    @State private var loader = PagedLoader()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MediaGrid(items: loader.items) { await loader.loadMore() }
                PagedFooter(loader: loader, emptyText: listing.isSortable ? "Здесь пока ничего нет — попробуйте другую сортировку" : "Здесь пока ничего нет")
            }
            .padding(28)
        }
        .navigationTitle(listing.title)
        .toolbar {
            if listing.isSortable {
                ToolbarItem {
                    Picker("Сортировка", selection: $filter) {
                        ForEach(CatalogFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .task(id: filter) {
            let key = filter.rawValue
            guard loader.key != key || (loader.items.isEmpty && loader.error == nil) else { return }
            let listing = listing, filter = filter
            loader.reset(key: key) { page in
                try await RezkaClient.shared.listing(listing.path, filter: listing.isSortable ? filter : nil, page: page)
            }
            await loader.loadMore()
        }
    }
}
