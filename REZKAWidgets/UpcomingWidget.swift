import SwiftUI
import WidgetKit

@main
struct REZKAWidgets: WidgetBundle {
    var body: some Widget {
        UpcomingWidget()
    }
}

/// "Скоро выйдет": new and coming episodes of the series in "Продолжить просмотр". The app finds them
/// and leaves a list in the shared folder; the widget only draws it and moves the dates on each midnight.
struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedContainer.upcomingWidgetKind, provider: UpcomingProvider()) { entry in
            UpcomingView(entry: entry)
        }
        .configurationDisplayName("Скоро выйдет")
        .description("Новые и ближайшие серии из «Продолжить просмотр» и фильмы, о выходе которых вы просили напомнить.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Timeline

struct UpcomingEntry: TimelineEntry {
    let date: Date
    let snapshot: UpcomingSnapshot?
}

struct UpcomingProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingEntry {
        UpcomingEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingEntry) -> Void) {
        let snapshot = SharedContainer.readSnapshot()
        // The widget gallery shows an example until the app has found something real.
        let hasRows = snapshot?.state == .ready && snapshot?.items.isEmpty == false
        completion(UpcomingEntry(date: Date(), snapshot: context.isPreview && !hasRows ? .sample : snapshot))
    }

    /// The same list redrawn at each of the next midnights, so "Сегодня" and "Завтра" move on even while
    /// the app is closed. The app asks for a new timeline whenever the list changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingEntry>) -> Void) {
        let snapshot = SharedContainer.readSnapshot()
        let calendar = Calendar.current
        var dates = [Date()]
        var day = calendar.startOfDay(for: Date())
        for _ in 0..<7 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            dates.append(next)
            day = next
        }
        completion(Timeline(entries: dates.map { UpcomingEntry(date: $0, snapshot: snapshot) }, policy: .atEnd))
    }
}

// MARK: Rows

/// One series as the widget shows it on a given day.
private struct Row: Identifiable {
    enum Group: Int {
        case released, late, today, tomorrow, soon, later
        /// A title the site is still waiting for, with no date to count down to.
        case awaited
    }

    let item: UpcomingSnapshot.Item
    let group: Group
    /// "Вышла", "Сегодня", "Пт, 21".
    let status: String
    /// "Пт, 21 ноября".
    let date: String
    /// The calendar leaf: "ПТ" over "21" within a week, "ДЕК" over "12" further on.
    let leafTop: String
    let leafDay: String
    /// Shown on the leaf instead of a date: an hourglass for a title still awaited.
    let leafSymbol: String?
    let longEpisode: String

    var id: String { item.id }
    var title: String { item.title }
    var url: URL { AppLink.title(path: item.path, title: item.title) ?? URL(string: "\(AppLink.scheme)://")! }

    /// Red for new, amber for late, the brand's teal for today and tomorrow; nil reads as plain.
    var tint: Color? {
        switch group {
        case .released: Palette.red
        case .late: Palette.amber
        case .today, .tomorrow: Palette.teal
        case .soon, .later, .awaited: nil
        }
    }

    /// Filled chips and leaves for what needs attention now; tomorrow only gets an outline.
    var isFilled: Bool {
        group == .released || group == .late || group == .today
    }

    var poster: NSImage? {
        guard let name = item.poster, let folder = SharedContainer.postersURL else { return nil }
        return NSImage(contentsOf: folder.appending(path: name))
    }

    /// The rows for `day`: an episode out longer than a few days, or late for more than a week, drops off;
    /// one whose day has come but that the app hasn't seen on the site yet counts as late.
    static func make(_ items: [UpcomingSnapshot.Item], on day: Date, words: Words) -> [Row] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: day)
        let rows = items.compactMap { item -> Row? in
            let air = item.airDate
            let offset = air.flatMap { calendar.dateComponents([.day], from: today, to: $0).day }
            let group: Group
            let status: String
            switch (item.status, offset) {
            case let (.released, offset?):
                guard offset >= -3 else { return nil }
                group = .released
                status = item.isTitle ? words("Вышел") : words("Вышла")
            case let (.late, offset?), let (.upcoming, offset?):
                switch offset {
                // A title's release date has passed, but nobody has seen it on the site yet.
                case ..<0 where item.isTitle: group = .awaited; status = words("Ждём")
                case ..<(-7): return nil
                case ..<0: group = .late; status = words("Ожидается")
                case 0: group = .today; status = words("Сегодня")
                case 1: group = .tomorrow; status = words("Завтра")
                case 2...6: group = .soon; status = words.format(air ?? today, template: "EEEd")
                default: group = .later; status = words.format(air ?? today, template: "dMMM")
                }
            case (.released, nil):
                return nil
            case (.late, nil), (.upcoming, nil), (.awaited, _):
                group = .awaited
                status = words("Ждём")
            }
            let leafDate = air ?? today
            let nearby = offset.map { (-7...6).contains($0) } ?? false
            return Row(item: item, group: group, status: status,
                       date: air.map { words.format($0, template: "EEEdMMMM") } ?? "",
                       leafTop: words.format(leafDate, template: nearby ? "EEE" : "LLL")
                           .replacingOccurrences(of: ".", with: "").uppercased(with: words.locale),
                       leafDay: words.format(leafDate, template: "d"),
                       leafSymbol: group == .awaited ? "hourglass" : nil,
                       longEpisode: Self.longEpisode(item, words: words))
        }
        return rows.sorted {
            if $0.group != $1.group { return $0.group.rawValue < $1.group.rawValue }
            switch $0.group {
            case .released: return $0.item.airDay > $1.item.airDay
            // Their dates are long past or missing, so by name, as the app sorts them.
            case .awaited: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            default: return $0.item.airDay < $1.item.airDay
            }
        }
    }

    /// "5 сезон, 3 серия", or "Фильм" for a whole title.
    private static func longEpisode(_ item: UpcomingSnapshot.Item, words: Words) -> String {
        if let kind = item.kind {
            switch kind {
            case "series": return words("Сериал")
            case "cartoon": return words("Мультфильм")
            case "anime": return words("Аниме")
            case "show": return words("Передача")
            default: return words("Фильм")
            }
        }
        return switch (item.season, item.episode) {
        case let (season?, episode?): String(format: words("%@ сезон, %@ серия"), season, episode)
        case let (nil, episode?): String(format: words("%@ серия"), episode)
        default: ""
        }
    }
}

/// The widget's words in the app's interface language, which may differ from the system's.
struct Words {
    private let bundle: Bundle?
    let locale: Locale

    init(language: String?) {
        let language = language ?? Bundle.main.preferredLocalizations.first ?? "ru"
        locale = Locale(identifier: language == "en" ? "en_US" : "ru_RU")
        // The texts are written in Russian; any other language comes from its own table.
        bundle = language == "ru" ? nil : Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    func callAsFunction(_ key: String) -> String {
        bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    /// A date from a template, capitalized: "Пт, 21", "12 дек.", "Пт, 21 ноября".
    func format(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased(with: locale) + text.dropFirst()
    }
}

// MARK: Look

/// The app's own colors: navy and its light gray twin for the canvas, teal for the accent.
private enum Palette {
    static let teal = Color(red: 0.227, green: 0.573, blue: 0.651)
    static let red = Color(red: 0.898, green: 0.243, blue: 0.267)
    static let amber = Color(red: 0.918, green: 0.561, blue: 0.098)
    static let navy = Color(red: 2 / 255, green: 18 / 255, blue: 25 / 255)
    static let deepTeal = Color(red: 10 / 255, green: 32 / 255, blue: 42 / 255)
    static let mist = Color(red: 245 / 255, green: 248 / 255, blue: 250 / 255)
    static let fog = Color(red: 236 / 255, green: 241 / 255, blue: 244 / 255)

    static func canvasTop(_ scheme: ColorScheme) -> Color { scheme == .dark ? deepTeal : mist }
    static func canvasBottom(_ scheme: ColorScheme) -> Color { scheme == .dark ? navy : fog }
}

/// The brand canvas with the first poster's colors glowing through it, like a title page in the app.
private struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    let image: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.canvasTop(scheme), Palette.canvasBottom(scheme)],
                           startPoint: .top, endPoint: .bottom)
            if let image {
                FilledImage(image: image)
                    .blur(radius: 46)
                    .saturation(1.3)
                    .opacity(scheme == .dark ? 0.55 : 0.4)
                LinearGradient(colors: [.clear, Palette.canvasBottom(scheme).opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

/// An image that covers whatever space it is given without ever asking for more.
private struct FilledImage: View {
    let image: NSImage

    var body: some View {
        Color.clear
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
    }
}

/// The small size: the poster fills it and fades into the dark under the title.
private struct PosterBackdrop: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.deepTeal, Palette.navy], startPoint: .top, endPoint: .bottom)
            if let image {
                FilledImage(image: image)
            } else {
                // No poster yet: the brand's teal glow and a large faint TV instead.
                RadialGradient(colors: [Palette.teal.opacity(0.55), .clear], center: .topTrailing,
                               startRadius: 0, endRadius: 170)
                Image(systemName: "play.tv")
                    .font(.system(size: 84, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.09))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 14, y: 6)
            }
            LinearGradient(stops: [
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .clear, location: 0.28),
                .init(color: .black.opacity(0.35), location: 0.5),
                .init(color: .black.opacity(0.85), location: 0.78),
                .init(color: .black.opacity(0.95), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct PosterCard: View {
    let image: NSImage?
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = 8

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Palette.teal.opacity(0.55), Palette.navy.opacity(0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "play.tv")
                    .font(.system(size: width * 0.28, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }
}

/// "ВЫШЛА", "СЕГОДНЯ", "ПТ, 21" in a capsule.
private struct StatusChip: View {
    let row: Row
    /// Over a poster a plain chip goes frosted instead of gray.
    var onPoster = false

    var body: some View {
        HStack(spacing: 4) {
            if row.group == .released {
                Circle().frame(width: 5, height: 5)
            }
            Text(verbatim: row.status.uppercased())
                .tracking(0.4)
        }
        .font(.system(size: 9.5, weight: .heavy))
        .lineLimit(1)
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background { background }
        .widgetAccentable()
    }

    private var foreground: Color {
        if row.isFilled { return .white }
        return row.tint ?? (onPoster ? .white : .secondary)
    }

    @ViewBuilder private var background: some View {
        if let tint = row.tint, row.isFilled {
            Capsule().fill(tint)
        } else if let tint = row.tint {
            Capsule().strokeBorder(tint, lineWidth: 1)
        } else if onPoster {
            Capsule().fill(.ultraThinMaterial)
        } else {
            Capsule().fill(Color.primary.opacity(0.08))
        }
    }
}

/// A tear-off calendar leaf: weekday or month on top, the day under it.
private struct DayLeaf: View {
    let row: Row
    var width: CGFloat = 34
    var height: CGFloat = 36

    var body: some View {
        Group {
            if let symbol = row.leafSymbol {
                Image(systemName: symbol)
                    .font(.system(size: height * 0.4, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    Text(verbatim: row.leafTop)
                        .font(.system(size: height * 0.22, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(topColor)
                    Text(verbatim: row.leafDay)
                        .font(.system(size: height * 0.44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(row.isFilled ? .white : .primary)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: width, height: height)
        .background {
            let shape = RoundedRectangle(cornerRadius: height * 0.24, style: .continuous)
            if let tint = row.tint, row.isFilled {
                shape.fill(tint)
            } else if let tint = row.tint {
                shape.fill(tint.opacity(0.12)).overlay(shape.strokeBorder(tint.opacity(0.7), lineWidth: 1))
            } else {
                shape.fill(Color.primary.opacity(0.07))
            }
        }
        .widgetAccentable()
    }

    private var topColor: Color {
        if row.isFilled { return .white.opacity(0.85) }
        return row.tint ?? .secondary
    }
}

// MARK: Views

struct UpcomingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingEntry

    var body: some View {
        let words = Words(language: entry.snapshot?.language)
        if let snapshot = entry.snapshot {
            switch snapshot.state {
            case .signedOut:
                MessageView(symbol: "person.crop.circle", title: words("Войдите в REZKA"),
                            detail: words("Виджет показывает сериалы из «Продолжить просмотр»."))
                    .containerBackground(for: .widget) { AmbientBackground(image: nil) }
            case .ready:
                let rows = Row.make(snapshot.items, on: entry.date, words: words)
                if rows.isEmpty {
                    MessageView(symbol: "calendar", title: words("Ближайших серий нет"),
                                detail: words("Здесь появятся новые серии из «Продолжить просмотр» и фильмы с «Напомнить о выходе»."))
                        .containerBackground(for: .widget) { AmbientBackground(image: nil) }
                } else {
                    switch family {
                    case .systemSmall:
                        SmallView(rows: rows)
                            .containerBackground(for: .widget) { PosterBackdrop(image: rows[0].poster) }
                    case .systemLarge:
                        LargeView(rows: rows, words: words)
                            .containerBackground(for: .widget) { AmbientBackground(image: rows[0].poster) }
                    default:
                        MediumView(rows: rows, words: words)
                            .containerBackground(for: .widget) { AmbientBackground(image: rows[0].poster) }
                    }
                }
            }
        } else {
            MessageView(symbol: "calendar", title: words("Откройте REZKA"),
                        detail: words("После этого здесь появятся ближайшие серии."))
                .containerBackground(for: .widget) { AmbientBackground(image: nil) }
        }
    }
}

private struct SmallView: View {
    let rows: [Row]

    var body: some View {
        let row = rows[0]
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                StatusChip(row: row, onPoster: true)
                Spacer(minLength: 4)
                if rows.count > 1 {
                    MoreBadge(count: rows.count - 1)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: row.title)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(2)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            Text(verbatim: row.longEpisode)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .padding(.top, 2)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(row.url)
    }
}

/// "+4" on frosted glass: how many more titles the widget has than it shows.
private struct MoreBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: "+\(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
    }
}

private struct MediumView: View {
    let rows: [Row]
    let words: Words

    var body: some View {
        let hero = rows[0]
        let rest = Array(rows.dropFirst().prefix(2))
        HStack(alignment: .top, spacing: 14) {
            Link(destination: hero.url) {
                PosterCard(image: hero.poster, width: 86, height: 129)
            }
            .overlay(alignment: .topLeading) {
                // What doesn't fit: everything after the two rows on the right.
                if rows.count > rest.count + 1 {
                    MoreBadge(count: rows.count - rest.count - 1)
                        .padding(5)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Link(destination: hero.url) {
                    VStack(alignment: .leading, spacing: 4) {
                        StatusChip(row: hero)
                        Text(verbatim: hero.title)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(rest.isEmpty ? 3 : 1)
                            .padding(.top, 2)
                        Text(verbatim: hero.longEpisode)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        // Alone, the series has room for its air date too.
                        if rest.isEmpty, !hero.date.isEmpty {
                            Text(verbatim: hero.date)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(rest) { row in
                        Link(destination: row.url) {
                            HStack(spacing: 9) {
                                DayLeaf(row: row, width: 28, height: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: row.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text(verbatim: row.longEpisode)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct LargeView: View {
    static let listLimit = 4
    let rows: [Row]
    let words: Words

    var body: some View {
        let hero = rows[0]
        let rest = Array(rows.dropFirst().prefix(Self.listLimit))
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(Palette.teal)
                    .widgetAccentable()
                Text(verbatim: words("Скоро выйдет"))
                Spacer(minLength: 4)
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 11)
                    .opacity(0.85)
            }
            .font(.system(size: 13, weight: .bold))

            // With little below it, the first series gets the room: a larger poster and title.
            let roomy = rest.count < 2
            Link(destination: hero.url) {
                HStack(spacing: roomy ? 16 : 12) {
                    PosterCard(image: hero.poster, width: roomy ? 120 : 64, height: roomy ? 180 : 96, radius: roomy ? 10 : 8)
                    VStack(alignment: .leading, spacing: 4) {
                        StatusChip(row: hero)
                        Text(verbatim: hero.title)
                            .font(.system(size: roomy ? 20 : 17, weight: .bold))
                            .lineLimit(roomy ? 3 : 2)
                            // Takes the lines it needs: otherwise the card cut a long name to two.
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 1)
                        Text(verbatim: hero.longEpisode)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !hero.date.isEmpty {
                            Text(verbatim: hero.date)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(rest) { row in
                    Link(destination: row.url) {
                        HStack(spacing: 11) {
                            DayLeaf(row: row)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: row.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Text(verbatim: row.longEpisode)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if row.tint != nil || row.group == .awaited {
                                Text(verbatim: row.status)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(row.tint ?? .secondary)
                                    .widgetAccentable()
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            if rows.count > rest.count + 1 {
                Text(verbatim: String(format: words("и ещё %ld"), rows.count - rest.count - 1))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MessageView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.teal))
                .widgetAccentable()
            Spacer(minLength: 8)
            Text(verbatim: title)
                .font(.system(size: 14, weight: .bold))
            Text(verbatim: detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: Example

extension UpcomingSnapshot {
    /// For the widget gallery and placeholders: made-up series around today.
    static var sample: UpcomingSnapshot {
        let calendar = Calendar.current
        func day(_ offset: Int) -> String {
            let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        return UpcomingSnapshot(
            state: .ready,
            language: Bundle.main.preferredLocalizations.first ?? "ru",
            updatedAt: Date(),
            items: [
                Item(path: "/sample-1", title: "Северный ветер", season: "2", episode: "5", airDay: day(-1), status: .released, poster: nil),
                Item(path: "/sample-2", title: "Ночная смена", season: "1", episode: "8", airDay: day(0), status: .upcoming, poster: nil),
                Item(path: "/sample-3", title: "Тихая гавань", season: "3", episode: "2", airDay: day(1), status: .upcoming, poster: nil),
                Item(path: "/sample-4", title: "Город у моря", season: "1", episode: "4", airDay: day(3), status: .upcoming, poster: nil),
                Item(path: "/sample-5", title: "Последний рейс", season: "4", episode: "1", airDay: day(12), status: .upcoming, poster: nil),
                Item(path: "/sample-6", title: "Дальний берег", season: nil, episode: nil, airDay: "", status: .awaited, poster: nil, kind: "film"),
            ]
        )
    }
}
