import AppKit
import SwiftUI

@main
struct RezkaApp: App {
    init() {
        URLCache.shared = URLCache(memoryCapacity: 80 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
        AppearancePreference.current.apply()
    }

    var body: some Scene {
        WindowGroup("REZKA", id: "main") {
            RootView()
                .environment(AuthSession.shared)
                .environment(WatchProgressStore.shared)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1320, height: 860)
        .commands { AppCommands() }

        WindowGroup("Плеер", id: "player", for: PlaybackRequest.self) { $request in
            if let request {
                PlayerView(request: request)
                    .environment(AuthSession.shared)
                    // Video looks best framed in dark, whatever the app's theme.
                    .preferredColorScheme(.dark)
            }
        }
        .defaultSize(width: 1280, height: 760)
        // Otherwise macOS reopens the last player window at launch and it starts playing by itself.
        .restorationBehavior(.disabled)

        Window("Обновление REZKA", id: "update") {
            UpdateView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        // Keeps it out of the Window menu; it opens by itself or from "Проверить обновления…".
        .commandsRemoved()

        Window("Горячие клавиши", id: "shortcuts") {
            ShortcutsView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        // It opens from the Help menu.
        .commandsRemoved()

        Settings {
            SettingsView()
                .environment(AuthSession.shared)
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
        .task { await offerUpdate() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await offerUpdate() }
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

    /// Looks for a new release at launch and then at most twice a day; the window opens only when there is one.
    private func offerUpdate() async {
        if await Updater.shared.checkInBackground() {
            openWindow(id: "update")
        }
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
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("О программе REZKA") { AboutPanel.show() }
            Button("Проверить обновления…") { checkForUpdates() }
        }
        // No "New Window": a second library window would load everything twice and share the first
        // one's sidebar, and the player's would open empty. The group can't be left empty either:
        // SwiftUI then drops the whole File menu, and Close (⌘W) with it.
        CommandGroup(replacing: .newItem) {
            Button("Главное окно") { showMainWindow() }
                .keyboardShortcut("0")
        }
        // Instead of the system "REZKA Help", which only says there is none.
        CommandGroup(replacing: .help) {
            Button("Горячие клавиши") { openWindow(id: "shortcuts") }
                .keyboardShortcut("/")
        }
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

extension AppCommands {
    @MainActor
    private func checkForUpdates() {
        openWindow(id: "update")
        Task { await Updater.shared.checkNow() }
    }

    /// Brings the library window forward, or opens it again after it was closed.
    @MainActor
    private func showMainWindow() {
        let window = NSApp.windows.first {
            $0.identifier?.rawValue.hasPrefix("main") == true && ($0.isVisible || $0.isMiniaturized)
        }
        guard let window else {
            openWindow(id: "main")
            return
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
}

enum AboutPanel {
    @MainActor
    static func show() {
        let mirror = Mirror.current.host() ?? Mirror.current.absoluteString
        let credits = NSAttributedString(
            string: String(localized: "Неофициальный клиент HDrezka для Mac\nЗеркало: \(mirror)\nРазработчик: github.com/mrgsdev"),
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
