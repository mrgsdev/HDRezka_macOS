import SwiftUI

/// An award in «Итоги» for watching in REZKA; `AchievementTracker` gives them out.
struct Achievement: Identifiable {
    enum Category: CaseIterable {
        case start, time, films, series, habits, genres, world, roulette, goal

        var title: String {
            switch self {
            case .start: String(localized: "Первые шаги")
            case .time: String(localized: "Часы у экрана")
            case .films: String(localized: "Фильмы")
            case .series: String(localized: "Сериалы")
            case .habits: String(localized: "Привычки")
            case .genres: String(localized: "Жанры")
            case .world: String(localized: "Страны и эпохи")
            case .roulette: String(localized: "Что посмотреть?")
            case .goal: String(localized: "Цели и франшизы")
            }
        }
    }

    let id: String
    let category: Category
    let title: String
    /// What it takes.
    let detail: String
    let medal: Medal

    static let all: [Achievement] = [
        // Первые шаги
        Achievement(id: "premiere", category: .start, title: String(localized: "Премьера"), detail: String(localized: "Досмотрите первый фильм до конца."),
                    medal: Medal(.circle, .gold, .red, "popcorn.fill")),
        Achievement(id: "pilot", category: .start, title: String(localized: "Пилотная серия"), detail: String(localized: "Посмотрите первую серию сериала."),
                    medal: Medal(.circle, .silver, .blue, "tv.fill")),
        Achievement(id: "first-hour", category: .start, title: String(localized: "Первый час"), detail: String(localized: "Наберите первый час просмотра."),
                    medal: Medal(.circle, .bronze, .sky, "clock.fill")),
        Achievement(id: "season", category: .start, title: String(localized: "Сезон закрыт"), detail: String(localized: "Досмотрите целый сезон сериала."),
                    medal: Medal(.circle, .gold, .green, "rectangle.stack.fill")),
        Achievement(id: "collector", category: .start, title: String(localized: "Коллекционер"), detail: String(localized: "Добавьте 10 тайтлов в закладки."),
                    medal: Medal(.circle, .rose, .purple, "bookmark.fill")),
        Achievement(id: "critic", category: .start, title: String(localized: "Своё мнение"), detail: String(localized: "Оцените тайтл звёздами на сайте."),
                    medal: Medal(.circle, .platinum, .sky, "star.leadinghalf.filled")),

        // Часы у экрана
        Achievement(id: "hours-10", category: .time, title: String(localized: "Вечер кино"), detail: String(localized: "10 часов просмотра."),
                    medal: Medal(.hexagon, .bronze, .sky, "clock.fill", number: "10")),
        Achievement(id: "hours-50", category: .time, title: String(localized: "Киноман"), detail: String(localized: "50 часов просмотра."),
                    medal: Medal(.hexagon, .silver, .blue, "clock.fill", number: "50")),
        Achievement(id: "hours-100", category: .time, title: String(localized: "Сотня часов"), detail: String(localized: "100 часов просмотра."),
                    medal: Medal(.hexagon, .gold, .navy, "clock.fill", number: "100")),
        Achievement(id: "hours-250", category: .time, title: String(localized: "Четверть тысячи"), detail: String(localized: "250 часов просмотра."),
                    medal: Medal(.hexagon, .rose, .purple, "clock.fill", number: "250")),
        Achievement(id: "hours-500", category: .time, title: String(localized: "Полтысячи"), detail: String(localized: "500 часов просмотра."),
                    medal: Medal(.hexagon, .platinum, .wine, "clock.fill", number: "500")),
        Achievement(id: "hours-1000", category: .time, title: String(localized: "Тысяча часов"), detail: String(localized: "1000 часов просмотра — это почти 42 дня без перерыва."),
                    medal: Medal(.hexagon, .gold, .graphite, "clock.fill", number: "1000")),

        // Фильмы
        Achievement(id: "films-10", category: .films, title: String(localized: "Десятка"), detail: String(localized: "Досмотрите 10 фильмов."),
                    medal: Medal(.octagon, .bronze, .navy, "film.fill", number: "10")),
        Achievement(id: "films-25", category: .films, title: String(localized: "25-й кадр"), detail: String(localized: "Досмотрите 25 фильмов."),
                    medal: Medal(.octagon, .copper, .red, "film.fill", number: "25")),
        Achievement(id: "films-50", category: .films, title: String(localized: "Полсотни"), detail: String(localized: "Досмотрите 50 фильмов."),
                    medal: Medal(.octagon, .silver, .teal, "film.fill", number: "50")),
        Achievement(id: "films-100", category: .films, title: String(localized: "Сотня"), detail: String(localized: "Досмотрите 100 фильмов."),
                    medal: Medal(.octagon, .gold, .blue, "film.fill", number: "100")),
        Achievement(id: "films-250", category: .films, title: String(localized: "Синефил"), detail: String(localized: "Досмотрите 250 фильмов."),
                    medal: Medal(.octagon, .platinum, .wine, "film.fill", number: "250")),

        // Сериалы
        Achievement(id: "hooked", category: .series, title: String(localized: "Затянуло"), detail: String(localized: "3 серии одного сериала за день."),
                    medal: Medal(.shield, .silver, .teal, "fish.fill")),
        Achievement(id: "marathon", category: .series, title: String(localized: "Марафонец"), detail: String(localized: "10 серий за один день."),
                    medal: Medal(.shield, .gold, .orange, "figure.run")),
        Achievement(id: "finale", category: .series, title: String(localized: "Финал"), detail: String(localized: "Досмотрите сериал до последней серии."),
                    medal: Medal(.shield, .platinum, .graphite, "flag.checkered")),
        Achievement(id: "episodes-100", category: .series, title: String(localized: "Сто серий"), detail: String(localized: "Посмотрите 100 серий."),
                    medal: Medal(.shield, .bronze, .blue, "tv.fill", number: "100")),
        Achievement(id: "episodes-500", category: .series, title: String(localized: "Пятьсот серий"), detail: String(localized: "Посмотрите 500 серий."),
                    medal: Medal(.shield, .gold, .purple, "tv.fill", number: "500")),
        Achievement(id: "long-run", category: .series, title: String(localized: "Долгострой"), detail: String(localized: "Досмотрите сериал, в котором 10 сезонов и больше."),
                    medal: Medal(.shield, .copper, .green, "hourglass")),
        Achievement(id: "same-day", category: .series, title: String(localized: "В день выхода"), detail: String(localized: "Посмотрите новую серию в день, когда она вышла."),
                    medal: Medal(.shield, .rose, .pink, "bell.badge.fill")),

        // Привычки
        Achievement(id: "week-streak", category: .habits, title: String(localized: "Неделя кино"), detail: String(localized: "Смотрите 7 дней подряд."),
                    medal: Medal(.rosette, .bronze, .teal, "flame.fill", number: "7")),
        Achievement(id: "month-streak", category: .habits, title: String(localized: "Месяц кино"), detail: String(localized: "Смотрите 30 дней подряд."),
                    medal: Medal(.rosette, .gold, .red, "flame.fill", number: "30")),
        Achievement(id: "weekend", category: .habits, title: String(localized: "Выходные дома"), detail: String(localized: "Больше 5 часов за одни выходные."),
                    medal: Medal(.rosette, .silver, .lime, "sofa.fill")),
        Achievement(id: "night-owl", category: .habits, title: String(localized: "Сова"), detail: String(localized: "Досмотрите фильм после трёх часов ночи."),
                    medal: Medal(.rosette, .platinum, .navy, "moon.stars.fill")),
        Achievement(id: "early-bird", category: .habits, title: String(localized: "Жаворонок"), detail: String(localized: "Начните смотреть до семи утра."),
                    medal: Medal(.rosette, .gold, .sky, "sunrise.fill")),
        Achievement(id: "new-year", category: .habits, title: String(localized: "Новогодний"), detail: String(localized: "Смотрите в ночь с 31 декабря на 1 января."),
                    medal: Medal(.rosette, .silver, .red, "snowflake")),

        // Жанры
        Achievement(id: "omnivore", category: .genres, title: String(localized: "Всеядный"), detail: String(localized: "Фильмы 10 разных жанров."),
                    medal: Medal(.diamond, .gold, .green, "fork.knife")),
        Achievement(id: "comedies", category: .genres, title: String(localized: "Хохотун"), detail: String(localized: "Досмотрите 20 комедий."),
                    medal: Medal(.diamond, .silver, .orange, "face.smiling.inverse")),
        Achievement(id: "horrors", category: .genres, title: String(localized: "Храбрец"), detail: String(localized: "Досмотрите 10 фильмов ужасов."),
                    medal: Medal(.diamond, .platinum, .graphite, "eye.fill")),
        Achievement(id: "detective", category: .genres, title: String(localized: "Сыщик"), detail: String(localized: "Досмотрите 15 детективов или триллеров."),
                    medal: Medal(.diamond, .bronze, .navy, "magnifyingglass")),
        Achievement(id: "cartoons", category: .genres, title: String(localized: "Мультипликатор"), detail: String(localized: "Досмотрите 25 мультфильмов."),
                    medal: Medal(.diamond, .rose, .pink, "paintpalette.fill")),
        Achievement(id: "otaku", category: .genres, title: String(localized: "Отаку"), detail: String(localized: "Посмотрите 100 серий аниме."),
                    medal: Medal(.diamond, .gold, .purple, "wand.and.stars")),

        // Страны и эпохи
        Achievement(id: "countries-10", category: .world, title: String(localized: "Кругосветка"), detail: String(localized: "10 стран в кинопаспорте."),
                    medal: Medal(.circle, .silver, .sky, "globe.europe.africa.fill", number: "10")),
        Achievement(id: "countries-25", category: .world, title: String(localized: "Весь мир"), detail: String(localized: "25 стран в кинопаспорте."),
                    medal: Medal(.circle, .gold, .blue, "globe.americas.fill", number: "25")),
        Achievement(id: "countries-50", category: .world, title: String(localized: "Полсотни стран"), detail: String(localized: "50 стран в кинопаспорте."),
                    medal: Medal(.circle, .rose, .sky, "globe.asia.australia.fill", number: "50")),
        Achievement(id: "countries-100", category: .world, title: String(localized: "Сотня стран"), detail: String(localized: "100 стран в кинопаспорте."),
                    medal: Medal(.circle, .platinum, .blue, "globe", number: "100")),
        Achievement(id: "continents", category: .world, title: String(localized: "Все континенты"), detail: String(localized: "Штампы со всех континентов: Европа, Азия, Африка, обе Америки и Океания."),
                    medal: Medal(.rosette, .gold, .teal, "map.fill")),
        Achievement(id: "scandinavia", category: .world, title: String(localized: "Скандинавия"), detail: String(localized: "Штампы Швеции, Норвегии, Дании, Финляндии и Исландии."),
                    medal: Medal(.shield, .silver, .sky, "mountain.2.fill")),
        Achievement(id: "big-five", category: .world, title: String(localized: "Большая пятёрка"), detail: String(localized: "Штампы Великобритании, Франции, Германии, Италии и Испании."),
                    medal: Medal(.octagon, .gold, .navy, "building.columns.fill")),
        Achievement(id: "asia-tour", category: .world, title: String(localized: "Азиатский тур"), detail: String(localized: "Штампы Японии, Китая, Южной Кореи, Индии, Гонконга и Таиланда."),
                    medal: Medal(.diamond, .rose, .red, "sun.horizon.fill")),
        Achievement(id: "latin-america", category: .world, title: String(localized: "Латинская Америка"), detail: String(localized: "Штампы Мексики, Бразилии, Аргентины, Чили, Колумбии и Кубы."),
                    medal: Medal(.hexagon, .copper, .orange, "guitars.fill")),
        Achievement(id: "africa", category: .world, title: String(localized: "Африканское сафари"), detail: String(localized: "Штампы ЮАР, Египта, Нигерии, Марокко и Кении."),
                    medal: Medal(.shield, .bronze, .lime, "sun.max.fill")),
        Achievement(id: "ussr", category: .world, title: String(localized: "Советская классика"), detail: String(localized: "Досмотрите 10 фильмов СССР."),
                    medal: Medal(.circle, .gold, .red, "star.fill")),
        Achievement(id: "korea", category: .world, title: String(localized: "Корейская волна"), detail: String(localized: "10 корейских фильмов или сериалов."),
                    medal: Medal(.circle, .platinum, .pink, "water.waves")),
        Achievement(id: "decades", category: .world, title: String(localized: "Машина времени"), detail: String(localized: "Фильмы шести разных десятилетий."),
                    medal: Medal(.circle, .copper, .teal, "clock.arrow.circlepath")),
        Achievement(id: "retro", category: .world, title: String(localized: "Ретро"), detail: String(localized: "Досмотрите фильм, снятый до 1960 года."),
                    medal: Medal(.circle, .bronze, .graphite, "movieclapper.fill")),

        // Что посмотреть?
        Achievement(id: "spins", category: .roulette, title: String(localized: "Испытай удачу"), detail: String(localized: "Прокрутите рулетку 10 раз."),
                    medal: Medal(.octagon, .silver, .purple, "dice.fill")),
        Achievement(id: "fate", category: .roulette, title: String(localized: "Доверился судьбе"), detail: String(localized: "Досмотрите фильм, который выпал в рулетке."),
                    medal: Medal(.octagon, .rose, .teal, "sparkles")),
        Achievement(id: "jackpot", category: .roulette, title: String(localized: "Джекпот"), detail: String(localized: "Досмотрите фильм из рулетки с рейтингом IMDb 8 и выше."),
                    medal: Medal(.octagon, .gold, .red, "crown.fill")),

        // Цели и франшизы
        Achievement(id: "goal-set", category: .goal, title: String(localized: "Целеустремлённый"), detail: String(localized: "Поставьте цель на год."),
                    medal: Medal(.hexagon, .silver, .green, "target")),
        Achievement(id: "goal-done", category: .goal, title: String(localized: "Цель достигнута"), detail: String(localized: "Выполните цель на год."),
                    medal: Medal(.hexagon, .gold, .lime, "checkmark.seal.fill")),
        Achievement(id: "goal-early", category: .goal, title: String(localized: "С опережением"), detail: String(localized: "Выполните цель на год до 1 октября."),
                    medal: Medal(.hexagon, .rose, .orange, "hare.fill")),
        Achievement(id: "franchise", category: .goal, title: String(localized: "Вся франшиза"), detail: String(localized: "Посмотрите все части франшизы."),
                    medal: Medal(.rosette, .platinum, .blue, "square.stack.3d.up.fill")),
        Achievement(id: "anniversary", category: .goal, title: String(localized: "Год с REZKA"), detail: String(localized: "Смотрите в REZKA целый год: от первого просмотра прошло 365 дней."),
                    medal: Medal(.rosette, .gold, .pink, "birthday.cake.fill")),
    ]
}

/// How a medal looks: a metal rim of some shape, an enamelled face and a raised emblem, with a
/// number struck under it for the ones that count something. Every achievement has its own.
struct Medal {
    enum Form {
        case circle, hexagon, octagon, diamond, shield, rosette
    }

    enum Metal {
        case gold, silver, bronze, copper, rose, platinum
    }

    enum Enamel {
        case teal, red, blue, purple, green, orange, pink, navy, graphite, sky, lime, wine
    }

    let form: Form
    let metal: Metal
    let enamel: Enamel
    let symbol: String
    var number: String?

    init(_ form: Form, _ metal: Metal, _ enamel: Enamel, _ symbol: String, number: String? = nil) {
        self.form = form
        self.metal = metal
        self.enamel = enamel
        self.symbol = symbol
        self.number = number
    }
}

extension Medal.Form {
    var outline: AnyShape {
        switch self {
        case .circle: AnyShape(Circle())
        case .hexagon: AnyShape(RoundedPolygon(sides: 6, corner: 0.16))
        case .octagon: AnyShape(RoundedPolygon(sides: 8, rotation: 22.5, corner: 0.12))
        case .diamond: AnyShape(RoundedPolygon(sides: 4, corner: 0.22))
        case .shield: AnyShape(ShieldShape())
        case .rosette: AnyShape(RosetteShape())
        }
    }

    /// The enamel's outline: the rim's own, but round inside a rosette.
    var face: AnyShape {
        self == .rosette ? AnyShape(Circle()) : outline
    }

    /// A diamond leaves the least room in the middle.
    var emblemScale: CGFloat {
        self == .diamond ? 0.8 : 1
    }
}

extension Medal.Metal {
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    /// Light and dark stops around the rim, as brushed metal catches the light.
    var rim: [Color] {
        let (light, dark, bright, deep, warm, shade): (Color, Color, Color, Color, Color, Color) = switch self {
        case .gold: (Self.rgb(1, 0.93, 0.62), Self.rgb(0.80, 0.58, 0.16), Self.rgb(1, 0.96, 0.78), Self.rgb(0.66, 0.45, 0.10), Self.rgb(0.98, 0.84, 0.42), Self.rgb(0.74, 0.52, 0.14))
        case .silver: (Self.rgb(0.95, 0.96, 0.98), Self.rgb(0.62, 0.65, 0.70), Self.rgb(1, 1, 1), Self.rgb(0.50, 0.53, 0.58), Self.rgb(0.88, 0.90, 0.93), Self.rgb(0.58, 0.60, 0.65))
        case .bronze: (Self.rgb(0.93, 0.70, 0.48), Self.rgb(0.55, 0.33, 0.16), Self.rgb(0.98, 0.80, 0.60), Self.rgb(0.45, 0.26, 0.12), Self.rgb(0.85, 0.60, 0.38), Self.rgb(0.52, 0.31, 0.15))
        case .copper: (Self.rgb(0.98, 0.65, 0.50), Self.rgb(0.68, 0.30, 0.18), Self.rgb(1, 0.78, 0.65), Self.rgb(0.55, 0.22, 0.12), Self.rgb(0.92, 0.55, 0.40), Self.rgb(0.62, 0.27, 0.16))
        case .rose: (Self.rgb(1, 0.82, 0.80), Self.rgb(0.78, 0.50, 0.50), Self.rgb(1, 0.92, 0.90), Self.rgb(0.65, 0.40, 0.42), Self.rgb(0.95, 0.72, 0.70), Self.rgb(0.72, 0.46, 0.46))
        case .platinum: (Self.rgb(0.75, 0.78, 0.82), Self.rgb(0.30, 0.32, 0.36), Self.rgb(0.92, 0.94, 0.96), Self.rgb(0.22, 0.24, 0.27), Self.rgb(0.62, 0.65, 0.70), Self.rgb(0.28, 0.30, 0.34))
        }
        return [light, dark, bright, deep, warm, shade, light]
    }

    /// The raised emblem, lit from above.
    var emblem: [Color] {
        switch self {
        case .gold: [Self.rgb(1, 0.95, 0.70), Self.rgb(0.86, 0.62, 0.16)]
        case .silver: [Self.rgb(1, 1, 1), Self.rgb(0.66, 0.69, 0.74)]
        case .bronze: [Self.rgb(0.98, 0.82, 0.62), Self.rgb(0.66, 0.42, 0.20)]
        case .copper: [Self.rgb(1, 0.80, 0.68), Self.rgb(0.75, 0.36, 0.22)]
        case .rose: [Self.rgb(1, 0.93, 0.92), Self.rgb(0.80, 0.55, 0.55)]
        case .platinum: [Self.rgb(0.95, 0.96, 0.98), Self.rgb(0.55, 0.58, 0.63)]
        }
    }
}

extension Medal.Enamel {
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    /// From the lit spot to the edge.
    var colors: [Color] {
        switch self {
        case .teal: [Self.rgb(0.42, 0.86, 0.88), Self.rgb(0.05, 0.36, 0.44), Self.rgb(0.02, 0.20, 0.27)]
        case .red: [Self.rgb(1, 0.50, 0.48), Self.rgb(0.72, 0.10, 0.14), Self.rgb(0.42, 0.03, 0.06)]
        case .blue: [Self.rgb(0.50, 0.72, 1), Self.rgb(0.12, 0.30, 0.75), Self.rgb(0.05, 0.12, 0.40)]
        case .purple: [Self.rgb(0.80, 0.62, 1), Self.rgb(0.42, 0.18, 0.72), Self.rgb(0.20, 0.06, 0.40)]
        case .green: [Self.rgb(0.55, 0.95, 0.60), Self.rgb(0.10, 0.52, 0.28), Self.rgb(0.03, 0.27, 0.13)]
        case .orange: [Self.rgb(1, 0.78, 0.42), Self.rgb(0.88, 0.42, 0.08), Self.rgb(0.52, 0.20, 0.02)]
        case .pink: [Self.rgb(1, 0.70, 0.86), Self.rgb(0.82, 0.25, 0.55), Self.rgb(0.45, 0.08, 0.28)]
        case .navy: [Self.rgb(0.45, 0.55, 0.85), Self.rgb(0.10, 0.15, 0.40), Self.rgb(0.03, 0.05, 0.18)]
        case .graphite: [Self.rgb(0.55, 0.57, 0.62), Self.rgb(0.18, 0.19, 0.22), Self.rgb(0.06, 0.06, 0.08)]
        case .sky: [Self.rgb(0.70, 0.92, 1), Self.rgb(0.20, 0.58, 0.88), Self.rgb(0.06, 0.28, 0.55)]
        case .lime: [Self.rgb(0.88, 1, 0.50), Self.rgb(0.45, 0.70, 0.08), Self.rgb(0.20, 0.38, 0.02)]
        case .wine: [Self.rgb(0.90, 0.45, 0.62), Self.rgb(0.52, 0.08, 0.25), Self.rgb(0.26, 0.02, 0.12)]
        }
    }
}

/// An award medal in the manner of Apple Watch's: a metal rim with a bevel, an enamelled face sunk
/// into it and a raised emblem, maybe with a number.
struct MedalView: View {
    let medal: Medal
    var size: CGFloat = 96
    var isEarned = true
    /// From -1 to 1 each way: where the medal leans, so the shine moves with it.
    var tilt: CGSize = .zero

    var body: some View {
        let outline = medal.form.outline
        let face = medal.form.face
        ZStack {
            // The rim, lit from the top left.
            outline
                .fill(AngularGradient(colors: medal.metal.rim, center: .center, angle: .degrees(tilt.width * 40)))
            outline
                .stroke(LinearGradient(colors: [.white.opacity(0.9), .clear, .black.opacity(0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: size * 0.05)

            // The face, sunk into the rim: shade on its upper edge, light on the lower.
            face.scale(0.76)
                .fill(RadialGradient(colors: medal.enamel.colors, center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: size * 0.42))
            face.scale(0.76)
                .stroke(LinearGradient(colors: [.black.opacity(0.5), .clear, .white.opacity(0.55)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: size * 0.022)
            // An engraved ring of dots.
            face.scale(0.62)
                .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: size * 0.014, lineCap: .round, dash: [0.1, size * 0.045]))

            emblem

            // The shine sweeping across as the medal leans.
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.78, height: size * 0.42)
                .offset(x: -tilt.width * size * 0.18, y: -size * 0.24 - tilt.height * size * 0.12)
                .blendMode(.screen)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .clipShape(outline)
        .compositingGroup()
        .saturation(isEarned ? 1 : 0)
        .opacity(isEarned ? 1 : 0.4)
        .shadow(color: .black.opacity(isEarned ? 0.4 : 0.15), radius: size * 0.06, y: size * 0.04)
    }

    /// Struck in the rim's metal: a highlight on top and a shadow under it.
    private var emblem: some View {
        let scale = size * medal.form.emblemScale
        return VStack(spacing: scale * 0.005) {
            Image(systemName: medal.symbol)
                .font(.system(size: scale * (medal.number == nil ? 0.28 : 0.12), weight: .black))
            if let number = medal.number {
                Text(verbatim: number)
                    .font(.system(size: scale * (number.count <= 2 ? 0.26 : number.count == 3 ? 0.21 : 0.165), weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(LinearGradient(colors: medal.metal.emblem, startPoint: .top, endPoint: .bottom))
        .shadow(color: .black.opacity(0.5), radius: size * 0.012, y: size * 0.018)
        // A shield's middle sits above its centre.
        .offset(y: medal.form == .shield ? -size * 0.05 : 0)
    }
}

/// A regular polygon with rounded corners, a corner on top unless turned.
struct RoundedPolygon: Shape {
    let sides: Int
    var rotation: Double = 0
    /// Of the radius.
    var corner: CGFloat = 0.12

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let points = (0..<sides).map { index -> CGPoint in
            let degrees: Double = Double(index) / Double(sides) * 360 + rotation - 90
            let angle = CGFloat(degrees * .pi / 180)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        var path = Path()
        let last = points[sides - 1]
        path.move(to: CGPoint(x: (last.x + points[0].x) / 2, y: (last.y + points[0].y) / 2))
        for index in 0..<sides {
            path.addArc(tangent1End: points[index], tangent2End: points[(index + 1) % sides], radius: radius * corner)
        }
        path.closeSubpath()
        return path
    }
}

/// A heraldic shield: square shoulders, coming to a point at the bottom.
struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let x = rect.midX - side / 2, y = rect.midY - side / 2
        let corner = side * 0.12
        var path = Path()
        path.move(to: CGPoint(x: x + side / 2, y: y))
        path.addArc(tangent1End: CGPoint(x: x + side, y: y), tangent2End: CGPoint(x: x + side, y: y + side), radius: corner)
        path.addLine(to: CGPoint(x: x + side, y: y + side * 0.48))
        path.addQuadCurve(to: CGPoint(x: x + side / 2, y: y + side), control: CGPoint(x: x + side, y: y + side * 0.86))
        path.addQuadCurve(to: CGPoint(x: x, y: y + side * 0.48), control: CGPoint(x: x, y: y + side * 0.86))
        path.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: x + side / 2, y: y), radius: corner)
        path.closeSubpath()
        return path
    }
}

/// A round medal with a scalloped edge.
struct RosetteShape: Shape {
    var bumps = 16

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for step in 0...360 {
            let angle = Double(step) / 360 * 2 * .pi
            let r = radius * (0.93 + 0.07 * cos(Double(bumps) * angle))
            let point = CGPoint(x: center.x + r * sin(angle), y: center.y - r * cos(angle))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// Every achievement by group: earned ones in colour with the day, the rest grey with how far along.
struct AchievementsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Achievement.ID?

    private let tracker = AchievementTracker.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Достижения")
                        .font(.largeTitle.bold())
                    Text("Получено \(tracker.earned.count) из \(Achievement.all.count) — за то, что смотрите в REZKA на этом Mac.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Achievement.Category.allCases, id: \.self) { category in
                        let items = Achievement.all.filter { $0.category == category }
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(category.title)
                                    .font(.title3.weight(.semibold))
                                Text("\(items.filter { tracker.earned[$0.id] != nil }.count) из \(items.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)], spacing: 22) {
                                ForEach(items) { cell($0) }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 820, idealWidth: 920, minHeight: 620, idealHeight: 760)
        .onAppear { tracker.evaluate(announce: true) }
    }

    private func cell(_ achievement: Achievement) -> some View {
        Button {
            selected = achievement.id
        } label: {
            VStack(spacing: 10) {
                MedalView(medal: achievement.medal, size: 92, isEarned: tracker.earned[achievement.id] != nil)
                Text(achievement.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(achievement.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                AchievementStatus(achievement: achievement)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { selected == achievement.id }, set: { if !$0 { selected = nil } }), arrowEdge: .bottom) {
            MedalDetail(achievement: achievement, isEarned: tracker.earned[achievement.id] != nil)
        }
    }
}

/// When it was earned, or how far along a counted one is.
private struct AchievementStatus: View {
    let achievement: Achievement

    private let tracker = AchievementTracker.shared

    var body: some View {
        if let date = tracker.earned[achievement.id] {
            Label(date.formatted(.dateTime.day().month(.wide).year().locale(AppLanguage.locale)), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
        } else if let progress = tracker.progress[achievement.id], progress.target > 1 {
            VStack(spacing: 4) {
                ProgressView(value: Double(min(progress.current, progress.target)), total: Double(progress.target))
                    .frame(width: 110)
                Text("\(min(progress.current, progress.target)) из \(progress.target)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
/// One medal up close: it turns in as it is shown, as on Apple Watch, and leans after the pointer.
private struct MedalDetail: View {
    let achievement: Achievement
    let isEarned: Bool

    @State private var tilt = CGSize.zero
    @State private var spin = -200.0

    private let size: CGFloat = 210

    var body: some View {
        VStack(spacing: 14) {
            MedalView(medal: achievement.medal, size: size, isEarned: isEarned, tilt: tilt)
                .rotation3DEffect(.degrees(spin + tilt.width * 22), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .rotation3DEffect(.degrees(-tilt.height * 22), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
                .padding(.vertical, 8)
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(point):
                        tilt = CGSize(width: min(max(point.x / size * 2 - 1, -1), 1), height: min(max(point.y / size * 2 - 1, -1), 1))
                    case .ended:
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { tilt = .zero }
                    }
                }
                .onAppear {
                    withAnimation(.spring(response: 1.1, dampingFraction: 0.55)) { spin = 0 }
                }
            Text(achievement.category.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(achievement.title)
                .font(.title2.bold())
            Text(achievement.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            AchievementStatus(achievement: achievement)
        }
        .padding(28)
        .frame(width: 320)
    }
}
