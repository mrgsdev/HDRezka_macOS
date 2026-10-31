import Foundation
import Observation

/// Local playback positions, used for "continue" buttons and episode progress bars.
@MainActor
@Observable
final class WatchProgressStore {
    struct Entry: Codable, Hashable {
        var postId: String
        var translatorId: String
        var seasonId: String?
        var episodeId: String?
        var position: Double
        var duration: Double
        var updatedAt: Date

        var fraction: Double { duration > 0 ? min(position / duration, 1) : 0 }
        var isFinished: Bool { duration > 0 && position >= duration * 0.92 }
    }

    static let shared = WatchProgressStore()

    private static let storageKey = "watchProgress.v1"
    private static let limit = 600

    private var entries: [String: Entry]
    private var lastPersist = Date.distantPast

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    var allEntries: [Entry] { Array(entries.values) }

    /// The most recently played episode (or the movie itself) of a title.
    func last(postId: String) -> Entry? {
        entries.values.filter { $0.postId == postId }.max { $0.updatedAt < $1.updatedAt }
    }

    func entry(postId: String, seasonId: String?, episodeId: String?) -> Entry? {
        entries[Self.key(postId, seasonId, episodeId)]
    }

    func update(_ entry: Entry, persistNow: Bool = false) {
        entries[Self.key(entry.postId, entry.seasonId, entry.episodeId)] = entry
        if persistNow || Date().timeIntervalSince(lastPersist) > 10 {
            persist()
        }
    }

    /// Forgets every saved position of a title (e.g. after removing it from "continue watching").
    func remove(postId: String) {
        entries = entries.filter { $0.value.postId != postId }
        persist()
    }

    func persist() {
        lastPersist = Date()
        if entries.count > Self.limit {
            let keep = entries.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(Self.limit)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func key(_ postId: String, _ seasonId: String?, _ episodeId: String?) -> String {
        "\(postId)|\(seasonId ?? "-")|\(episodeId ?? "-")"
    }
}

enum QualityPreference {
    static let options = ["Лучшее", "1080p Ultra", "1080p", "720p", "480p", "360p"]
    private static let key = "preferredQuality"

    static var current: String {
        get { UserDefaults.standard.string(forKey: key) ?? options[0] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Picks the preferred quality if present, otherwise the best one not above it.
    /// Without Premium, premium qualities are only used when chosen explicitly: they are teasers.
    static func pick(from qualities: [StreamQuality], allowPremium: Bool) -> StreamQuality? {
        let sorted = qualities.sorted { $0.rank > $1.rank }
        let preferred = current
        if let exact = sorted.first(where: { $0.label.caseInsensitiveCompare(preferred) == .orderedSame }) { return exact }
        let free = allowPremium ? sorted : sorted.filter { !$0.isPremium }
        let pool = free.isEmpty ? sorted : free
        if preferred == options[0] { return pool.first }
        let target = StreamQuality(label: preferred, url: Mirror.fallback, fallbackURL: nil).rank
        return pool.first { $0.rank <= target } ?? pool.last
    }
}

enum SubtitlePreference {
    private static let key = "preferredSubtitle"

    /// Label of the last chosen subtitle track, or nil when subtitles are off.
    static var current: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
