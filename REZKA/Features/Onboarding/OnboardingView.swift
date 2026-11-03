import SwiftUI

/// A tour of the app, shown once after signing in and again from Help: a page for each part of it,
/// with what it does and where it lives.
struct OnboardingView: View {
    struct Feature: Hashable {
        let symbol: String
        let title: String
        let text: String
    }

    struct Page: Identifiable {
        enum Art {
            case logo
            case symbol(String)
            case medal(String)
        }

        let id: Int
        let art: Art
        let title: String
        let subtitle: String
        let features: [Feature]
        /// Short labels floating round the picture.
        let chips: [String]
        /// The last page: its subtitle is the developer's note, and the disclaimer stands in for features.
        var isFarewell = false
    }

    /// The same points as Help → «Отказ от ответственности и лицензии», put shortly.
    static let disclaimer = [
        String(localized: "Программа предоставляется «как есть», без каких-либо гарантий."),
        String(localized: "REZKA не связана с HDrezka и не является её официальным клиентом."),
        String(localized: "REZKA ничего не размещает и не хранит. Фильмы, сериалы, постеры и описания принадлежат правообладателям."),
        String(localized: "Автор не поощряет какую-либо незаконную деятельность."),
        String(localized: "Используйте программу на свой страх и риск и соблюдайте законы своей страны."),
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @AppStorage("onboardingSeen") private var isSeen = false
    @State private var index = 0
    @State private var isForward = true
    @State private var isFloating = false

    static let pages: [Page] = [
        Page(id: 0, art: .logo,
             title: String(localized: "Добро пожаловать в REZKA"),
             subtitle: String(localized: "Неофициальный клиент HDrezka для Mac. Быстрый, нативный и с вещами, которых нет на сайте."),
             features: [
                Feature(symbol: "play.rectangle.fill", title: String(localized: "Смотрите без браузера"),
                        text: String(localized: "Нативный плеер, продолжение с того же места и горячие клавиши.")),
                Feature(symbol: "sparkles", title: String(localized: "Больше, чем на сайте"),
                        text: String(localized: "Рулетка, итоги, достижения, кинопаспорт и детский режим.")),
                Feature(symbol: "lock.shield", title: String(localized: "Ваши данные у вас"),
                        text: String(localized: "Статистика и достижения хранятся только на этом Mac.")),
             ],
             chips: [String(localized: "Фильмы"), String(localized: "Сериалы"), String(localized: "Мультфильмы"), String(localized: "Аниме")]),
        Page(id: 1, art: .symbol("square.grid.2x2.fill"),
             title: String(localized: "Каталог и поиск"),
             subtitle: String(localized: "Всё, что есть на сайте, в удобных разделах слева."),
             features: [
                Feature(symbol: "film", title: String(localized: "Разделы и жанры"),
                        text: String(localized: "Фильмы, сериалы, мультфильмы, аниме, передачи и шоу. Жанры, страны и лучшие по годам.")),
                Feature(symbol: "square.stack", title: String(localized: "Подборки и закладки"),
                        text: String(localized: "Подборки сайта и ваши папки закладок.")),
                Feature(symbol: "magnifyingglass", title: String(localized: "Поиск"),
                        text: String(localized: "Ищите по названию. ⌘F открывает поиск из любого места.")),
                Feature(symbol: "info.circle", title: String(localized: "Подсказка на постере"),
                        text: String(localized: "Наведите на метку «Фильм» или «Сериал», чтобы увидеть рейтинг и описание.")),
             ],
             chips: [String(localized: "Жанры"), String(localized: "Подборки"), String(localized: "Лучшие"), String(localized: "Закладки")]),
        Page(id: 2, art: .symbol("film.stack.fill"),
             title: String(localized: "Карточка тайтла"),
             subtitle: String(localized: "Всё о фильме или сериале на одной странице."),
             features: [
                Feature(symbol: "waveform", title: String(localized: "Озвучки"),
                        text: String(localized: "Выбор озвучки, её популярность и какие сезоны в ней есть.")),
                Feature(symbol: "list.number", title: String(localized: "Сезоны и график"),
                        text: String(localized: "Серии с прогрессом, даты выхода и отметки «просмотрено».")),
                Feature(symbol: "star.fill", title: String(localized: "Оценки и отзывы"),
                        text: String(localized: "IMDb, Кинопоиск, ваша оценка звёздами и лайки отзывам.")),
                Feature(symbol: "play.rectangle", title: String(localized: "Трейлер и франшиза"),
                        text: String(localized: "Трейлер на YouTube и все части франшизы по порядку.")),
             ],
             chips: ["IMDb", String(localized: "Озвучки"), String(localized: "Трейлер"), String(localized: "Франшиза")]),
        Page(id: 3, art: .symbol("play.circle.fill"),
             title: String(localized: "Плеер"),
             subtitle: String(localized: "Нативный плеер macOS со всем, что нужно для сериалов."),
             features: [
                Feature(symbol: "clock.arrow.circlepath", title: String(localized: "Продолжение"),
                        text: String(localized: "Позиция сохраняется и уходит на сайт, так что смотреть можно и на других устройствах.")),
                Feature(symbol: "forward.end.fill", title: String(localized: "Следующая серия"),
                        text: String(localized: "Включается сама после конца серии или по ⇧⌘N.")),
                Feature(symbol: "captions.bubble", title: String(localized: "Субтитры, скорость, качество"),
                        text: String(localized: "Всё в панели плеера. Качество по умолчанию выбирается в Настройках.")),
                Feature(symbol: "arrow.down.circle", title: String(localized: "Загрузка"),
                        text: String(localized: "В заголовке окна видно, насколько фильм или серия загрузились для быстрой перемотки.")),
             ],
             chips: ["1080p", "1,5×", String(localized: "Субтитры"), "⇧⌘N"]),
        Page(id: 4, art: .symbol("dice.fill"),
             title: String(localized: "Что посмотреть?"),
             subtitle: String(localized: "Когда не можете выбрать, пусть выберет случай."),
             features: [
                Feature(symbol: "dice", title: String(localized: "Рулетка"),
                        text: String(localized: "Барабан из постеров крутится и останавливается на фильме.")),
                Feature(symbol: "rectangle.portrait.on.rectangle.portrait.angled.fill", title: String(localized: "Скретч-карта"),
                        text: String(localized: "Сотрите фольгу и узнайте фильм на вечер.")),
                Feature(symbol: "slider.horizontal.3", title: String(localized: "Фильтры"),
                        text: String(localized: "Раздел, жанры, страны, годы и рейтинг IMDb.")),
             ],
             chips: [String(localized: "IMDb от 7"), String(localized: "Жанры"), String(localized: "Страны"), String(localized: "Годы")]),
        Page(id: 5, art: .medal("films-100"),
             title: String(localized: "Итоги"),
             subtitle: String(localized: "Сколько, когда и что вы смотрели в REZKA."),
             features: [
                Feature(symbol: "chart.bar.xaxis", title: String(localized: "Часы и календарь"),
                        text: String(localized: "График по месяцам и календарь просмотров, как вклады на GitHub.")),
                Feature(symbol: "target", title: String(localized: "Цель на год"),
                        text: String(localized: "Сколько фильмов хотите посмотреть и как идёте по плану.")),
                Feature(symbol: "globe.europe.africa.fill", title: String(localized: "Кинопаспорт"),
                        text: String(localized: "Штампы стран, золотые визы и вид на жительство.")),
                Feature(symbol: "medal.fill", title: String(localized: "Достижения"),
                        text: String(localized: "Медали в стиле Apple Watch за фильмы, сериалы, привычки и страны.")),
             ],
             chips: [String(localized: "Цель"), String(localized: "Паспорт"), String(localized: "Медали"), String(localized: "Озвучки")]),
        Page(id: 6, art: .symbol("lock.shield.fill"),
             title: String(localized: "Детский режим"),
             subtitle: String(localized: "Спокойствие, если за Mac садятся дети. Включается в Настройках."),
             features: [
                Feature(symbol: "figure.and.child.holdinghands", title: String(localized: "Возраст"),
                        text: String(localized: "0+, 6+, 12+ или 16+. Всё, что старше, скрыто и не запускается.")),
                Feature(symbol: "lock.fill", title: String(localized: "PIN-код"),
                        text: String(localized: "Изменить или выключить режим можно только с PIN-кодом.")),
                Feature(symbol: "key.fill", title: String(localized: "Код восстановления"),
                        text: String(localized: "Если PIN забыт, поможет код, который показывается один раз.")),
             ],
             chips: ["0+", "6+", "12+", "16+"]),
        Page(id: 7, art: .symbol("lightbulb.fill"),
             title: String(localized: "Полезные мелочи"),
             subtitle: String(localized: "Несколько вещей, которые пригодятся каждый день."),
             features: [
                Feature(symbol: "keyboard", title: String(localized: "Горячие клавиши"),
                        text: String(localized: "Разделы открываются по ⌘1…⌘9, все сочетания показывает ⌘/.")),
                Feature(symbol: "paintbrush", title: String(localized: "Тема и язык"),
                        text: String(localized: "Светлая, тёмная или как в системе. Русский или английский интерфейс.")),
                Feature(symbol: "arrow.triangle.2.circlepath", title: String(localized: "Зеркала и обновления"),
                        text: String(localized: "Если сайт не открывается, найдите зеркало в Настройках. Обновления приложение проверяет само.")),
                Feature(symbol: "questionmark.circle", title: String(localized: "Это знакомство"),
                        text: String(localized: "Открывается снова в меню Справка.")),
             ],
             chips: ["⌘F", "⌘/", "⌘,", "⇧⌘N"]),
        Page(id: 8, art: .symbol("heart.text.square.fill"),
             title: String(localized: "Пара слов от разработчика"),
             subtitle: String(localized: "Я сделал REZKA для себя, потому что сам смотрю через неё фильмы и сериалы каждый день. Буду рад, если приложение пригодится и вам. Только, пожалуйста, помните о правилах сайта."),
             features: [],
             chips: [String(localized: "Для себя"), String(localized: "Открытый код"), "MIT", String(localized: "Бесплатно")],
             isFarewell: true),
    ]

    private var page: Page { Self.pages[index] }
    private var isLast: Bool { index == Self.pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if !isLast {
                    Button("Пропустить", action: finish)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .frame(height: 28)
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ZStack {
                content(page)
                    .id(page.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: isForward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: isForward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
        }
        .frame(width: 900, height: 580)
        .background {
            ZStack {
                Brand.background
                RadialGradient(colors: [Color.accentColor.opacity(0.28), .clear], center: UnitPoint(x: 0.22, y: 0.4), startRadius: 0, endRadius: 420)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { isFloating = true }
        }
    }

    // MARK: Page

    private func content(_ page: Page) -> some View {
        HStack(spacing: 44) {
            art(page)
                .frame(width: 320, height: 400)
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(page.title)
                        .font(.system(size: 30, weight: .bold))
                    if !page.isFarewell {
                        Text(page.subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if page.isFarewell {
                    farewell(page)
                } else {
                    features(page)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 48)
    }

    private func features(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(page.features, id: \.self) { feature in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.headline)
                        Text(feature.text)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// The developer's note in a card, then the disclaimer point by point and where to read it in full.
    private func farewell(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(page.subtitle)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 14)
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 4)
                        .padding(.vertical, 12)
                        .padding(.leading, 8)
                }
            VStack(alignment: .leading, spacing: 7) {
                Label("Отказ от ответственности", systemImage: "exclamationmark.shield.fill")
                    .font(.headline)
                    .padding(.bottom, 2)
                ForEach(Self.disclaimer, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "•")
                            .foregroundStyle(Color.accentColor)
                        Text(line)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                }
            }
            HStack(spacing: 18) {
                Link(destination: URL(string: "https://rezka.ag/rules/")!) {
                    Label("Правила сайта HDrezka", systemImage: "doc.text")
                }
                Button {
                    openWindow(id: "legal")
                } label: {
                    Label("Отказ от ответственности и лицензии…", systemImage: "info.circle")
                }
                .buttonStyle(.link)
            }
            .font(.callout)
        }
    }

    /// Two tilted tiles behind the page's picture, with its labels floating round them.
    private func art(_ page: Page) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40)
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.08)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 210, height: 210)
                .rotationEffect(.degrees(-9))
            RoundedRectangle(cornerRadius: 40)
                .fill(Brand.panel)
                .overlay(RoundedRectangle(cornerRadius: 40).strokeBorder(Brand.stroke))
                .frame(width: 210, height: 210)
                .rotationEffect(.degrees(6))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)

            switch page.art {
            case .logo:
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 170)
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: 80, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 18)
            case let .medal(id):
                if let medal = Achievement.all.first(where: { $0.id == id })?.medal {
                    MedalView(medal: medal, size: 170)
                }
            }

            ForEach(Array(page.chips.enumerated()), id: \.offset) { index, chip in
                Text(verbatim: chip)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Brand.stroke))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .offset(Self.chipPlaces[index % Self.chipPlaces.count])
                    .offset(y: isFloating ? (index.isMultiple(of: 2) ? -6 : 6) : 0)
            }
        }
    }

    private static let chipPlaces = [CGSize(width: -112, height: -132), CGSize(width: 118, height: -96),
                                     CGSize(width: -124, height: 108), CGSize(width: 110, height: 140)]

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Self.pages) { item in
                    Capsule()
                        .fill(item.id == index ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: item.id == index ? 22 : 8, height: 8)
                        .onTapGesture { go(to: item.id) }
                }
            }
            .animation(.easeOut(duration: 0.25), value: index)
            Spacer()
            if index > 0 {
                Button("Назад") { go(to: index - 1) }
                    .controlSize(.large)
            }
            Button(isLast ? "Начать" : "Далее") {
                if isLast { finish() } else { go(to: index + 1) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func go(to target: Int) {
        guard target != index, Self.pages.indices.contains(target) else { return }
        isForward = target > index
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { index = target }
    }

    private func finish() {
        isSeen = true
        dismiss()
    }
}
