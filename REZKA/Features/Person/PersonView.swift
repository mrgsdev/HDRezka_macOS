import SwiftUI

/// An actor's or a director's page: photo, the site's info table, and a shelf of titles per role.
struct PersonView: View {
    let person: PersonLink

    private enum LoadState {
        case loading
        case loaded(PersonDetails)
        case failed(Error)
    }

    @State private var state = LoadState.loading

    var body: some View {
        ZStack {
            switch state {
            case .loading:
                ProgressView()
            case let .failed(error):
                ErrorStateView(error: error) { await load() }
            case let .loaded(details):
                content(details)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
        .navigationTitle(person.name)
        .task {
            if case .loading = state { await load() }
        }
    }

    private func load() async {
        guard let path = person.path else { return }
        state = .loading
        do {
            state = .loaded(try await RezkaClient.shared.person(path: path))
        } catch where !error.isCancellation {
            state = .failed(error)
            AuthSession.shared.handle(error)
        } catch {}
    }

    private func content(_ details: PersonDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack(alignment: .top, spacing: 30) {
                    PosterImage(url: details.photoURL ?? person.photoURL)
                        .frame(width: 200, height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(details.name)
                            .font(.largeTitle.bold())
                            .textSelection(.enabled)
                        if let original = details.originalName {
                            Text(original)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                            ForEach(details.info, id: \.self) { row in
                                GridRow {
                                    Text(row.title)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(row.value)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                }
                .padding(.horizontal, 28)

                if details.careers.isEmpty {
                    Text("На сайте пока нет фильмов и сериалов с этим человеком.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 28)
                }
                ForEach(details.careers) { career in
                    MediaRow(items: career.items) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(career.title)
                            if let stats = career.stats {
                                Text(stats)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 28)
        }
    }
}

/// A small round photo of a person, or a silhouette when the site has none.
struct PersonPhoto: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                PosterImage(url: url)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(Circle())
    }
}
