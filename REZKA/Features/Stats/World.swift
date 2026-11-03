import Foundation

/// Countries as the site names them, by continent, with their flags: for the film passport and the
/// achievements that ask for countries. Only those the site has titles from (checked against it in
/// November 2026, including the gone ones it keeps, like СССР); a name is the one its links use.
enum World {
    struct Continent: Identifiable {
        let id: String
        let name: String
        let countries: [String]
    }

    /// Country, ISO code for the flag; nil for one with no flag of today.
    private static let table: [(continent: String, countries: [(String, String?)])] = [
        ("europe", [
            ("Россия", "RU"), ("Украина", "UA"), ("Беларусь", "BY"), ("Великобритания", "GB"), ("Ирландия", "IE"),
            ("Франция", "FR"), ("Германия", "DE"), ("Италия", "IT"), ("Испания", "ES"), ("Португалия", "PT"),
            ("Нидерланды", "NL"), ("Бельгия", "BE"), ("Люксембург", "LU"), ("Швейцария", "CH"), ("Австрия", "AT"),
            ("Лихтенштейн", "LI"), ("Монако", "MC"), ("Андорра", "AD"), ("Ватикан", "VA"),
            ("Мальта", "MT"), ("Швеция", "SE"), ("Норвегия", "NO"), ("Дания", "DK"), ("Финляндия", "FI"),
            ("Исландия", "IS"), ("Эстония", "EE"), ("Латвия", "LV"), ("Литва", "LT"), ("Польша", "PL"),
            ("Чехия", "CZ"), ("Словакия", "SK"), ("Венгрия", "HU"), ("Румыния", "RO"), ("Болгария", "BG"),
            ("Молдова", "MD"), ("Сербия", "RS"), ("Черногория", "ME"), ("Хорватия", "HR"), ("Словения", "SI"),
            ("Босния и Герцеговина", "BA"), ("Северная Македония", "MK"), ("Албания", "AL"), ("Греция", "GR"), ("Кипр", "CY"),
            ("СССР", nil), ("Чехословакия", nil), ("Югославия", nil), ("Германия (ГДР)", nil), ("Германия (ФРГ)", "DE"),
        ]),
        ("asia", [
            ("Япония", "JP"), ("Китай", "CN"), ("Корея Южная", "KR"), ("Корея Северная", "KP"), ("Гонконг", "HK"),
            ("Тайвань", "TW"), ("Макао", "MO"), ("Монголия", "MN"), ("Индия", "IN"), ("Пакистан", "PK"),
            ("Бангладеш", "BD"), ("Шри-Ланка", "LK"), ("Непал", "NP"), ("Бутан", "BT"),
            ("Афганистан", "AF"), ("Иран", "IR"), ("Ирак", "IQ"), ("Сирия", "SY"), ("Ливан", "LB"),
            ("Иордания", "JO"), ("Израиль", "IL"), ("Палестина", "PS"), ("Саудовская Аравия", "SA"), ("ОАЭ", "AE"),
            ("Катар", "QA"), ("Кувейт", "KW"), ("Бахрейн", "BH"), ("Йемен", "YE"),
            ("Турция", "TR"), ("Грузия", "GE"), ("Армения", "AM"), ("Азербайджан", "AZ"), ("Казахстан", "KZ"),
            ("Узбекистан", "UZ"), ("Туркменистан", "TM"), ("Кыргызстан", "KG"), ("Таджикистан", "TJ"), ("Таиланд", "TH"),
            ("Вьетнам", "VN"), ("Камбоджа", "KH"), ("Лаос", "LA"), ("Малайзия", "MY"),
            ("Сингапур", "SG"), ("Индонезия", "ID"), ("Филиппины", "PH"),
        ]),
        ("africa", [
            ("Египет", "EG"), ("Марокко", "MA"), ("Алжир", "DZ"), ("Тунис", "TN"), ("Ливия", "LY"),
            ("Судан", "SD"), ("Эфиопия", "ET"),
            ("Сомали", "SO"), ("Кения", "KE"), ("Танзания", "TZ"), ("Уганда", "UG"), ("Руанда", "RW"),
            ("Нигерия", "NG"), ("Гана", "GH"), ("Сенегал", "SN"),
            ("Мали", "ML"), ("Буркина-Фасо", "BF"), ("Кот-д’Ивуар", "CI"), ("Либерия", "LR"), ("Сьерра-Леоне", "SL"),
            ("Гвинея-Бисау", "GW"), ("Мавритания", "MR"), ("Нигер", "NE"), ("Чад", "TD"),
            ("Камерун", "CM"), ("ЦАР", "CF"), ("Конго", "CG"),
            ("Ангола", "AO"), ("Замбия", "ZM"),
            ("Зимбабве", "ZW"), ("Мадагаскар", "MG"), ("Намибия", "NA"),
            ("Ботсвана", "BW"), ("ЮАР", "ZA"), ("Лесото", "LS"),
            ("Маврикий", "MU"),
        ]),
        ("north-america", [
            ("США", "US"), ("Канада", "CA"), ("Мексика", "MX"), ("Гренландия", "GL"), ("Куба", "CU"),
            ("Ямайка", "JM"), ("Гаити", "HT"), ("Доминикана", "DO"), ("Пуэрто-Рико", "PR"), ("Багамы", "BS"),
            ("Тринидад и Тобаго", "TT"), ("Барбадос", "BB"), ("Гватемала", "GT"), ("Белиз", "BZ"), ("Гондурас", "HN"),
            ("Сальвадор", "SV"), ("Никарагуа", "NI"), ("Коста-Рика", "CR"), ("Панама", "PA"),
        ]),
        ("south-america", [
            ("Бразилия", "BR"), ("Аргентина", "AR"), ("Чили", "CL"), ("Колумбия", "CO"), ("Перу", "PE"),
            ("Венесуэла", "VE"), ("Эквадор", "EC"), ("Боливия", "BO"), ("Парагвай", "PY"), ("Уругвай", "UY"),
           
        ]),
        ("oceania", [
            ("Австралия", "AU"), ("Новая Зеландия", "NZ"), ("Фиджи", "FJ"),
           
        ]),
    ]

    static let continents: [Continent] = table.map { id, countries in
        let name = switch id {
        case "europe": String(localized: "Европа")
        case "asia": String(localized: "Азия")
        case "africa": String(localized: "Африка")
        case "north-america": String(localized: "Северная Америка")
        case "south-america": String(localized: "Южная Америка")
        default: String(localized: "Океания")
        }
        return Continent(id: id, name: name, countries: countries.map(\.0))
    }

    private static let codes: [String: String] = Dictionary(
        table.flatMap(\.countries).compactMap { name, code in code.map { (name, $0) } },
        uniquingKeysWith: { first, _ in first }
    )

    static func continent(of country: String) -> String? {
        table.first { $0.countries.contains { $0.0 == country } }?.continent
    }

    static func flag(for country: String) -> String {
        if country == "СССР" { return "☭" }
        guard let code = codes[country] else { return "🌐" }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }))
    }

    // MARK: Achievements

    static let scandinavia = ["Швеция", "Норвегия", "Дания", "Финляндия", "Исландия"]
    static let bigFive = ["Великобритания", "Франция", "Германия", "Италия", "Испания"]
    static let asiaTour = ["Япония", "Китай", "Корея Южная", "Индия", "Гонконг", "Таиланд"]
    static let latinAmerica = ["Мексика", "Бразилия", "Аргентина", "Чили", "Колумбия", "Куба"]
    static let africa = ["ЮАР", "Египет", "Нигерия", "Марокко", "Кения"]
}
