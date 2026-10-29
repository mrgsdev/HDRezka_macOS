import SwiftUI

/// A section title in the details page, aligned with the header.
private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title2.bold())
            .padding(.horizontal, 28)
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
                LinearGradient(colors: [Color(white: 0.24), Color(white: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "play.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.25))
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
                Text(episode.title.isEmpty ? "Без названия" : episode.title)
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
                        .foregroundStyle(.yellow)
                }
            }
            .frame(width: 80, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color.white.opacity(0.06) : .clear)
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
            var piece = AttributedString(part.isSpoiler && !isRevealed ? "[спойлер]" : part.text)
            if part.isSpoiler { piece.foregroundColor = .orange }
            result += piece
        }
        return result
    }
}
