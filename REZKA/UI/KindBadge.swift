import SwiftUI

extension MediaKind {
    /// For the label in a poster's corner, as the site draws it.
    var symbol: String {
        switch self {
        case .film: "video.fill"
        case .series: "tv.fill"
        case .cartoon: "sparkles.tv.fill"
        case .anime: "wand.and.stars"
        case .show: "theatermasks.fill"
        case .unknown: "questionmark"
        }
    }
}

/// «Фильм», «Сериал»… in a poster's top corner, as on the site. Pointing at it a moment opens the
/// title's card from the site: its rating, the start of the description, genres, people, IMDb.
struct KindBadge: View {
    let item: MediaItem

    @State private var isOverBadge = false
    @State private var isOverCard = false
    @State private var isShown = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        if let title = item.kind.title {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: item.kind.symbol)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor, in: UnevenRoundedRectangle(bottomLeadingRadius: 8))
            // The card's own tooltip with the title would cover the popover.
            .help(Text(verbatim: ""))
            .onHover { inside in
                isOverBadge = inside
                follow()
            }
            .popover(isPresented: $isShown, arrowEdge: .trailing) {
                QuickInfoView(item: item)
                    .onHover { inside in
                        isOverCard = inside
                        follow()
                    }
            }
        }
    }

    /// Opens after a moment over the badge and stays while the pointer is on it or the card, so it can
    /// be read; a pointer only passing by opens nothing.
    private func follow() {
        hoverTask?.cancel()
        let wanted = isOverBadge || isOverCard
        hoverTask = Task {
            try? await Task.sleep(for: .milliseconds(wanted ? 350 : 250))
            guard !Task.isCancelled else { return }
            isShown = isOverBadge || isOverCard
        }
    }
}

/// The site's hover card for a title, loaded once per title while the app runs.
struct QuickInfoView: View {
    let item: MediaItem

    @State private var info: QuickInfo?
    @State private var failed = false

    @MainActor private static var cache: [String: QuickInfo] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let info {
                content(info)
            } else if failed {
                Text("Не удалось загрузить информацию.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Загружаем…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .padding(18)
        .frame(width: 380, alignment: .leading)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ info: QuickInfo) -> some View {
        Text(info.title.isEmpty ? item.title : info.title)
            .font(.title3.bold())
            .fixedSize(horizontal: false, vertical: true)
        if let rating = info.rating {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if let label = info.ratingLabel {
                        Text(verbatim: label + ":").foregroundStyle(.secondary)
                    }
                    Text(verbatim: rating.value).bold()
                    Text(verbatim: "(\(rating.votes))").foregroundStyle(.secondary)
                }
                Stars(value: Double(rating.value.replacingOccurrences(of: ",", with: ".")) ?? 0)
            }
        }
        if !info.description.isEmpty {
            Text(info.description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(info.rows, id: \.self) { row in
            (Text(verbatim: row.label + ": ").foregroundStyle(.secondary) + Text(verbatim: row.values.joined(separator: ", ")))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        if info.imdb != nil || info.kinopoisk != nil {
            HStack(spacing: 16) {
                if let imdb = info.imdb { score("IMDb", imdb) }
                if let kinopoisk = info.kinopoisk { score("Кинопоиск", kinopoisk) }
            }
            .padding(.top, 2)
        }
    }

    private func score(_ name: String, _ score: QuickInfo.Score) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: name + ":").foregroundStyle(.secondary)
            Text(verbatim: score.value).bold()
            Text(verbatim: "(\(score.votes))").foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard let postId = RezkaParser.idFromPath(item.path) else { failed = true; return }
        if let cached = Self.cache[postId] {
            info = cached
            return
        }
        do {
            let loaded = try await RezkaClient.shared.quickInfo(postId: postId)
            Self.cache[postId] = loaded
            info = loaded
        } catch {
            if !error.isCancellation { failed = true }
        }
    }
}

/// Ten stars, filled as far as the rating goes, as on the site.
private struct Stars: View {
    let value: Double

    var body: some View {
        let stars = HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { _ in Image(systemName: "star.fill") }
        }
        .font(.system(size: 15))
        stars
            .foregroundStyle(.quaternary)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    stars
                        .foregroundStyle(Brand.gold)
                        .frame(width: proxy.size.width, alignment: .leading)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: proxy.size.width * min(max(value / 10, 0), 1))
                        }
                }
            }
    }
}
