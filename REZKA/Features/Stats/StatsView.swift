import Charts
import SwiftUI

/// «Итоги»: how much was watched in REZKA on this Mac over a month, a year or all along, by day or
/// month, in which genres and which titles most.
struct StatsView: View {
    enum Span: Hashable, CaseIterable {
        case month, year, all

        var title: String {
            switch self {
            case .month: String(localized: "Месяц")
            case .year: String(localized: "Год")
            case .all: String(localized: "Всё время")
            }
        }
    }

    @State private var span = Span.month
    /// A day inside the month or year on screen.
    @State private var anchor = Date()

    private let stats = WatchStats.shared
    private let calendar = Calendar.current

    /// Origin tags the site files among genres.
    private static let notGenres: Set<String> = ["Зарубежные", "Русские", "Украинские"]

    var body: some View {
        let summary = summary()
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if summary.total < 60 {
                    EmptyStateView(text: "Здесь появятся итоги, когда вы что-нибудь посмотрите в REZKA на этом Mac.")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    tiles(summary)
                    chart(summary)
                    HStack(alignment: .top, spacing: 20) {
                        genres(summary)
                        topTitles(summary)
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Итоги")
        .navigationSubtitle(periodTitle)
        .task { await stats.resolveUnknown() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            Picker("Период", selection: $span) {
                ForEach(Span.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if span != .all {
                HStack(spacing: 4) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        .help("Раньше")
                    Text(periodTitle)
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 150)
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .help("Позже")
                        .disabled(isCurrentPeriod)
                }
                .buttonStyle(.borderless)
            }
            Spacer()
        }
    }

    private var periodTitle: String {
        switch span {
        case .month:
            let text = anchor.formatted(.dateTime.month(.wide).year().locale(AppLanguage.locale))
            return text.prefix(1).uppercased() + text.dropFirst()
        case .year:
            return anchor.formatted(.dateTime.year().locale(AppLanguage.locale))
        case .all:
            return Span.all.title
        }
    }

    private var isCurrentPeriod: Bool {
        let component: Calendar.Component = span == .month ? .month : .year
        return calendar.isDate(anchor, equalTo: Date(), toGranularity: component)
    }

    private func shift(_ step: Int) {
        let component: Calendar.Component = span == .month ? .month : .year
        anchor = calendar.date(byAdding: component, value: step, to: anchor) ?? anchor
    }

    // MARK: Summary

    private struct Summary {
        var total: Double = 0
        /// Seconds by title id.
        var byTitle: [String: Double] = [:]
        /// Seconds by bar: a day of the month, a month of the year, or a month of all time.
        var bars: [Bar] = []
        var activeDays = 0
    }

    private struct Bar: Identifiable {
        let date: Date
        let seconds: Double
        var id: Date { date }
    }

    private func summary() -> Summary {
        var summary = Summary()
        var bars: [Date: Double] = [:]
        for (key, titles) in stats.days {
            guard let day = WatchStats.date(ofDay: key), contains(day) else { continue }
            let seconds = titles.values.reduce(0, +)
            guard seconds > 0 else { continue }
            summary.total += seconds
            summary.activeDays += 1
            for (id, value) in titles { summary.byTitle[id, default: 0] += value }
            let bucket = span == .month
                ? calendar.startOfDay(for: day)
                : calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
            bars[bucket, default: 0] += seconds
        }
        summary.bars = bars.map { Bar(date: $0.key, seconds: $0.value) }.sorted { $0.date < $1.date }
        return summary
    }

    private func contains(_ day: Date) -> Bool {
        switch span {
        case .month: calendar.isDate(day, equalTo: anchor, toGranularity: .month)
        case .year: calendar.isDate(day, equalTo: anchor, toGranularity: .year)
        case .all: true
        }
    }

    private func titles(_ summary: Summary, of kind: MediaKind) -> Int {
        summary.byTitle.keys.filter { stats.titles[$0]?.kind == kind }.count
    }

    // MARK: Tiles

    private func tiles(_ summary: Summary) -> some View {
        HStack(spacing: 16) {
            tile(Self.hours(summary.total), "Посмотрено", "clock.fill")
            tile("\(titles(summary, of: .film))", "Фильмов", "film.fill")
            tile("\(titles(summary, of: .series))", "Сериалов", "tv.fill")
            tile("\(summary.activeDays)", "Дней с просмотром", "calendar")
        }
    }

    private func tile(_ value: String, _ title: LocalizedStringKey, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Chart

    private func chart(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(span == .month ? "По дням" : "По месяцам")
                .font(.headline)
            Chart(summary.bars) { bar in
                BarMark(
                    x: .value("Дата", bar.date, unit: span == .month ? .day : .month),
                    y: .value("Часы", bar.seconds / 3600)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(4)
            }
            .chartXScale(domain: chartDomain(summary))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hours = value.as(Double.self) { Text(Self.hours(hours * 3600)) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: span == .month ? .day : .month, count: span == .month ? 5 : 1)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: axisFormat, centered: true)
                }
            }
            .environment(\.locale, AppLanguage.locale)
            .frame(height: 220)
        }
        .padding(18)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    /// All time may run over several years, so its months carry the year.
    private var axisFormat: Date.FormatStyle {
        switch span {
        case .month: .dateTime.day()
        case .year: .dateTime.month(.abbreviated)
        case .all: .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    /// The whole month or year, so empty days and months show as gaps.
    private func chartDomain(_ summary: Summary) -> ClosedRange<Date> {
        let component: Calendar.Component
        switch span {
        case .month: component = .month
        case .year: component = .year
        case .all:
            // Through the end of the last month, so its bar stays inside.
            let first = summary.bars.first?.date ?? Date()
            let last = summary.bars.last?.date ?? first
            return first...(calendar.date(byAdding: .month, value: 1, to: last) ?? last)
        }
        guard let interval = calendar.dateInterval(of: component, for: anchor) else { return anchor...anchor }
        return interval.start...interval.end
    }

    // MARK: Genres

    private func genres(_ summary: Summary) -> some View {
        var seconds: [String: Double] = [:]
        for (id, value) in summary.byTitle {
            for genre in stats.titles[id]?.genres ?? [] where !Self.notGenres.contains(genre) {
                seconds[genre, default: 0] += value
            }
        }
        let total = seconds.values.reduce(0, +)
        let top = seconds.sorted { $0.value > $1.value }.prefix(6)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Любимые жанры")
                .font(.headline)
            if top.isEmpty {
                Text("Жанры появятся у того, что вы посмотрите теперь.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(top), id: \.key) { genre, value in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(genre)
                        Spacer()
                        Text((value / total).formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.locale)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.accentColor.gradient)
                            .frame(width: max(6, proxy.size.width * value / (top.first?.value ?? value)))
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Titles

    private func topTitles(_ summary: Summary) -> some View {
        let top = summary.byTitle.sorted { $0.value > $1.value }.prefix(5)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Больше всего смотрели")
                .font(.headline)
            ForEach(Array(top), id: \.key) { id, value in
                titleRow(id: id, seconds: value)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func titleRow(id: String, seconds: Double) -> some View {
        let title = stats.titles[id]
        let row = HStack(spacing: 12) {
            PosterImage(url: title?.posterURL)
                .frame(width: 36, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(title?.name ?? String(localized: "Без названия"))
                    .lineLimit(1)
                if let kind = title?.kind.title {
                    Text(kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Self.hours(seconds))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        if let title, let path = title.path {
            NavigationLink(value: MediaItem(path: path, title: title.name, subtitle: "", posterURL: title.posterURL, kind: title.kind, badge: nil)) {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    // MARK: Formatting

    /// "12 ч 40 мин", "35 мин".
    static func hours(_ seconds: Double) -> String {
        Duration.seconds(Int64(seconds.rounded()))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(AppLanguage.locale))
    }
}
