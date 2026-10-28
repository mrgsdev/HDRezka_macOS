import Foundation
import Observation

@MainActor
@Observable
final class AuthSession {
    static let shared = AuthSession()

    private(set) var isLoggedIn: Bool
    /// HDrezka Premium subscription, read from the page header on every page load.
    private(set) var isPremium: Bool

    private static let premiumKey = "isPremiumUser"

    private init() {
        CookieVault.restore()
        isLoggedIn = RezkaClient.shared.isLoggedIn
        isPremium = UserDefaults.standard.bool(forKey: Self.premiumKey)
    }

    func login(email: String, password: String) async throws {
        try await RezkaClient.shared.login(email: email, password: password)
        isLoggedIn = RezkaClient.shared.isLoggedIn
        if !isLoggedIn { throw RezkaError.site("Сайт не выдал сессию. Попробуйте ещё раз или смените зеркало.") }
    }

    func logout() async {
        await RezkaClient.shared.logout()
        isLoggedIn = false
        updatePremium(false)
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
