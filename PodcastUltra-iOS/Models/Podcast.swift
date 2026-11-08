import Foundation

struct Podcast: Identifiable, Codable {
    var id: Int { collectionId }
    let collectionId: Int
    let artistName: String
    let collectionName: String
    let artworkUrl100: String?
    let artworkUrl600: String?
    let feedUrl: String?
    let genres: [String]?
    let primaryGenreName: String?
    let releaseDate: String?
    let country: String?
    let description: String?
    var source: String?
    var totalDurationMillis: Int? = nil
    var episodeCount: Int? = nil
    var trackCount: Int? = nil
    
    var formattedTotalDuration: String? {
        guard let millis = totalDurationMillis, millis > 0 else { return nil }
        let totalMinutes = max(1, millis / 60000)
        let hours = totalMinutes / 60
        let remMinutes = totalMinutes % 60
        if hours > 0 {
            return remMinutes > 0 ? "\(hours)h \(remMinutes)m" : "\(hours)h"
        } else {
            return "\(totalMinutes) min"
        }
    }
}
