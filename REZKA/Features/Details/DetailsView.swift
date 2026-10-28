import SwiftUI

struct DetailsView: View {
    let item: MediaItem

    @State private var model: DetailsModel
    @Environment(WatchProgressStore.self) private var progress
    @Environment(AuthSession.self) private var auth
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""

    init(item: MediaItem) {
        self.item = item
        _model = State(initialValue: DetailsModel(item: item))
    }

    var body: some View {
        ZStack {
            switch model.state {
            case .loading:
                ProgressView()
            case let .failed(error):
                ErrorStateView(error: error) { await model.load() }
            case let .loaded(details):
                content(details)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { backdrop }
        .navigationTitle(model.details?.title ?? item.title)
        .task { await model.loadIfNeeded() }
        .alert("Новая папка закладок", isPresented: $isCreatingFolder) {
            TextField("Название", text: $newFolderName)
            Button("Создать и добавить") {
                let name = newFolderName
                Task { await model.createBookmarkFolder(named: name) }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Не получилось", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private var backdrop: some View {
        Brand.navy
            .overlay(alignment: .top) {
                PosterImage(url: model.details?.posterURL ?? item.posterURL)
                    .frame(height: 520)
                    .blur(radius: 70)
                    .opacity(0.35)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
            .clipped()
            .ignoresSafeArea()
    }

    private func content(_ details: MediaDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header(details)
                    .padding(.horizontal, 28)

                if details.isSeries {
                    EpisodesSection(model: model, details: details)
                }

                if !details.schedule.isEmpty {
                    ScheduleSection(seasons: details.schedule, model: model)
                }

                if let franchise = details.franchise {
                    FranchiseSection(franchise: franchise)
                }

                if !details.related.isEmpty {
                    MediaRow(title: "Смотрите также", items: details.related)
                }

                if details.commentsCount > 0 || !model.comments.isEmpty {
                    CommentsSection(model: model, total: details.commentsCount)
                }
            }
            .padding(.vertical, 28)
        }
    }

    // MARK: Header

    private func header(_ details: MediaDetails) -> some View {
        HStack(alignment: .top, spacing: 30) {
            PosterImage(url: details.posterURL ?? item.posterURL)
                .frame(width: 240, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)

            VStack(alignment: .leading, spacing: 14) {
                Text(details.title)
                    .font(.largeTitle.bold())
                    .textSelection(.enabled)
                if !details.originalTitle.isEmpty {
                    Text(details.originalTitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                metaLine(details)
                if let ratings = details.info("Рейтинги") {
                    Label(ratings, systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
                actions(details)
                    .padding(.vertical, 6)
                if model.translator?.isPremium == true, !auth.isPremium {
                    Label("Эта озвучка только для HDrezka Premium — без подписки покажут короткое превью. Выберите озвучку без короны.",
                          systemImage: "crown.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if !details.description.isEmpty {
                    Text(details.description)
                        .font(.body)
                        .lineSpacing(3)
                        .frame(maxWidth: 820, alignment: .leading)
                        .textSelection(.enabled)
                }
                if let cast = details.info("В ролях") {
                    Text("В ролях: \(cast)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 820, alignment: .leading)
                }
                if !details.collections.isEmpty {
                    collections(details.collections)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metaLine(_ details: MediaDetails) -> some View {
        let parts = [
            details.info("Дата выхода") ?? details.info("Год"),
            details.info("Страна"),
            details.info("Жанр"),
            details.info("Время"),
            details.info("Возраст"),
        ].compactMap { $0 }
        return Text(parts.joined(separator: "  ·  "))
            .foregroundStyle(.secondary)
    }

    /// The "Из серии" row as buttons into those collections.
    private func collections(_ listings: [Listing]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(listings) { listing in
                    NavigationLink(value: listing) {
                        Label(listing.title, systemImage: "square.stack")
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Brand.panel, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 820, alignment: .leading)
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ details: MediaDetails) -> some View {
        HStack(spacing: 12) {
            if details.upcomingStatus != nil {
                Label("В ожидании", systemImage: "clock.fill")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.1), in: Capsule())
            } else if details.isSeries {
                if let target = model.resumeEpisode(progress: progress) {
                    let season = model.seasons.first { $0.id == target.episode.seasonId }?.title ?? ""
                    Button {
                        model.play(episode: target.episode)
                    } label: {
                        Label(target.entry == nil ? "Смотреть: \(season), \(target.episode.title)" : "Продолжить: \(season), \(target.episode.title)",
                              systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else if model.isLoadingEpisodes {
                    ProgressView().controlSize(.small)
                }
            } else {
                let entry = progress.entry(postId: details.postId, seasonId: nil, episodeId: nil)
                if let entry, !entry.isFinished, entry.position > 30 {
                    Button {
                        model.play()
                    } label: {
                        Label("Продолжить с \(entry.position.playbackTime)", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    Button {
                        model.play(from: 0)
                    } label: {
                        Label("Сначала", systemImage: "backward.end.fill")
                    }
                } else {
                    Button {
                        model.play(from: 0)
                    } label: {
                        Label("Смотреть", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }

            if details.translators.count > 1 {
                Menu {
                    ForEach(details.translators) { translator in
                        Button {
                            Task { await model.select(translator) }
                        } label: {
                            let title = translator.isPremium ? "\(translator.name) · Premium" : translator.name
                            if translator == model.translator {
                                Label(title, systemImage: "checkmark")
                            } else if translator.isPremium {
                                Label(title, systemImage: "crown.fill")
                            } else {
                                Text(title)
                            }
                        }
                    }
                } label: {
                    Label(model.translator?.name ?? "Озвучка", systemImage: model.translator?.isPremium == true ? "crown.fill" : "waveform")
                }
                .fixedSize()
                .help("Озвучка")
            } else if let translator = model.translator {
                Label(translator.name, systemImage: "waveform")
                    .foregroundStyle(.secondary)
            }

            if let folders = model.bookmarkFolders {
                bookmarkMenu(folders)
            }
        }
        .controlSize(.large)
    }

    /// Folders with a checkmark where the title is; picking one adds or removes it there.
    private func bookmarkMenu(_ folders: [BookmarkFolder]) -> some View {
        Menu {
            ForEach(folders) { folder in
                Button {
                    Task { await model.toggleBookmark(in: folder) }
                } label: {
                    if model.bookmarkedIn.contains(folder.id) {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }
            Divider()
            Button {
                newFolderName = ""
                isCreatingFolder = true
            } label: {
                Label("Новая папка…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label(model.bookmarkedIn.isEmpty ? "В закладки" : "В закладках",
                  systemImage: model.bookmarkedIn.isEmpty ? "bookmark" : "bookmark.fill")
        }
        .fixedSize()
    }
}
