import SwiftUI
import BackgroundTasks

@main
struct PodcastUltraApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @ObservedObject private var storage = LocalStorageManager.shared
    
    private let backgroundRefreshTaskId = "com.podcastultra.app.refresh"
    private let backgroundProcessingTaskId = "com.podcastultra.app.processing"
    
    init() {
        registerBackgroundTasks()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioPlayer)
                .preferredColorScheme(storage.isLightTheme ? .light : .dark)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        scheduleHourlyBackgroundRefresh()
                        runImmediateBackgroundRefreshIfNeeded()
                    }
                }
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
    
    private func registerBackgroundTasks() {
        let permitted = (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]) ?? []
        if permitted.contains(backgroundRefreshTaskId) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: backgroundRefreshTaskId,
                using: nil
            ) { task in
                guard let refreshTask = task as? BGAppRefreshTask else { return }
                handleBackgroundRefresh(task: refreshTask)
            }
        }
        
        if permitted.contains(backgroundProcessingTaskId) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: backgroundProcessingTaskId,
                using: nil
            ) { task in
                guard let processingTask = task as? BGProcessingTask else { return }
                handleBackgroundProcessing(task: processingTask)
            }
        }
    }
    
    private func scheduleHourlyBackgroundRefresh() {
        let refreshRequest = BGAppRefreshTaskRequest(identifier: backgroundRefreshTaskId)
        // Request background execution 1 hour (3600 seconds) from now
        refreshRequest.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(refreshRequest)
        
        let processingRequest = BGProcessingTaskRequest(identifier: backgroundProcessingTaskId)
        processingRequest.requiresNetworkConnectivity = true
        processingRequest.requiresExternalPower = false
        processingRequest.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(processingRequest)
    }
    
    private func runImmediateBackgroundRefreshIfNeeded() {
        let storage = LocalStorageManager.shared
        guard !storage.favoritePodcasts.isEmpty else { return }
        guard storage.shouldRefresh(lastFetch: storage.lastEpisodesFetchDate, minInterval: 50 * 60) else {
            return
        }
        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "PodcastUltraBackgroundEpisodesRefresh") {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }
        Task {
            await storage.performBackgroundRefresh(force: true)
            if bgTaskID != .invalid {
                await MainActor.run {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                    bgTaskID = .invalid
                }
            }
        }
    }
    
    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleHourlyBackgroundRefresh()
        
        let refreshJob = Task {
            await LocalStorageManager.shared.performBackgroundRefresh(force: true)
        }
        
        task.expirationHandler = {
            refreshJob.cancel()
        }
        
        Task {
            _ = await refreshJob.result
            task.setTaskCompleted(success: true)
        }
    }
    
    private func handleBackgroundProcessing(task: BGProcessingTask) {
        scheduleHourlyBackgroundRefresh()
        
        let processingJob = Task {
            await LocalStorageManager.shared.performBackgroundRefresh(force: true)
        }
        
        task.expirationHandler = {
            processingJob.cancel()
        }
        
        Task {
            _ = await processingJob.result
            task.setTaskCompleted(success: true)
        }
    }
}
