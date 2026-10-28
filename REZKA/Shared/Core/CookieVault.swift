import Foundation
import Security

/// The session cookies are mirrored into the Keychain and restored on launch, so signing in survives
/// a cleared cookie jar.
enum CookieVault {
    private static let service = "com.mrgsdev.hdrezkamac.cookies"
    private static let account = "session"

    static func save() {
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let stored: [[String: String]] = cookies.map { cookie in
            var dict = [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
                "secure": cookie.isSecure ? "1" : "0",
            ]
            if let expires = cookie.expiresDate {
                dict["expires"] = String(expires.timeIntervalSince1970)
            }
            return dict
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        write(data)
    }

    static func restore() {
        guard let data = read(), let stored = try? JSONDecoder().decode([[String: String]].self, from: data) else { return }
        for dict in stored {
            if let cookie = makeCookie(dict) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    static func clear() {
        let storage = HTTPCookieStorage.shared
        storage.cookies?.forEach(storage.deleteCookie)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Copies the session cookies to a new mirror domain so switching mirrors keeps the user signed in.
    static func migrate(from old: URL, to new: URL) {
        guard let oldHost = old.host(), let newHost = new.host(), oldHost != newHost else { return }
        let storage = HTTPCookieStorage.shared
        for cookie in storage.cookies(for: old) ?? [] {
            var properties = cookie.properties ?? [:]
            properties[.domain] = ".\(newHost)"
            if let copy = HTTPCookie(properties: properties) {
                storage.setCookie(copy)
            }
        }
        save()
    }

    private static func makeCookie(_ dict: [String: String]) -> HTTPCookie? {
        guard let name = dict["name"], let value = dict["value"], let domain = dict["domain"] else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: dict["path"] ?? "/",
        ]
        if dict["secure"] == "1" { properties[.secure] = "TRUE" }
        if let expires = dict["expires"].flatMap(Double.init) {
            let date = Date(timeIntervalSince1970: expires)
            guard date > Date() else { return nil }
            properties[.expires] = date
        }
        return HTTPCookie(properties: properties)
    }

    private static func write(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func read() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
