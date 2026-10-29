import Foundation
import Observation

@MainActor
@Observable
final class AuthSession {
    static let shared = AuthSession()

    private(set) var isLoggedIn: Bool
    /// HDrezka Premium subscription, read from the page header on every page load.
    private(set) var isPremium: Bool
    /// The account's nickname from its profile settings on the site; nil until read.
    private(set) var userName: String?

    private static let premiumKey = "isPremiumUser"
    private static let userNameKey = "accountUserName"

    private init() {
        CookieVault.restore()
        isLoggedIn = RezkaClient.shared.isLoggedIn
        isPremium = UserDefaults.standard.bool(forKey: Self.premiumKey)
        userName = UserDefaults.standard.string(forKey: Self.userNameKey)
    }

    func login(email: String, password: String) async throws {
        try await RezkaClient.shared.login(email: email, password: password)
        isLoggedIn = RezkaClient.shared.isLoggedIn
        if !isLoggedIn { throw RezkaError.site("Сайт не выдал сессию. Попробуйте ещё раз или смените зеркало.") }
        // It may be another account than the last one.
        updateUserName(nil)
    }

    func logout() async {
        await RezkaClient.shared.logout()
        isLoggedIn = false
        updatePremium(false)
        updateUserName(nil)
    }

    /// Re-reads the nickname, which the site shows only on the profile settings page;
    /// keeps the last known one if that fails.
    func refreshUserName() async {
        guard isLoggedIn, let name = try? await RezkaClient.shared.accountName() else { return }
        updateUserName(name)
    }

    private func updateUserName(_ value: String?) {
        guard value != userName else { return }
        userName = value
        UserDefaults.standard.set(value, forKey: Self.userNameKey)
    }

    func refresh() {
        isLoggedIn = RezkaClient.shared.isLoggedIn
    }

    func updatePremium(_ value: Bool) {
        guard value != isPremium else { return }
        isPremium = value
        UserDefaults.standard.set(value, forKey: Self.premiumKey)
    }

    /// Call from any screen that got an error: an expired session sends the user back to sign in.
    func handle(_ error: Error) {
        if case RezkaError.loginRequired = error {
            isLoggedIn = false
        }
    }
}
