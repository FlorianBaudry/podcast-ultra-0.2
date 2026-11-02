import Foundation

struct Episode: Identifiable, Codable {
    var id: Int { trackId }
    let trackId: Int
    let trackName: String
    let description: String?
    let releaseDate: String?
    let previewUrl: String?
    let trackTimeMillis: Int?
    let artworkUrl60: String?
    let artworkUrl160: String?
    let artworkUrl600: String?
    let collectionName: String?
    let collectionId: Int?
    let artistName: String?
}
