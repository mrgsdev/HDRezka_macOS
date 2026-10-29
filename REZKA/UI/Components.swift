import AppKit
import SwiftUI

/// The REZKA look shared with the Apple TV app: pink wordmark on dark navy, and a cool light gray
/// version of it for the light theme. Every color here follows the window's appearance.
enum Brand {
    static let navy = Color(red: 2 / 255, green: 18 / 255, blue: 25 / 255)
    static let pink = Color(red: 1, green: 221 / 255, blue: 221 / 255)

    /// Cards, chips and table rows.
    static let panel = adaptive(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.06))
    /// A row under the mouse pointer.
    static let hover = adaptive(light: NSColor(white: 0, alpha: 0.04), dark: NSColor(white: 1, alpha: 0.06))
    /// The thin outline around posters.
    static let stroke = adaptive(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.08))
    /// Ratings and stars: the system yellow on dark, a deeper gold that stays readable on light.
    static let gold = adaptive(light: rgb(196, 134, 0), dark: .systemYellow)
    /// The window's plain background, under a details page's blurred poster.
    static let canvas = adaptive(light: rgb(236, 241, 244), dark: rgb(2, 18, 25))

    static let background = LinearGradient(
        colors: [adaptive(light: rgb(245, 248, 250), dark: rgb(10, 32, 42)), canvas],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Where a poster or a cover is still loading or missing.
    static let placeholder = LinearGradient(
        colors: [adaptive(light: NSColor(white: 0.9, alpha: 1), dark: NSColor(white: 0.2, alpha: 1)),
                 adaptive(light: NSColor(white: 0.82, alpha: 1), dark: NSColor(white: 0.11, alpha: 1))],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }
}

// MARK: Posters

/// Decoded posters kept in memory so rows scrolling back into view show them at once.
enum PosterCache {
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    static func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    static func store(_ image: NSImage, for url: URL) {
        let pixels = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
        cache.setObject(image, forKey: url as NSURL, cost: pixels * 4)
    }
}

/// Loads a poster and retries a load that was cancelled because the view scrolled away.
struct PosterImage: View {
    let url: URL?

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image = url.flatMap(PosterCache.image(for:)) ?? image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                ZStack {
                    Brand.placeholder
                    if failed {
                        Image(systemName: "film").font(.system(size: 28)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .clipped()
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            failed = true
            return
        }
        if let cached = PosterCache.image(for: url) {
            image = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let decoded = NSImage(data: data) else {
                failed = true
                return
            }
            PosterCache.store(decoded, for: url)
            withAnimation(.easeOut(duration: 0.2)) { image = decoded }
        } catch {
            if !error.isCancellation { failed = true }
        }
    }
}

/// An entry of a poster's context menu, e.g. "remove from this list".
struct CardAction: Identifiable {
    let title: String
    let systemImage: String
    var isDestructive = false
    let perform: () -> Void

    var id: String { title }
}

/// Lifts and outlines a card under the mouse pointer, the Mac counterpart of tvOS focus.
struct HoverLift: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.035 : 1)
            .shadow(color: .black.opacity(isHovered ? 0.55 : 0.25), radius: isHovered ? 16 : 6, y: isHovered ? 8 : 3)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }

    @ViewBuilder
    func cardActions(_ actions: [CardAction]) -> some View {
        if actions.isEmpty {
            self
        } else {
            contextMenu {
                ForEach(actions) { action in
                    Button(role: action.isDestructive ? .destructive : nil, action: action.perform) {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            }
        }
    }
}

struct PosterCard: View {
    let item: MediaItem
    var width: CGFloat = 170
    /// Shown on right-click; no menu when empty.
    var actions: [CardAction] = []

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 8) {
                PosterImage(url: item.posterURL)
                    .frame(width: width, height: width * 1.5)
                    .overlay(alignment: .bottomLeading) {
                        if let badge = item.badge {
                            Text(badge)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                // On the poster itself, so white in both themes.
                                .foregroundStyle(.white)
                                .background(.black.opacity(0.75), in: Capsule())
                                .padding(7)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brand.stroke))
                    .hoverLift()

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
        .cardActions(actions)
    }
}

/// A titled horizontal shelf of posters.
struct MediaRow: View {
    let title: String
    let items: [MediaItem]
    var actions: (MediaItem) -> [CardAction] = { _ in [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, 28)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(items) { item in
                        PosterCard(item: item, actions: actions(item))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
            }
        }
    }
}

/// A grid of posters that asks for more when its last item appears.
struct MediaGrid: View {
    let items: [MediaItem]
    var onReachEnd: () async -> Void = {}
    var actions: (MediaItem) -> [CardAction] = { _ in [] }

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 170), spacing: 24, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
            ForEach(items) { item in
                PosterCard(item: item, actions: actions(item))
                    .onAppear {
                        if item.id == items.last?.id {
                            Task { await onReachEnd() }
                        }
                    }
            }
        }
    }
}

// MARK: States

struct ErrorStateView: View {
    let error: Error
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Brand.gold)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button("Повторить") { Task { await retry() } }
        }
        .padding(40)
    }
}

struct EmptyStateView: View {
    let text: String
    var icon = "tray"

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .padding(40)
    }
}

/// Footer for paged grids: spinner, error with retry, or empty state.
struct PagedFooter: View {
    let loader: PagedLoader
    var emptyText = "Ничего не найдено"

    var body: some View {
        Group {
            if loader.isLoading {
                ProgressView().padding(30)
            } else if let error = loader.error {
                ErrorStateView(error: error) { await loader.loadMore() }
            } else if loader.items.isEmpty, !loader.hasMore {
                EmptyStateView(text: emptyText)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Details pages and site lists open inside the current section's navigation stack.
    func mediaDestinations() -> some View {
        navigationDestination(for: MediaItem.self) { DetailsView(item: $0) }
            .navigationDestination(for: Listing.self) { ListingView(listing: $0) }
    }
}

extension Double {
    /// `754` → `12:34`, `3723` → `1:02:03`.
    var playbackTime: String {
        let total = Int(self)
        let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
