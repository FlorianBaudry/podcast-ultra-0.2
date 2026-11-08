import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Dedicated progress observable so only the player scrubber re-renders every second,
/// preventing full-app SwiftUI view hierarchy invalidations during playback.
final class AudioPlaybackProgress: ObservableObject {
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
}

class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()
    
    @Published var isPlaying = false
    @Published var currentTrackName: String?
    @Published var currentArtworkUrl: String?
    @Published var currentSubtitle: String?
    
    // Detailed states
    @Published var currentEpisode: Episode?
    @Published var currentRadio: RadioStation?
    @Published var playbackType: String = "podcast" // "podcast", "radio"
    
    @Published var queue: [Episode] = []
    
    // Isolated progress object for 1s time updates
    let progress = AudioPlaybackProgress()
    
    var currentTime: Double {
        get { progress.currentTime }
        set { progress.currentTime = newValue }
    }
    
    var duration: Double {
        get { progress.duration }
        set { progress.duration = newValue }
    }
    
    // Sleep Timer
    @Published var sleepTimerTimeLeft: TimeInterval? = nil
    private var sleepTimer: Timer?
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private var endObserverToken: NSObjectProtocol?
    private var failObserverToken: NSObjectProtocol?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var currentStreamURLString: String?
    
    private var cancellables = Set<AnyCancellable>()
    private var hasMarkedPlayed = false
    private var lastNowPlayingUpdateSec: Int = -1
    
    init() {
        setupAudioSession()
        setupRemoteTransportControls()
        setupSystemNotifications()
        
        // Listen to playback speed changes in LocalStorageManager (deferred to avoid singleton init cycles)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            LocalStorageManager.shared.$settings
                .map { $0.playbackSpeed }
                .removeDuplicates()
                .sink { [weak self] speed in
                    self?.setPlaybackRate(speed)
                }
                .store(in: &self.cancellables)
        }
    }
    
    private var isAudioSessionActive = false
    private let audioSessionQueue = DispatchQueue(label: "com.podcastultra.audiosession", qos: .userInitiated)
    
    private func setupAudioSession() {
        audioSessionQueue.async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetoothA2DP])
            } catch {
                print("Failed to setup audio session category: \(error)")
            }
        }
    }
    
    private func ensureAudioSessionActive() {
        guard !isAudioSessionActive else { return }
        audioSessionQueue.async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetoothA2DP])
                if #available(iOS 17.0, *) {
                    if #available(iOS 27.0, *) {
                        session.activate(options: []) { success, error in
                            if let error = error {
                                print("AudioSession async activation error: \(error)")
                            } else {
                                self.isAudioSessionActive = success
                            }
                        }
                    } else {
                        // Fallback on earlier versions
                    }
                } else {
                    try session.setActive(true)
                    self.isAudioSessionActive = true
                }
            } catch {
                print("AudioSession activation warning: \(error)")
            }
        }
    }
    
    private func setupSystemNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resume()
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        if reason == .oldDeviceUnavailable {
            DispatchQueue.main.async { [weak self] in
                self?.pause()
            }
        }
    }
    
    @objc private func handleDidEnterBackground() {
        if playbackType == "podcast", let ep = currentEpisode, progress.currentTime > 0 {
            LocalStorageManager.shared.setSavedPosition(progress.currentTime, for: ep.trackId, flushImmediately: true)
        }
        if isPlaying {
            ensureAudioSessionActive()
            updateNowPlayingInfoPlaybackState()
        }
    }
    
    private func beginBackgroundTransitionTask() {
        endBackgroundTransitionTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "PodcastUltraAudioTransition") { [weak self] in
            self?.endBackgroundTransitionTask()
        }
    }
    
    private func endBackgroundTransitionTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    func playEpisode(_ episode: Episode, exactResumeTime: Double? = nil) {
        beginBackgroundTransitionTask()
        self.currentEpisode = episode
        self.currentRadio = nil
        self.playbackType = "podcast"
        self.currentTrackName = episode.trackName
        self.currentArtworkUrl = episode.artworkUrl600 ?? episode.artworkUrl160 ?? episode.artworkUrl60
        self.currentSubtitle = episode.artistName ?? episode.collectionName
        self.hasMarkedPlayed = false
        
        if let durationMillis = episode.trackTimeMillis, durationMillis > 0 {
            self.progress.duration = Double(durationMillis) / 1000.0
        } else {
            self.progress.duration = 0.0
        }
        
        // Add to history
        LocalStorageManager.shared.addToHistory(episode)
        
        // Handle positions & skip intro settings
        let settings = LocalStorageManager.shared.settings
        var startTime: Double = 0.0
        let savedPos = LocalStorageManager.shared.getSavedPosition(for: episode.trackId)
        if let exact = exactResumeTime, exact > 0 {
            startTime = exact
        } else if savedPos > 0 {
            startTime = savedPos
        } else if settings.skipIntro {
            startTime = 30.0
        }
        self.progress.currentTime = startTime
        
        // Record initial position (at least 1s) immediately when playback starts so the "Non lu" filter knows this episode has been started
        let initialRecordedPos = max(startTime, 1.0)
        LocalStorageManager.shared.setSavedPosition(initialRecordedPos, for: episode.trackId, flushImmediately: true)
        
        // Record in-progress state for Subscriptions / Audiobooks / Podcasts
        LocalStorageManager.shared.recordInProgress(
            episode: episode,
            positionSeconds: initialRecordedPos,
            durationSeconds: self.progress.duration
        )
        
        let resolvedURL: String
        let localURL = DownloadManager.shared.fileURL(for: episode.trackId)
        if FileManager.default.fileExists(atPath: localURL.path) {
            resolvedURL = localURL.path
        } else if let urlString = episode.previewUrl {
            resolvedURL = urlString
        } else {
            endBackgroundTransitionTask()
            return
        }
        
        self.currentStreamURLString = episode.previewUrl ?? resolvedURL
        playURL(resolvedURL, initialSeekTime: startTime)
        updateWidgetState()
        WatchSessionManager.shared.syncContextToWatch()
        endBackgroundTransitionTask()
    }
    
    func isSubscriptionPlaying(_ podcast: Podcast) -> Bool {
        guard isPlaying else { return false }
        if currentEpisode?.collectionId == podcast.collectionId { return true }
        if let state = LocalStorageManager.shared.getInProgressState(for: podcast),
           currentEpisode?.trackId == state.episode.trackId {
            return true
        }
        return false
    }
    
    func toggleSubscriptionPlayback(_ podcast: Podcast) {
        if isSubscriptionPlaying(podcast) {
            togglePlayPause()
        } else {
            resumeSubscription(podcast)
        }
    }
    
    func resumeSubscription(_ podcast: Podcast) {
        if let state = LocalStorageManager.shared.getInProgressState(for: podcast) {
            if currentEpisode?.trackId == state.episode.trackId, player != nil {
                let targetTime = max(progress.currentTime, state.positionSeconds)
                seek(to: targetTime)
                if !isPlaying {
                    resume()
                }
                return
            }
            playEpisode(state.episode, exactResumeTime: state.positionSeconds)
            return
        }
        
        // Fallback: load episodes for this item and play the first one with saved position or first episode
        Task {
            let eps = (try? await APIService.shared.getPodcastEpisodes(
                collectionId: podcast.collectionId,
                preferredCountry: LocalStorageManager.shared.currentLanguage.itunes,
                feedUrl: podcast.feedUrl
            )) ?? []
            guard !eps.isEmpty else { return }
            await MainActor.run {
                if let savedEp = eps.first(where: { LocalStorageManager.shared.getSavedPosition(for: $0.trackId) > 0 }) {
                    let pos = LocalStorageManager.shared.getSavedPosition(for: savedEp.trackId)
                    self.playEpisode(savedEp, exactResumeTime: pos)
                } else if let first = eps.first {
                    self.playEpisode(first)
                }
            }
        }
    }
    
    func stopIfPlayingCollection(_ collectionId: Int) {
        guard playbackType == "podcast", currentEpisode?.collectionId == collectionId else { return }
        player?.pause()
        isPlaying = false
    }
    
    func playRadio(_ radio: RadioStation) {
        beginBackgroundTransitionTask()
        let directURL = APIService.shared.cleanAdFreeRadioURL(name: radio.name, rawURL: radio.url)
        self.currentRadio = radio
        self.currentEpisode = nil
        self.playbackType = "radio"
        self.currentTrackName = radio.name
        self.currentArtworkUrl = radio.favicon
        self.currentSubtitle = radio.country ?? "Radio Direct"
        self.progress.currentTime = 0.0
        self.progress.duration = 0.0
        self.currentStreamURLString = directURL
        
        playURL(directURL, initialSeekTime: 0)
        updateWidgetState()
        WatchSessionManager.shared.syncContextToWatch()
        endBackgroundTransitionTask()
    }
    
    func syncCurrentTrackToChromecastIfConnected() {
        guard ChromecastManager.shared.connectedDevice != nil,
              let remoteUrl = currentEpisode?.previewUrl ?? currentRadio?.url ?? currentStreamURLString,
              !remoteUrl.hasPrefix("/") else { return }
        
        player?.pause()
        ChromecastManager.shared.loadMedia(
            url: remoteUrl,
            title: currentTrackName ?? "Podcast Ultra",
            subtitle: currentSubtitle ?? "",
            artworkUrl: currentArtworkUrl,
            isLive: playbackType == "radio",
            startTime: progress.currentTime
        )
        isPlaying = true
    }
    
    private func playURL(_ urlString: String, initialSeekTime: Double = 0.0) {
        ensureAudioSessionActive()
        
        // If connected to a Chromecast and playing an HTTP stream, cast to the receiver
        if ChromecastManager.shared.connectedDevice != nil,
           let castUrl = currentEpisode?.previewUrl ?? currentRadio?.url,
           castUrl.lowercased().hasPrefix("http") {
            removeTimeObserver()
            removeItemObservers()
            player?.pause()
            isPlaying = true
            ChromecastManager.shared.loadMedia(
                url: castUrl,
                title: currentTrackName ?? "Podcast Ultra",
                subtitle: currentSubtitle ?? "",
                artworkUrl: currentArtworkUrl,
                isLive: playbackType == "radio",
                startTime: initialSeekTime
            )
            updateNowPlayingInfo()
            updateWidgetState()
            return
        }
        
        let sanitizedUrlString = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
        
        let url: URL
        if sanitizedUrlString.hasPrefix("/") || sanitizedUrlString.hasPrefix("file://") {
            let cleanPath = sanitizedUrlString.replacingOccurrences(of: "file://", with: "")
            url = URL(fileURLWithPath: cleanPath)
        } else if let directURL = URL(string: sanitizedUrlString) {
            url = directURL
        } else {
            guard let encodedUrlString = sanitizedUrlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let parsedURL = URL(string: encodedUrlString) else { return }
            url = parsedURL
        }
        
        removeTimeObserver()
        removeItemObservers()
        
        let asset: AVURLAsset
        if playbackType == "radio" && !url.isFileURL {
            // Use a clean Icecast User-Agent to avoid Adswizz mobile pre-roll ad injection
            let headers: [String: String] = [
                "Icy-MetaData": "0",
                "User-Agent": "VLC/3.0.20 LibVLC/3.0.20"
            ]
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        } else if !url.isFileURL {
            // Standard podcast HTTP headers (prevents CDN 403 / anti-scraping blocks on College de France, Radio France, Akamai)
            let podcastHeaders: [String: String] = [
                "User-Agent": "PodcastUltra/1.0 (iPhone; iOS; AppleCoreMedia)",
                "Accept": "*/*"
            ]
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": podcastHeaders])
        } else {
            asset = AVURLAsset(url: url)
        }
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 120 // Buffer 2 minutes ahead for reliable background playback
        self.playerItem = item
        
        if let existingPlayer = player {
            existingPlayer.replaceCurrentItem(with: item)
        } else {
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            self.player = newPlayer
        }
        
        setupItemObservers(for: item)
        addTimeObserver()
        
        if initialSeekTime > 0 && playbackType == "podcast" {
            let cmTime = CMTime(seconds: initialSeekTime, preferredTimescale: 600)
            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        
        player?.play()
        isPlaying = true
        
        setPlaybackRate(LocalStorageManager.shared.settings.playbackSpeed)
        updateNowPlayingInfo()
        updateWidgetState()
    }
    
    private func setupItemObservers(for item: AVPlayerItem) {
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.playNextTrack()
        }
        
        failObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Attempt seamless recovery at current position if network dropped briefly
            if self.playbackType == "podcast", let ep = self.currentEpisode, let urlStr = ep.previewUrl {
                let savedTime = self.progress.currentTime
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.currentEpisode?.trackId == ep.trackId {
                        self.playURL(urlStr, initialSeekTime: savedTime)
                    }
                }
            }
        }
    }
    
    private func removeItemObservers() {
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
        if let token = failObserverToken {
            NotificationCenter.default.removeObserver(token)
            failObserverToken = nil
        }
    }
    
    func pause() {
        if ChromecastManager.shared.connectedDevice != nil {
            ChromecastManager.shared.pause()
        }
        player?.pause()
        isPlaying = false
        if playbackType == "podcast", let ep = currentEpisode, progress.currentTime > 0 {
            LocalStorageManager.shared.setSavedPosition(progress.currentTime, for: ep.trackId, flushImmediately: true)
            LocalStorageManager.shared.recordInProgress(episode: ep, positionSeconds: progress.currentTime, durationSeconds: progress.duration)
        }
        updateNowPlayingInfoPlaybackState()
        updateWidgetState()
        WatchSessionManager.shared.syncContextToWatch()
    }
    
    func resume() {
        ensureAudioSessionActive()
        if ChromecastManager.shared.connectedDevice != nil {
            ChromecastManager.shared.play()
            isPlaying = true
        } else {
            player?.play()
            isPlaying = true
            setPlaybackRate(LocalStorageManager.shared.settings.playbackSpeed)
        }
        updateNowPlayingInfoPlaybackState()
        updateWidgetState()
        WatchSessionManager.shared.syncContextToWatch()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            playLastInProgressOrDefault()
        }
    }
    
    /// Plays the last episode in progress (or resumes current player item) if nothing is currently playing.
    func playLastInProgressOrDefault() {
        guard !isPlaying else { return }
        
        // 1. If a player item or Chromecast session is already loaded in memory, resume it directly
        if (player != nil && (currentEpisode != nil || currentRadio != nil)) || ChromecastManager.shared.connectedDevice != nil {
            resume()
            return
        }
        
        let storage = LocalStorageManager.shared
        
        // 2. If there is a queued episode waiting in the playlist, start playing the playlist
        if !queue.isEmpty {
            let firstQueued = queue.removeFirst()
            playEpisode(firstQueued)
            return
        }
        
        // 3. Check listening history (most recent first) for the last played episode
        if let lastHistoryEp = storage.history.first {
            let savedPos = storage.getSavedPosition(for: lastHistoryEp.trackId)
            if savedPos > 0 {
                playEpisode(lastHistoryEp, exactResumeTime: savedPos)
            } else {
                playEpisode(lastHistoryEp)
            }
            return
        }
        
        // 4. Check inProgressByCollection for the most recently updated in-progress episode
        if let mostRecentInProgress = storage.inProgressByCollection.values.max(by: { $0.updatedAt < $1.updatedAt }) {
            let pos = max(mostRecentInProgress.positionSeconds, storage.getSavedPosition(for: mostRecentInProgress.episode.trackId))
            playEpisode(mostRecentInProgress.episode, exactResumeTime: pos)
            return
        }
        
        // 5. Fallback: play the most recent unplayed episode from cachedEpisodes (Favoris)
        let dismissed = Set(storage.dismissedEpisodeIds)
        let played = Set(storage.playedEpisodeIds)
        if let latestUnplayed = storage.cachedEpisodes.first(where: { !dismissed.contains($0.trackId) && !played.contains($0.trackId) }) {
            playEpisode(latestUnplayed)
        } else if let latest = storage.cachedEpisodes.first(where: { !dismissed.contains($0.trackId) }) ?? storage.cachedEpisodes.first {
            playEpisode(latest)
        }
    }
    
    func seek(to time: Double) {
        let clamped = max(0, time)
        self.progress.currentTime = clamped
        if ChromecastManager.shared.connectedDevice != nil {
            ChromecastManager.shared.seek(to: clamped)
        } else {
            let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
            player?.seek(to: cmTime)
        }
        if playbackType == "podcast", let ep = currentEpisode {
            LocalStorageManager.shared.setSavedPosition(clamped, for: ep.trackId, flushImmediately: true)
            LocalStorageManager.shared.recordInProgress(episode: ep, positionSeconds: clamped, durationSeconds: progress.duration)
        }
        updateNowPlayingInfoPlaybackState()
    }
    
    func skip(seconds: Double) {
        let currentSeconds = progress.currentTime
        var targetSeconds = currentSeconds + seconds
        if targetSeconds < 0 { targetSeconds = 0 }
        if progress.duration > 0 && targetSeconds > progress.duration {
            targetSeconds = progress.duration
        }
        seek(to: targetSeconds)
    }
    
    private func setPlaybackRate(_ speed: Double) {
        guard isPlaying else { return }
        guard playbackType == "podcast" else {
            player?.rate = 1.0
            return
        }
        player?.rate = Float(speed)
    }
    
    // Queue management
    func addToQueue(_ episode: Episode, playNext: Bool = false) {
        if playNext {
            queue.insert(episode, at: 0)
        } else {
            queue.append(episode)
        }
        
        // If nothing is currently playing, immediately start playing the queue
        if !isPlaying {
            let nextEp = queue.removeFirst()
            playEpisode(nextEp)
        }
    }
    
    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        queue.remove(at: index)
    }
    
    func moveQueueItem(fromIndex: Int, direction: Int) {
        let toIndex = fromIndex + direction
        guard fromIndex >= 0 && fromIndex < queue.count,
              toIndex >= 0 && toIndex < queue.count else { return }
        
        let item = queue.remove(at: fromIndex)
        queue.insert(item, at: toIndex)
    }
    
    func playNextTrack() {
        beginBackgroundTransitionTask()
        let storage = LocalStorageManager.shared
        
        // Mark current episode as played and clean up download if configured
        if playbackType == "podcast", let ep = currentEpisode {
            storage.markPlayedEpisode(ep.trackId)
            storage.setSavedPosition(0, for: ep.trackId, flushImmediately: true)
            if let colId = ep.collectionId {
                storage.clearInProgressIfFinished(collectionId: colId, finishedEpisodeId: ep.trackId)
            }
            if storage.settings.deleteAfterListening {
                DownloadManager.shared.deleteDownload(episodeId: ep.trackId)
            }
        }
        
        if !queue.isEmpty {
            let nextEp = queue.removeFirst()
            playEpisode(nextEp)
            endBackgroundTransitionTask()
            return
        }
        
        // Fallback: play the next radio station if in radio mode
        if playbackType == "radio", let currentStation = currentRadio {
            let stations = !storage.favoriteRadioStations.isEmpty ? storage.favoriteRadioStations : storage.cachedRadioStations
            if !stations.isEmpty, let idx = stations.firstIndex(where: { $0.id == currentStation.id }) {
                let nextIdx = (idx + 1) % stations.count
                playRadio(stations[nextIdx])
                endBackgroundTransitionTask()
                return
            }
        }
        
        // Fallback: automatically play the next unplayed episode from cachedEpisodes
        let currentId = currentEpisode?.trackId
        if let curId = currentId,
           let curIdx = storage.cachedEpisodes.firstIndex(where: { $0.trackId == curId }) {
            let remaining = storage.cachedEpisodes.suffix(from: curIdx + 1)
            if let nextAfterCurrent = remaining.first(where: { !storage.isPlayedEpisode($0.trackId) && !storage.isDismissedEpisode($0.trackId) })
                ?? remaining.first(where: { !storage.isDismissedEpisode($0.trackId) }) {
                playEpisode(nextAfterCurrent)
                endBackgroundTransitionTask()
                return
            }
        }
        if let nextUnplayed = storage.cachedEpisodes.first(where: {
            $0.trackId != currentId && !storage.isPlayedEpisode($0.trackId) && !storage.isDismissedEpisode($0.trackId)
        }) {
            playEpisode(nextUnplayed)
            endBackgroundTransitionTask()
            return
        }
        
        // Nothing left to play
        removeTimeObserver()
        removeItemObservers()
        playbackType = "podcast"
        currentEpisode = nil
        currentRadio = nil
        currentTrackName = nil
        currentArtworkUrl = nil
        currentSubtitle = nil
        isPlaying = false
        progress.currentTime = 0.0
        progress.duration = 0.0
        player?.pause()
        player = nil
        playerItem = nil
        updateWidgetState()
        WatchSessionManager.shared.syncContextToWatch()
        endBackgroundTransitionTask()
    }
    
    func playPreviousTrack() {
        let storage = LocalStorageManager.shared
        
        // Radio mode: switch to the previous station
        if playbackType == "radio", let currentStation = currentRadio {
            let stations = !storage.favoriteRadioStations.isEmpty ? storage.favoriteRadioStations : storage.cachedRadioStations
            if !stations.isEmpty, let idx = stations.firstIndex(where: { $0.id == currentStation.id }) {
                let prevIdx = (idx - 1 + stations.count) % stations.count
                playRadio(stations[prevIdx])
            }
            return
        }
        
        // Podcast mode: if more than 5 seconds into the current episode, restart it from 0:00
        if playbackType == "podcast", currentEpisode != nil, progress.currentTime > 5.0 {
            seek(to: 0)
            if !isPlaying {
                resume()
            }
            return
        }
        
        // Otherwise play the previous episode from history (putting the current episode at the front of the queue)
        let currentId = currentEpisode?.trackId
        if let prevHistoryEp = storage.history.first(where: { $0.trackId != currentId }) {
            if let currentEp = currentEpisode, !queue.contains(where: { $0.trackId == currentEp.trackId }) {
                queue.insert(currentEp, at: 0)
            }
            playEpisode(prevHistoryEp)
            return
        }
        
        // Or play the previous episode in cachedEpisodes list
        if let curId = currentId,
           let curIdx = storage.cachedEpisodes.firstIndex(where: { $0.trackId == curId }),
           curIdx > 0 {
            let prevEp = storage.cachedEpisodes[curIdx - 1]
            if let currentEp = currentEpisode, !queue.contains(where: { $0.trackId == currentEp.trackId }) {
                queue.insert(currentEp, at: 0)
            }
            playEpisode(prevEp)
            return
        }
        
        // Fallback: restart current episode or start default playback
        if currentEpisode != nil {
            seek(to: 0)
            if !isPlaying {
                resume()
            }
        } else {
            playLastInProgressOrDefault()
        }
    }
    
    // Time Observer (1.0s interval, updates only isolated `progress` object)
    private func addTimeObserver() {
        let interval = CMTime(seconds: 1.0, preferredTimescale: 600)
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, let item = self.playerItem else { return }
            
            let currentSec = CMTimeGetSeconds(time)
            guard currentSec.isFinite && currentSec >= 0 else { return }
            self.progress.currentTime = currentSec
            
            let durationTime = item.duration
            if durationTime.isValid && !durationTime.isIndefinite {
                let totalSec = CMTimeGetSeconds(durationTime)
                if totalSec.isFinite && totalSec > 0 {
                    self.progress.duration = totalSec
                }
            }
            
            let secInt = Int(currentSec)
            // Update lockscreen elapsed time every 15s without recreating artwork
            if abs(secInt - self.lastNowPlayingUpdateSec) >= 15 {
                self.lastNowPlayingUpdateSec = secInt
                self.updateNowPlayingInfoPlaybackState()
            }
            
            if self.playbackType == "podcast", let ep = self.currentEpisode {
                // Save position in background without triggering SwiftUI @Published on LocalStorageManager
                LocalStorageManager.shared.setSavedPosition(currentSec, for: ep.trackId, flushImmediately: false)
                if secInt > 0 && secInt % 10 == 0 {
                    LocalStorageManager.shared.updateInProgressPositionQuietly(episode: ep, positionSeconds: currentSec, durationSeconds: self.progress.duration)
                }
                
                // Mark as played only when the episode is genuinely finished (within 15s of the end or >= 98% of duration)
                let totalDur = self.progress.duration > 0 ? self.progress.duration : Double(ep.trackTimeMillis ?? 0) / 1000.0
                if !self.hasMarkedPlayed && totalDur > 30 && (currentSec >= totalDur - 15.0 || currentSec / totalDur >= 0.98) {
                    self.hasMarkedPlayed = true
                    LocalStorageManager.shared.markPlayedEpisode(ep.trackId)
                }
            }
        }
    }
    
    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
    
    // Sleep Timer
    func startSleepTimer(minutes: Int) {
        stopSleepTimer()
        var secondsLeft = TimeInterval(minutes * 60)
        sleepTimerTimeLeft = secondsLeft
        
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            secondsLeft -= 1
            self.sleepTimerTimeLeft = secondsLeft
            
            if secondsLeft <= 0 {
                self.stopSleepTimer()
                self.pause()
            }
        }
    }
    
    func stopSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerTimeLeft = nil
    }
    
    // Remote Lockscreen Controls
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.resume()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.pause()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.skip(seconds: 30)
            return .success
        }
        
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.skip(seconds: -15)
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.playNextTrack()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.playPreviousTrack()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: posEvent.positionTime)
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTrackName ?? "Unknown Track"
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentSubtitle ?? "Podcast Ultra"
        
        if playbackType == "podcast" {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress.currentTime
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = progress.duration
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Float(LocalStorageManager.shared.settings.playbackSpeed) : 0.0
        } else {
            nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        if let artworkUrlString = currentArtworkUrl,
           let url = URL(string: artworkUrlString) {
            if let cachedImage = DecodedImageMemoryCache.shared.image(for: url) {
                let artwork = MPMediaItemArtwork(boundsSize: cachedImage.size) { _ in cachedImage }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            } else {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data = data, let image = UIImage(data: data) {
                        DecodedImageMemoryCache.shared.insert(image, for: url)
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        DispatchQueue.main.async {
                            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                            info[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                        }
                    }
                }.resume()
            }
        }
    }
    
    private func updateNowPlayingInfoPlaybackState() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress.currentTime
        if progress.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = progress.duration
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? (playbackType == "podcast" ? Float(LocalStorageManager.shared.settings.playbackSpeed) : 1.0) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func updateWidgetState() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if let sharedDefaults = UserDefaults(suiteName: "group.com.podcastultra.app") {
                sharedDefaults.set(self.currentTrackName, forKey: "currentTrackName")
                sharedDefaults.set(self.currentSubtitle, forKey: "currentSubtitle")
                sharedDefaults.set(self.currentArtworkUrl, forKey: "currentArtworkUrl")
                sharedDefaults.set(self.isPlaying, forKey: "isPlaying")
            }
            #if canImport(WidgetKit) && os(iOS)
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
            }
            #endif
        }
    }
}
