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
                .onChange(of: viewMode) { _, _ in
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
    
    @State private var showingUnifiedCastSheet = false
    @State private var showingItemInfoSheet = false
    @State private var selectedPodcastForNavigation: Podcast? = nil
    
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            
            // Artwork Cover with top-right (i) Info Badge
            ZStack(alignment: .topTrailing) {
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
                    .frame(maxWidth: 280, maxHeight: 280)
                    .cornerRadius(28)
                    .shadow(color: Color.black.opacity(storage.isLightTheme ? 0.15 : 0.4), radius: 15, x: 0, y: 10)
                    .padding(.horizontal, 40)
                }
            }
            
            // Active Chromecast or Sleep Timer status pill
            HStack(spacing: 8) {
                if let device = chromecast.connectedDevice {
                    HStack(spacing: 6) {
                        Image(systemName: "tv.badge.wifi")
                            .font(.system(size: 11, weight: .bold))
                        Text(storage.currentLanguage == .fr ? "Diffusé sur \(device.name)" : "Casting to \(device.name)")
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(storage.accentColorColor()))
                }
                
                if let timeLeft = audioPlayer.sleepTimerTimeLeft {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                        Text(formatSleepTime(timeLeft))
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(storage.accentColorColor())
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(storage.accentColorColor().opacity(0.14)))
                }
            }
            
            Spacer()
            
            // Track Info + Clickable Podcast/Book Name + (i) Information Button
            VStack(spacing: 8) {
                let title = audioPlayer.currentTrackName ?? (storage.currentLanguage == .fr ? "Aucune lecture" : "Not Playing")
                let subtitle = resolvedClickableTitle()
                let hasPlayingItem = audioPlayer.currentEpisode != nil || audioPlayer.currentRadio != nil
                
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.system(size: 19, weight: .black))
                        .foregroundColor(storage.primaryTextColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    if hasPlayingItem {
                        Button(action: {
                            HapticManager.shared.trigger(.light)
                            showingItemInfoSheet = true
                        }) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(storage.accentColorColor())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(storage.currentLanguage == .fr ? "Informations sur la lecture" : "Now Playing Info")
                    }
                }
                .padding(.horizontal, 24)
                
                if !subtitle.isEmpty {
                    if audioPlayer.playbackType == "podcast", let podcast = resolveCurrentPodcast() {
                        Button(action: {
                            HapticManager.shared.trigger(.light)
                            selectedPodcastForNavigation = podcast
                        }) {
                            HStack(spacing: 5) {
                                Text(subtitle.uppercased())
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(storage.accentColorColor())
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(storage.accentColorColor())
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(storage.accentColorColor().opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 24)
                    } else {
                        Text(subtitle.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(storage.accentColorColor())
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .padding(.horizontal, 24)
                    }
                }
            }
            
            // Scrubber Slider (Only for Podcasts / Books)
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
            
            // Playback controls (Previous, -15s, Play/Pause, +30s, Next)
            HStack(spacing: 22) {
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    audioPlayer.playPreviousTrack()
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(storage.primaryTextColor)
                        .frame(width: 40, height: 40)
                        .background(storage.subtleSurfaceColor)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(storage.currentLanguage == .fr ? "Précédent" : "Previous")
                
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    audioPlayer.skip(seconds: -15)
                }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(storage.primaryTextColor)
                }
                .disabled(audioPlayer.playbackType == "radio")
                .opacity(audioPlayer.playbackType == "radio" ? 0.3 : 1.0)
                
                Button(action: {
                    HapticManager.shared.trigger(.medium)
                    audioPlayer.togglePlayPause()
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 70))
                        .foregroundColor(storage.accentColorColor())
                        .background(Circle().fill(storage.isLightTheme ? Color.white : Color.white).padding(4))
                }
                
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    audioPlayer.skip(seconds: 30)
                }) {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(storage.primaryTextColor)
                }
                .disabled(audioPlayer.playbackType == "radio")
                .opacity(audioPlayer.playbackType == "radio" ? 0.3 : 1.0)
                
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    audioPlayer.playNextTrack()
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(storage.primaryTextColor)
                        .frame(width: 40, height: 40)
                        .background(storage.subtleSurfaceColor)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(storage.currentLanguage == .fr ? "Suivant" : "Next")
            }
            .padding(.vertical, 6)
            
            // Centered & Evenly Distributed Bottom Action Row (Vitesse, Diffuser [AirPlay + Chromecast], Info (i))
            HStack(spacing: 16) {
                Spacer()
                
                // 1. Speed Rate Button
                Button(action: {
                    cycleSpeed()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 13, weight: .bold))
                        Text("\(String(format: "%.1f", storage.settings.playbackSpeed))x")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(storage.primaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(storage.subtleSurfaceColor)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(storage.cardBorderColor, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(audioPlayer.playbackType == "radio")
                .opacity(audioPlayer.playbackType == "radio" ? 0.45 : 1.0)
                
                // 2. Unified Cast Button (Apple AirPlay + Google Chromecast merged)
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    showingUnifiedCastSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: chromecast.connectedDevice != nil ? "tv.fill" : "airplayaudio")
                            .font(.system(size: 13, weight: .bold))
                        Text(
                            chromecast.connectedDevice != nil
                            ? (chromecast.connectedDevice?.name ?? "Cast")
                            : (storage.currentLanguage == .fr ? "Diffuser" : "Cast")
                        )
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    }
                    .foregroundColor(chromecast.connectedDevice != nil ? .white : storage.accentColorColor())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(chromecast.connectedDevice != nil ? storage.accentColorColor() : storage.subtleSurfaceColor)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(storage.accentColorColor().opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .sheet(isPresented: $showingUnifiedCastSheet) {
            ChromecastPickerSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingItemInfoSheet) {
            PlayingItemInfoSheet(
                onOpenPodcast: { podcast in
                    showingItemInfoSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selectedPodcastForNavigation = podcast
                    }
                }
            )
            .environmentObject(audioPlayer)
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedPodcastForNavigation) { podcast in
            NavigationStack {
                EpisodeListView(podcast: podcast)
                    .environmentObject(audioPlayer)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(storage.currentLanguage == .fr ? "Fermer" : "Close") {
                                selectedPodcastForNavigation = nil
                            }
                        }
                    }
            }
            .preferredColorScheme(storage.isLightTheme ? .light : .dark)
        }
    }
    
    private func resolvedClickableTitle() -> String {
        if audioPlayer.playbackType == "podcast" {
            if let colName = audioPlayer.currentEpisode?.collectionName, !colName.isEmpty {
                return colName
            }
            if let artist = audioPlayer.currentEpisode?.artistName, !artist.isEmpty {
                return artist
            }
        }
        return audioPlayer.currentSubtitle ?? ""
    }
    
    func resolveCurrentPodcast() -> Podcast? {
        guard let ep = audioPlayer.currentEpisode else { return nil }
        let colId = ep.collectionId ?? 0
        
        if colId != 0 {
            if let fav = storage.favoritePodcasts.first(where: { $0.collectionId == colId }) {
                return fav
            }
            if let book = storage.favoriteAudiobooks.first(where: { $0.collectionId == colId }) {
                return book
            }
            for (_, list) in storage.cachedSubscriptionsBySection {
                if let match = list.first(where: { $0.collectionId == colId }) {
                    return match
                }
            }
            if let trend = storage.cachedTrendingPodcasts.first(where: { $0.collectionId == colId }) {
                return trend
            }
        }
        
        let name = ep.collectionName ?? ep.artistName ?? ""
        guard !name.isEmpty else { return nil }
        return Podcast(
            collectionId: colId != 0 ? colId : ep.trackId,
            artistName: ep.artistName ?? name,
            collectionName: name,
            artworkUrl100: ep.artworkUrl160 ?? ep.artworkUrl60,
            artworkUrl600: ep.artworkUrl600 ?? ep.artworkUrl160,
            feedUrl: nil,
            genres: nil,
            primaryGenreName: nil,
            releaseDate: ep.releaseDate,
            country: nil,
            description: ep.description,
            source: nil
        )
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

// MARK: - Rich Information Sheet (i) for Currently Playing Item
struct PlayingItemInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var progress = AudioPlayerManager.shared.progress
    @ObservedObject var storage = LocalStorageManager.shared
    
    var onOpenPodcast: ((Podcast) -> Void)? = nil
    
    private var resolvedPodcast: Podcast? {
        guard let ep = audioPlayer.currentEpisode else { return nil }
        let colId = ep.collectionId ?? 0
        if colId != 0 {
            if let fav = storage.favoritePodcasts.first(where: { $0.collectionId == colId }) { return fav }
            if let book = storage.favoriteAudiobooks.first(where: { $0.collectionId == colId }) { return book }
            for (_, list) in storage.cachedSubscriptionsBySection {
                if let match = list.first(where: { $0.collectionId == colId }) { return match }
            }
            if let trend = storage.cachedTrendingPodcasts.first(where: { $0.collectionId == colId }) { return trend }
        }
        let name = ep.collectionName ?? ep.artistName ?? ""
        guard !name.isEmpty else { return nil }
        return Podcast(
            collectionId: colId != 0 ? colId : ep.trackId,
            artistName: ep.artistName ?? name,
            collectionName: name,
            artworkUrl100: ep.artworkUrl160 ?? ep.artworkUrl60,
            artworkUrl600: ep.artworkUrl600 ?? ep.artworkUrl160,
            feedUrl: nil,
            genres: nil,
            primaryGenreName: nil,
            releaseDate: ep.releaseDate,
            country: nil,
            description: ep.description,
            source: nil
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCardView
                    metadataCardView
                    descriptionCardView
                    openPodcastButtonView
                }
                .padding()
            }
            .background(storage.mainBackgroundColor.ignoresSafeArea())
            .navigationTitle(storage.currentLanguage == .fr ? "Informations" : "Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(storage.currentLanguage == .fr ? "Fermer" : "Close") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(storage.isLightTheme ? .light : .dark)
    }
    
    @ViewBuilder
    private var headerCardView: some View {
        let trackTitle = audioPlayer.currentTrackName ?? (storage.currentLanguage == .fr ? "Aucune lecture" : "Not Playing")
        let artistText = audioPlayer.currentEpisode?.artistName ?? resolvedPodcast?.artistName ?? ""
        
        HStack(alignment: .top, spacing: 14) {
            if audioPlayer.playbackType == "radio", let radio = audioPlayer.currentRadio {
                RadioStationArtworkView(station: radio, size: 84, cornerRadius: 18)
            } else {
                CachedAsyncImage(url: URL(string: audioPlayer.currentArtworkUrl ?? ""), maxPixelSize: 300) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    storage.subtleSurfaceColor
                }
                .frame(width: 84, height: 84)
                .cornerRadius(18)
                .clipped()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(trackTitle)
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(storage.primaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let podcast = resolvedPodcast {
                    Button(action: {
                        HapticManager.shared.trigger(.light)
                        onOpenPodcast?(podcast)
                    }) {
                        HStack(spacing: 4) {
                            Text(podcast.collectionName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(storage.accentColorColor())
                                .multilineTextAlignment(.leading)
                            Image(systemName: "arrow.up.right.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(storage.accentColorColor())
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                } else if let subtitle = audioPlayer.currentSubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(storage.accentColorColor())
                }
                
                if !artistText.isEmpty {
                    Text(artistText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(storage.cardBackgroundColor)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
    }
    
    @ViewBuilder
    private var metadataCardView: some View {
        let isFr = storage.currentLanguage == .fr
        VStack(alignment: .leading, spacing: 10) {
            Text(isFr ? "DÉTAILS RÉCUPÉRÉS" : "RETRIEVED METADATA")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(.secondary)
                .tracking(1)
            
            if let ep = audioPlayer.currentEpisode {
                episodeMetadataRows(ep: ep, isFr: isFr)
            } else if let radio = audioPlayer.currentRadio {
                radioMetadataRows(radio: radio, isFr: isFr)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(storage.cardBackgroundColor)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
    }
    
    @ViewBuilder
    private func episodeMetadataRows(ep: Episode, isFr: Bool) -> some View {
        let podcast = resolvedPodcast
        let durSec = progress.duration > 0 ? progress.duration : Double(ep.trackTimeMillis ?? 0) / 1000.0
        let genreText = podcast?.primaryGenreName ?? podcast?.genres?.first ?? ""
        let allGenresText = (podcast?.genres?.count ?? 0) > 1 ? (podcast?.genres?.joined(separator: " • ") ?? "") : ""
        let sourceText = podcast?.source ?? ""
        let feedText = podcast?.feedUrl ?? ""
        let previewText = ep.previewUrl ?? ""
        
        if let dateStr = ep.releaseDate, let date = DateFormatterUtility.parse(dateStr) {
            infoRow(
                icon: "calendar",
                label: isFr ? "Date de publication" : "Release Date",
                value: DateFormatterUtility.formatOutput(date, lang: storage.currentLanguage.rawValue)
            )
        }
        if durSec > 0 {
            infoRow(
                icon: "clock.fill",
                label: isFr ? "Durée & Progression" : "Duration & Progress",
                value: "\(formatDurationSeconds(progress.currentTime)) / \(formatDurationSeconds(durSec))"
            )
        }
        if !genreText.isEmpty {
            infoRow(
                icon: "tag.fill",
                label: isFr ? "Catégorie" : "Category",
                value: genreText
            )
        }
        if !allGenresText.isEmpty {
            infoRow(
                icon: "sparkles",
                label: isFr ? "Thématiques" : "Topics",
                value: allGenresText
            )
        }
        if !sourceText.isEmpty {
            infoRow(
                icon: "building.columns.fill",
                label: "Source",
                value: sourceText.uppercased()
            )
        }
        if !feedText.isEmpty {
            infoRow(
                icon: "dot.radiowaves.up.forward",
                label: "Flux RSS",
                value: feedText
            )
        }
        if !previewText.isEmpty {
            infoRow(
                icon: "waveform",
                label: isFr ? "Flux Audio" : "Audio Stream",
                value: previewText
            )
        }
    }
    
    @ViewBuilder
    private func radioMetadataRows(radio: RadioStation, isFr: Bool) -> some View {
        if let country = radio.country, !country.isEmpty {
            infoRow(
                icon: "globe",
                label: isFr ? "Pays" : "Country",
                value: country
            )
        }
        if let tags = radio.tags, !tags.isEmpty {
            infoRow(
                icon: "tag.fill",
                label: isFr ? "Style / Tags" : "Tags",
                value: tags
            )
        }
        if !radio.url.isEmpty {
            infoRow(
                icon: "dot.radiowaves.left.and.right",
                label: isFr ? "Flux Direct" : "Live Stream",
                value: radio.url
            )
        }
    }
    
    @ViewBuilder
    private var descriptionCardView: some View {
        let rawDesc = audioPlayer.currentEpisode?.description ?? resolvedPodcast?.description ?? ""
        let cleanDesc = cleanHTMLText(rawDesc)
        if !cleanDesc.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(storage.currentLanguage == .fr ? "DESCRIPTION & NOTES DE L'ÉPISODE" : "DESCRIPTION & SHOW NOTES")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                Text(cleanDesc)
                    .font(.system(size: 14))
                    .foregroundColor(storage.primaryTextColor)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(storage.cardBackgroundColor)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
        }
    }
    
    @ViewBuilder
    private var openPodcastButtonView: some View {
        if let podcast = resolvedPodcast {
            Button(action: {
                HapticManager.shared.trigger(.light)
                onOpenPodcast?(podcast)
            }) {
                HStack {
                    Image(systemName: "list.bullet.rectangle.fill")
                    Text(storage.currentLanguage == .fr ? "Voir tous les épisodes de « \(podcast.collectionName) »" : "View all episodes of '\(podcast.collectionName)'")
                        .lineLimit(1)
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(storage.accentColorColor())
                .cornerRadius(14)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    @ViewBuilder
    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(storage.accentColorColor())
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(storage.primaryTextColor)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
    
    private func formatDurationSeconds(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%dh %02dm %02ds", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
    
    private func cleanHTMLText(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        var s = raw
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<li>", with: "• ", options: .caseInsensitive)
            .replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [String: String] = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#8217;": "’",
            "&#8216;": "‘", "&#8220;": "“", "&#8221;": "”", "&#8211;": "–",
            "&#8212;": "—", "&#8230;": "…"
        ]
        for (k, v) in entities {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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
                // 1. Apple AirPlay Section (Unified with Chromecast)
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(storage.accentColorColor().opacity(0.15))
                            .frame(width: 44, height: 44)
                        AirPlayButton(tintColor: UIColor(storage.accentColorColor()))
                            .frame(width: 36, height: 36)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple AirPlay & Bluetooth")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(storage.primaryTextColor)
                        Text(storage.currentLanguage == .fr ? "Touchez l'icône AirPlay à gauche pour choisir HomePod, Apple TV ou AirPods" : "Tap the AirPlay icon on the left for HomePod, Apple TV, or AirPods")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(14)
                .background(storage.cardBackgroundColor)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(storage.cardBorderColor, lineWidth: 1))
                .padding(.horizontal)
                
                // 2. Connected Chromecast Device Status
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
            .navigationTitle(storage.currentLanguage == .fr ? "Diffuser (AirPlay & Cast)" : "Cast (AirPlay & Cast)")
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
