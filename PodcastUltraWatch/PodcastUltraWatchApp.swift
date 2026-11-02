import SwiftUI
import WatchConnectivity
import AVFoundation

struct WatchEpisodeItem: Identifiable {
    let id: Int
    let title: String
    let podcastName: String
    let previewUrl: String
}

struct WatchRadioItem: Identifiable {
    let id: String
    let name: String
    let url: String
    let country: String
}

final class WatchAppState: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchAppState()
    
    @Published var isPlaying: Bool = false
    @Published var currentTrackName: String = "Podcast Ultra"
    @Published var currentSubtitle: String = "Prêt à écouter"
    @Published var episodes: [WatchEpisodeItem] = []
    @Published var radios: [WatchRadioItem] = []
    
    private var localPlayer: AVPlayer?
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    func sendCommand(_ command: String, extra: [String: Any] = [:]) {
        var payload = extra
        payload["command"] = command
        if WCSession.isSupported(), WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }
    
    func playOnWatchOrPhone(episode: WatchEpisodeItem) {
        currentTrackName = episode.title
        currentSubtitle = episode.podcastName
        isPlaying = true
        if WCSession.isSupported() && WCSession.default.isReachable {
            sendCommand("playEpisode", extra: ["trackId": episode.id])
        } else if let url = URL(string: episode.previewUrl) {
            localPlayer = AVPlayer(url: url)
            localPlayer?.play()
        }
    }
    
    func playRadioOnWatchOrPhone(radio: WatchRadioItem) {
        currentTrackName = radio.name
        currentSubtitle = radio.country.isEmpty ? "Radio Direct" : radio.country
        isPlaying = true
        if WCSession.isSupported() && WCSession.default.isReachable {
            sendCommand("playRadio", extra: ["radioId": radio.id])
        } else if let url = URL(string: radio.url) {
            localPlayer = AVPlayer(url: url)
            localPlayer?.play()
        }
    }
    
    func togglePlayPause() {
        if WCSession.isSupported() && WCSession.default.isReachable {
            sendCommand("togglePlayPause")
        } else if let player = localPlayer {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            applyContext(session.receivedApplicationContext)
            sendCommand("requestSync")
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        applyContext(applicationContext)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        applyContext(message)
    }
    
    private func applyContext(_ context: [String: Any]) {
        DispatchQueue.main.async {
            if let playing = context["isPlaying"] as? Bool {
                self.isPlaying = playing
            }
            if let title = context["currentTrackName"] as? String, !title.isEmpty {
                self.currentTrackName = title
            }
            if let sub = context["currentSubtitle"] as? String, !sub.isEmpty {
                self.currentSubtitle = sub
            }
            if let eps = context["episodes"] as? [[String: Any]] {
                self.episodes = eps.compactMap { dict in
                    guard let id = dict["trackId"] as? Int,
                          let title = dict["trackName"] as? String else { return nil }
                    return WatchEpisodeItem(
                        id: id,
                        title: title,
                        podcastName: dict["collectionName"] as? String ?? "Podcast",
                        previewUrl: dict["previewUrl"] as? String ?? ""
                    )
                }
            }
            if let rads = context["radios"] as? [[String: Any]] {
                self.radios = rads.compactMap { dict in
                    guard let id = dict["id"] as? String,
                          let name = dict["name"] as? String else { return nil }
                    return WatchRadioItem(
                        id: id,
                        name: name,
                        url: dict["url"] as? String ?? "",
                        country: dict["country"] as? String ?? ""
                    )
                }
            }
        }
    }
}

struct PodcastUltraWatchRootView: View {
    @ObservedObject var state = WatchAppState.shared
    
    var body: some View {
        TabView {
            // 1. Now Playing
            VStack(spacing: 8) {
                Text(state.currentTrackName)
                    .font(.system(size: 13, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(state.currentSubtitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.indigo)
                    .lineLimit(1)
                
                HStack(spacing: 14) {
                    Button(action: { state.sendCommand("skipBackward") }) {
                        Image(systemName: "gobackward.15")
                    }
                    Button(action: { state.togglePlayPause() }) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .tint(.indigo)
                    Button(action: { state.sendCommand("skipForward") }) {
                        Image(systemName: "goforward.30")
                    }
                }
            }
            .padding(6)
            
            // 2. Latest Episodes
            List {
                Section("Derniers Épisodes") {
                    if state.episodes.isEmpty {
                        Text("Synchronisez depuis l'iPhone")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(state.episodes) { ep in
                            Button(action: { state.playOnWatchOrPhone(episode: ep) }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ep.title)
                                        .font(.system(size: 12, weight: .bold))
                                        .lineLimit(2)
                                    Text(ep.podcastName)
                                        .font(.system(size: 10))
                                        .foregroundColor(.indigo)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            
            // 3. Favorite Radios
            List {
                Section("Radios Favorites") {
                    if state.radios.isEmpty {
                        Text("Aucune radio favorite")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(state.radios) { radio in
                            Button(action: { state.playRadioOnWatchOrPhone(radio: radio) }) {
                                HStack {
                                    Image(systemName: "radio.fill")
                                        .foregroundColor(.indigo)
                                    Text(radio.name)
                                        .font(.system(size: 12, weight: .bold))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@main
struct PodcastUltraWatchApp: App {
    var body: some Scene {
        WindowGroup {
            PodcastUltraWatchRootView()
        }
    }
}

