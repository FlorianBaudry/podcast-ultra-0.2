import Foundation

class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    var downloadsDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Downloads")
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    func fileURL(for episodeId: Int) -> URL {
        downloadsDirectory.appendingPathComponent("\(episodeId).mp3")
    }
    
    func getFileSize(episodeId: Int) -> Int64 {
        let path = fileURL(for: episodeId).path
        let attrs = try? fileManager.attributesOfItem(atPath: path)
        return attrs?[.size] as? Int64 ?? 0
    }
    
    func getDownloadedEpisodes() -> [(episodeId: Int, sizeBytes: Int64)] {
        var results: [(episodeId: Int, sizeBytes: Int64)] = []
        guard let files = try? fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        for file in files {
            if file.pathExtension == "mp3",
               let id = Int(file.deletingPathExtension().lastPathComponent) {
                let size = (try? fileManager.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
                results.append((id, size))
            }
        }
        return results
    }
    
    func getTotalStorageSize() -> Int64 {
        getDownloadedEpisodes().reduce(0) { $0 + $1.sizeBytes }
    }
    
    func syncDownloadedIds() {
        let list = getDownloadedEpisodes().map { $0.episodeId }
        DispatchQueue.main.async {
            LocalStorageManager.shared.downloadedEpisodeIds = list
        }
    }
    
    func deleteDownload(episodeId: Int) {
        let url = fileURL(for: episodeId)
        try? fileManager.removeItem(at: url)
        syncDownloadedIds()
    }
    
    func purgeAllDownloads() {
        guard let files = try? fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
        syncDownloadedIds()
    }
    
    func downloadEpisode(_ episode: Episode) async {
        guard let urlString = episode.previewUrl,
              let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            return
        }
        
        let destination = fileURL(for: episode.trackId)
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            try? fileManager.removeItem(at: destination) // Remove if exists
            try fileManager.moveItem(at: tempURL, to: destination)
            syncDownloadedIds()
        } catch {
            print("Download error: \(error)")
        }
    }
    
    func performAutoDownloadAndCleanup(favoritePodcasts: [Podcast], allEpisodes: [Episode]) {
        // Deactivated as per user request to remove auto-download logic
    }
}
