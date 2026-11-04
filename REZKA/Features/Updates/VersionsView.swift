import AppKit
import SwiftUI

/// «Другие версии…» from Settings: every release on GitHub with its notes, and a way to install any of
/// them, back to an older one too. Before installing it tells what to expect, then the updater does
/// the rest as for an update: download, the same signature check, the swap and a relaunch.
struct VersionsView: View {
    @State private var updater = Updater.shared
    @State private var releases: [AppRelease] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var expanded: Set<String> = []
    /// The version picked to install, waiting for the go-ahead under «Что важно знать заранее».
    @State private var pending: AppRelease?
    @Environment(\.dismiss) private var dismiss

    private var newest: AppRelease? { releases.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
        }
        .padding(24)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .task { await load() }
        .onDisappear {
            if case .downloading = updater.state { updater.cancelInstall() }
            if case .failed = updater.state { updater.cancelInstall() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("Версии REZKA").font(.headline)
                Text("Установлена версия \(Updater.currentVersion). Здесь можно вернуться к прошлой версии или поставить другую.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case let .downloading(release):
            Text("Устанавливаем версию \(release.version)").font(.headline)
            ProgressView().progressViewStyle(.linear)
            Text("Загружаем и устанавливаем. REZKA перезапустится сама.")
                .foregroundStyle(.secondary)
            buttons {
                Button("Отмена", role: .cancel) { updater.cancelInstall() }
            }
        case let .failed(message, release) where pending != nil:
            Text("Не получилось").font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Открыть страницу релиза") {
                    NSWorkspace.shared.open(release?.htmlURL ?? Updater.releasesPage)
                }
                Button("К списку версий") {
                    updater.cancelInstall()
                    pending = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        default:
            if let pending {
                confirmation(pending)
            } else {
                list
            }
        }
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if isLoading, releases.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Загружаем список версий с GitHub…").foregroundStyle(.secondary)
            }
        } else if let loadError, releases.isEmpty {
            Text(loadError)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Открыть страницу релизов") { NSWorkspace.shared.open(Updater.releasesPage) }
                Button("Повторить") { Task { await load() } }
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(releases) { row($0) }
                }
            }
            .frame(maxHeight: 380)
            buttons {
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func row(_ release: AppRelease) -> some View {
        let isCurrent = release.version == Updater.currentVersion
        let isOpen = expanded.contains(release.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("REZKA \(release.version)").font(.body.weight(.semibold))
                if let date = release.publishedDate {
                    Text(date.formatted(.dateTime.day().month(.wide).year().locale(AppLanguage.locale)))
                        .foregroundStyle(.secondary)
                }
                if isCurrent {
                    badge(String(localized: "Установлена"), color: .green)
                } else if release.id == newest?.id {
                    badge(String(localized: "Последняя"), color: .accentColor)
                }
                if release.version == updater.skippedVersion {
                    badge(String(localized: "Пропущена"), color: .secondary)
                }
                Spacer()
                // The installed one has its label beside the version instead.
                if !isCurrent {
                    Button(Self.isOlder(release) ? String(localized: "Вернуться") : String(localized: "Установить")) {
                        pending = release
                    }
                }
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { expanded.remove(release.id) } else { expanded.insert(release.id) }
                }
            } label: {
                Label("Что нового", systemImage: isOpen ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.link)
            if isOpen {
                ReleaseNotes(text: release.body ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    // MARK: Confirmation

    private func confirmation(_ release: AppRelease) -> some View {
        let older = Self.isOlder(release)
        return VStack(alignment: .leading, spacing: 12) {
            Text(older ? "Вернуться к версии \(release.version)?" : "Установить версию \(release.version)?")
                .font(.headline)
            Text("Что важно знать заранее")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            UpdateNotesBox(notes: notes(for: release))
            buttons {
                Button("Отмена", role: .cancel) { pending = nil }
                Button(older ? "Вернуться к \(release.version)" : "Установить \(release.version)") {
                    updater.install(release, allowingOlder: true, newest: newest)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private typealias Note = UpdateNote

    /// What changes for the viewer with this version, older or newer than the one installed.
    private func notes(for release: AppRelease) -> [Note] {
        let version = release.version
        var notes = [Note(symbol: "checkmark.circle",
                          text: String(localized: "Вход, настройки, история просмотров и Итоги сохранятся: приложение то же и с той же подписью."))]
        guard Self.isOlder(release) else {
            if let newest, newest.id != release.id {
                notes.append(Note(symbol: "info.circle",
                                  text: String(localized: "Это не последняя версия. О версии \(newest.version) REZKA сообщит как обычно.")))
            }
            notes.append(Note(symbol: "arrow.clockwise", text: String(localized: "После установки REZKA перезапустится сама.")))
            return notes
        }
        notes.append(Note(symbol: "exclamationmark.triangle",
                          text: String(localized: "Версия \(version) не знает о том, что появилось позже. Новые настройки и часть Итогов в ней могут не отображаться, но не пропадут: после обновления всё вернётся."),
                          isWarning: true))
        if Updater.knowsSkipping(version) {
            let skipped = newest?.version ?? Updater.currentVersion
            notes.append(Note(symbol: "forward",
                              text: String(localized: "Версия \(skipped) будет пропущена: сама она предлагаться не будет. О более новой версии REZKA сообщит как обычно.")))
        } else {
            notes.append(Note(symbol: "bell",
                              text: String(localized: "В версии \(version) ещё нет кнопки «Пропустить эту версию», поэтому при запуске она будет предлагать обновиться. Нажимайте «Позже»."),
                              isWarning: true))
        }
        notes.append(Note(symbol: "arrow.uturn.forward",
                          text: String(localized: "Вернуться на новую версию можно в любой момент через «Проверить обновления…» в меню REZKA или в Настройках.")))
        return notes
    }

    private static func isOlder(_ release: AppRelease) -> Bool {
        Updater.isVersion(Updater.currentVersion, newerThan: release.version)
    }

    // MARK: Loading

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        do {
            releases = try await updater.releases()
        } catch {
            if !error.isCancellation {
                loadError = String(localized: "Не удалось загрузить список версий: \(error.localizedDescription)")
            }
        }
        isLoading = false
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack {
            Spacer()
            content()
        }
        .controlSize(.large)
        .padding(.top, 4)
    }
}

/// A line of «Что важно знать заранее»: before an update, or before going back to an older version.
struct UpdateNote {
    let symbol: String
    let text: String
    var isWarning = false

    /// For an ordinary update to a newer version.
    static var forUpdate: [UpdateNote] {
        [
            UpdateNote(symbol: "checkmark.circle",
                       text: String(localized: "Вход, настройки, история просмотров и Итоги сохранятся: приложение то же и с той же подписью.")),
            UpdateNote(symbol: "arrow.clockwise", text: String(localized: "После установки REZKA перезапустится сама.")),
            UpdateNote(symbol: "arrow.uturn.backward",
                       text: String(localized: "Если новая версия не понравится, вернуться к прошлой можно в Настройках: «Другие версии…».")),
        ]
    }
}

/// The notes on a panel, each with its symbol; warnings in orange.
struct UpdateNotesBox: View {
    let notes: [UpdateNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: note.symbol)
                        .foregroundStyle(note.isWarning ? Color.orange : Color.secondary)
                        .frame(width: 16)
                    Text(note.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 10))
    }
}
