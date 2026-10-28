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
