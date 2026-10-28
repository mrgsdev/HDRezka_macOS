import SwiftUI

/// The site's collections ("Фильмы Netflix", "Сериалы 2024 года"…), with announcements first.
struct CollectionsView: View {
    let model: CollectionsModel

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 250), spacing: 24, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                    CollectionCard(listing: .announcements, coverURL: nil, count: nil, icon: "megaphone")
                    ForEach(model.items) { collection in
                        CollectionCard(listing: collection.listing, coverURL: collection.coverURL, count: collection.count)
                            .onAppear {
                                if collection.id == model.items.last?.id {
                                    Task { await model.loadMore() }
                                }
                            }
                    }
                }

                Group {
                    if model.isLoading {
                        ProgressView().padding(30)
                    } else if let error = model.error {
                        ErrorStateView(error: error) { await model.loadMore() }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(28)
        }
        .navigationTitle("Подборки")
        .task {
            if model.items.isEmpty { await model.loadMore() }
        }
    }
}

private struct CollectionCard: View {
    let listing: Listing
    let coverURL: URL?
    let count: Int?
    /// Drawn instead of a cover, for entries the site shows without one.
    var icon: String? = nil

    var body: some View {
        NavigationLink(value: listing) {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let icon {
                        ZStack {
                            LinearGradient(colors: [Color(white: 0.24), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.secondary)
                        }
                    } else {
                        PosterImage(url: coverURL)
                    }
                }
                .frame(width: 250, height: 144)
                .overlay(alignment: .bottomTrailing) {
                    if let count {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.75), in: Capsule())
                            .padding(7)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .hoverLift()

                Text(listing.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .frame(width: 250, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
