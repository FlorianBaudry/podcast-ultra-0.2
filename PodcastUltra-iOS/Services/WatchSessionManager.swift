import Foundation
import Combine
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()
    
    @Published var isWatchPaired: Bool = false
    @Published var isWatchReachable: Bool = false
    @Published var lastSyncDate: Date? = nil
    
    private override init() {
        super.init()
        activateSession()
    }
    
    func activateSession() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }
    
    func syncContextToWatch() {
        #if canImport(WatchConnectivity)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard WCSession.isSupported() else { return }
            let session = WCSession.default
            guard session.activationState == .activated else { return }
            
            let storage = LocalStorageManager.shared
            let player = AudioPlayerManager.shared
            
            let episodesList: [[String: Any]] = storage.cachedEpisodes.prefix(8).map { ep in
                [
                    "trackId": ep.trackId,
                    "trackName": ep.trackName,
                    "collectionName": ep.collectionName ?? ep.artistName ?? "Podcast",
                    "previewUrl": ep.previewUrl ?? "",
                    "artworkUrl": ep.artworkUrl160 ?? ep.artworkUrl60 ?? "",
                    "duration": ep.trackTimeMillis ?? 0
                ]
            }
            
            let radiosList: [[String: Any]] = storage.favoriteRadioStations.prefix(8).map { r in
                [
                    "id": r.id,
                    "name": r.name,
                    "url": r.url,
                    "country": r.country ?? ""
                ]
            }
            
            let context: [String: Any] = [
                "isPlaying": player.isPlaying,
                "currentTrackName": player.currentTrackName ?? "",
                "currentSubtitle": player.currentSubtitle ?? "",
                "playbackType": player.playbackType,
                "playbackSpeed": storage.settings.playbackSpeed,
                "accentColor": storage.settings.accentColor,
                "episodes": episodesList,
                "radios": radiosList,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            try? session.updateApplicationContext(context)
            if session.isReachable {
                session.sendMessage(context, replyHandler: nil, errorHandler: nil)
            }
            self.lastSyncDate = Date()
        }
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchPaired = session.isPaired
            self.isWatchReachable = session.isReachable
        }
        if activationState == .activated {
            syncContextToWatch()
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchPaired = session.isPaired
            self.isWatchReachable = session.isReachable
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {}
    
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            guard let command = message["command"] as? String else { return }
            let player = AudioPlayerManager.shared
            let storage = LocalStorageManager.shared
            
            switch command {
            case "togglePlayPause":
                player.togglePlayPause()
            case "next":
                player.playNextTrack()
            case "skipForward":
                player.skip(seconds: 30)
            case "skipBackward":
                player.skip(seconds: -15)
            case "playEpisode":
                if let trackId = message["trackId"] as? Int,
                   let ep = storage.cachedEpisodes.first(where: { $0.trackId == trackId }) {
                    player.playEpisode(ep)
                }
            case "playRadio":
                if let radioId = message["radioId"] as? String,
                   let station = storage.favoriteRadioStations.first(where: { $0.id == radioId }) ?? storage.cachedRadioStations.first(where: { $0.id == radioId }) {
                    player.playRadio(station)
                }
            case "requestSync":
                self.syncContextToWatch()
            default:
                break
            }
        }
    }
}
#endif

