import SwiftUI

/// A section title in the details page, aligned with the header.
private struct SectionTitle: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.title2.bold())
            .padding(.horizontal, 28)
    }
}

// MARK: Dub popularity

/// "Не можешь выбрать озвучку?" next to the dub menu. Like the site's tooltip, the table opens on hover
/// and stays while the pointer is on the link or the table; a click works too. A row picks that dub.
struct DubPopularityLink: View {
    let popularity: DubPopularity
    let translators: [Translator]
    let current: Translator?
    let onSelect: (Translator) -> Void

    @State private var isShown = false
    @State private var overLink = false
    @State private var overTable = false

    var body: some View {
        Button("Не можешь выбрать озвучку?") { isShown.toggle() }
            .buttonStyle(.link)
            .controlSize(.regular)
            .onHover { inside in
                overLink = inside
                hoverChanged()
            }
            .popover(isPresented: $isShown, arrowEdge: .bottom) {
                DubPopularityTable(popularity: popularity, translators: translators, current: current) { translator in
                    isShown = false
                    onSelect(translator)
                }
                .onHover { inside in
                    overTable = inside
                    hoverChanged()
                }
            }
    }

    /// A short pause either way: passing over the link doesn't open the table, and moving
    /// from the link onto the table doesn't close it.
    private func hoverChanged() {
        let opening = overLink || overTable
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(opening ? 250 : 350))
            if opening, overLink || overTable {
                isShown = true
            } else if !opening, !overLink, !overTable {
                isShown = false
            }
        }
    }
}

private struct DubPopularityTable: View {
    let popularity: DubPopularity
    let translators: [Translator]
    let current: Translator?
    let onSelect: (Translator) -> Void


    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(popularity.title)
                .font(.title3.bold())
            VStack(spacing: 4) {
                ForEach(popularity.entries) { row($0) }
            }
            if !popularity.note.isEmpty {
                Text(popularity.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    private func row(_ entry: DubPopularity.Entry) -> some View {
        let translator = translators.first { $0.name == entry.name }
        let isCurrent = translator != nil && translator == current
        return Button {
            if let translator { onSelect(translator) }
        } label: {
            HStack(spacing: 6) {
                Text(entry.name)
                    .fontWeight(isCurrent ? .bold : .medium)
                    .lineLimit(1)
                if isCurrent {
                    Image(systemName: "checkmark")
                } else if translator?.isPremium == true {
                    Image(systemName: "crown.fill").foregroundStyle(.orange)
                }
                Spacer(minLength: 12)
                // "42,59%" as on the site; the Russian percent format would put a space before the sign.
                Text(entry.percent.formatted(.number.precision(.fractionLength(0...2)).locale(AppLanguage.locale)) + "%")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    Color.accentColor.opacity(0.35)
                        .frame(width: proxy.size.width * min(max(entry.percent, 0), 100) / 100)
                }
            }
            .background(Brand.panel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(translator == nil)
        .help(translator == nil ? "Этой озвучки нет среди доступных для просмотра" : "Смотреть в этой озвучке")
    }
}

// MARK: Rating

/// The site's rating as ten stars filled to the average, like on the site. Until the account votes,
/// hovering a star previews that score and clicking it asks to vote.
struct SiteRatingView: View {
    let rating: SiteRating
    let myRating: Int?
    let isRating: Bool
    let onRate: (Int) -> Void

    @State private var hovered: Int?


    var body: some View {
        // A narrow window drops the idle hint first, then moves the votes under the stars;
        // nothing gets squeezed into a column.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                stars
                average
                votes
                status(showsHint: true)
            }
            HStack(spacing: 12) {
                stars
                average
                votes
                status(showsHint: false)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    stars
                    average
                }
                HStack(spacing: 12) {
                    votes
                    status(showsHint: false)
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var average: some View {
        Text(rating.value.formatted(.number.precision(.fractionLength(2)).locale(AppLanguage.locale)))
            .font(.headline.monospacedDigit())
    }

    private var votes: some View {
        Text("\(rating.votes.formatted(.number.locale(AppLanguage.locale))) \(Self.votesWord(rating.votes))")
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func status(showsHint: Bool) -> some View {
        Group {
            if isRating {
                ProgressView().controlSize(.small)
            } else if let hovered {
                Text("Оценить на \(hovered)").foregroundStyle(Color.accentColor)
            } else if let myRating {
                Label("Ваша оценка: \(myRating)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else if !rating.canVote {
                Label("Вы уже оценили", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            } else if showsHint {
                Text("Наведите на звёзды, чтобы оценить").foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .lineLimit(1)
    }

    private var row: some View {
        HStack(spacing: 3) {
            ForEach(1...10, id: \.self) { _ in
                Image(systemName: "star.fill")
            }
        }
        .font(.system(size: 17))
    }

    private var stars: some View {
        row
            .foregroundStyle(Color.primary.opacity(0.18))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(hovered == nil ? Brand.gold : Color.accentColor)
                        .frame(width: proxy.size.width * fill)
                }
                .mask(row)
                .allowsHitTesting(false)
            }
            .overlay {
                if rating.canVote, myRating == nil, !isRating {
                    HStack(spacing: 0) {
                        ForEach(1...10, id: \.self) { score in
                            Color.clear
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    if inside { hovered = score } else if hovered == score { hovered = nil }
                                }
                                .onTapGesture { onRate(score) }
                                .help("Оценить на \(score)")
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Рейтинг на сайте")
            .accessibilityValue("\(rating.value.formatted(.number.precision(.fractionLength(2)).locale(AppLanguage.locale))) из 10")
            .accessibilityIdentifier("siteRating")
    }

    /// The hovered score, or the average; star N ends at N tenths of the row.
    private var fill: CGFloat {
        CGFloat(hovered.map(Double.init) ?? min(max(rating.value, 0), 10)) / 10
    }

    /// Russian has three plural forms and English two; the number is formatted separately, with grouping.
    private static func votesWord(_ count: Int) -> String {
        guard AppLanguage.isRussian else { return count == 1 ? "vote" : "votes" }
        let tens = count % 100, ones = count % 10
        if (11...14).contains(tens) { return "голосов" }
        switch ones {
        case 1: return "голос"
        case 2...4: return "голоса"
        default: return "голосов"
        }
    }
}

// MARK: Episodes

struct EpisodesSection: View {
    let model: DetailsModel
    let details: MediaDetails
    @Environment(WatchProgressStore.self) private var progress

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 220), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                SectionTitle(text: "Серии")
                    .padding(.trailing, -28)
                if model.seasons.count > 1 {
                    Picker("Сезон", selection: Binding(
                        get: { model.selectedSeason?.id ?? "" },
                        set: { model.selectedSeasonId = $0 }
                    )) {
                        ForEach(model.seasons) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                } else if let season = model.selectedSeason {
                    Text(season.title).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 28)

            if model.isLoadingEpisodes {
                ProgressView().padding(.horizontal, 28)
            } else if let error = model.episodesError {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
            } else if let season = model.selectedSeason {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(season.episodes) { episode in
                        let scheduled = model.scheduleEpisode(for: episode)
                        EpisodeCard(
                            episode: episode,
                            entry: progress.entry(postId: details.postId, seasonId: episode.seasonId, episodeId: episode.id),
                            isWatched: scheduled.map { model.watchedEpisodes.contains($0.id) } ?? false,
                            onToggleWatched: scheduled.map { scheduled in { Task { await model.toggleWatched(scheduled) } } }
                        ) {
                            model.play(episode: episode)
                        }
                    }
                }
                .padding(.horizontal, 28)
            }
        }
    }
}

private struct EpisodeCard: View {
    let episode: Episode
    let entry: WatchProgressStore.Entry?
    /// Marked "просмотрено" on the site.
    var isWatched = false
    /// Set when the episode is in the site's schedule, so its mark can be changed from the context menu.
    var onToggleWatched: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Brand.placeholder
                Image(systemName: "play.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(episode.title)
                            .font(.headline)
                            .lineLimit(2)
                        Spacer()
                        if entry?.isFinished == true || isWatched {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    if let entry, !entry.isFinished, !isWatched {
                        ProgressView(value: entry.fraction)
                            .tint(.accentColor)
                    }
                }
                .padding(12)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .hoverLift()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: action) {
                Label("Смотреть", systemImage: "play.fill")
            }
            if let onToggleWatched {
                Button(action: onToggleWatched) {
                    Label(isWatched ? "Снять отметку «просмотрено»" : "Отметить просмотренной",
                          systemImage: isWatched ? "eye.slash" : "eye")
                }
            }
        }
    }
}

// MARK: Schedule

/// The site's air-date table with a per-row button for the "просмотрено" mark.
struct ScheduleSection: View {
    let seasons: [ScheduleSeason]
    let model: DetailsModel

    @State private var seasonId: String?

    var body: some View {
        let season = seasons.first { $0.id == seasonId } ?? seasons[0]
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Text("График выхода серий")
                    .font(.title2.bold())
                if seasons.count > 1 {
                    Picker("Сезон", selection: Binding(get: { season.id }, set: { seasonId = $0 })) {
                        ForEach(seasons) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            VStack(spacing: 0) {
                ForEach(season.episodes) { episode in
                    ScheduleRow(episode: episode, isWatched: model.watchedEpisodes.contains(episode.id)) {
                        Task { await model.toggleWatched(episode) }
                    }
                    if episode.id != season.episodes.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
            .background(Brand.panel, in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .padding(.horizontal, 28)
    }
}

private struct ScheduleRow: View {
    let episode: ScheduleEpisode
    let isWatched: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Text(episode.label)
                .font(.headline)
                .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title.isEmpty ? String(localized: "Без названия") : episode.title)
                    .lineLimit(1)
                if let original = episode.originalTitle {
                    Text(original)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(episode.date)
                .foregroundStyle(.secondary)
            Label(episode.isReleased ? "Вышла" : "Ожидается",
                  systemImage: episode.isReleased ? "checkmark.circle.fill" : "clock")
                .font(.callout)
                .foregroundStyle(episode.isReleased ? .green : .orange)
                .frame(width: 110, alignment: .leading)
            Button(action: onToggle) {
                Label(isWatched ? "Просмотрено" : "Не просмотрено", systemImage: isWatched ? "eye.fill" : "eye.slash")
                    .frame(width: 140, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isWatched ? Color.accentColor : .secondary)
            .help(isWatched ? "Удалить эпизод из просмотренных" : "Отметить эпизод как просмотренный")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: Franchise

/// The parts as rows in one panel, like the schedule, so the page scrolls past them with the wheel.
/// A long franchise shows its first few until expanded.
struct FranchiseSection: View {
    let franchise: Franchise

    @State private var isExpanded = false
    private let collapsedCount = 6

    var body: some View {
        let isCollapsible = franchise.parts.count > collapsedCount
        let parts = isCollapsible && !isExpanded ? Array(franchise.parts.prefix(collapsedCount)) : franchise.parts
        VStack(alignment: .leading, spacing: 14) {
            Text(franchise.title)
                .font(.title2.bold())

            VStack(spacing: 0) {
                ForEach(parts) { part in
                    FranchiseRow(part: part)
                    if part.id != parts.last?.id || isCollapsible {
                        Divider().opacity(0.4)
                    }
                }
                if isCollapsible {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Label(isExpanded ? "Свернуть" : "Показать все (\(franchise.parts.count))",
                              systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .background(Brand.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .padding(.horizontal, 28)
    }
}

/// A part of the franchise; the one being viewed is marked and not a link.
private struct FranchiseRow: View {
    let part: FranchisePart
    @State private var isHovered = false

    var body: some View {
        if let path = part.path {
            NavigationLink(value: MediaItem(path: path, title: part.title, subtitle: part.year, posterURL: nil, kind: .unknown, badge: nil)) {
                content
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 18) {
            Text("Часть \(part.number)")
                .font(.headline)
                .frame(width: 90, alignment: .leading)
            Text(part.title)
                .lineLimit(1)
                .foregroundStyle(part.isCurrent ? Color.accentColor : .primary)
                .help(part.title)
            Spacer()
            Text(part.year)
                .foregroundStyle(.secondary)
            Group {
                if part.isCurrent {
                    Text("Сейчас")
                        .font(.callout.bold())
                        .foregroundStyle(Color.accentColor)
                } else if let rating = part.rating {
                    Label(rating, systemImage: "star.fill")
                        .font(.callout)
                        .foregroundStyle(Brand.gold)
                }
            }
            .frame(width: 80, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Brand.hover : .clear)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
    }
}

// MARK: Comments

struct CommentsSection: View {
    let model: DetailsModel
    let total: Int

    @State private var revealedSpoilers: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Отзывы (\(max(total, model.comments.count)))")
                .font(.title2.bold())

            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(model.comments) { comment in
                    CommentCard(comment: comment, isRevealed: revealedSpoilers.contains(comment.id)) {
                        if revealedSpoilers.contains(comment.id) {
                            revealedSpoilers.remove(comment.id)
                        } else {
                            revealedSpoilers.insert(comment.id)
                        }
                    }
                }
            }

            if let error = model.commentsError {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
            }
            if model.commentsError != nil || model.hasMoreComments {
                Button {
                    Task { await model.loadMoreComments() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isLoadingComments { ProgressView().controlSize(.small) }
                        Text(model.commentsError != nil ? "Повторить" : "Показать ещё отзывы")
                    }
                }
                .disabled(model.isLoadingComments)
            } else if model.isLoadingComments {
                ProgressView()
            }
        }
        .padding(.horizontal, 28)
    }
}

private struct CommentCard: View {
    let comment: Comment
    let isRevealed: Bool
    let toggleSpoiler: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(comment.author)
                    .font(.headline)
                Text(comment.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if comment.likes > 0 {
                    Label("\(comment.likes)", systemImage: "hand.thumbsup.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if comment.hasSpoiler {
                Button(isRevealed ? "Скрыть спойлер" : "Показать спойлер", action: toggleSpoiler)
                    .buttonStyle(.link)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: 900, alignment: .leading)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 12))
        // Replies step in under their parent.
        .padding(.leading, CGFloat(min(comment.depth, 4)) * 36)
    }

    private var text: AttributedString {
        var result = AttributedString()
        for part in comment.parts {
            var piece = AttributedString(part.isSpoiler && !isRevealed ? String(localized: "[спойлер]") : part.text)
            if part.isSpoiler { piece.foregroundColor = .orange }
            result += piece
        }
        return result
    }
}
