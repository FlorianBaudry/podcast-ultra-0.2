import SwiftUI

@main
struct PodcastUltraApp: App {
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @ObservedObject private var storage = LocalStorageManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioPlayer)
                .preferredColorScheme(storage.isLightTheme ? .light : .dark)
                .onOpenURL { url in
                    guard url.scheme == "podcastultra" else { return }
                    if url.host == "toggle-play" {
                        audioPlayer.togglePlayPause()
                    } else if url.host == "next" {
                        audioPlayer.playNextTrack()
                    } else if url.host == "refresh-episodes" {
                        storage.triggerAppOpenEpisodesRefresh()
                    } else if url.host == "play-episode" {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                           let idStr = components.queryItems?.first(where: { $0.name == "id" })?.value,
                           let episodeId = Int(idStr),
                           let episode = storage.cachedEpisodes.first(where: { $0.trackId == episodeId }) {
                            audioPlayer.playEpisode(episode)
                        } else {
                            audioPlayer.togglePlayPause()
                        }
                    }
                }
        }
    }
}
