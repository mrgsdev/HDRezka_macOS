import AppKit
import SwiftUI

/// A scratch card for «Что посмотреть?»: the pick's poster under silver foil that wears off where the
/// pointer drags across it. Past half, the rest falls away by itself and the card tells it is open;
/// a double click opens it at once. Until a card is dealt, the foil covers an empty face.
struct ScratchCard: View {
    /// The pick under the foil; nil until a card is dealt.
    let item: MediaItem?
    let onReveal: () -> Void

    @State private var strokes: [[CGPoint]] = []
    @State private var isDragging = false
    @State private var scratched: Set<Int> = []
    @State private var isOpen = false

    static let size = CGSize(width: 260, height: 390)
    private static let brush: CGFloat = 46
    private static let columns = 13
    private static let rows = 19
    /// Of the card, scratched by hand before the rest falls away.
    private static let enough = 0.55

    var body: some View {
        ZStack {
            face
            if !isOpen {
                foil
                    .mask {
                        ZStack {
                            Rectangle()
                            scratches
                                .stroke(style: StrokeStyle(lineWidth: Self.brush, lineCap: .round, lineJoin: .round))
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.06)))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in scratch(at: value.location) }
                .onEnded { _ in isDragging = false }
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded { open() })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOpen ? (item?.title ?? "") : String(localized: "Скретч-карта"))
        .accessibilityAction(named: Text("Открыть")) { open() }
    }

    // MARK: Layers

    /// The poster with its title along the bottom, as the foil comes off it.
    private var face: some View {
        ZStack(alignment: .bottomLeading) {
            if let item {
                PosterImage(url: item.posterURL)
                    .frame(width: Self.size.width, height: Self.size.height)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title3.bold())
                        .lineLimit(2)
                    Text(item.subtitle)
                        .font(.caption)
                        .opacity(0.75)
                        .lineLimit(2)
                }
                .foregroundStyle(.white)
                .padding(16)
            } else {
                Brand.placeholder
            }
        }
    }

    /// Silver foil with a faint pattern of stars and an embossed «Сотрите», as on a lottery ticket.
    private var foil: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.86), Color(white: 0.66), Color(white: 0.92), Color(white: 0.6), Color(white: 0.82)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Canvas { context, size in
                let star = context.resolve(Text(verbatim: "✦").font(.system(size: 13)).foregroundColor(.white.opacity(0.35)))
                var row = 0
                var y: CGFloat = 14
                while y < size.height {
                    var x: CGFloat = row.isMultiple(of: 2) ? 12 : 30
                    while x < size.width {
                        context.draw(star, at: CGPoint(x: x, y: y))
                        x += 36
                    }
                    y += 30
                    row += 1
                }
            }
            VStack(spacing: 10) {
                Image(systemName: item == nil ? "rectangle.portrait.on.rectangle.portrait.angled.fill" : "hand.draw.fill")
                    .font(.system(size: 40))
                Text(item == nil ? "Возьмите карту" : "Сотрите")
                    .font(.title2.weight(.heavy))
                    .textCase(.uppercase)
                    .tracking(2)
                Text(item == nil ? "Под фольгой будет фильм на вечер" : "Под фольгой — фильм на вечер")
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.black.opacity(0.45))
            .shadow(color: .white.opacity(0.7), radius: 0, y: 1)
            .padding(24)
        }
    }

    private var scratches: Path {
        var path = Path()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: first)
            // A single point still leaves a round mark.
            if stroke.count == 1 { path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y)) }
            for point in stroke.dropFirst() { path.addLine(to: point) }
        }
        return path
    }

    // MARK: Scratching

    private func scratch(at point: CGPoint) {
        guard item != nil, !isOpen else { return }
        if !isDragging {
            strokes.append([])
            isDragging = true
        }
        strokes[strokes.count - 1].append(point)

        // Which cells of a coarse grid the brush has passed over, for how much is scratched.
        let cell = CGSize(width: Self.size.width / CGFloat(Self.columns), height: Self.size.height / CGFloat(Self.rows))
        let reach = Self.brush / 2 + max(cell.width, cell.height) / 2
        for row in 0..<Self.rows {
            for column in 0..<Self.columns {
                let center = CGPoint(x: (CGFloat(column) + 0.5) * cell.width, y: (CGFloat(row) + 0.5) * cell.height)
                if hypot(center.x - point.x, center.y - point.y) <= reach { scratched.insert(row * Self.columns + column) }
            }
        }
        if Double(scratched.count) / Double(Self.columns * Self.rows) >= Self.enough { open() }
    }

    private func open() {
        guard item != nil, !isOpen else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        withAnimation(.easeOut(duration: 0.45)) { isOpen = true }
        onReveal()
    }
}
