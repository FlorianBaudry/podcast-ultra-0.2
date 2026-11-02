import SwiftUI
import AVKit

struct PlayerView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    @State private var viewMode: PlayerViewMode = .player
    @State private var showingSleepTimerDialog = false
    
    enum PlayerViewMode: String, CaseIterable, Identifiable {
        case player, queue, history
        var id: String { rawValue }
        
        func label(lang: LangCode) -> String {
            switch self {
            case .player: return lang == .fr ? "Lecteur" : "Player"
            case .queue: return Translations.shared.t("up_next", lang)
            case .history: return lang == .fr ? "Historique" : "History"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.down")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(8)
                }
                
                Spacer()
                
                Picker("", selection: $viewMode) {
                    ForEach(PlayerViewMode.allCases) { mode in
                        Text(mode.label(lang: storage.currentLanguage)).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 260)
                .onChange(of: viewMode) { _ in
                    HapticManager.shared.trigger(.light)
                }
                
                Spacer()
                
                // Sleep Timer Button
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    showingSleepTimerDialog = true
                }) {
                    Image(systemName: audioPlayer.sleepTimerTimeLeft != nil ? "hourglass.badge.plus" : "hourglass")
                        .font(.title3)
                        .foregroundColor(audioPlayer.sleepTimerTimeLeft != nil ? storage.accentColorColor() : .secondary)
                        .padding(8)
                }
            }
            .padding()
            
            switch viewMode {
            case .player:
                PlayerTabContent()
            case .queue:
                QueueTabContent()
            case .history:
                HistoryTabContent()
            }
        }
        .background(
            ZStack {
                storage.mainBackgroundColor
                if let urlString = audioPlayer.currentArtworkUrl, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url, maxPixelSize: 300) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 60)
                            .opacity(storage.isLightTheme ? 0.08 : 0.15)
                    } placeholder: {
                        Color.clear
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
        )
        .preferredColorScheme(storage.isLightTheme ? .light : .dark)
        .confirmationDialog(
            storage.currentLanguage == .fr ? "Minuterie de mise en veille" : "Sleep Timer",
            isPresented: $showingSleepTimerDialog,
            titleVisibility: .visible
        ) {
            Button("15 minutes") {
                HapticManager.shared.trigger(.light)
                audioPlayer.startSleepTimer(minutes: 15)
            }
            Button("30 minutes") {
                HapticManager.shared.trigger(.light)
                audioPlayer.startSleepTimer(minutes: 30)
            }
            Button("45 minutes") {
                HapticManager.shared.trigger(.light)
                audioPlayer.startSleepTimer(minutes: 45)
            }
            Button("60 minutes") {
                HapticManager.shared.trigger(.light)
                audioPlayer.startSleepTimer(minutes: 60)
            }
            if audioPlayer.sleepTimerTimeLeft != nil {
                Button(storage.currentLanguage == .fr ? "Désactiver la minuterie" : "Disable Timer", role: .destructive) {
                    HapticManager.shared.trigger(.medium)
                    audioPlayer.stopSleepTimer()
                }
            }
            Button(storage.currentLanguage == .fr ? "Annuler" : "Cancel", role: .cancel) {}
        }
    }
}

struct PlayerProgressScrubberView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var progress = AudioPlayerManager.shared.progress
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            Slider(value: Binding(
                get: { progress.currentTime },
                set: { value in
                    audioPlayer.seek(to: value)
                }
            ), in: 0...max(progress.duration, 1))
            .tint(storage.accentColorColor())
            
            HStack {
                Text(formatTime(progress.currentTime))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(progress.duration))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PlayerTabContent: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    @ObservedObject var chromecast = ChromecastManager.shared
    
    @State private var showingChromecastSheet = false
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Artwork Cover
            if audioPlayer.playbackType == "radio", let radio = audioPlayer.currentRadio {
                RadioStationArtworkView(station: radio, size: 240, cornerRadius: 28)
                    .shadow(color: Color.black.opacity(storage.isLightTheme ? 0.15 : 0.4), radius: 15, x: 0, y: 10)
                    .padding(.horizontal, 40)
            } else {
                CachedAsyncImage(url: URL(string: audioPlayer.currentArtworkUrl ?? ""), maxPixelSize: 600) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    ZStack {
                        storage.subtleSurfaceColor
                        Image(systemName: "music.note")
                            .font(.system(size: 80))
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                }
                .frame(maxWidth: 300, maxHeight: 300)
                .cornerRadius(28)
                .shadow(color: Color.black.opacity(storage.isLightTheme ? 0.15 : 0.4), radius: 15, x: 0, y: 10)
                .padding(.horizontal, 40)
            }
            
            // Active Chromecast Banner if casting
            if let device = chromecast.connectedDevice {
                HStack(spacing: 6) {
                    Image(systemName: "tv.badge.wifi")
                        .font(.system(size: 12, weight: .bold))
                    Text(storage.currentLanguage == .fr ? "Diffusé sur \(device.name)" : "Casting to \(device.name)")
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(storage.accentColorColor()))
            }
            
            Spacer()
            
            // Track Info
            VStack(spacing: 6) {
                let title = audioPlayer.currentTrackName ?? (storage.currentLanguage == .fr ? "Aucune lecture" : "Not Playing")
                let subtitle = audioPlayer.currentSubtitle ?? ""
                let isDuplicate = !subtitle.isEmpty && (
                    title.localizedCaseInsensitiveContains(subtitle) ||
                    subtitle.localizedCaseInsensitiveContains(title)
                )
                
                Text(title)
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(storage.primaryTextColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                
                if !isDuplicate && !subtitle.isEmpty {
                    Text(subtitle.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(storage.accentColorColor())
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                }
            }
            
            // Scrubber Slider (Only for Podcasts)
            Group {
                if audioPlayer.playbackType == "podcast" {
                    PlayerProgressScrubberView()
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.caption)
                            .fontWeight(.black)
                            .foregroundColor(.red)
                            .tracking(1.5)
                    }
                    .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 32)
            
            // Playback controls
            HStack(spacing: 28) {
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    audioPlayer.skip(seconds: -15)
                }) {
                    Image(systemName: "gobackward.15")
                        .font(.title)
                        .foregroundColor(storage.primaryTextColor)
                }
                .disabled(audioPlayer.playbackType == "radio")
                .opacity(audioPlayer.playbackType == "radio" ? 0.3 : 1.0)
                
                Button(action: {
                    HapticManager.shared.trigger(.medium)
                    audioPlayer.togglePlayPause()
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                        .foregroundColor(storage.accentColorColor())
                        .background(Circle().fill(storage.isLightTheme ? Color.white : Color.white).padding(4))
                }
                
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    audioPlayer.skip(seconds: 30)
                }) {
                    Image(systemName: "goforward.30")
                        .font(.title)
                        .foregroundColor(storage.primaryTextColor)
                }
                .disabled(audioPlayer.playbackType == "radio")
                .opacity(audioPlayer.playbackType == "radio" ? 0.3 : 1.0)
            }
            .padding(.vertical, 6)
            
            // Extra info row (Speed rate / Chromecast + AirPlay / Sleep Timer)
            HStack {
                if audioPlayer.playbackType == "podcast" {
                    Button(action: {
                        cycleSpeed()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "speedometer")
                            Text("\(String(format: "%.1f", storage.settings.playbackSpeed))x")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(storage.primaryTextColor)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(storage.subtleSurfaceColor)
                        .cornerRadius(10)
                    }
                } else {
                    Color.clear.frame(width: 64, height: 32)
                }
                
                Spacer()
                
                // Chromecast & AirPlay Cast Controls
                HStack(spacing: 14) {
                    // Real Chromecast Button
                    Button(action: {
                        HapticManager.shared.trigger(.light)
                        showingChromecastSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: chromecast.connectedDevice != nil ? "tv.fill" : "tv.badge.wifi")
                                .font(.system(size: 14, weight: .bold))
                            Text("Chromecast")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(chromecast.connectedDevice != nil ? .white : storage.accentColorColor())
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(chromecast.connectedDevice != nil ? storage.accentColorColor() : storage.subtleSurfaceColor)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(storage.accentColorColor().opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // AirPlay Button
                    AirPlayButton(tintColor: UIColor(storage.accentColorColor()))
                        .frame(width: 34, height: 34)
                        .background(storage.subtleSurfaceColor)
                        .cornerRadius(10)
                }
                
                Spacer()
                
                if let timeLeft = audioPlayer.sleepTimerTimeLeft {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                        Text(formatSleepTime(timeLeft))
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(storage.accentColorColor())
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(storage.accentColorColor().opacity(0.12))
                    .cornerRadius(10)
                } else {
                    Color.clear
                        .frame(width: 64, height: 32)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .sheet(isPresented: $showingChromecastSheet) {
            ChromecastPickerSheet()
                .presentationDetents([.medium, .large])
        }
    }
    
    private func cycleSpeed() {
        HapticManager.shared.trigger(.light)
        let speedsList = [0.5, 0.8, 1.0, 1.2, 1.5, 1.8, 2.0, 2.5]
        if let idx = speedsList.firstIndex(of: storage.settings.playbackSpeed) {
            let nextIdx = (idx + 1) % speedsList.count
            storage.settings.playbackSpeed = speedsList[nextIdx]
        } else {
            storage.settings.playbackSpeed = 1.0
        }
    }
    
    private func formatSleepTime(_ time: TimeInterval) -> String {
        let min = Int(time) / 60
        let sec = Int(time) % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

struct ChromecastPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var chromecast = ChromecastManager.shared
    @ObservedObject var storage = LocalStorageManager.shared
    @State private var manualIP: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Connected Device Status
                if let active = chromecast.connectedDevice {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "tv.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(storage.accentColorColor())
                                .cornerRadius(12)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(active.name)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(storage.primaryTextColor)
                                Text(storage.currentLanguage == .fr ? "Connecté • Diffusion active" : "Connected • Casting audio")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            Spacer()
                            
                            Button(role: .destructive, action: {
                                HapticManager.shared.trigger(.medium)
                                chromecast.disconnect()
                            }) {
                                Text(storage.currentLanguage == .fr ? "Déconnecter" : "Disconnect")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.12))
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    .background(storage.cardBackgroundColor)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(storage.accentColorColor(), lineWidth: 1))
                    .padding(.horizontal)
                }
                
                // Discovered Chromecast Devices on Wi-Fi
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(
                            storage.currentLanguage == .fr ? "Appareils Chromecast sur le Wi-Fi" : "Chromecast Devices on Wi-Fi",
                            systemImage: "wifi"
                        )
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if chromecast.isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        
                        Button(action: {
                            chromecast.startDiscovery()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(storage.accentColorColor())
                        }
                    }
                    .padding(.horizontal)
                    
                    if chromecast.discoveredDevices.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tv.badge.wifi")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text(
                                storage.currentLanguage == .fr
                                ? "Recherche d'appareils Google Cast / Chromecast sur votre réseau local..."
                                : "Scanning for Google Cast / Chromecast devices on your local network..."
                            )
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(storage.cardBackgroundColor)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(storage.cardBorderColor, lineWidth: 1))
                        .padding(.horizontal)
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(chromecast.discoveredDevices) { device in
                                    Button(action: {
                                        HapticManager.shared.trigger(.medium)
                                        chromecast.connect(to: device)
                                    }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "tv.badge.wifi")
                                                .font(.title3)
                                                .foregroundColor(storage.accentColorColor())
                                                .frame(width: 38, height: 38)
                                                .background(storage.subtleSurfaceColor)
                                                .cornerRadius(10)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(device.name)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(storage.primaryTextColor)
                                                Text(device.model)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            Spacer()
                                            
                                            if chromecast.connectedDevice?.id == device.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                            } else {
                                                Text(storage.currentLanguage == .fr ? "Connecter" : "Connect")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(storage.accentColorColor())
                                            }
                                        }
                                        .padding(12)
                                        .background(storage.cardBackgroundColor)
                                        .cornerRadius(14)
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(storage.cardBorderColor, lineWidth: 1))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                // Manual IP Fallback for Chromecast
                VStack(alignment: .leading, spacing: 8) {
                    Text(storage.currentLanguage == .fr ? "Connexion directe par IP (Chromecast :8009)" : "Direct IP Connection (Chromecast :8009)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 10) {
                        TextField("Ex: 192.168.1.45", text: $manualIP)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(storage.subtleSurfaceColor)
                            .cornerRadius(10)
                            .foregroundColor(storage.primaryTextColor)
                        
                        Button(action: {
                            HapticManager.shared.trigger(.medium)
                            chromecast.connectToIP(manualIP)
                        }) {
                            Text(storage.currentLanguage == .fr ? "Caster" : "Cast")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(storage.accentColorColor())
                                .cornerRadius(10)
                        }
                        .disabled(manualIP.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    
                    if let msg = chromecast.statusMessage {
                        Text(msg)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(storage.accentColorColor())
                    }
                }
                .padding()
                .background(storage.cardBackgroundColor)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(storage.cardBorderColor, lineWidth: 1))
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top, 12)
            .background(storage.mainBackgroundColor.ignoresSafeArea())
            .navigationTitle("Chromecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(storage.currentLanguage == .fr ? "Fermer" : "Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                chromecast.startDiscovery()
            }
            .onDisappear {
                chromecast.stopDiscovery()
            }
        }
    }
}

struct QueueTabContent: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Current Track Header in Queue
            HStack(spacing: 12) {
                CachedAsyncImage(url: URL(string: audioPlayer.currentArtworkUrl ?? ""), maxPixelSize: 160) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    storage.subtleSurfaceColor
                }
                .frame(width: 48, height: 48)
                .cornerRadius(10)
                .clipped()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(storage.currentLanguage == .fr ? "En Lecture" : "Now Playing")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(storage.accentColorColor())
                        .textCase(.uppercase)
                    
                    Text(audioPlayer.currentTrackName ?? "Unknown")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(storage.primaryTextColor)
                        .lineLimit(1)
                }
                Spacer()
                
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(storage.accentColorColor())
            }
            .padding()
            .background(storage.cardBackgroundColor)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(storage.cardBorderColor, lineWidth: 1))
            .padding()
            
            // Queue List
            HStack {
                Text("\(Translations.shared.t("up_next", storage.currentLanguage)) (\(audioPlayer.queue.count))")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                Spacer()
            }
            .padding(.bottom, 6)
            
            if audioPlayer.queue.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(storage.currentLanguage == .fr ? "File d'attente vide" : "Queue is empty")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(Array(audioPlayer.queue.enumerated()), id: \.offset) { index, episode in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                                .frame(width: 18)
                            
                            CachedAsyncImage(url: URL(string: episode.artworkUrl60 ?? ""), maxPixelSize: 120) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                storage.subtleSurfaceColor
                            }
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                            .clipped()
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(episode.trackName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(storage.primaryTextColor)
                                    .lineLimit(1)
                                
                                Text(episode.collectionName ?? "")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 10) {
                                if index > 0 {
                                    Button(action: {
                                        HapticManager.shared.trigger(.light)
                                        audioPlayer.moveQueueItem(fromIndex: index, direction: -1)
                                    }) {
                                        Image(systemName: "chevron.up")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                
                                if index < audioPlayer.queue.count - 1 {
                                    Button(action: {
                                        HapticManager.shared.trigger(.light)
                                        audioPlayer.moveQueueItem(fromIndex: index, direction: 1)
                                    }) {
                                        Image(systemName: "chevron.down")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                
                                Button(action: {
                                    HapticManager.shared.trigger(.medium)
                                    audioPlayer.removeFromQueue(at: index)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red.opacity(0.8))
                                        .font(.caption)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(storage.cardBorderColor)
                    }
                }
                .listStyle(PlainListStyle())
                .background(Color.clear)
            }
        }
    }
}

struct HistoryTabContent: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(storage.currentLanguage == .fr ? "Historique d'écoute" : "Listening History")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                Spacer()
                
                if !storage.history.isEmpty {
                    Button(action: {
                        HapticManager.shared.trigger(.medium)
                        storage.history.removeAll()
                    }) {
                        Text(storage.currentLanguage == .fr ? "Effacer" : "Clear")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 6)
            
            if storage.history.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(storage.currentLanguage == .fr ? "Historique vide" : "History is empty")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(storage.history) { episode in
                        HStack(spacing: 12) {
                            CachedAsyncImage(url: URL(string: episode.artworkUrl60 ?? ""), maxPixelSize: 120) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                storage.subtleSurfaceColor
                            }
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                            .clipped()
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(episode.trackName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(storage.primaryTextColor)
                                    .lineLimit(1)
                                
                                Text(episode.collectionName ?? "")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                HapticManager.shared.trigger(.light)
                                audioPlayer.playEpisode(episode)
                            }) {
                                Image(systemName: "play.fill")
                                    .foregroundColor(storage.accentColorColor())
                                    .font(.caption)
                                    .padding(8)
                                    .background(storage.subtleSurfaceColor)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(storage.cardBorderColor)
                    }
                }
                .listStyle(PlainListStyle())
                .background(Color.clear)
            }
        }
    }
}

// MARK: – AirPlay button
struct AirPlayButton: UIViewRepresentable {
    var tintColor: UIColor = .white
    
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = tintColor
        picker.activeTintColor = tintColor
        picker.backgroundColor = .clear
        return picker
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
        uiView.activeTintColor = tintColor
    }
}
