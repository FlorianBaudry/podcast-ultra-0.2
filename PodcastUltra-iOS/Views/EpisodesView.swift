import SwiftUI
import WidgetKit

struct EpisodesView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    @State private var episodes: [Episode] = LocalStorageManager.shared.cachedEpisodes
    @State private var isLoading = LocalStorageManager.shared.cachedEpisodes.isEmpty
    @State private var isRefreshing = false
    @State private var activeFilter: EpisodeFilter = .all
    @StateObject private var weatherService = WeatherService.shared
    @State private var selectedPodcast: Podcast? = nil
    @State private var navigateToPodcast = false
    @State private var isDownloadingAll = false
    
    enum EpisodeFilter: String, CaseIterable, Identifiable {
        case all, unplayed
        var id: String { rawValue }
        
        func label(lang: LangCode) -> String {
            switch self {
            case .all: return Translations.shared.t("filter_all", lang)
            case .unplayed: return Translations.shared.t("filter_unplayed", lang)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            HStack(spacing: 8) {
                // Refresh button
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    fetchEpisodes(force: true)
                }) {
                    ZStack {
                        if isRefreshing && !isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: storage.accentColorColor()))
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(storage.accentColorColor())
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(storage.subtleSurfaceColor)
                    .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRefreshing)
                
                // Auto-download button
                Button(action: {
                    HapticManager.shared.trigger(.medium)
                    toggleAutoDownload()
                }) {
                    HStack(spacing: 6) {
                        if isDownloadingAll {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: storage.settings.autoDownloadLatest ? .white : storage.accentColorColor()))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: storage.settings.autoDownloadLatest ? "arrow.down.circle.fill" : "arrow.down.circle")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(storage.currentLanguage == .fr ? "Charger" : "Download")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(storage.settings.autoDownloadLatest ? storage.accentColorColor() : storage.subtleSurfaceColor)
                    .cornerRadius(18)
                    .foregroundColor(storage.settings.autoDownloadLatest ? .white : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isDownloadingAll)
                
                Spacer()
                
                Picker("", selection: $activeFilter) {
                    ForEach(EpisodeFilter.allCases) { filter in
                        Text(filter.label(lang: storage.currentLanguage)).tag(filter)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 130)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            if isLoading {
                Spacer()
                VStack(spacing: 24) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: storage.accentColorColor()))
                    
                    VStack(spacing: 8) {
                        Text(storage.currentLanguage == .fr ? "Synchronisation" : "Syncing")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(storage.primaryTextColor)
                        
                        Text(storage.currentLanguage == .fr ? "Nous récupérons les derniers épisodes de vos podcasts favoris..." : "We are fetching the latest episodes of your favorite podcasts...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 240)
                            .lineSpacing(3)
                    }
                    .padding(.bottom, 8)
                    
                    if let temp = weatherService.temperature {
                        HStack(spacing: 16) {
                            ZStack {
                                storage.subtleSurfaceColor
                                Image(systemName: weatherService.weatherIcon)
                                    .font(.system(size: 22))
                                    .foregroundColor(storage.accentColorColor())
                            }
                            .frame(width: 48, height: 48)
                            .cornerRadius(16)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(weatherService.cityName)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(storage.primaryTextColor)
                                
                                Text(weatherService.weatherDescription)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("\(Int(round(temp)))°C")
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(storage.primaryTextColor)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(storage.cardBackgroundColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(storage.cardBorderColor, lineWidth: 1)
                                )
                        )
                        .frame(maxWidth: 300)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)
                    }
                }
                .padding(.horizontal)
                Spacer()
            } else if filteredEpisodes().isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text(storage.currentLanguage == .fr ? "Aucun épisode disponible" : "No episodes available")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List(filteredEpisodes()) { episode in
                    EpisodeRowView(episode: episode)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(storage.cardBorderColor)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticManager.shared.trigger(.light)
                            audioPlayer.playEpisode(episode)
                        }
                        .onLongPressGesture {
                            let podcast = Podcast(
                                collectionId: episode.collectionId ?? 0,
                                artistName: episode.artistName ?? "",
                                collectionName: episode.collectionName ?? "",
                                artworkUrl100: episode.artworkUrl160,
                                artworkUrl600: episode.artworkUrl600,
                                feedUrl: nil,
                                genres: nil,
                                primaryGenreName: nil,
                                releaseDate: nil,
                                country: nil,
                                description: nil,
                                source: nil
                            )
                            selectedPodcast = podcast
                            navigateToPodcast = true
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                audioPlayer.addToQueue(episode)
                            } label: {
                                Label(Translations.shared.t("add_to_queue", storage.currentLanguage), systemImage: "plus.circle.fill")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    storage.dismissEpisode(episode.trackId)
                                }
                            } label: {
                                Label(Translations.shared.t("hide", storage.currentLanguage), systemImage: "eye.slash.fill")
                            }
                        }
                }
                .listStyle(PlainListStyle())
                .background(Color.clear)
            }
        }
        .ipadMaxWidth()
        .padding(.bottom, 80)
        .onAppear {
            self.episodes = LocalStorageManager.sanitizeEpisodesDates(storage.cachedEpisodes)
            storage.syncWidgetLatestEpisodes(from: filteredEpisodes())
            fetchEpisodes(force: true)
            weatherService.requestLocation()
        }
        .onChange(of: storage.appOpenRefreshTrigger) { _ in
            fetchEpisodes(force: true)
        }
        .onChange(of: storage.favoritePodcasts.count) { _ in
            fetchEpisodes(force: true)
        }
        .onChange(of: storage.cachedEpisodes.count) { _ in
            self.episodes = storage.cachedEpisodes
            storage.syncWidgetLatestEpisodes(from: filteredEpisodes())
        }
        .onChange(of: activeFilter) { _ in
            storage.syncWidgetLatestEpisodes(from: filteredEpisodes())
        }
        .navigationDestination(isPresented: $navigateToPodcast) {
            if let podcast = selectedPodcast {
                EpisodeListView(podcast: podcast)
            }
        }
    }
    
    private func fetchEpisodes(force: Bool = false) {
        let favPodcasts = storage.favoritePodcasts.filter { !LocalStorageManager.isAudiobookItem($0) }
        guard !favPodcasts.isEmpty else {
            self.episodes = []
            self.isLoading = false
            self.isRefreshing = false
            storage.syncWidgetLatestEpisodes(from: [])
            return
        }
        
        if !force && !episodes.isEmpty && !storage.shouldRefresh(lastFetch: storage.lastEpisodesFetchDate) {
            return
        }
        
        isLoading = episodes.isEmpty
        isRefreshing = true
        Task {
            let fetched = await withTaskGroup(of: [Episode].self) { group -> [Episode] in
                for p in favPodcasts {
                    group.addTask {
                        do {
                            return try await APIService.shared.getPodcastEpisodes(
                                collectionId: p.collectionId,
                                preferredCountry: storage.currentLanguage.itunes,
                                feedUrl: p.feedUrl
                            )
                        } catch {
                            return []
                        }
                    }
                }
                
                var allEpisodes = [Episode]()
                for await eps in group {
                    allEpisodes.append(contentsOf: eps)
                }
                return allEpisodes
            }
            
            let sanitized = LocalStorageManager.sanitizeEpisodesDates(fetched)
            
            // Sort by parsed Date Descending
            let sorted = sanitized.sorted { a, b in
                let dateA = DateFormatterUtility.parse(a.releaseDate) ?? .distantPast
                let dateB = DateFormatterUtility.parse(b.releaseDate) ?? .distantPast
                return dateA > dateB
            }
            
            await MainActor.run {
                var processed = sorted
                if storage.settings.longestPerDayOnly {
                    processed = applyLongestPerDayFilter(sorted)
                }
                
                // Record accurate latest episode date per podcast so Podcasts tab badges & ordering match
                storage.updateLatestEpisodeDates(from: processed)
                
                // Filter episodes up to 1 week (7 days)
                let now = Date()
                let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 24 * 3600)
                let withinOneWeek = processed.filter { ep in
                    guard let releaseStr = ep.releaseDate,
                          let date = DateFormatterUtility.parse(releaseStr) else { return false }
                    return date >= oneWeekAgo && date <= now
                }
                
                self.episodes = withinOneWeek
                storage.cachedEpisodes = withinOneWeek
                storage.lastEpisodesFetchDate = now
                self.isLoading = false
                self.isRefreshing = false
                
                // Sync the exact 5 latest visible episodes to Widget
                storage.syncWidgetLatestEpisodes(from: self.filteredEpisodes())
            }
        }
    }
    
    private func filteredEpisodes() -> [Episode] {
        var list = episodes
        
        list = list.filter { !storage.isDismissedEpisode($0.trackId) }
        
        if activeFilter == .unplayed {
            list = list.filter { !storage.isPlayedEpisode($0.trackId) }
        }
        
        if storage.settings.longestPerDayOnly {
            list = applyLongestPerDayFilter(list)
        }
        
        return list
    }
    
    private func applyLongestPerDayFilter(_ input: [Episode]) -> [Episode] {
        var grouped: [String: Episode] = [:]
        
        for ep in input {
            guard let collectionId = ep.collectionId,
                  let releaseStr = ep.releaseDate,
                  let date = DateFormatterUtility.parse(releaseStr) else { continue }
            
            let dateStr = DateFormatterUtility.formatKey(date)
            let key = "\(collectionId)-\(dateStr)"
            
            let time = ep.trackTimeMillis ?? 0
            
            if let existing = grouped[key] {
                if time > (existing.trackTimeMillis ?? 0) {
                    grouped[key] = ep
                }
            } else {
                grouped[key] = ep
            }
        }
        
        return Array(grouped.values).sorted { a, b in
            let dateA = DateFormatterUtility.parse(a.releaseDate) ?? .distantPast
            let dateB = DateFormatterUtility.parse(b.releaseDate) ?? .distantPast
            return dateA > dateB
        }
    }
    
    private func toggleAutoDownload() {
        let newValue = !storage.settings.autoDownloadLatest
        storage.settings.autoDownloadLatest = newValue
        
        if newValue {
            isDownloadingAll = true
            Task {
                let targets = Array(filteredEpisodes().prefix(10))
                let targetIds = Set(targets.map { $0.trackId })
                
                for ep in targets {
                    await DownloadManager.shared.downloadEpisode(ep)
                }
                
                let downloaded = LocalStorageManager.shared.downloadedEpisodeIds
                for id in downloaded {
                    if !targetIds.contains(id) {
                        DownloadManager.shared.deleteDownload(episodeId: id)
                    }
                }
                
                await MainActor.run {
                    isDownloadingAll = false
                }
            }
        } else {
            DownloadManager.shared.purgeAllDownloads()
        }
    }
}

struct EpisodeRowView: View {
    let episode: Episode
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CachedAsyncImage(url: artworkUrl, maxPixelSize: 160) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.primary.opacity(0.07)
                    Image(systemName: "music.note")
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }
            .frame(width: 50, height: 50)
            .cornerRadius(10)
            .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.trackName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(storage.isPlayedEpisode(episode.trackId) ? .secondary : storage.primaryTextColor)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 6) {
                    let showPodcastName = episode.collectionName != nil && !episode.trackName.localizedCaseInsensitiveContains(episode.collectionName ?? "")
                    
                    if showPodcastName, let colName = episode.collectionName {
                        Text(colName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(storage.accentColorColor())
                            .lineLimit(1)
                            .frame(maxWidth: 150, alignment: .leading)
                    }
                    
                    if let dateStr = episode.releaseDate {
                        if showPodcastName {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(formatReleaseDate(dateStr))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    if let durationMillis = episode.trackTimeMillis {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(formatDuration(durationMillis))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            
            HStack(spacing: 8) {
                if storage.downloadedEpisodeIds.contains(episode.trackId) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.green)
                        .font(.subheadline)
                }
                
                if storage.isPlayedEpisode(episode.trackId) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatReleaseDate(_ dateStr: String) -> String {
        guard let date = DateFormatterUtility.parse(dateStr) else { return "" }
        return DateFormatterUtility.formatOutput(date, lang: storage.currentLanguage.rawValue)
    }
    
    private func formatDuration(_ durationMillis: Int) -> String {
        let seconds = durationMillis / 1000
        let minutes = seconds / 60
        let hours = minutes / 60
        
        if hours > 0 {
            let remMin = minutes % 60
            return "\(hours)h \(remMin)m"
        } else {
            return "\(minutes) min"
        }
    }
    
    private var artworkUrl: URL? {
        if let urlStr = episode.artworkUrl160, !urlStr.isEmpty { return URL(string: urlStr) }
        if let urlStr = episode.artworkUrl60, !urlStr.isEmpty { return URL(string: urlStr) }
        if let urlStr = episode.artworkUrl600, !urlStr.isEmpty { return URL(string: urlStr) }
        
        if let colId = episode.collectionId,
           let podcast = storage.favoritePodcasts.first(where: { $0.collectionId == colId }) {
            if let urlStr = podcast.artworkUrl600, !urlStr.isEmpty { return URL(string: urlStr) }
            if let urlStr = podcast.artworkUrl100, !urlStr.isEmpty { return URL(string: urlStr) }
        }
        return nil
    }
}
