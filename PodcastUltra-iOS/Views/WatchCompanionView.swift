import SwiftUI
import Combine

struct WatchCompanionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    @ObservedObject var watchSession = WatchSessionManager.shared
    @ObservedObject var progress = AudioPlayerManager.shared.progress
    
    enum WatchScreenTab: Int, CaseIterable {
        case nowPlaying = 0
        case episodes = 1
        case radios = 2
    }
    
    @State private var activeWatchScreen: WatchScreenTab = .nowPlaying
    @State private var currentWatchTimeString: String = ""
    private let clockTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    Label("Podcast Ultra • Apple Watch", systemImage: "applewatch.watchface")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(storage.primaryTextColor)
                    
                    Spacer()
                    
                    Button(action: {
                        HapticManager.shared.trigger(.light)
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                // Interactive Apple Watch Casing inside the App
                ZStack {
                    // Watch Straps
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 140, height: 36)
                        
                        Spacer()
                        
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.25)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 140, height: 36)
                    }
                    .frame(height: 390)
                    
                    // Digital Crown & Side Button on the right
                    HStack(spacing: 0) {
                        Spacer()
                        VStack(spacing: 28) {
                            // Digital Crown (tapping cycles watch screen)
                            Button(action: {
                                HapticManager.shared.trigger(.light)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    let next = (activeWatchScreen.rawValue + 1) % WatchScreenTab.allCases.count
                                    activeWatchScreen = WatchScreenTab(rawValue: next) ?? .nowPlaying
                                }
                            }) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(storage.accentColorColor())
                                    .frame(width: 12, height: 42)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            
                            // Side Button (toggles play/pause)
                            Button(action: {
                                HapticManager.shared.trigger(.medium)
                                audioPlayer.togglePlayPause()
                            }) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.gray.opacity(0.6))
                                    .frame(width: 8, height: 28)
                            }
                        }
                        .offset(x: 6, y: -20)
                    }
                    .frame(width: 266)
                    
                    // Watch Titanium / Aluminum Case
                    RoundedRectangle(cornerRadius: 54, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 55/255, green: 65/255, blue: 81/255),
                                    Color(red: 17/255, green: 24/255, blue: 39/255)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 256, height: 312)
                        .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 54, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 2)
                        )
                    
                    // Watch OLED Screen
                    VStack(spacing: 0) {
                        // Watch Status Bar
                        HStack {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(storage.accentColorColor())
                                    .frame(width: 6, height: 6)
                                Text(watchScreenTitle)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(storage.accentColorColor())
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(currentWatchTimeString)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                        
                        // Watch Screen Content
                        Group {
                            switch activeWatchScreen {
                            case .nowPlaying:
                                watchNowPlayingContent
                            case .episodes:
                                watchEpisodesContent
                            case .radios:
                                watchRadiosContent
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Watch Page Dots / Quick Switcher
                        HStack(spacing: 14) {
                            watchTabDot(tab: .nowPlaying, icon: "play.fill")
                            watchTabDot(tab: .episodes, icon: "list.bullet")
                            watchTabDot(tab: .radios, icon: "radio")
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(width: 232, height: 286)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                }
                
                // Instructions / Screen Switcher Pills
                HStack(spacing: 10) {
                    watchModePill(
                        tab: .nowPlaying,
                        title: storage.currentLanguage == .fr ? "Lecteur" : "Player",
                        icon: "play.circle.fill"
                    )
                    watchModePill(
                        tab: .episodes,
                        title: storage.currentLanguage == .fr ? "Épisodes" : "Episodes",
                        icon: "waveform"
                    )
                    watchModePill(
                        tab: .radios,
                        title: "Radios",
                        icon: "dot.radiowaves.left.and.right"
                    )
                }
                .padding(.horizontal)
                
                // Physical Apple Watch Companion Sync Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "applewatch.radiowaves.left.and.right")
                            .font(.title3)
                            .foregroundColor(storage.accentColorColor())
                        Text(storage.currentLanguage == .fr ? "Synchronisation Apple Watch" : "Apple Watch Sync")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(storage.primaryTextColor)
                        Spacer()
                        HStack(spacing: 5) {
                            Circle()
                                .fill(watchSession.isWatchPaired ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(
                                watchSession.isWatchPaired
                                ? (storage.currentLanguage == .fr ? "Jumelée" : "Paired")
                                : (storage.currentLanguage == .fr ? "Mode autonome" : "Standalone")
                            )
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    Text(
                        storage.currentLanguage == .fr
                        ? "Utilisez l'aperçu Apple Watch ci-dessus directement dans l'application ou synchronisez vos derniers épisodes, vos radios favorites et le contrôle de lecture avec votre Apple Watch."
                        : "Use the Apple Watch interface above directly in the app or sync your latest episodes, favorite radios and playback controls with your paired Apple Watch."
                    )
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    
                    Button(action: {
                        HapticManager.shared.trigger(.medium)
                        watchSession.syncLatestPodcastsToWatch()
                    }) {
                        HStack {
                            if watchSession.isSyncingPodcasts {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.85)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(
                                watchSession.isSyncingPodcasts
                                ? (storage.currentLanguage == .fr ? "Chargement des derniers podcasts..." : "Loading latest podcasts...")
                                : (storage.currentLanguage == .fr ? "Synchroniser avec l'Apple Watch" : "Sync with Apple Watch")
                            )
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(storage.accentColorColor())
                        .cornerRadius(12)
                    }
                    .disabled(watchSession.isSyncingPodcasts)
                }
                .padding(16)
                .background(storage.cardBackgroundColor)
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
                .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
        .background(storage.mainBackgroundColor.ignoresSafeArea())
        .onAppear {
            updateClock()
            watchSession.syncContextToWatch()
        }
        .onReceive(clockTimer) { _ in
            updateClock()
        }
    }
    
    private var watchScreenTitle: String {
        switch activeWatchScreen {
        case .nowPlaying: return " À l'écoute"
        case .episodes: return " Épisodes"
        case .radios: return " Radios"
        }
    }
    
    private var watchNowPlayingContent: some View {
        VStack(spacing: 8) {
            CachedAsyncImage(url: URL(string: audioPlayer.currentArtworkUrl ?? ""), maxPixelSize: 200) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundColor(storage.accentColorColor())
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            
            VStack(spacing: 2) {
                Text(audioPlayer.currentTrackName ?? (storage.currentLanguage == .fr ? "Aucune lecture" : "Not Playing"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                
                Text(audioPlayer.currentSubtitle ?? "Podcast Ultra")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(storage.accentColorColor())
                    .lineLimit(1)
                    .padding(.horizontal, 10)
            }
            
            if audioPlayer.playbackType == "podcast" && progress.duration > 0 {
                ProgressView(value: min(progress.currentTime, progress.duration), total: max(progress.duration, 1))
                    .tint(storage.accentColorColor())
                    .padding(.horizontal, 20)
            }
            
            HStack(spacing: 18) {
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    audioPlayer.skip(seconds: -15)
                }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                
                Button(action: {
                    HapticManager.shared.trigger(.medium)
                    audioPlayer.togglePlayPause()
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(storage.accentColorColor())
                        .clipShape(Circle())
                }
                
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    audioPlayer.skip(seconds: 30)
                }) {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            .padding(.top, 2)
        }
    }
    
    private var watchEpisodesContent: some View {
        ScrollView {
            VStack(spacing: 6) {
                let topEps = Array(storage.cachedEpisodes.filter { !storage.isDismissedEpisode($0.trackId) }.prefix(5))
                if topEps.isEmpty {
                    Text(storage.currentLanguage == .fr ? "Aucun épisode récent" : "No recent episodes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.top, 40)
                } else {
                    ForEach(topEps) { ep in
                        Button(action: {
                            HapticManager.shared.trigger(.light)
                            audioPlayer.playEpisode(ep)
                            withAnimation { activeWatchScreen = .nowPlaying }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: audioPlayer.currentEpisode?.trackId == ep.trackId && audioPlayer.isPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(storage.accentColorColor())
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ep.trackName)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(ep.collectionName ?? "")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }
    
    private var watchRadiosContent: some View {
        ScrollView {
            VStack(spacing: 6) {
                let stations = storage.favoriteRadioStations.isEmpty
                    ? Array(storage.cachedRadioStations.prefix(6))
                    : storage.favoriteRadioStations
                if stations.isEmpty {
                    Text(storage.currentLanguage == .fr ? "Aucune radio" : "No radios")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.top, 40)
                } else {
                    ForEach(stations) { station in
                        Button(action: {
                            HapticManager.shared.trigger(.light)
                            audioPlayer.playRadio(station)
                            withAnimation { activeWatchScreen = .nowPlaying }
                        }) {
                            HStack(spacing: 8) {
                                RadioStationArtworkView(station: station, size: 22, cornerRadius: 6)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(station.name)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    if let country = station.country, !country.isEmpty {
                                        Text(country)
                                            .font(.system(size: 9))
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }
    
    private func watchTabDot(tab: WatchScreenTab, icon: String) -> some View {
        Button(action: {
            HapticManager.shared.trigger(.light)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                activeWatchScreen = tab
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(activeWatchScreen == tab ? storage.accentColorColor() : .gray)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func watchModePill(tab: WatchScreenTab, title: String, icon: String) -> some View {
        Button(action: {
            HapticManager.shared.trigger(.light)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                activeWatchScreen = tab
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(activeWatchScreen == tab ? .white : storage.primaryTextColor)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(activeWatchScreen == tab ? storage.accentColorColor() : storage.subtleSurfaceColor)
            .cornerRadius(14)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func updateClock() {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        currentWatchTimeString = df.string(from: Date())
    }
}
