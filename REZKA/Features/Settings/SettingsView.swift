import SwiftUI

/// The app's Settings window (⌘,).
struct SettingsView: View {
    @Environment(AuthSession.self) private var auth

    @State private var mirror = Mirror.current.absoluteString
    @State private var mirrorStatus: String?
    @State private var foundMirrors: [URL] = []
    @State private var isSearchingMirrors = false
    @State private var quality = QualityPreference.current
    @State private var confirmLogout = false

    static let mirrorHint = "Напишите на mirror@hdrezka.org, чтобы узнать актуальное зеркало, и введите его сюда."

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    var body: some View {
        Form {
            Section("Аккаунт") {
                LabeledContent("Статус", value: auth.isLoggedIn ? "Вход выполнен" : "Не выполнен вход")
                LabeledContent("Подписка", value: auth.isPremium ? "HDrezka Premium" : "Обычный аккаунт")
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
                Text(mirrorStatus ?? "\(Self.mirrorHint) Сессия перенесётся на новое зеркало.")
                    .foregroundStyle(.secondary)
            }

            Section("Воспроизведение") {
                Picker("Качество по умолчанию", selection: $quality) {
                    ForEach(QualityPreference.options, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: quality) { _, value in QualityPreference.current = value }
            }

            Section("О приложении") {
                LabeledContent("Версия", value: "\(Self.version) (\(Self.build))")
                LabeledContent("Разработчик") {
                    Link("github.com/mrgsdev", destination: URL(string: "https://github.com/mrgsdev")!)
                }
                Text("Неофициальный клиент HDrezka для Mac. Проект не связан с HDrezka.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 560)
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout) {
            Button("Выйти", role: .destructive) { Task { await auth.logout() } }
        }
    }

    private func applyMirror() {
        guard let url = Mirror.normalize(mirror) else {
            mirrorStatus = "Некорректный адрес"
            return
        }
        apply(url)
    }

    private func apply(_ url: URL) {
        Mirror.current = url
        mirror = url.absoluteString
        mirrorStatus = "Сохранено: \(url.host() ?? url.absoluteString)"
        auth.refresh()
    }

    private func findMirrors() async {
        isSearchingMirrors = true
        mirrorStatus = nil
        foundMirrors = await Mirror.findWorking()
        isSearchingMirrors = false

        if foundMirrors.isEmpty {
            mirrorStatus = "Рабочих зеркал не нашли. \(Self.mirrorHint)"
        } else if foundMirrors.contains(Mirror.current) {
            mirrorStatus = "Текущее зеркало работает. Можно выбрать и другое из найденных."
        } else {
            mirrorStatus = "Текущее зеркало не отвечает — выберите одно из найденных."
        }
    }
}
