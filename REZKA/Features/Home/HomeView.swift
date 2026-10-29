import SwiftUI

struct HomeView: View {
    let model: HomeModel

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 30) {
                ForEach(model.shelves) { shelf in
                    if shelf.isContinue {
                        MediaRow(title: shelf.title, items: shelf.items) { item in
                            [CardAction(title: "Убрать из «Продолжить просмотр»", systemImage: "trash", isDestructive: true) {
                                Task { await model.removeFromContinue(item) }
                            }]
                        }
                    } else if shelf.isNewest {
                        MediaRow(items: shelf.items) {
                            NewestTitle(model: model)
                        }
                    } else {
                        MediaRow(title: shelf.title, items: shelf.items)
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .overlay {
            if model.shelves.isEmpty {
                if let error = model.error {
                    ErrorStateView(error: error) { await model.load() }
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Главная")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Обновить (⌘R)")
            }
        }
        .task { await model.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryChanged)) { _ in
            Task { await model.refreshContinue() }
        }
        .alert("Не удалось убрать", isPresented: Binding(
            get: { model.removalError != nil },
            set: { if !$0 { model.removalError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.removalError ?? "")
        }
    }
}

/// "Новые фильмы, сериалы, мультфильмы и аниме" as on the site: a word shows only that section,
/// the one shown is plain text, and "(все новинки)" brings the mix back.
private struct NewestTitle: View {
    let model: HomeModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Новые ")
            word(.films)
            Text(", ")
            word(.series)
            Text(", ")
            word(.cartoons)
            Text(" и ")
            word(.anime)
            if model.newestSection != .all {
                Button {
                    Task { await model.showNewest(.all) }
                } label: {
                    Text("(\(NewestSection.all.word))")
                        .underline(pattern: .dot)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .font(.title3)
                .padding(.leading, 10)
            }
            if model.isLoadingNewest {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 10)
            }
        }
    }

    @ViewBuilder
    private func word(_ section: NewestSection) -> some View {
        if section == model.newestSection {
            Text(section.word)
                .foregroundStyle(.secondary)
        } else {
            Button {
                Task { await model.showNewest(section) }
            } label: {
                Text(section.word)
                    .underline(pattern: .dot)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Только \(section.word)")
        }
    }
}
