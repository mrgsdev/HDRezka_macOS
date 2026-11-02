import CryptoKit
import Foundation
import Observation
import Security

/// The highest age rating kid mode lets through.
enum AgeLimit: Int, CaseIterable, Identifiable, Codable {
    case age0 = 0
    case age6 = 6
    case age12 = 12
    case age16 = 16

    var id: Int { rawValue }
    var title: String { "\(rawValue)+" }

    /// Hidden even when the site gives no age: the first genre on a card is often all there is.
    var blockedGenres: Set<String> {
        switch self {
        case .age16: ["Эротика"]
        case .age12: ["Эротика", "Ужасы"]
        case .age6, .age0: ["Эротика", "Ужасы", "Триллеры", "Криминал", "Боевики", "Военные", "Детективы"]
        }
    }

    /// For the youngest, a title of unknown age shows only when it is clearly for children.
    var allowedUnratedGenres: Set<String>? {
        switch self {
        case .age0: ["Детские", "Семейные"]
        case .age6: ["Детские", "Семейные", "Приключения", "Комедии", "Фэнтези", "Мюзиклы", "Спортивные"]
        case .age12, .age16: nil
        }
    }
}

/// Kid mode: titles above an age are hidden from lists and cannot be played, and reviews are hidden.
/// Turning it off or changing it takes a 4-digit PIN; a forgotten PIN is reset with the recovery code
/// shown when kid mode was set up. Everything is kept in the Keychain, so it outlives deleting the app
/// and cannot be switched off from Terminal with `defaults`.
@MainActor
@Observable
final class ParentalControl {
    static let shared = ParentalControl()

    enum CheckResult: Equatable {
        case ok
        case wrong
        /// Too many wrong tries: the next one waits until then.
        case locked(until: Date)
    }

    /// nil while kid mode is off.
    private(set) var limit: AgeLimit?
    /// After many wrong PINs or codes, when the next try is allowed.
    private(set) var lockedUntil: Date?
    /// The Keychain did not give the settings back, e.g. access was denied: strictest until it does.
    private(set) var isUnreadable = false

    private var stored: Stored?

    private init() {
        load()
    }

    /// Reads the settings again, e.g. after the Keychain refused them once.
    func load() {
        switch Vault.read() {
        case let .found(stored):
            self.stored = stored
            limit = stored.limit
            lockedUntil = stored.lockedUntil
            isUnreadable = false
        case .missing:
            stored = nil
            limit = nil
            isUnreadable = false
        case .unreadable:
            // When in doubt, closed: the strictest level until the Keychain answers.
            stored = nil
            limit = .age0
            isUnreadable = true
        }
    }

    var isOn: Bool { limit != nil }

    // MARK: Setup

    /// Turns kid mode on with a new PIN; returns the recovery code to show once.
    func enable(limit: AgeLimit, pin: String) -> String {
        let code = Self.newRecoveryCode()
        save(Stored(limit: limit, pin: Self.hash(pin), recovery: Self.hash(Self.normalized(code)), failures: 0, lockedUntil: nil))
        return code
    }

    /// Changes the level, or turns kid mode off with nil; only after `check(pin:)` passed.
    func setLimit(_ limit: AgeLimit?) {
        guard var stored else { return }
        if let limit {
            stored.limit = limit
            save(stored)
        } else {
            Vault.delete()
            self.stored = nil
            self.limit = nil
            lockedUntil = nil
        }
    }

    /// A new PIN after the old one or the recovery code was entered; returns a new recovery code,
    /// since the one just used may have been seen.
    func resetPIN(to pin: String) -> String {
        let code = Self.newRecoveryCode()
        let level = stored?.limit ?? limit ?? .age0
        save(Stored(limit: level, pin: Self.hash(pin), recovery: Self.hash(Self.normalized(code)), failures: 0, lockedUntil: nil))
        return code
    }

    // MARK: Checks

    func check(pin: String) -> CheckResult {
        verify { $0.pin.matches(pin) }
    }

    func check(recoveryCode: String) -> CheckResult {
        verify { $0.recovery.matches(Self.normalized(recoveryCode)) }
    }

    /// Wrong tries in a row lock further ones for 1, then 5, then 30 minutes.
    private func verify(_ matches: (Stored) -> Bool) -> CheckResult {
        guard var stored else { return .wrong }
        if let lockedUntil = stored.lockedUntil, lockedUntil > Date() { return .locked(until: lockedUntil) }
        if matches(stored) {
            stored.failures = 0
            stored.lockedUntil = nil
            save(stored)
            return .ok
        }
        stored.failures += 1
        let pause: TimeInterval? = switch stored.failures {
        case 5: 60
        case 10: 5 * 60
        case 15...: 30 * 60
        default: nil
        }
        stored.lockedUntil = pause.map { Date().addingTimeInterval($0) }
        save(stored)
        return pause == nil ? .wrong : .locked(until: stored.lockedUntil!)
    }

    // MARK: Ages

    /// Whether a card may show in a list; the age is known only for titles opened before.
    func allows(_ item: MediaItem) -> Bool {
        guard let limit else { return true }
        if let age = AgeBook.age(path: item.path) { return age <= limit.rawValue }
        let genre = item.subtitle.components(separatedBy: ", ").dropFirst(2).first
        return Self.allowsUnrated(kind: item.kind, genres: genre.map { [$0] } ?? [], limit: limit)
    }

    /// Whether a title page may offer to play.
    func allows(_ details: MediaDetails, kind: MediaKind) -> Bool {
        guard let limit else { return true }
        if let age = Self.age(details) { return age <= limit.rawValue }
        let genres = details.info("Жанр")?.components(separatedBy: ", ") ?? []
        return Self.allowsUnrated(kind: kind, genres: genres, limit: limit)
    }

    /// For a player window reopened with the app: the title's age as last seen.
    func allows(postId: String) -> Bool {
        guard let limit else { return true }
        return AgeBook.age(postId: postId).map { $0 <= limit.rawValue } ?? (limit.allowedUnratedGenres == nil)
    }

    private static func allowsUnrated(kind: MediaKind, genres: [String], limit: AgeLimit) -> Bool {
        if genres.contains(where: limit.blockedGenres.contains) { return false }
        guard let allowed = limit.allowedUnratedGenres else { return true }
        return kind == .cartoon || genres.contains(where: allowed.contains)
    }

    /// "18+ только для взрослых" → 18.
    nonisolated static func age(_ details: MediaDetails) -> Int? {
        details.info("Возраст")?.firstMatch(of: /(\d+)\+/).flatMap { Int($0.1) }
    }

    // MARK: Storage

    private func save(_ stored: Stored) {
        Vault.write(stored)
        self.stored = stored
        limit = stored.limit
        lockedUntil = stored.lockedUntil
    }

    struct Hashed: Codable {
        let salt: Data
        let hash: Data

        func matches(_ text: String) -> Bool {
            ParentalControl.digest(text, salt: salt) == hash
        }
    }

    private struct Stored: Codable {
        var limit: AgeLimit
        var pin: Hashed
        var recovery: Hashed
        var failures: Int
        var lockedUntil: Date?
    }

    private static func hash(_ text: String) -> Hashed {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return Hashed(salt: salt, hash: digest(text, salt: salt))
    }

    nonisolated static func digest(_ text: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(text.utf8)))
    }

    /// Twelve letters and digits without the ones easily mixed up, as `K7QM-4XRT-9PLD`.
    private static func newRecoveryCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let characters = (0..<12).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] }
        return stride(from: 0, to: 12, by: 4).map { String(characters[$0..<$0 + 4]) }.joined(separator: "-")
    }

    /// Upper case, letters and digits only, and a letter typed with the Russian layout taken as the Latin
    /// one on the same key: `л7йь` is `K7QM`.
    private static func normalized(_ code: String) -> String {
        String(code.lowercased().compactMap { character -> Character? in
            let latin = russianKeys[character] ?? character
            return latin.isLetter || latin.isNumber ? Character(latin.uppercased()) : nil
        })
    }

    private static let russianKeys: [Character: Character] = Dictionary(uniqueKeysWithValues: zip(
        "йцукенгшщзфывапролдячсмить", "qwertyuiopasdfghjklzxcvbnm"
    ))

    private enum Vault {
        enum Read {
            case found(Stored), missing, unreadable
        }

        private static let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.mrgsdev.hdrezkamac.parental",
            kSecAttrAccount as String: "settings",
        ]

        static func read() -> Read {
            var search = query
            search[kSecReturnData as String] = true
            search[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            let status = SecItemCopyMatching(search as CFDictionary, &result)
            if status == errSecItemNotFound { return .missing }
            guard status == errSecSuccess, let data = result as? Data,
                  let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return .unreadable }
            return .found(stored)
        }

        static func write(_ stored: Stored) {
            guard let data = try? JSONEncoder().encode(stored) else { return }
            let attributes: [String: Any] = [kSecValueData as String: data]
            if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
                var insert = query
                insert[kSecValueData as String] = data
                insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                SecItemAdd(insert as CFDictionary, nil)
            }
        }

        static func delete() {
            SecItemDelete(query as CFDictionary)
        }
    }
}

/// The ages of titles opened before, so their cards can be hidden from lists: the site puts the age
/// only on a title's own page. Not a secret: losing it only shows more cards, the page still blocks.
enum AgeBook {
    private static let pathsKey = "ageBook.paths"
    private static let idsKey = "ageBook.ids"

    static func age(path: String) -> Int? {
        (UserDefaults.standard.dictionary(forKey: pathsKey) as? [String: Int])?[path]
    }

    static func age(postId: String) -> Int? {
        (UserDefaults.standard.dictionary(forKey: idsKey) as? [String: Int])?[postId]
    }

    static func remember(_ details: MediaDetails, path: String) {
        guard let age = ParentalControl.age(details) else { return }
        var paths = UserDefaults.standard.dictionary(forKey: pathsKey) as? [String: Int] ?? [:]
        var ids = UserDefaults.standard.dictionary(forKey: idsKey) as? [String: Int] ?? [:]
        guard paths[path] != age || ids[details.postId] != age else { return }
        paths[path] = age
        ids[details.postId] = age
        UserDefaults.standard.set(paths, forKey: pathsKey)
        UserDefaults.standard.set(ids, forKey: idsKey)
    }
}
