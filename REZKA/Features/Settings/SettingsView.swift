import SwiftUI

/// The app's Settings window (⌘,).
struct SettingsView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.openWindow) private var openWindow

    @State private var mirror = Mirror.current.absoluteString
    @State private var mirrorStatus: String?
    @State private var foundMirrors: [URL] = []
    @State private var isSearchingMirrors = false
    @State private var quality = QualityPreference.current
    @State private var appearance = AppearancePreference.current
    @State private var language = AppLanguage.current
    @State private var confirmLogout = false
    @State private var cacheSize = URLCache.shared.currentDiskUsage

    static let mirrorHint = String(localized: "Напишите на mirror@hdrezka.org, чтобы узнать актуальное зеркало, и введите его сюда.")

    /// The language the app runs in; another choice takes a relaunch.
    private static let launchLanguage = AppLanguage.current

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    var body: some View {
        Form {
            Section("Аккаунт") {
                if auth.isLoggedIn {
                    LabeledContent("Ник") {
                        if let name = auth.userName {
                            Text(name).textSelection(.enabled)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                LabeledContent("Статус", value: auth.isLoggedIn ? String(localized: "Вход выполнен") : String(localized: "Не выполнен вход"))
                LabeledContent("Подписка", value: auth.isPremium ? "HDrezka Premium" : String(localized: "Обычный аккаунт"))
                if auth.isLoggedIn {
                    Button("Выйти из аккаунта", role: .destructive) { confirmLogout = true }
                }
            }

            Section {
                TextField("Адрес", text: $mirror, prompt: Text("https://rezka.fi"))
                    .onSubmit(applyMirror)
                HStack {
                    Button("Применить зеркало", action: applyMirror)
                    Button("Найти рабочее зеркало") { Task { await findMirrors() } }
                        .disabled(isSearchingMirrors)
                    if isSearchingMirrors {
                        ProgressView().controlSize(.small)
                    }
                }
                ForEach(foundMirrors, id: \.self) { url in
                    LabeledContent(url.host() ?? url.absoluteString) {
                        if url == Mirror.current {
                            Text("Текущее").foregroundStyle(.secondary)
                        } else {
                            Button("Выбрать") { apply(url) }
                        }
                    }
                }
            } header: {
                Text("Зеркало сайта")
            } footer: {
                Text(mirrorStatus ?? String(localized: "\(Self.mirrorHint) Сессия перенесётся на новое зеркало."))
                    .foregroundStyle(.secondary)
            }

            Section("Оформление") {
                Picker("Тема", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, value in AppearancePreference.current = value }
                Picker("Язык", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: language) { _, value in AppLanguage.current = value }
                if language != Self.launchLanguage {
                    HStack {
                        Text("Язык сменится после перезапуска.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Перезапустить") { try? AppRelaunch.relaunch() }
                    }
                }
            }

            Section("Воспроизведение") {
                Picker("Качество по умолчанию", selection: $quality) {
                    ForEach(QualityPreference.options, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                }
                .onChange(of: quality) { _, value in QualityPreference.current = value }
            }

            Section {
                LabeledContent("Кэш на диске", value: Int64(cacheSize).formatted(.byteCount(style: .file)))
                Button("Очистить кэш", action: clearCache)
                    .disabled(cacheSize == 0)
            } header: {
                Text("Хранилище")
            } footer: {
                Text("Постеры и страницы сайта, чтобы не скачивать их заново; не больше 400 МБ. Видео не сохраняется.")
                    .foregroundStyle(.secondary)
            }

            Section("О приложении") {
                LabeledContent("Версия", value: "\(Self.version) (\(Self.build))")
                Button("Проверить обновления…") {
                    openWindow(id: "update")
                    Task { await Updater.shared.checkNow() }
                }
                LabeledContent("Разработчик") {
                    Link("github.com/mrgsdev", destination: URL(string: "https://github.com/mrgsdev")!)
                }
                Text("Неофициальный клиент HDrezka для Mac. Проект не связан с HDrezka.")
                    .foregroundStyle(.secondary)
                Button("Отказ от ответственности и лицензии…") { openWindow(id: "legal") }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 560)
        // The site may have renamed the account since; the last known name shows meanwhile.
        .task { await auth.refreshUserName() }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout) {
            Button("Выйти", role: .destructive) { Task { await auth.logout() } }
        }
    }

    /// Posters and pages load again from the site after this; the session and history stay.
    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        PosterCache.removeAll()
        cacheSize = URLCache.shared.currentDiskUsage
    }

    private func applyMirror() {
        guard let url = Mirror.normalize(mirror) else {
            mirrorStatus = String(localized: "Некорректный адрес")
            return
        }
        apply(url)
    }

    private func apply(_ url: URL) {
        Mirror.current = url
        mirror = url.absoluteString
        mirrorStatus = String(localized: "Сохранено: \(url.host() ?? url.absoluteString)")
        auth.refresh()
    }

    private func findMirrors() async {
        isSearchingMirrors = true
        mirrorStatus = nil
        foundMirrors = await Mirror.findWorking()
        isSearchingMirrors = false

        if foundMirrors.isEmpty {
            mirrorStatus = String(localized: "Рабочих зеркал не нашли. \(Self.mirrorHint)")
        } else if foundMirrors.contains(Mirror.current) {
            mirrorStatus = String(localized: "Текущее зеркало работает. Можно выбрать и другое из найденных.")
        } else {
            mirrorStatus = String(localized: "Текущее зеркало не отвечает — выберите одно из найденных.")
        }
    }
}
