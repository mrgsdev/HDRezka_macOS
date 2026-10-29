import SwiftUI

/// "Справка → Горячие клавиши": every shortcut the app has, grouped like the app itself.
struct ShortcutsView: View {
    private struct Shortcut: Identifiable {
        let keys: [String]
        let action: String

        var id: String { action }
    }

    private struct ShortcutGroup: Identifiable {
        let title: String
        let shortcuts: [Shortcut]

        var id: String { title }
    }

    /// Two columns, so the whole list is in view at once.
    private static let left: [ShortcutGroup] = [
        ShortcutGroup(title: "Разделы", shortcuts: [
            Shortcut(keys: ["⌘", "1"], action: "Главная"),
            Shortcut(keys: ["⌘", "2"], action: "Фильмы"),
            Shortcut(keys: ["⌘", "3"], action: "Сериалы"),
            Shortcut(keys: ["⌘", "4"], action: "Мультфильмы"),
            Shortcut(keys: ["⌘", "5"], action: "Аниме"),
            Shortcut(keys: ["⌘", "6"], action: "Подборки"),
            Shortcut(keys: ["⌘", "7"], action: "Закладки"),
            Shortcut(keys: ["⌘", "F"], action: "Поиск"),
        ]),
        ShortcutGroup(title: "Главная и карточка", shortcuts: [
            Shortcut(keys: ["⌘", "R"], action: "Обновить главную"),
            Shortcut(keys: ["↩"], action: "Смотреть или продолжить в карточке"),
        ]),
    ]

    private static let right: [ShortcutGroup] = [
        ShortcutGroup(title: "Плеер", shortcuts: [
            Shortcut(keys: ["Пробел"], action: "Пауза и воспроизведение"),
            // AVPlayerView's own keys, as in QuickTime Player.
            Shortcut(keys: ["←", "→"], action: "Пауза и шаг на кадр назад или вперёд"),
            Shortcut(keys: ["⇧", "⌘", "N"], action: "Следующая серия"),
            Shortcut(keys: ["⌃", "⌘", "F"], action: "Во весь экран"),
            Shortcut(keys: ["⌘", "W"], action: "Закрыть плеер, позиция сохранится"),
        ]),
        ShortcutGroup(title: "Окна", shortcuts: [
            Shortcut(keys: ["⌘", "0"], action: "Главное окно, в том числе после закрытия"),
            Shortcut(keys: ["⌘", ","], action: "Настройки"),
            Shortcut(keys: ["⌘", "W"], action: "Закрыть окно"),
            Shortcut(keys: ["⌘", "M"], action: "Свернуть окно"),
            Shortcut(keys: ["⌘", "/"], action: "Эта справка"),
            Shortcut(keys: ["⌘", "Q"], action: "Выйти из REZKA"),
        ]),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            column(Self.left)
            column(Self.right)
        }
        .frame(width: 900)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func column(_ groups: [ShortcutGroup]) -> some View {
        Form {
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.shortcuts) { shortcut in
                        LabeledContent(shortcut.action) {
                            HStack(spacing: 4) {
                                ForEach(shortcut.keys, id: \.self) { KeyCap(key: $0) }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 450, height: 560)
    }
}

/// One key drawn like a key on the keyboard.
private struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .frame(minWidth: 22)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Brand.panel, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Brand.stroke))
    }
}
