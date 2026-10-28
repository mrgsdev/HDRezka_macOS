import AppKit
import SwiftUI

/// The update window: offers a newer release with its notes under «Что нового»,
/// or says the app is up to date when the check was started from the menu.
struct UpdateView: View {
    @State private var updater = Updater.shared
    @State private var showsNotes = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if updater.state == .idle {
                Task { await updater.checkNow() }
            }
        }
        .onDisappear {
            updater.windowClosed()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .idle, .checking:
            Text("Проверка обновлений").font(.headline)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Ищем новую версию на GitHub…").foregroundStyle(.secondary)
            }
            buttons {
                Button("Отмена", role: .cancel) { dismiss() }
            }

        case .upToDate:
            Text("У вас последняя версия").font(.headline)
            Text("REZKA \(Updater.currentVersion) — самая новая версия.")
                .foregroundStyle(.secondary)
            buttons {
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

        case let .available(release):
            Text("Доступна новая версия REZKA").font(.headline)
            Text("Версия \(release.version) — у вас \(Updater.currentVersion). Хотите обновить приложение?")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsNotes.toggle() }
            } label: {
                Label("Что нового", systemImage: showsNotes ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.link)
            if showsNotes {
                ScrollView {
                    ReleaseNotes(text: release.body ?? "")
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            buttons {
                Button("Позже", role: .cancel) { dismiss() }
                Button("Обновить") { updater.install(release) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }

        case let .downloading(release):
            Text("Обновление до версии \(release.version)").font(.headline)
            ProgressView()
                .progressViewStyle(.linear)
            Text("Загружаем и устанавливаем. REZKA перезапустится сама.")
                .foregroundStyle(.secondary)
            buttons {
                Button("Отмена", role: .cancel) { dismiss() }
            }

        case let .failed(message, release):
            Text("Не получилось").font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Открыть страницу релиза") {
                    NSWorkspace.shared.open(release?.htmlURL ?? Updater.releasesPage)
                }
                Button("Закрыть") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
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

/// The release description from GitHub: headings, bullet lists and paragraphs with inline Markdown.
private struct ReleaseNotes: View {
    let text: String

    private var lines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if lines.isEmpty {
                Text("Описание изменений не указано.").foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func row(_ line: String) -> some View {
        if line.hasPrefix("#") {
            Text(Self.inline(String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                .font(.headline)
                .padding(.top, 4)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(Self.inline(String(line.dropFirst(2))))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(Self.inline(line))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func inline(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}
