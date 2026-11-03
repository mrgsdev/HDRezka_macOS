import SwiftUI
import UniformTypeIdentifiers

/// «Итоги» in one file, to keep a copy or carry them to another Mac: the time watched by day, title and
/// dub, what the titles are, the yearly goals and the achievements. Reading a file adds to what is here
/// and takes nothing away, so reading the same one twice changes nothing.
struct RecapArchive: Codable {
    static let currentVersion = 1

    var app = "REZKA"
    var version = currentVersion
    var exported = Date()
    var days: [String: [String: Double]]
    var titles: [String: WatchStats.Title]
    var dubs: [String: [String: Double]]
    var goals: [String: Int]
    var achievements: AchievementTracker.Archive

    /// What reading a file brought that was not here.
    struct Outcome {
        let days: Int
        let titles: Int
        let achievements: Int
    }

    enum ReadError: LocalizedError {
        case notRecap
        case newer

        var errorDescription: String? {
            switch self {
            case .notRecap: String(localized: "Это не файл итогов REZKA.")
            case .newer: String(localized: "Файл сохранён более новой версией REZKA. Обновите приложение и попробуйте снова.")
            }
        }
    }

    @MainActor
    static func current() -> RecapArchive {
        let stats = WatchStats.shared
        return RecapArchive(days: stats.days, titles: stats.titles, dubs: stats.dubs,
                            goals: WatchGoal.all, achievements: AchievementTracker.shared.archive)
    }

    /// "Итоги REZKA 2026-11-03", for the save panel.
    @MainActor
    static var fileName: String {
        String(localized: "Итоги REZKA \(WatchStats.dayKey(Date()))")
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> RecapArchive {
        // Which app and version first, so a file from a newer REZKA says so instead of failing to read.
        struct Header: Decodable {
            let app: String
            let version: Int
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: data), header.app == "REZKA" else { throw ReadError.notRecap }
        guard header.version <= currentVersion else { throw ReadError.newer }
        do {
            return try decoder.decode(RecapArchive.self, from: data)
        } catch {
            throw ReadError.notRecap
        }
    }

    @MainActor
    func apply() -> Outcome {
        let stats = WatchStats.shared
        let tracker = AchievementTracker.shared
        // Only the days «Итоги» show.
        let newDays = days.filter { day, titles in
            stats.days[day] == nil && titles.values.contains { $0 > 0 }
                && (WatchStats.date(ofDay: day).map { $0 >= WatchStats.firstDay } ?? false)
        }.count
        let newTitles = titles.keys.filter { stats.titles[$0] == nil }.count
        let earnedBefore = tracker.earned.count
        stats.merge(days: days, titles: titles, dubs: dubs)
        WatchGoal.merge(goals)
        tracker.merge(achievements)
        return Outcome(days: newDays, titles: newTitles, achievements: tracker.earned.count - earnedBefore)
    }
}

/// An exported file of «Итоги», for the save panel.
struct RecapFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
