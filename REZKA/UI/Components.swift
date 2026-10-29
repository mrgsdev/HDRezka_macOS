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

// MARK: Flow

/// Lays its views out in lines like words, starting a new line when the width runs out:
/// every chip in view without scrolling sideways, which a mouse wheel can't do, and buttons
/// that keep their full labels in a narrow window instead of being squeezed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(subviews, width: proposal.width ?? .infinity)
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                // A view wider than the whole line gets the line's width, and truncates.
                let width = min(size.width, bounds.width)
                // Centered in its line, so a link sits level with the buttons beside it.
                let origin = CGPoint(x: x, y: y + (line.height - size.height) / 2)
                subviews[index].place(at: origin, proposal: ProposedViewSize(width: width, height: size.height))
                x += width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = min(size.width, width)
            if !line.indices.isEmpty, line.width + spacing + itemWidth > width {
                lines.append(line)
                line = Line()
            }
            line.width += (line.indices.isEmpty ? 0 : spacing) + itemWidth
            line.height = max(line.height, size.height)
            line.indices.append(index)
        }
        if !line.indices.isEmpty { lines.append(line) }
        return lines
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

/// A titled shelf of posters that scrolls sideways. The title is plain text, or any view, like the home's
/// "Новые …" with its section links.
///
/// A mouse wheel scrolls the page, not the shelf: taking it over here would leave the page no place to
/// scroll from, shelves cover most of it. So, as in the site's slider, arrows on the edges turn the shelf
/// a screen at a time, shown while the pointer is over it; ⇧ with the wheel turns it a poster at a time,
/// and a trackpad scrolls it sideways as usual.
struct MediaRow<Title: View>: View {
    let items: [MediaItem]
    let actions: (MediaItem) -> [CardAction]
    let title: Title

    /// The first poster in view; follows trackpad scrolling too.
    @State private var position: MediaItem.ID?
    @State private var isHovered = false
    @State private var width: CGFloat = 0
    @State private var wheelMonitor: Any?
    /// Wheel travel not yet turned into a whole poster.
    @State private var wheelTravel: CGFloat = 0

    // Computed: a generic type can't store statics.
    private static var cardWidth: CGFloat { 170 }
    private static var spacing: CGFloat { 20 }
    private static var margin: CGFloat { 28 }

    init(items: [MediaItem], actions: @escaping (MediaItem) -> [CardAction] = { _ in [] }, @ViewBuilder title: () -> Title) {
        self.items = items
        self.actions = actions
        self.title = title()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
                .font(.title2.bold())
                .padding(.horizontal, Self.margin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(items) { item in
                        PosterCard(item: item, width: Self.cardWidth, actions: actions(item))
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 10)
            }
            .contentMargins(.horizontal, Self.margin, for: .scrollContent)
            .scrollPosition(id: $position, anchor: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay(alignment: .topLeading) {
                if isHovered, firstIndex > 0 { arrow(back: true) }
            }
            .overlay(alignment: .topTrailing) {
                if isHovered, firstIndex + pageSize < items.count { arrow(back: false) }
            }
            .onHover { inside in
                isHovered = inside
                if inside { watchShiftWheel() } else { stopWatchingShiftWheel() }
            }
            .onDisappear { stopWatchingShiftWheel() }
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
    }

    /// How many posters fit in the visible width.
    private var pageSize: Int {
        max(1, Int((width - 2 * Self.margin + Self.spacing) / (Self.cardWidth + Self.spacing)))
    }

    private var firstIndex: Int {
        position.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
    }

    /// Moves the shelf by whole posters; the last page is a full one, not a lone poster at the edge.
    private func move(by posters: Int) {
        let target = min(max(firstIndex + posters, 0), max(items.count - pageSize, 0))
        guard items.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.3)) { position = items[target].id }
    }

    /// While the pointer is over the shelf, ⇧ with the wheel turns it instead of the page. A wheel the
    /// system already turned sideways, or a trackpad, has a horizontal delta and is left to the scroll view.
    private func watchShiftWheel() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.modifierFlags.contains(.shift), event.scrollingDeltaX == 0, event.scrollingDeltaY != 0 else { return event }
            // A notched wheel counts lines, one per click; a smooth one counts points.
            let perPoster: CGFloat = event.hasPreciseScrollingDeltas ? 80 : 1
            wheelTravel += event.scrollingDeltaY
            let posters = Int(wheelTravel / perPoster)
            if posters != 0 {
                wheelTravel -= CGFloat(posters) * perPoster
                // Down, or toward the user, moves on.
                move(by: -posters)
            }
            return nil
        }
    }

    private func stopWatchingShiftWheel() {
        if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
        wheelMonitor = nil
        wheelTravel = 0
    }

    private func arrow(back: Bool) -> some View {
        Button {
            move(by: back ? -pageSize : pageSize)
        } label: {
            Image(systemName: back ? "chevron.left" : "chevron.right")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 36, height: 72)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(back ? "Назад" : "Дальше")
        .accessibilityLabel(back ? "Назад" : "Дальше")
        // Level with the middle of the posters.
        .padding(.top, 10 + (Self.cardWidth * 1.5 - 72) / 2)
        .padding(.horizontal, 6)
        .transition(.opacity)
    }
}

extension MediaRow where Title == Text {
    init(title: String, items: [MediaItem], actions: @escaping (MediaItem) -> [CardAction] = { _ in [] }) {
        self.init(items: items, actions: actions) { Text(title) }
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
