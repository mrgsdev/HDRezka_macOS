import SwiftUI

/// Help → «Отказ от ответственности и лицензии», also opened from Settings: what the app is and is not,
/// whose the content is, and the licenses of the open-source code inside.
struct LegalView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("Отказ от ответственности") {
                    bullet("Программа предоставляется «как есть», без каких-либо гарантий.")
                    bullet("REZKA не связана с HDrezka и не является её официальным клиентом.")
                    bullet("Автор не поощряет какую-либо незаконную деятельность.")
                    bullet("Используйте программу на свой страх и риск и соблюдайте законы своей страны.")
                    Link("Правила сайта HDrezka", destination: URL(string: "https://rezka.ag/rules/")!)
                        .padding(.top, 4)
                }

                section("Содержимое") {
                    bullet("Фильмы, сериалы, постеры, описания и отзывы принадлежат их правообладателям и авторам.")
                    bullet("REZKA ничего не размещает и не хранит: она показывает страницы и видео сайта, который вы указали в настройках, через ваш аккаунт на нём.")
                    bullet("Вход, история просмотра и «Итоги» хранятся только на этом Mac.")
                }

                section("Лицензия") {
                    license(
                        name: "REZKA",
                        url: "https://github.com/mrgsdev/HDRezka_macOS",
                        kind: "MIT License",
                        text: Self.rezkaLicense
                    )
                }

                section("Открытые библиотеки") {
                    license(
                        name: "SwiftSoup",
                        url: "https://github.com/scinfu/SwiftSoup",
                        kind: "MIT License",
                        text: Self.swiftSoupLicense
                    )
                }

                section("Благодарности") {
                    Text("Разбор API сайта и идеи взяты из открытых проектов:")
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://github.com/Agnidia/rezka-payer")!) { Text(verbatim: "rezka-payer") }
                    Link(destination: URL(string: "https://github.com/voidboost/hdrezka-swiftui")!) { Text(verbatim: "hdrezka-swiftui (MIT)") }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 620, height: 640)
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "•")
                .foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func license(name: String, url: String, kind: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Link(name, destination: URL(string: url)!)
                    .font(.headline)
                Text(verbatim: kind)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.panel, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// The LICENSE file at the root of the repository.
    private static let rezkaLicense = """
        MIT License

        Copyright (c) 2026 mrgsdev

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all \
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
        SOFTWARE.
        """

    /// As shipped with SwiftSoup 2.14.3.
    private static let swiftSoupLicense = """
        The MIT License

        Copyright (c) 2009-2025 Jonathan Hedley <https://jsoup.org/>
        Copyright (c) 2016-2025 Nabil Chatbi (Swift port)

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all \
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
        SOFTWARE.
        """
}
