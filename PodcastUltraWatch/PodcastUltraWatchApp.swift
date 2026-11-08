import SwiftUI
import WatchConnectivity
import AVFoundation

struct WatchEpisodeItem: Identifiable, Codable {
    var id: Int { trackId }
    let trackId: Int
    let trackName: String
    let collectionName: String
    let previewUrl: String?
}

struct WatchRadioItem: Identifiable, Codable {
    let id: String
    let name: String
    let url: String
    let country: String
}

final class WatchAppState: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchAppState()
    static let appGroupId = "group.com.podcastultra.app"
    
    @Published var isPlaying: Bool = false
    @Published var currentTrackName: String = "Podcast Ultra"
    @Published var currentSubtitle: String = "Prêt à écouter"
    @Published var episodes: [WatchEpisodeItem] = []
    @Published var radios: [WatchRadioItem] = [
        WatchRadioItem(id: "rtl-fr", name: "RTL", url: "https://streaming.radio.rtl.fr/rtl-1-44-128", country: "France"),
        WatchRadioItem(id: "franceinter-fr", name: "France Inter", url: "https://icecast.radiofrance.fr/franceinter-midfi.mp3", country: "France"),
        WatchRadioItem(id: "franceinfo-fr", name: "France Info", url: "https://icecast.radiofrance.fr/franceinfo-midfi.mp3", country: "France"),
        WatchRadioItem(id: "rmc-fr", name: "RMC", url: "https://audio.bfmtv.com/rmcradio_128.mp3", country: "France"),
        WatchRadioItem(id: "europe1-fr", name: "Europe 1", url: "https://stream.europe1.fr/europe1.mp3", country: "France"),
        WatchRadioItem(id: "fip-fr", name: "FIP", url: "https://icecast.radiofrance.fr/fip-midfi.mp3", country: "France")
    ]
    
    private var localPlayer: AVPlayer?
    
    override init() {
        super.init()
        loadCachedSharedData()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        if episodes.isEmpty {
            Task {
                await fetchStandaloneEpisodesIfNeeded()
            }
        }
    }
    
    private func loadCachedSharedData() {
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        if let data = defaults?.data(forKey: "widgetLatestEpisodes"),
           let decoded = try? JSONDecoder().decode([WatchEpisodeItem].self, from: data),
           !decoded.isEmpty {
            self.episodes = decoded
        }
        if let title = defaults?.string(forKey: "currentTrackName"), !title.isEmpty {
            self.currentTrackName = title
        }
        if let sub = defaults?.string(forKey: "currentSubtitle"), !sub.isEmpty {
            self.currentSubtitle = sub
        }
        if let playing = defaults?.object(forKey: "isPlaying") as? Bool {
            self.isPlaying = playing
        }
    }
    
    func fetchStandaloneEpisodesIfNeeded() async {
        struct LookupResponse: Codable {
            struct Item: Codable {
                let trackId: Int?
                let trackName: String?
                let collectionName: String?
                let previewUrl: String?
            }
            let results: [Item]
        }
        let defaultIds = [369369012, 1146402624, 140644703, 912451024, 589182365]
        var fetched: [WatchEpisodeItem] = []
        for pid in defaultIds {
            guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(pid)&entity=podcastEpisode&limit=2&country=fr") else { continue }
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let resp = try? JSONDecoder().decode(LookupResponse.self, from: data),
               let ep = resp.results.dropFirst().first,
               let tid = ep.trackId, let tName = ep.trackName {
                fetched.append(WatchEpisodeItem(
                    trackId: tid,
                    trackName: tName,
                    collectionName: ep.collectionName ?? "Podcast",
                    previewUrl: ep.previewUrl
                ))
            }
        }
        if !fetched.isEmpty {
            let finalFetched = fetched
            await MainActor.run {
                if self.episodes.isEmpty {
                    self.episodes = finalFetched
                }
            }
        }
    }
    
    private func activateWatchAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Watch audio session warning: \(error)")
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
        currentTrackName = episode.trackName
        currentSubtitle = episode.collectionName
        isPlaying = true
        if WCSession.isSupported() && WCSession.default.isReachable {
            sendCommand("playEpisode", extra: ["trackId": episode.trackId])
        } else if let urlStr = episode.previewUrl, let url = URL(string: urlStr) {
            activateWatchAudioSession()
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
            activateWatchAudioSession()
            localPlayer = AVPlayer(url: url)
            localPlayer?.play()
        }
    }
    
    func togglePlayPause() {
        if WCSession.isSupported() && WCSession.default.isReachable {
            isPlaying.toggle()
            sendCommand("togglePlayPause")
        } else if let player = localPlayer {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                activateWatchAudioSession()
                player.play()
                isPlaying = true
            }
        } else if let firstEp = episodes.first {
            playOnWatchOrPhone(episode: firstEp)
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
            if let eps = context["episodes"] as? [[String: Any]], !eps.isEmpty {
                self.episodes = eps.compactMap { dict in
                    guard let id = dict["trackId"] as? Int,
                          let title = dict["trackName"] as? String else { return nil }
                    return WatchEpisodeItem(
                        trackId: id,
                        trackName: title,
                        collectionName: dict["collectionName"] as? String ?? "Podcast",
                        previewUrl: dict["previewUrl"] as? String
                    )
                }
            }
            if let rads = context["radios"] as? [[String: Any]], !rads.isEmpty {
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
                Image(systemName: state.isPlaying ? "waveform.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.indigo)
                
                Text(state.currentTrackName)
                    .font(.system(size: 13, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(state.currentSubtitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.indigo)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
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
                        Text("Chargement des épisodes...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(state.episodes) { ep in
                            Button(action: { state.playOnWatchOrPhone(episode: ep) }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ep.trackName)
                                        .font(.system(size: 12, weight: .bold))
                                        .lineLimit(2)
                                    Text(ep.collectionName)
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
                Section("Radios") {
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

@main
struct PodcastUltraWatchApp: App {
    var body: some Scene {
        WindowGroup {
            PodcastUltraWatchRootView()
        }
    }
}
