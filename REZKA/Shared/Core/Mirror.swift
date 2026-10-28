import Foundation

/// The site mirror all requests go to. Stored in UserDefaults so it can be changed when a domain gets blocked.
enum Mirror {
    static let fallback = URL(string: "https://rezka.fi/")!
    private static let key = "mirror"

    static var current: URL {
        get {
            UserDefaults.standard.string(forKey: key).flatMap(normalize) ?? fallback
        }
        set {
            let old = current
            UserDefaults.standard.set(newValue.absoluteString, forKey: key)
            CookieVault.migrate(from: old, to: newValue)
        }
    }

    /// Turns user input like `rezka.ag` or `https://rezka.ag/films/` into `https://rezka.ag/`.
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let components = URLComponents(string: text), let host = components.host, host.contains(".") else { return nil }
        return URL(string: "\(components.scheme ?? "https")://\(host)/")
    }

    // MARK: Search

    /// Domains HDrezka has used. Old ones often redirect to a live mirror; many sit behind
    /// a JavaScript bot check the app cannot pass, so each one is probed before it is offered.
    static let known = [
        "rezka.fi", "hdrezka.cm", "standby-rezka.tv", "rezka.ag", "hdrezka.ag", "hdrezka.me",
        "hdrezka.website", "hdrezka.sh", "hdrezka.kim", "hdrezka.name", "hdrezka.club",
        "rezka-ua.tv", "rezka-ua.co", "rezka-ua.in",
    ]

    /// Probes the current and known mirrors at once and returns those that answer
    /// with an HDrezka page, the current mirror first.
    static func findWorking() async -> [URL] {
        var seen = Set<String>()
        let candidates = ([current] + known.compactMap(normalize)).filter { seen.insert($0.host() ?? "").inserted }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpAdditionalHeaders = ["User-Agent": RezkaClient.userAgent]
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let found = await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, url) in candidates.enumerated() {
                group.addTask { (index, await probe(url, session: session)) }
            }
            var found: [(Int, URL)] = []
            for await case let (index, url?) in group { found.append((index, url)) }
            return found
        }

        // Several old domains may redirect to the same mirror.
        seen = []
        return found.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0.host() ?? "").inserted }
    }

    /// The mirror the request ended up on after redirects, if it serves the site:
    /// the login wall or a listing. A bot check or a lookalike site has neither.
    private static func probe(_ url: URL, session: URLSession) async -> URL? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        guard html.contains("id=\"loginForm\"") || html.contains("b-content__inline_item") else { return nil }
        return response.url.flatMap { normalize($0.absoluteString) }
    }
}
