import SwiftUI

/// Days of watching as GitHub draws contributions: a column a week, a square a day, the brighter the
/// longer it was watched. Pointing at a day tells how long; a click opens its month.
struct WatchCalendar: View {
    /// The days to draw, e.g. a year.
    let interval: DateInterval
    /// Seconds watched by the start of each day.
    let seconds: [Date: Double]
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current
    /// Up to half an hour, an hour and a half, three hours, more.
    private static let levels: [Double] = [30 * 60, 90 * 60, 3 * 3600]
    private static let spacing: CGFloat = 3

    var body: some View {
        let weeks = weeks()
        VStack(alignment: .leading, spacing: 14) {
            Text("Календарь просмотров")
                .font(.headline)
            GeometryReader { proxy in
                let labelWidth: CGFloat = 26
                let cell = min(16, max(8, (proxy.size.width - labelWidth) / CGFloat(max(weeks.count, 1)) - Self.spacing))
                HStack(alignment: .top, spacing: Self.spacing) {
                    weekdayLabels(cell: cell)
                        .frame(width: labelWidth - Self.spacing, alignment: .leading)
                    ForEach(weeks.indices, id: \.self) { index in
                        VStack(spacing: Self.spacing) {
                            monthLabel(for: weeks[index], cell: cell)
                            ForEach(0..<7, id: \.self) { row in
                                square(weeks[index][row], cell: cell)
                            }
                        }
                    }
                }
            }
            .frame(height: 7 * 16 + 6 * Self.spacing + 18)
            footer
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Grid

    /// Whole weeks from the one the interval starts in; days outside it are nil.
    private func weeks() -> [[Date?]] {
        guard var day = calendar.dateInterval(of: .weekOfYear, for: interval.start)?.start else { return [] }
        var weeks: [[Date?]] = []
        while day < interval.end {
            var week: [Date?] = []
            for _ in 0..<7 {
                week.append(interval.contains(day) && day < interval.end ? day : nil)
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
            }
            weeks.append(week)
        }
        return weeks
    }

    private func weekdayLabels(cell: CGFloat) -> some View {
        var localized = calendar
        localized.locale = AppLanguage.locale
        let symbols = localized.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return VStack(alignment: .leading, spacing: Self.spacing) {
            Color.clear.frame(height: 15)
            ForEach(0..<7, id: \.self) { row in
                // Every other day, as GitHub does, so the labels don't crowd.
                Text(verbatim: row.isMultiple(of: 2) ? symbols[(first + row) % 7] : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: cell)
            }
        }
    }

    /// The month's name over the week its first day falls in.
    private func monthLabel(for week: [Date?], cell: CGFloat) -> some View {
        let first = week.compactMap { $0 }.first { calendar.component(.day, from: $0) == 1 }
            ?? (week.compactMap { $0 }.first == interval.start ? interval.start : nil)
        return Text(verbatim: first.map { $0.formatted(.dateTime.month(.abbreviated).locale(AppLanguage.locale)) } ?? "")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize()
            .frame(width: cell, height: 15, alignment: .leading)
    }

    @ViewBuilder
    private func square(_ day: Date?, cell: CGFloat) -> some View {
        if let day {
            let watched = seconds[day] ?? 0
            let isToday = calendar.isDateInToday(day)
            RoundedRectangle(cornerRadius: cell * 0.22)
                .fill(Self.color(for: watched))
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: cell * 0.22).strokeBorder(.primary.opacity(0.6), lineWidth: 1)
                    }
                }
                .frame(width: cell, height: cell)
                .help(Self.tooltip(day, watched))
                .onTapGesture { onSelect(day) }
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private static func color(for seconds: Double) -> Color {
        guard seconds >= 60 else { return Color.primary.opacity(0.07) }
        let level = levels.firstIndex { seconds <= $0 } ?? levels.count
        return Color.accentColor.opacity([0.3, 0.55, 0.8, 1][level])
    }

    private static func tooltip(_ day: Date, _ seconds: Double) -> String {
        let date = day.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(AppLanguage.locale))
        return seconds >= 60 ? "\(date): \(StatsView.hours(seconds))" : String(localized: "\(date): не смотрели")
    }

    // MARK: Footer

    private var footer: some View {
        let days = seconds.filter { $0.value >= 60 && interval.contains($0.key) }
        let longest = days.max { $0.value < $1.value }
        return HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text("Дней с просмотром: \(days.count)")
            Text("Дней подряд, самое большее: \(longestStreak(Set(days.keys)))")
            if let longest {
                Text("Самый долгий день: \(longest.key.formatted(.dateTime.day().month(.wide).locale(AppLanguage.locale))), \(StatsView.hours(longest.value))")
            }
            Spacer()
            HStack(spacing: 4) {
                Text("Меньше")
                ForEach([0, 20 * 60, 60 * 60, 2 * 3600, 4 * 3600] as [Double], id: \.self) { seconds in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Self.color(for: seconds))
                        .frame(width: 11, height: 11)
                }
                Text("Больше")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func longestStreak(_ days: Set<Date>) -> Int {
        var best = 0
        for day in days {
            guard let before = calendar.date(byAdding: .day, value: -1, to: day), !days.contains(before) else { continue }
            var length = 1
            var next = day
            while let following = calendar.date(byAdding: .day, value: 1, to: next), days.contains(following) {
                length += 1
                next = following
            }
            best = max(best, length)
        }
        return best
    }
}
