import SwiftUI

/// The first screen before signing in: posters orbiting the REZKA logo, rushing round now and then,
/// until one of them comes forward and grows over the window into the sign-in screen's background.
struct PosterIntro: View {
    let onFinish: () -> Void

    /// Posters on the orbits, from the asset catalog; more can be added to the list.
    static let posters = ["IntroPoster1", "IntroPoster2", "IntroPoster3", "IntroPosterOdyssey"]
    /// The poster that comes forward, and the still it turns into: the sign-in screen's background.
    static let hero = "IntroPosterOdyssey"
    static let heroStill = "LoginBackdrop3"

    // When each part ends, in seconds from the start.
    private static let spinEnd = 3.6
    private static let gatherEnd = 4.4
    private static let growEnd = 5.4

    @State private var start = Date()
    @State private var isFinished = false

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: isFinished)) { context in
                scene(at: context.date.timeIntervalSince(start), size: proxy.size)
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .overlay(alignment: .bottomTrailing) {
            Button("Пропустить", action: finish)
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.55))
                .padding(24)
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.growEnd))
            finish()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("REZKA")
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        onFinish()
    }

    // MARK: Scene

    private func scene(at time: Double, size: CGSize) -> some View {
        let orbitTime = min(time, Self.spinEnd)
        let gather = Self.ease((time - Self.spinEnd) / (Self.gatherEnd - Self.spinEnd))
        let grow = Self.ease((time - Self.gatherEnd) / (Self.growEnd - Self.gatherEnd))
        let cards = Self.cards.map { place($0, at: orbitTime, in: size) }
        let heroIndex = Self.heroIndex(in: Self.cards.map { place($0, at: Self.spinEnd, in: size) })

        return ZStack {
            ForEach(cards.indices, id: \.self) { index in
                let card = cards[index]
                if index != heroIndex || time < Self.spinEnd {
                    poster(card.name, width: card.width)
                        .scaleEffect(1 - 0.3 * gather)
                        .opacity(card.opacity * (1 - gather))
                        .blur(radius: card.blur)
                        .position(card.center)
                        .zIndex(card.depth)
                }
            }

            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: min(380, size.width * 0.3))
                .shadow(color: .black.opacity(0.8), radius: 24)
                .scaleEffect(1 + 0.15 * gather)
                .opacity(1 - gather)
                .position(x: size.width / 2, y: size.height / 2)
                .zIndex(2)

            if time >= Self.spinEnd {
                hero(from: cards[heroIndex], gather: gather, grow: grow, in: size)
                    .zIndex(3)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// The hero leaves its orbit for the middle, then grows to the whole window while the poster
    /// gives way to the wide still and darkens as the sign-in screen does.
    private func hero(from card: PlacedCard, gather: Double, grow: Double, in size: CGSize) -> some View {
        let posterWidth = size.height * 0.62 / 1.5
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        let center = Self.mix(card.center, middle, gather)
        let gatheredWidth = Self.mix(card.width, posterWidth, gather)
        let width = Self.mix(gatheredWidth, size.width, grow)
        let height = Self.mix(gatheredWidth * 1.5, size.height, grow)
        let stillShare = min(max((grow - 0.25) / 0.55, 0), 1)
        // Each picture framed on its own, so each fills the card from its middle.
        return ZStack {
            filled(Self.heroStill, width: width, height: height)
            filled(Self.hero, width: width, height: height).opacity(1 - stillShare)
            Color.black.opacity(0.45 * grow)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12 * (1 - grow), style: .continuous))
        .shadow(color: .black.opacity(0.6 * (1 - grow)), radius: 30, y: 12)
        .position(center)
    }

    private func filled(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
    }

    private func poster(_ name: String, width: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }

    // MARK: Orbits

    /// A poster's seat on one of the orbits.
    private struct Card {
        let name: String
        let orbit: Orbit
        /// Where on its orbit, as a share of a full turn.
        let slot: Double
    }

    /// A tilted ring the posters run round: wide across, flattened top to bottom, the near side lower
    /// for one ring and higher for the other, so together they look like a sphere turning.
    private struct Orbit {
        let radiusX: CGFloat
        let radiusY: CGFloat
        /// +1 brings the near side down, -1 up.
        let tilt: CGFloat
        /// Turns per second between the rushes; negative runs the other way.
        let speed: Double
        let count: Int
    }

    private struct PlacedCard {
        let name: String
        let center: CGPoint
        let width: CGFloat
        let depth: Double
        let opacity: Double
        let blur: CGFloat
    }

    private static let orbits = [
        Orbit(radiusX: 0.42, radiusY: 0.3, tilt: 1, speed: 0.05, count: 10),
        Orbit(radiusX: 0.26, radiusY: 0.2, tilt: -1, speed: -0.07, count: 7),
    ]

    private static let cards: [Card] = {
        var cards: [Card] = []
        var poster = 0
        for orbit in orbits {
            for seat in 0..<orbit.count {
                cards.append(Card(name: posters[poster % posters.count], orbit: orbit, slot: Double(seat) / Double(orbit.count)))
                poster += 1
            }
        }
        return cards
    }()

    /// The rushes: two quick extra spins on top of the steady turn, as in the reference.
    private static func rush(_ time: Double) -> Double {
        0.22 * (sigmoid((time - 0.8) / 0.1) + sigmoid((time - 2.5) / 0.1))
    }

    private static func rushSpeed(_ time: Double) -> Double {
        let first = sigmoid((time - 0.8) / 0.1), second = sigmoid((time - 2.5) / 0.1)
        return 0.22 * (first * (1 - first) + second * (1 - second)) / 0.1
    }

    private func place(_ card: Card, at time: Double, in size: CGSize) -> PlacedCard {
        let orbit = card.orbit
        let direction = orbit.speed < 0 ? -1.0 : 1.0
        let turn = card.slot + orbit.speed * time + direction * Self.rush(time)
        let angle = turn * 2 * .pi
        let depth = cos(angle)
        let near = (depth + 1) / 2
        let base = min(size.width, size.height) * 0.2
        let speed = abs(orbit.speed) + Self.rushSpeed(time)
        return PlacedCard(
            name: card.name,
            center: CGPoint(
                x: size.width / 2 + size.width * orbit.radiusX * sin(angle),
                y: size.height / 2 + size.height * orbit.radiusY * depth * orbit.tilt
            ),
            width: base * (0.6 + 0.4 * near),
            depth: depth,
            opacity: 0.45 + 0.55 * near,
            blur: (1 - near) * 2.5 + min(8, speed * 18)
        )
    }

    /// The hero poster nearest the viewer when the spin ends.
    private static func heroIndex(in cards: [PlacedCard]) -> Int {
        cards.indices
            .filter { cards[$0].name == hero }
            .max { cards[$0].depth < cards[$1].depth } ?? 0
    }

    // MARK: Curves

    private static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    private static func ease(_ progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    private static func mix(_ from: CGFloat, _ to: CGFloat, _ share: Double) -> CGFloat {
        from + (to - from) * share
    }

    private static func mix(_ from: CGPoint, _ to: CGPoint, _ share: Double) -> CGPoint {
        CGPoint(x: mix(from.x, to.x, share), y: mix(from.y, to.y, share))
    }
}
