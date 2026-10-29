import AppKit
import Foundation
import Observation
import os
import Security

/// A release on GitHub, as `releases/latest` returns it.
struct AppRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets
        case htmlURL = "html_url"
    }

    /// "v2.0" → "2.0".
    var version: String {
        tagName.hasPrefix("v") || tagName.hasPrefix("V") ? String(tagName.dropFirst()) : tagName
    }

    /// The packed app attached to the release.
    var archive: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip") }
    }
}

/// Updates the app from the GitHub releases of mrgsdev/HDRezka_macOS: finds a newer release,
/// downloads its zip, checks that the app inside is signed by the same developer,
/// puts it in place of this one and relaunches.
@MainActor
@Observable
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case downloading(AppRelease)
        case failed(String, release: AppRelease?)
    }

    static let shared = Updater()

    private(set) var state: State = .idle

    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let releasesPage = URL(string: "https://github.com/mrgsdev/HDRezka_macOS/releases")!
    private static let latestRelease = URL(string: "https://api.github.com/repos/mrgsdev/HDRezka_macOS/releases/latest")!
    private static let log = Logger(subsystem: "com.mrgsdev.hdrezkamac", category: "update")

    @ObservationIgnored private var lastCheck = Date.distantPast
    @ObservationIgnored private var installTask: Task<Void, Never>?
    /// The version the viewer put off with "Позже"; not offered again until the next launch.
    @ObservationIgnored private var postponed: String?

    private let session = URLSession(configuration: .ephemeral)

    private init() {}

    // MARK: Checking

    /// Checks at most twice a day without asking; returns true when there is an update to offer.
    func checkInBackground() async -> Bool {
        guard Date().timeIntervalSince(lastCheck) > 12 * 3600, !isBusy else { return false }
        await check()
        if case let .available(release) = state, release.version != postponed { return true }
        if case .available = state {} else { state = .idle }
        return false
    }

    /// "Проверить обновления…": the window shows the result, including "no updates" and errors.
    func checkNow() async {
        guard !isBusy else { return }
        await check()
    }

    private var isBusy: Bool {
        switch state {
        case .checking, .downloading: true
        default: false
        }
    }

    private func check() async {
        state = .checking
        lastCheck = Date()
        do {
            var request = URLRequest(url: Self.feedURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            // No release published yet.
            if status == 404 {
                state = .upToDate
                return
            }
            guard (200..<300).contains(status) else { throw UpdateError.server(status) }
            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            state = Self.isVersion(release.version, newerThan: Self.currentVersion) ? .available(release) : .upToDate
        } catch {
            Self.log.error("update check failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(String(localized: "Не удалось проверить обновления: \(error.localizedDescription)"), release: nil)
        }
    }

    /// GitHub's API, or a local feed for testing (Debug builds only).
    private static var feedURL: URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "updateFeedURL"), let url = URL(string: override) {
            return url
        }
        #endif
        return latestRelease
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let parse = { (version: String) in version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 } }
        let lhs = parse(candidate), rhs = parse(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: Choices

    /// The update window closed: an offered version counts as «Позже», a download stops.
    func windowClosed() {
        switch state {
        case let .available(release):
            postponed = release.version
        case .downloading:
            installTask?.cancel()
            installTask = nil
        default:
            break
        }
        state = .idle
    }

    // MARK: Installing

    func install(_ release: AppRelease) {
        guard installTask == nil else { return }
        state = .downloading(release)
        installTask = Task {
            do {
                try await download(release)
            } catch is CancellationError {
            } catch {
                Self.log.error("update failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription, release: release)
            }
            installTask = nil
        }
    }

    private func download(_ release: AppRelease) async throws {
        let current = Bundle.main.bundleURL
        // Run straight from Downloads, macOS starts a quarantined app from a read-only copy.
        guard !current.path.contains("/AppTranslocation/") else { throw UpdateError.translocated }
        let folder = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else { throw UpdateError.notWritable(folder.path) }
        guard let archive = release.archive else { throw UpdateError.noArchive }

        let (downloaded, _) = try await session.download(from: archive.browserDownloadURL)
        try Task.checkCancellation()

        // Unpacked on the same volume as the app, so the swap below is a rename.
        let workspace = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: current, create: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let zip = workspace.appending(path: "update.zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)
        try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, workspace.path])
        try Task.checkCancellation()

        let apps = try FileManager.default.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard let newApp = apps.first, let bundle = Bundle(url: newApp) else { throw UpdateError.noApp }
        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier else { throw UpdateError.wrongApp }
        let newVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard Self.isVersion(newVersion, newerThan: Self.currentVersion) else { throw UpdateError.notNewer(newVersion) }
        try Self.checkSignature(of: newApp)

        _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)
        relaunch(current)
    }

    /// The new app must satisfy this app's own designated requirement: same bundle ID, same developer.
    /// It is also what keeps the keychain session readable after the update.
    private static func checkSignature(of app: URL) throws {
        var currentCode: SecStaticCode?
        var newCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &currentCode) == errSecSuccess,
              let currentCode,
              SecCodeCopyDesignatedRequirement(currentCode, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess,
              let newCode
        else { throw UpdateError.badSignature }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess else { throw UpdateError.badSignature }
    }

    private func relaunch(_ app: URL) {
        do {
            try AppRelaunch.relaunch(app)
        } catch {
            state = .failed(String(localized: "Обновление установлено, но перезапустить REZKA не получилось. Откройте приложение снова."), release: nil)
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.unpack)
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

enum UpdateError: LocalizedError {
    case server(Int)
    case translocated
    case notWritable(String)
    case noArchive
    case unpack
    case noApp
    case wrongApp
    case notNewer(String)
    case badSignature

    var errorDescription: String? {
        switch self {
        case let .server(status): String(localized: "GitHub ответил ошибкой \(status).")
        case .translocated: String(localized: "Переместите REZKA в папку «Программы», запустите её оттуда и обновите снова.")
        case let .notWritable(path): String(localized: "Нет прав на запись в \(path). Скачайте новую версию со страницы релиза.")
        case .noArchive: String(localized: "К релизу не приложен архив с приложением.")
        case .unpack: String(localized: "Не удалось распаковать архив обновления.")
        case .noApp: String(localized: "В архиве обновления нет приложения.")
        case .wrongApp: String(localized: "В архиве обновления другое приложение.")
        case let .notNewer(version): String(localized: "В архиве версия \(version) — она не новее установленной.")
        case .badSignature: String(localized: "Подпись обновления не совпадает с подписью REZKA. Обновление не установлено.")
        }
    }
}
