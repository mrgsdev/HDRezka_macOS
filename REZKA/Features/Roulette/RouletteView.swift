import SwiftUI

/// "Что посмотреть?": a reel of posters that spins to a random title, or shows one at once,
/// with what it landed on and buttons to watch it or roll again.
struct RouletteView: View {
    @Bindable var model: RouletteModel

    private var menu: SectionMenu? { SiteMenu.shared.menus[model.section] }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                filters
                    .padding(.horizontal, 28)
                RouletteReel(model: model)
                    .frame(height: 420)
                    .overlay {
                        if model.phase == .loading { LoadingPill() }
                    }

                if model.phase == .done, let pick = model.pick {
                    RouletteResult(model: pick)
                        .padding(.horizontal, 28)
                        .transition(.opacity.combined(with: .offset(y: 12)))
                } else if let error = model.error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                controls
            }
            .padding(.vertical, 24)
            .animation(.easeOut(duration: 0.3), value: model.phase == .done)
            .animation(.easeOut(duration: 0.25), value: model.phase == .loading)
        }
        .navigationTitle("Что посмотреть?")
        .navigationSubtitle(model.section.title)
        .task { await SiteMenu.shared.loadIfNeeded() }
        .task(id: model.key) {
            // A pause first, so dragging the years or ticking several genres loads once.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await model.prepare()
        }
    }

    /// As on Kinopoisk's random film page: what kind, which genres and countries, and which years.
    private var filters: some View {
        FlowLayout(spacing: 12, lineSpacing: 12) {
            Picker("Раздел", selection: $model.section) {
                ForEach(CatalogSection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            MultiChoice(
                empty: String(localized: "Все жанры"), many: String(localized: "Жанры"),
                options: (menu?.genres ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
                selection: $model.genres, label: \.title
            )
            .disabled(menu == nil)

            MultiChoice(
                empty: String(localized: "Все страны"), many: String(localized: "Страны"),
                options: RouletteModel.countryOptions, selection: $model.countries, label: { $0 }
            )

            YearRangeSlider(range: $model.years, bounds: RouletteModel.allYears)
                .frame(width: 300)

            if model.hasFilters {
                Button("Сбросить", action: model.resetFilters)
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(model.phase == .spinning)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.roll(animated: true) }
            } label: {
                Label(model.phase == .done ? "Крутить ещё" : "Крутить", systemImage: "dice.fill")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            Button {
                Task { await model.roll(animated: false) }
            } label: {
                Label("Без анимации", systemImage: "forward.end.fill")
            }
        }
        .controlSize(.large)
        // Nothing to roll from until the first list has come, unless it failed and a roll should retry.
        .disabled(model.isBusy || (model.reel.isEmpty && model.error == nil))
    }
}

/// The posters in a row: the one in the middle full size and lit from behind, the others smaller
/// and dimmer the further out. While the reel spins, its position comes from the spin each frame.
private struct RouletteReel: View {
    let model: RouletteModel

    /// Space between neighbouring cards whatever their size.
    private static let gap: CGFloat = 18
    /// Cards shrink this much per step from the middle, down to `minScale`.
    private static let shrink: CGFloat = 0.16
    private static let minScale: CGFloat = 0.62

    var body: some View {
        GeometryReader { proxy in
            let width = min(230, (proxy.size.height - 50) / 1.5)
            TimelineView(.animation(paused: model.spin == nil)) { context in
                let position = model.spin?.position(at: context.date) ?? model.position
                ZStack {
                    glow(width: width)
                    ForEach(visibleIndices(around: position), id: \.self) { index in
                        let distance = Double(index) - position
                        card(model.reel[index], width: width, distance: distance)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func visibleIndices(around position: Double) -> [Int] {
        guard !model.reel.isEmpty else { return [] }
        let middle = Int(position.rounded())
        return Array(max(0, middle - 6)...min(model.reel.count - 1, middle + 6))
    }

    @ViewBuilder
    private func card(_ item: MediaItem, width: CGFloat, distance: Double) -> some View {
        let away = abs(CGFloat(distance))
        let isPick = model.phase == .done && away < 0.01
        let poster = ReelCard(item: item, width: width, isLit: away < 0.5)
            .scaleEffect(max(Self.minScale, 1 - Self.shrink * away))
            .opacity(1 - 0.28 * min(away, 2.5))
            .blur(radius: min(away, 2) * 1.2)
            .offset(x: offset(for: CGFloat(distance), width: width))
            .zIndex(-Double(away))
        if isPick {
            NavigationLink(value: item) { poster }
                .buttonStyle(.plain)
                .help("Открыть карточку")
        } else {
            poster
        }
    }

    /// Centre-to-centre distance summed over the shrinking widths between here and the middle,
    /// so the gaps stay even as the cards get smaller.
    private func offset(for distance: CGFloat, width: CGFloat) -> CGFloat {
        let away = abs(distance)
        let flat = (1 - Self.minScale) / Self.shrink
        let covered = away <= flat
            ? away - Self.shrink / 2 * away * away
            : flat - Self.shrink / 2 * flat * flat + Self.minScale * (away - flat)
        return (covered * width + Self.gap * away) * (distance < 0 ? -1 : 1)
    }

    private func glow(width: CGFloat) -> some View {
        let color = model.glow ?? Color(red: 0.85, green: 0.1, blue: 0.12)
        return Ellipse()
            .fill(RadialGradient(colors: [color.opacity(0.7), color.opacity(0)], center: .center, startRadius: 0, endRadius: width * 1.5))
            // Within the reel's height, so the scroll view's edge never cuts it off straight.
            .frame(width: width * 4.2, height: width * 1.55)
            .blur(radius: 24)
            .allowsHitTesting(false)
    }
}

/// A poster with its title and year over the bottom, as on the reel.
private struct ReelCard: View {
    let item: MediaItem
    let width: CGFloat
    let isLit: Bool

    var body: some View {
        PosterImage(url: item.posterURL)
            .frame(width: width, height: width * 1.5)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(14)
                .padding(.top, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(isLit ? 0.25 : 0.1)))
            .shadow(color: .black.opacity(isLit ? 0.5 : 0.2), radius: isLit ? 24 : 8, y: 10)
    }
}

/// What the reel stopped on: the title, ratings and description from its page, and the buttons to watch it.
private struct RouletteResult: View {
    let model: DetailsModel
    @Environment(WatchProgressStore.self) private var progress

    var body: some View {
        VStack(spacing: 10) {
            Text(model.item.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            if !model.item.subtitle.isEmpty {
                Text(model.item.subtitle)
                    .foregroundStyle(.secondary)
            }
            if let details = model.details {
                if let ratings = details.info("Рейтинги") {
                    Label(ratings, systemImage: "star.fill")
                        .foregroundStyle(Brand.gold)
                }
                if !details.description.isEmpty {
                    Text(details.description)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 680)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            HStack(spacing: 12) {
                watchButton
                NavigationLink(value: model.item) {
                    Label("Открыть карточку", systemImage: "info.circle")
                }
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
    }

    /// Same choice as the title page's main button: the next episode, or the film from where it stopped.
    @ViewBuilder
    private var watchButton: some View {
        if let details = model.details, details.upcomingStatus == nil {
            if details.isSeries {
                if let target = model.resumeEpisode(progress: progress) {
                    Button {
                        model.play(episode: target.episode)
                    } label: {
                        Label(target.entry == nil ? "Смотреть" : "Продолжить", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else if model.isLoadingEpisodes {
                    ProgressView().controlSize(.small)
                }
            } else {
                let entry = progress.entry(postId: details.postId, seasonId: nil, episodeId: nil)
                let resumes = entry.map { !$0.isFinished && $0.position > 30 } ?? false
                Button {
                    model.play(from: resumes ? nil : 0)
                } label: {
                    Label(resumes ? "Продолжить" : "Смотреть", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// A button that opens a list of checkboxes, for picking any number of genres or countries.
private struct MultiChoice<Option: Hashable>: View {
    /// Shown with nothing picked, e.g. "Все жанры".
    let empty: String
    /// Shown with the count when several are picked, e.g. "Жанры: 3".
    let many: String
    let options: [Option]
    @Binding var selection: Set<Option>
    let label: (Option) -> String

    @State private var isOpen = false

    private var summary: String {
        switch selection.count {
        case 0: empty
        case 1: selection.first.map(label) ?? empty
        default: "\(many): \(selection.count)"
        }
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(summary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            Toggle(label(option), isOn: Binding(
                                get: { selection.contains(option) },
                                set: { if $0 { selection.insert(option) } else { selection.remove(option) } }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 360)
                Button("Сбросить") { selection = [] }
                    .disabled(selection.isEmpty)
            }
            .padding(16)
            .frame(width: 380)
        }
    }
}

/// Two handles on one track for a span of years, like the slider on Kinopoisk's random film page.
private struct YearRangeSlider: View {
    @Binding var range: ClosedRange<Int>
    let bounds: ClosedRange<Int>

    private let handle: CGFloat = 16

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(verbatim: String(range.lowerBound))
                Spacer()
                Text("Годы")
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(verbatim: String(range.upperBound))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let track = proxy.size.width - handle
                let x = { (year: Int) in CGFloat(year - bounds.lowerBound) / CGFloat(bounds.count - 1) * track }
                let year = { (x: CGFloat) in bounds.lowerBound + Int((min(max(x, 0), track) / track * CGFloat(bounds.count - 1)).rounded()) }
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 4)
                        .padding(.horizontal, handle / 2)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: x(range.upperBound) - x(range.lowerBound), height: 4)
                        .offset(x: x(range.lowerBound) + handle / 2)
                    knob
                        .offset(x: x(range.lowerBound))
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("years")).onChanged { value in
                            range = min(year(value.location.x - handle / 2), range.upperBound)...range.upperBound
                        })
                    knob
                        .offset(x: x(range.upperBound))
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("years")).onChanged { value in
                            range = range.lowerBound...max(year(value.location.x - handle / 2), range.lowerBound)
                        })
                }
                .frame(maxHeight: .infinity)
                .coordinateSpace(.named("years"))
            }
            .frame(height: handle + 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Годы")
        .accessibilityValue(Text(verbatim: "\(range.lowerBound)–\(range.upperBound)"))
    }

    private var knob: some View {
        Circle()
            .fill(.white)
            .frame(width: handle, height: handle)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .overlay(Circle().strokeBorder(.black.opacity(0.1)))
    }
}

/// A light running round a border, white fading into violet, as on a button that glows while
/// something happens behind it.
private struct GlowingBorder: View {
    let cornerRadius: CGFloat
    /// Seconds per round.
    var period: Double = 2.4

    private static let light: [Gradient.Stop] = [
        .init(color: .clear, location: 0),
        .init(color: .clear, location: 0.5),
        .init(color: Color(red: 0.3, green: 0.35, blue: 1), location: 0.72),
        .init(color: Color(red: 0.8, green: 0.3, blue: 1), location: 0.86),
        .init(color: .white, location: 0.96),
        .init(color: .clear, location: 1),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let gradient = AngularGradient(stops: Self.light, center: .center, angle: .degrees(turn * 360))
            // A corner radius past half the height draws a capsule.
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                shape.strokeBorder(gradient, lineWidth: 4).blur(radius: 5)
                shape.strokeBorder(gradient, lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Over the reel while titles for the new filters load: a dark pill with a light running round it.
private struct LoadingPill: View {
    var body: some View {
        Text("Загружается, подождите…")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            }
            .overlay { GlowingBorder(cornerRadius: 100) }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
