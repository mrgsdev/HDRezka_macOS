import SwiftUI

/// The countries visited by watching, as stamps on a page of «Итоги»: each with the day the first title from
/// it was watched in REZKA on this Mac and how many there have been. A stamp opens the country's list
/// on the site; below them, countries not visited yet.
struct FilmPassportView: View {
    @State private var isFilling = false

    private let stats = WatchStats.shared

    var body: some View {
        let stamps = FilmPassport.stamps(from: stats)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                cover(stamps)
                if stamps.isEmpty {
                    EmptyStateView(text: "Паспорт пока пуст: посмотрите что-нибудь от десяти минут — и первая страна поставит свой штамп.")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    panel("Штампы") {
                        Text("Штамп ставится с первого тайтла страны, золотая виза — с пятого, вид на жительство — с двадцатого.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 18)], spacing: 22) {
                            ForEach(stamps) { stamp in
                                NavigationLink(value: Self.listing(stamp.country)) {
                                    StampView(stamp: stamp)
                                }
                                .buttonStyle(.plain)
                                .help(stamp.hint)
                            }
                        }
                    }
                }
                let visited = Set(stamps.map(\.country))
                ForEach(World.continents) { continent in
                    let next = continent.countries.filter { !visited.contains($0) }
                    if !next.isEmpty {
                        panel("\(continent.name) · \(continent.countries.count - next.count) из \(continent.countries.count)") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 14)], spacing: 14) {
                                ForEach(next, id: \.self) { trip($0) }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Кинопаспорт")
        .task {
            // Titles watched before «Итоги» kept countries: once, from their pages.
            isFilling = true
            await stats.fillMissingFacts()
            isFilling = false
        }
    }

    // MARK: Cover

    /// Like the yearly goal's card in «Итоги»: what it is, the first country, and how many.
    private func cover(_ stamps: [PassportStamp]) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
                .frame(width: 56, height: 56)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Кинопаспорт")
                    .font(.title2.bold())
                Text("Страны, где вы побывали, глядя в экран REZKA на этом Mac.")
                    .foregroundStyle(.secondary)
                if let first = stamps.last {
                    Text("Первая страна — \(first.country), \(first.firstDay.formatted(.dateTime.day().month(.wide).year().locale(AppLanguage.locale)))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                let visas = stamps.filter { $0.level == .visa }.count
                let residences = stamps.filter { $0.level == .residence }.count
                if visas + residences > 0 {
                    Text("Золотых виз: \(visas) · Видов на жительство: \(residences)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if isFilling {
                    Label("Уточняем страны старых просмотров…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "\(stamps.count)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("Стран в паспорте")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    /// A country not visited yet: its flag in grey and a dashed outline, opening its list.
    private func trip(_ country: String) -> some View {
        NavigationLink(value: Self.listing(country)) {
            VStack(spacing: 6) {
                Text(verbatim: World.flag(for: country))
                    .font(.system(size: 30))
                    .grayscale(1)
                    .opacity(0.6)
                Text(verbatim: country)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(Rectangle())
            .hoverLift()
        }
        .buttonStyle(.plain)
    }

    private func panel(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Data

    private static func listing(_ country: String) -> Listing {
        .country(country)
    }
}

/// The passport's stamps, for its page and the achievements.
@MainActor
enum FilmPassport {
    /// Titles watched at least ten minutes count; a country's day is the first day any of them played.
    static func stamps(from stats: WatchStats) -> [PassportStamp] {
        var total: [String: Double] = [:]
        var first: [String: String] = [:]
        for (day, titles) in stats.days {
            for (postId, seconds) in titles {
                total[postId, default: 0] += seconds
                if first[postId].map({ day < $0 }) ?? true { first[postId] = day }
            }
        }
        var byCountry: [String: (day: String, titles: Int)] = [:]
        for (postId, seconds) in total where seconds >= 600 {
            guard let day = first[postId], let countries = stats.titles[postId]?.countries else { continue }
            for country in countries {
                let current = byCountry[country]
                byCountry[country] = (min(current?.day ?? day, day), (current?.titles ?? 0) + 1)
            }
        }
        return byCountry.compactMap { country, value in
            WatchStats.date(ofDay: value.day).map { PassportStamp(country: country, firstDay: $0, titles: value.titles) }
        }
        .sorted { $0.firstDay != $1.firstDay ? $0.firstDay > $1.firstDay : $0.country < $1.country }
    }
}

/// Opens the passport from «Итоги» through the stack's path, so its stamps can push country lists after it.
struct FilmPassportLink: Hashable {}

struct PassportStamp: Identifiable {
    enum Level {
        case stamp, visa, residence
    }

    /// Titles from a country for a gold visa and for a residence permit.
    static let visaAt = 5
    static let residenceAt = 20

    let country: String
    let firstDay: Date
    let titles: Int

    var id: String { country }

    var level: Level {
        titles >= Self.residenceAt ? .residence : titles >= Self.visaAt ? .visa : .stamp
    }

    /// The country, its titles and what the next level takes.
    var hint: String {
        switch level {
        case .stamp: String(localized: "\(country) · тайтлов: \(titles) · до визы ещё \(Self.visaAt - titles)")
        case .visa: String(localized: "\(country) · тайтлов: \(titles) · до вида на жительство ещё \(Self.residenceAt - titles)")
        case .residence: String(localized: "\(country) · тайтлов: \(titles) · вид на жительство")
        }
    }
}

/// An ink stamp: the flag, the country, the day of the first visit and how many titles since, in its
/// own ink, shape and tilt, the same every time. A visa is struck in gold; a residence permit is gold
/// and filled, with laurels round the flag.
private struct StampView: View {
    let stamp: PassportStamp

    /// Light enough to read on the dark panels, deep enough on the light ones.
    private static let inks: [Color] = [
        Color(red: 0.93, green: 0.38, blue: 0.38), Color(red: 0.40, green: 0.62, blue: 0.98), Color(red: 0.32, green: 0.78, blue: 0.52),
        Color(red: 0.72, green: 0.52, blue: 0.95), Color(red: 0.96, green: 0.62, blue: 0.30), Color(red: 0.28, green: 0.78, blue: 0.82),
    ]

    /// Stable across launches, unlike `hashValue`.
    private var seed: Int {
        stamp.country.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    }

    /// Deeper on the light panels, where pale gold would fade into them.
    private static let gold = LinearGradient(
        colors: [
            Brand.adaptive(light: NSColor(red: 0.9, green: 0.65, blue: 0.15, alpha: 1), dark: NSColor(red: 1, green: 0.86, blue: 0.45, alpha: 1)),
            Brand.adaptive(light: NSColor(red: 0.7, green: 0.45, blue: 0.08, alpha: 1), dark: NSColor(red: 0.86, green: 0.6, blue: 0.16, alpha: 1)),
        ],
        startPoint: .top, endPoint: .bottom
    )
    private static let goldGlow = Color(red: 1, green: 0.78, blue: 0.3)

    var body: some View {
        let level = stamp.level
        let ink = level == .stamp ? AnyShapeStyle(Self.inks[seed % Self.inks.count]) : AnyShapeStyle(Self.gold)
        let shape = seed % 3
        let border: CGFloat = level == .residence ? 3.5 : 2.5
        VStack(spacing: 3) {
            if level != .stamp {
                Text(level == .visa ? "Виза" : "Вид на жительство")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .lineLimit(1)
            }
            HStack(spacing: 2) {
                if level == .residence { Image(systemName: "laurel.leading").font(.system(size: 18)) }
                Text(verbatim: World.flag(for: stamp.country))
                    .font(.system(size: 30))
                if level == .residence { Image(systemName: "laurel.trailing").font(.system(size: 18)) }
            }
            Text(verbatim: stamp.country.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: stamp.firstDay.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(AppLanguage.locale)))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text(verbatim: "× \(stamp.titles)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .opacity(0.8)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: shape == 0 ? 136 : 154, height: shape == 0 ? 136 : (level == .stamp ? 112 : 124))
        .background {
            let fill = level == .residence ? AnyShapeStyle(Self.goldGlow.opacity(0.12)) : AnyShapeStyle(Color.clear)
            switch shape {
            case 0:
                Circle().fill(fill)
                    .overlay(Circle().strokeBorder(ink, lineWidth: border))
                    .overlay(Circle().strokeBorder(ink, lineWidth: 1).padding(5))
            case 1:
                Ellipse().fill(fill)
                    .overlay(Ellipse().strokeBorder(ink, lineWidth: border))
                    .overlay(Ellipse().strokeBorder(ink, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).padding(5))
            default:
                RoundedRectangle(cornerRadius: 10).fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ink, lineWidth: border))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ink, lineWidth: 1).padding(5))
            }
        }
        // Gold catches the light; ink never takes evenly.
        .shadow(color: level == .stamp ? .clear : Self.goldGlow.opacity(level == .residence ? 0.5 : 0.3), radius: level == .residence ? 10 : 6)
        .opacity(level == .stamp ? 0.82 : 1)
        .rotationEffect(.degrees(Double(seed % 17) - 8))
        .frame(maxWidth: .infinity, minHeight: 140)
        .contentShape(Rectangle())
    }
}
