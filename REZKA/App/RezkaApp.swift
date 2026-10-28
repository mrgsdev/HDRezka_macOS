import AppKit
import SwiftUI

@main
struct RezkaApp: App {
    init() {
        URLCache.shared = URLCache(memoryCapacity: 80 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup("REZKA", id: "main") {
            RootView()
                .environment(AuthSession.shared)
                .environment(WatchProgressStore.shared)
                .preferredColorScheme(.dark)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1320, height: 860)
        .commands { AppCommands() }

        WindowGroup("Плеер", id: "player", for: PlaybackRequest.self) { $request in
            if let request {
                PlayerView(request: request)
                    .environment(AuthSession.shared)
                    .preferredColorScheme(.dark)
            }
        }
        .defaultSize(width: 1280, height: 760)
        // Otherwise macOS reopens the last player window at launch and it starts playing by itself.
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(AuthSession.shared)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if auth.isLoggedIn {
                MainView()
            } else {
                LoginView()
            }
        }
        .onAppear {
            PlayerPresenter.open = { openWindow(id: "player", value: $0) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            persist()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            persist()
        }
    }

    private func persist() {
        CookieVault.save()
        WatchProgressStore.shared.persist()
    }
}

/// Opens the player window. Details screens call it through `DetailsModel.play`.
@MainActor
enum PlayerPresenter {
    static var open: ((PlaybackRequest) -> Void)?

    static func present(_ request: PlaybackRequest) {
        open?(request)
    }
}

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("О программе REZKA") { AboutPanel.show() }
        }
        // One library window is enough; extra ones would load everything twice.
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Разделы") {
            Button("Главная") { Router.shared.selection = .home }
                .keyboardShortcut("1")
            Button("Поиск") { Router.shared.focusSearch() }
                .keyboardShortcut("f")
            Divider()
            ForEach(Array(CatalogSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { Router.shared.selection = .section(section) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 2))))
            }
            Divider()
            Button("Подборки") { Router.shared.selection = .collections }
                .keyboardShortcut("6")
            Button("Закладки") { Router.shared.selection = .bookmarks }
                .keyboardShortcut("7")
        }
    }
}

enum AboutPanel {
    @MainActor
    static func show() {
        let mirror = Mirror.current.host() ?? Mirror.current.absoluteString
        let credits = NSAttributedString(
            string: "Неофициальный клиент HDrezka для Mac\nЗеркало: \(mirror)\nРазработчик: github.com/mrgsdev",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }(),
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "REZKA", .credits: credits])
        NSApp.activate()
    }
}
