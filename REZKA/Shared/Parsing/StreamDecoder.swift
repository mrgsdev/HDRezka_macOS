import Foundation

/// Decodes the obfuscated `url` field returned by `/ajax/get_cdn_series/`.
///
/// The payload is `#h` + base64, with junk inserted after `//_//` separators. The junk is the base64
/// of a run of the symbols `@ # ! ^ $`, i.e. a sequence of 4-character base64 groups of 2–3 symbols.
enum StreamDecoder {
    private static let separator = "//_//"

    private static let junkGroups: Set<String> = {
        let symbols = ["@", "#", "!", "^", "$"]
        var groups = Set<String>()
        for a in symbols {
            for b in symbols {
                groups.insert(Data((a + b).utf8).base64EncodedString())
                for c in symbols {
                    groups.insert(Data((a + b + c).utf8).base64EncodedString())
                }
            }
        }
        return groups
    }()

    static func decode(_ encoded: String) -> String? {
        guard encoded.hasPrefix("#") else { return encoded }
        let body = String(encoded.dropFirst(2))
        return decodeStrict(body) ?? decodeLoose(body)
    }

    /// Removes junk groups only right after each separator.
    private static func decodeStrict(_ body: String) -> String? {
        let parts = body.components(separatedBy: separator)
        var cleaned = parts[0]
        for part in parts.dropFirst() {
            var rest = Substring(part)
            while rest.count >= 4, junkGroups.contains(String(rest.prefix(4))) {
                let group = rest.prefix(4)
                rest = rest.dropFirst(4)
                if group.hasSuffix("=") { break }
            }
            cleaned += rest
        }
        return base64Decode(cleaned)
    }

    /// Fallback: strips separators, then every junk group anywhere in the string.
    private static func decodeLoose(_ body: String) -> String? {
        var cleaned = body.replacingOccurrences(of: separator, with: "")
        for group in junkGroups.sorted(by: { $0.count > $1.count }) {
            cleaned = cleaned.replacingOccurrences(of: group, with: "")
        }
        return base64Decode(cleaned)
    }

    private static func base64Decode(_ string: String) -> String? {
        var padded = string
        let remainder = padded.count % 4
        if remainder > 0 { padded += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: padded), let text = String(data: data, encoding: .utf8), text.contains("http") else {
            return nil
        }
        return text
    }

    /// Parses `[720p]https://a/720.mp4:hls:manifest.m3u8 or https://b/720.mp4,[1080p]...`.
    static func qualities(from decoded: String) -> [StreamQuality] {
        labeledEntries(in: decoded).compactMap { label, rawLabel, value in
            let urls = value
                .components(separatedBy: " or ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0 != "null" }
                .compactMap(progressiveURL)
            var unique: [URL] = []
            for url in urls where !unique.contains(url) { unique.append(url) }
            guard let first = unique.first else { return nil }
            return StreamQuality(label: label, url: first, fallbackURL: unique.dropFirst().first,
                                 isPremium: rawLabel.contains("prem") || rawLabel.contains("<img"))
        }
    }

    /// Parses `[Русский]https://.../ru.vtt,[English]https://.../en.vtt`.
    static func subtitles(from raw: String?, languages: [String: Any]?) -> [SubtitleTrack] {
        guard let raw, !raw.isEmpty else { return [] }
        return labeledEntries(in: raw).compactMap { label, _, value in
            guard let url = URL(string: value.trimmingCharacters(in: .whitespaces)) else { return nil }
            return SubtitleTrack(label: label, url: url, language: languages?[label] as? String)
        }
    }

    /// Prefers the plain `.mp4` file over the `:hls:manifest.m3u8` wrapper: it seeks reliably in AVPlayer.
    private static func progressiveURL(_ string: String) -> URL? {
        if let range = string.range(of: ".mp4") {
            return URL(string: String(string[..<range.upperBound]))
        }
        return URL(string: string)
    }

    /// Splits `[label]value,[label]value`; returns the plain label, the raw label HTML and the value.
    private static func labeledEntries(in text: String) -> [(String, String, String)] {
        var result: [(String, String, String)] = []
        var index = text.startIndex
        while let open = text[index...].firstIndex(of: "["),
              let close = text[open...].firstIndex(of: "]") {
            let rawLabel = String(text[text.index(after: open)..<close])
            let label = stripTags(rawLabel)
            let valueStart = text.index(after: close)
            let next = text[valueStart...].range(of: ",[")?.lowerBound ?? text.endIndex
            let value = String(text[valueStart..<next])
            if !label.isEmpty { result.append((label, rawLabel, value)) }
            guard next < text.endIndex else { break }
            index = text.index(after: next)
        }
        return result
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
