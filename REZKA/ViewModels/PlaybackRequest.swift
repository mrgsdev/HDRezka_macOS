import Foundation

/// What the player window plays. Codable so the window can be opened and restored with it.
struct PlaybackRequest: Codable, Hashable {
    let postId: String
    let title: String
    let posterURL: URL?
    let favs: String
    let translator: Translator
    /// All seasons for this translator; used for "next episode".
    let seasons: [Season]
    var seasonId: String?
    var episodeId: String?
    /// nil resumes from the saved position, 0 starts over.
    var startPosition: Double?
    /// For «Итоги»; optional so windows saved before them still restore.
    var genres: [String]?
    var kind: MediaKind?
    var path: String?
}
