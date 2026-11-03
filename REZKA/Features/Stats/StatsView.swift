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

    @State private var goals = WatchGoal.all
    @State private var isEditingGoal = false
    @State private var goalDraft = 24
    @State private var showsAchievements = false
    @State private var exportFile: RecapFile?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var notice: Notice?

    private let stats = WatchStats.shared
    private let calendar = Calendar.current

    /// Origin tags the site files among genres.
    private static let notGenres: Set<String> = ["Зарубежные", "Русские", "Украинские"]

    var body: some View {
        let summary = summary()
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if span != .all {
                    goal
                }

                if summary.total < 60 {
                    EmptyStateView(text: "Здесь появятся итоги, когда вы что-нибудь посмотрите в REZKA на этом Mac.")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    tiles(summary)
                    chart(summary)
                    if let interval = calendarInterval {
                        WatchCalendar(interval: interval, seconds: secondsByDay) { day in
                            span = .month
                            anchor = day
                        }
                    }
                    HStack(alignment: .top, spacing: 20) {
                        genres(summary)
                        dubs(summary)
                        topTitles(summary)
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Итоги")
        .navigationSubtitle(periodTitle)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case let .success(url): importRecap(from: url)
            case let .failure(error): notice = Notice(title: String(localized: "Не удалось импортировать итоги"), text: error.localizedDescription)
            }
        }
        // Where an export is saved unless chosen otherwise, so the file is right there.
        .fileDialogDefaultDirectory(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }), presenting: notice) { _ in
            Button("OK") {}
        } message: { notice in
            Text(notice.text)
        }
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
                        .disabled(isFirstPeriod)
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
            NavigationLink(value: FilmPassportLink()) {
                Label("Кинопаспорт", systemImage: "globe.europe.africa.fill")
            }
            Button {
                showsAchievements = true
            } label: {
                Label("Достижения \(AchievementTracker.shared.earned.count)/\(Achievement.all.count)", systemImage: "medal.fill")
                    .monospacedDigit()
            }
            .sheet(isPresented: $showsAchievements) { AchievementsView() }
            Menu {
                Button("Экспортировать итоги…", systemImage: "square.and.arrow.up") { exportRecap() }
                Button("Импортировать итоги…", systemImage: "square.and.arrow.down") { isImporting = true }
            } label: {
                Label("Экспорт и импорт", systemImage: "arrow.up.arrow.down.circle")
            }
            .fixedSize()
            .fileExporter(isPresented: $isExporting, document: exportFile, contentType: .json,
                          defaultFilename: RecapArchive.fileName) { result in
                if case let .failure(error) = result {
                    notice = Notice(title: String(localized: "Не удалось сохранить итоги"), text: error.localizedDescription)
                }
            }
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

    /// November 2026, when «Итоги» began, or its year.
    private var isFirstPeriod: Bool {
        let component: Calendar.Component = span == .month ? .month : .year
        return calendar.isDate(anchor, equalTo: WatchStats.firstDay, toGranularity: component)
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
        /// Seconds by dub.
        var byDub: [String: Double] = [:]
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
        for (key, dubs) in stats.dubs {
            guard let day = WatchStats.date(ofDay: key), contains(day) else { continue }
            for (dub, value) in dubs { summary.byDub[dub, default: 0] += value }
        }
        summary.bars = bars.map { Bar(date: $0.key, seconds: $0.value) }.sorted { $0.date < $1.date }
        return summary
    }

    private func contains(_ day: Date) -> Bool {
        guard day >= WatchStats.firstDay else { return false }
        return switch span {
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
            // Through the end of this month, so its bar stays inside.
            let end = calendar.dateInterval(of: .month, for: Date())?.end ?? Date()
            return WatchStats.firstDay...max(end, WatchStats.firstDay)
        }
        guard let interval = calendar.dateInterval(of: component, for: anchor) else { return anchor...anchor }
        return max(interval.start, WatchStats.firstDay)...interval.end
    }

    // MARK: Calendar

    /// The year on screen, or up to the last 52 weeks through this month for all time; a month has its
    /// chart by days. Neither starts before «Итоги» did.
    private var calendarInterval: DateInterval? {
        switch span {
        case .month:
            return nil
        case .year:
            guard let year = calendar.dateInterval(of: .year, for: anchor) else { return nil }
            return DateInterval(start: max(year.start, WatchStats.firstDay), end: max(year.end, WatchStats.firstDay))
        case .all:
            let today = calendar.startOfDay(for: Date())
            guard let yearAgo = calendar.date(byAdding: .day, value: -363, to: today),
                  let end = calendar.dateInterval(of: .month, for: today)?.end else { return nil }
            let start = max(yearAgo, WatchStats.firstDay)
            return DateInterval(start: start, end: max(end, start))
        }
    }

    private var secondsByDay: [Date: Double] {
        Dictionary(stats.days.compactMap { key, titles in
            WatchStats.date(ofDay: key).flatMap { day in
                day >= WatchStats.firstDay ? (calendar.startOfDay(for: day), titles.values.reduce(0, +)) : nil
            }
        }, uniquingKeysWith: +)
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
                Text("У этих тайтлов не нашлось жанров.")
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

    // MARK: Dubs

    /// The studios heard most, by time: the player counts them as it plays.
    private func dubs(_ summary: Summary) -> some View {
        let total = summary.byDub.values.reduce(0, +)
        let top = summary.byDub.sorted { $0.value > $1.value }.prefix(6)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Любимые озвучки")
                .font(.headline)
            if top.isEmpty {
                Text("Озвучки считаются с этого обновления: посмотрите что-нибудь, и они появятся здесь.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(top), id: \.key) { dub, value in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: dub)
                            .lineLimit(1)
                        Spacer()
                        Text(Self.hours(value))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text((value / total).formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.locale)))
                            .monospacedDigit()
                            .frame(minWidth: 38, alignment: .trailing)
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

    // MARK: Goal

    private static let goalPresets = [12, 24, 52, 100]

    /// The goal of the year on screen, or an offer to set one for this year.
    @ViewBuilder
    private var goal: some View {
        let year = calendar.component(.year, from: anchor)
        if let interval = calendar.dateInterval(of: .year, for: anchor) {
            if let target = goals[String(year)] {
                goalProgress(target, films: AchievementTracker.shared.finishedFilms(in: interval), year: year, interval: interval)
            } else if year == calendar.component(.year, from: Date()) {
                HStack(spacing: 12) {
                    Label("Цель на \(String(year))", systemImage: "target")
                        .font(.headline)
                    Text("Сколько фильмов хотите посмотреть за год?")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Поставить цель…") { editGoal(year: year) }
                        .popover(isPresented: $isEditingGoal, arrowEdge: .bottom) { goalEditor(year: year) }
                }
                .padding(18)
                .background(Brand.panel, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func goalProgress(_ target: Int, films: [AchievementTracker.FinishedFilm], year: Int, interval: DateInterval) -> some View {
        let now = Date()
        let isThisYear = interval.contains(now)
        // Where an even pace would be by today; the whole year for a year that is over.
        let elapsed = isThisYear ? now.timeIntervalSince(interval.start) / interval.duration : 1
        let done = films.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Цель на \(String(year))", systemImage: "target")
                    .font(.headline)
                Spacer()
                if isThisYear {
                    Button("Изменить…") { editGoal(year: year) }
                        .popover(isPresented: $isEditingGoal, arrowEdge: .bottom) { goalEditor(year: year) }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(done) из \(target)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("фильмов посмотрено")
                    .foregroundStyle(.secondary)
                Spacer()
                Text((Double(done) / Double(target)).formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.locale)))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            GoalBar(done: min(Double(done) / Double(target), 1), pace: isThisYear ? elapsed : nil)
            Label(goalPace(target: target, done: done, elapsed: elapsed, interval: interval, isThisYear: isThisYear),
                  systemImage: done >= target ? "checkmark.seal.fill" : "speedometer")
                .foregroundStyle(done >= target ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            if !films.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(films, id: \.postId) { goalPoster($0.postId) }
                    }
                }
            }
        }
        .padding(18)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Ahead or behind an even pace, and what it takes to make it by the end of the year.
    private func goalPace(target: Int, done: Int, elapsed: Double, interval: DateInterval, isThisYear: Bool) -> String {
        if done >= target { return String(localized: "Цель выполнена") }
        guard isThisYear else { return String(localized: "Не хватило: \(target - done)") }
        let behind = Int((Double(target) * elapsed).rounded(.down)) - done
        let pace = behind > 0 ? String(localized: "Отстаёте от плана на \(behind).")
            : behind < 0 ? String(localized: "Опережаете план на \(-behind).")
            : String(localized: "Идёте точно по плану.")
        let weeksLeft = max(interval.end.timeIntervalSinceNow / (7 * 86_400), 1)
        let perWeek = (Double(target - done) / weeksLeft)
            .formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.locale))
        return pace + " " + String(localized: "Осталось \(target - done), примерно \(perWeek) в неделю.")
    }

    @ViewBuilder
    private func goalPoster(_ postId: String) -> some View {
        let title = stats.titles[postId]
        let poster = PosterImage(url: title?.posterURL)
            .frame(width: 48, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .help(title?.name ?? "")
        if let title, let path = title.path {
            NavigationLink(value: MediaItem(path: path, title: title.name, subtitle: "", posterURL: title.posterURL, kind: title.kind, badge: nil)) {
                poster
            }
            .buttonStyle(.plain)
        } else {
            poster
        }
    }

    private func editGoal(year: Int) {
        goalDraft = goals[String(year)] ?? 24
        isEditingGoal = true
    }

    private func goalEditor(year: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Сколько фильмов посмотреть в \(String(year))?")
                .font(.headline)
            // None lit when the number is typed in.
            Picker("Цель", selection: $goalDraft) {
                ForEach(Self.goalPresets, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Stepper(value: $goalDraft, in: 1...999) {
                TextField("Фильмов", value: $goalDraft, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
            Text("Цель 12 значит фильм в месяц, 52 значит фильм в неделю. Считаются фильмы, мультфильмы и аниме без серий, досмотренные в REZKA.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if goals[String(year)] != nil {
                    Button("Убрать цель", role: .destructive) { saveGoal(nil, year: year) }
                }
                Spacer()
                Button("Отмена") { isEditingGoal = false }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить") { saveGoal(min(max(goalDraft, 1), 999), year: year) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
    }

    private func saveGoal(_ films: Int?, year: Int) {
        WatchGoal.set(films, for: year)
        goals = WatchGoal.all
        isEditingGoal = false
        AchievementTracker.shared.evaluate(announce: true)
    }

    // MARK: Export and import

    private struct Notice {
        let title: String
        let text: String
    }

    private func exportRecap() {
        do {
            exportFile = RecapFile(data: try RecapArchive.current().encoded())
            isExporting = true
        } catch {
            notice = Notice(title: String(localized: "Не удалось сохранить итоги"), text: error.localizedDescription)
        }
    }

    private func importRecap(from url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let outcome = try RecapArchive.decode(Data(contentsOf: url)).apply()
            goals = WatchGoal.all
            let text = outcome.days == 0 && outcome.titles == 0 && outcome.achievements == 0
                ? String(localized: "Всё из этого файла уже было здесь.")
                : String(localized: "Новых дней с просмотром: \(outcome.days). Новых тайтлов: \(outcome.titles). Новых достижений: \(outcome.achievements).")
            notice = Notice(title: String(localized: "Итоги импортированы"), text: text)
        } catch {
            notice = Notice(title: String(localized: "Не удалось импортировать итоги"), text: error.localizedDescription)
        }
    }

    // MARK: Formatting

    /// "12 ч 40 мин", "35 мин".
    static func hours(_ seconds: Double) -> String {
        Duration.seconds(Int64(seconds.rounded()))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(AppLanguage.locale))
    }
}

/// The goal's progress, with a tick where an even pace would be by today.
private struct GoalBar: View {
    /// Both from 0 to 1.
    let done: Double
    let pace: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: max(done > 0 ? 10 : 0, width * done))
                if let pace {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.primary.opacity(0.7))
                        .frame(width: 2, height: 16)
                        .offset(x: min(max(width * pace - 1, 0), width - 2))
                        .help("План на сегодня")
                }
            }
        }
        .frame(height: 10)
    }
}
