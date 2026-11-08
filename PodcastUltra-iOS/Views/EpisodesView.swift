import SwiftUI
import WidgetKit

struct EpisodesView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    enum FavoritesSection: String, CaseIterable, Identifiable {
        case podcasts, culture, enfants
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .podcasts: return "mic.fill"
            case .culture: return "building.columns.fill"
            case .enfants: return "teddybear.fill"
            }
        }
        
        func title(for lang: LangCode) -> String {
            switch self {
            case .podcasts:
                return Translations.shared.t("subscriptions_btn", lang)
            case .culture:
                return SubscriptionSection.culture.title(for: lang)
            case .enfants:
                return SubscriptionSection.enfants.title(for: lang)
            }
        }
    }
    
    enum SubscriptionFavoritesFilter: String, CaseIterable, Identifiable {
        case all, inProgress, books, podcasts
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .all: return "sparkles"
            case .inProgress: return "play.circle.fill"
            case .books: return "book.fill"
            case .podcasts: return "waveform"
            }
        }
        
        func label(for lang: LangCode) -> String {
            let isFr = lang == .fr
            switch self {
            case .all: return isFr ? "Tous" : "All"
            case .inProgress: return isFr ? "En cours" : "In Progress"
            case .books: return isFr ? "Livres" : "Books"
            case .podcasts: return isFr ? "Émissions" : "Shows"
            }
        }
    }
    
    enum SubscriptionFavoritesSort: String, CaseIterable, Identifiable {
        case inProgressFirst, alphabetical, durationDesc, durationAsc
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .inProgressFirst: return "clock.badge.checkmark"
            case .alphabetical: return "textformat.abc"
            case .durationDesc: return "arrow.down.right.circle"
            case .durationAsc: return "arrow.up.right.circle"
            }
        }
        
        func label(for lang: LangCode) -> String {
            let isFr = lang == .fr
            switch self {
            case .inProgressFirst: return isFr ? "En cours d'abord" : "In Progress First"
            case .alphabetical: return isFr ? "Ordre A–Z" : "A–Z"
            case .durationDesc: return isFr ? "Durée (long → court)" : "Duration (Long → Short)"
            case .durationAsc: return isFr ? "Durée (court → long)" : "Duration (Short → Long)"
            }
        }
    }
    
    @State private var activeSection: FavoritesSection = .podcasts
    @State private var episodes: [Episode] = LocalStorageManager.shared.cachedEpisodes
    @State private var displayedEpisodes: [Episode] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var activeFilter: EpisodeFilter = .all
    @ObservedObject private var weatherService = WeatherService.shared
    @State private var selectedPodcast: Podcast? = nil
    @State private var selectedIsAudiobook: Bool = false
    @State private var navigateToPodcast = false
    @State private var isDownloadingAll = false
    
    // Filters & Sorts for Culture & Enfants sections
    @State private var cultureFilter: SubscriptionFavoritesFilter = .all
    @State private var cultureSort: SubscriptionFavoritesSort = .inProgressFirst
    @State private var enfantsFilter: SubscriptionFavoritesFilter = .all
    @State private var enfantsSort: SubscriptionFavoritesSort = .inProgressFirst
    
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
        ZStack {
            VStack(spacing: 0) {
                // 1. Top 3 Sections Selector: Podcasts, Culture, Enfants (fixed non-scrollable bar, full-width without line wrap)
                HStack(spacing: 8) {
                    ForEach(FavoritesSection.allCases) { sec in
                        let isSelected = activeSection == sec
                        Button(action: {
                            HapticManager.shared.trigger(.light)
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                activeSection = sec
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: sec.icon)
                                    .font(.system(size: 12, weight: .bold))
                                Text(sec.title(for: storage.currentLanguage))
                                    .font(.system(size: 13, weight: .black))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .background(
                                isSelected
                                    ? AnyView(storage.accentColorColor())
                                    : AnyView(storage.cardBackgroundColor)
                            )
                            .foregroundColor(isSelected ? .white : storage.primaryTextColor)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isSelected ? Color.white.opacity(0.25) : storage.cardBorderColor, lineWidth: 1)
                            )
                            .shadow(color: isSelected ? storage.accentColorColor().opacity(0.3) : .clear, radius: 6, y: 3)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 6)
                
                // 2. Content by active section
                if activeSection == .podcasts {
                    podcastsSectionContent
                } else if activeSection == .culture {
                    subscriptionFavoritesListContent(
                        section: .culture,
                        activeFilter: $cultureFilter,
                        activeSort: $cultureSort
                    )
                } else {
                    subscriptionFavoritesListContent(
                        section: .enfants,
                        activeFilter: $enfantsFilter,
                        activeSort: $enfantsSort
                    )
                }
            }
            
            // Full-screen knowledge & productivity loading overlay during refresh
            if isRefreshing {
                RefreshLoadingOverlay()
                    .zIndex(100)
            }
        }
        .onAppear {
            if !storage.cachedEpisodes.isEmpty && (self.episodes.isEmpty || self.episodes.count != storage.cachedEpisodes.count || self.episodes.first?.trackId != storage.cachedEpisodes.first?.trackId) {
                self.episodes = storage.cachedEpisodes
            }
            recomputeDisplayedEpisodes(syncWidget: false)
            let favPodcasts = storage.favoritePodcasts.filter { !LocalStorageManager.isAudiobookItem($0) && !LocalStorageManager.isKidsOrEnfantsItem($0) }
            let cachedPodcastIds = Set(self.episodes.compactMap { $0.collectionId })
            let hasMissingPodcastEpisodes = favPodcasts.contains { !cachedPodcastIds.contains($0.collectionId) }
            if !favPodcasts.isEmpty && (self.episodes.isEmpty || self.displayedEpisodes.isEmpty || hasMissingPodcastEpisodes) {
                fetchEpisodes(force: false)
            } else {
                self.isLoading = false
            }
        }
        .onChange(of: storage.favoritePodcasts.count) { _, _ in
            fetchEpisodes(force: true)
        }
        .onChange(of: storage.cachedEpisodes.count) { _, newCount in
            if newCount > 0 || storage.favoritePodcasts.isEmpty {
                self.episodes = storage.cachedEpisodes
                recomputeDisplayedEpisodes(syncWidget: false)
            }
        }
        .onChange(of: storage.dismissedEpisodeIds.count) { _, _ in
            recomputeDisplayedEpisodes(syncWidget: true)
        }
        .onChange(of: storage.playedEpisodeIds.count) { _, _ in
            if activeFilter == .unplayed {
                recomputeDisplayedEpisodes(syncWidget: false)
            }
        }
        .onChange(of: storage.history.count) { _, _ in
            if activeFilter == .unplayed {
                recomputeDisplayedEpisodes(syncWidget: false)
            }
        }
        .onChange(of: audioPlayer.currentEpisode?.trackId) { _, _ in
            if activeFilter == .unplayed {
                recomputeDisplayedEpisodes(syncWidget: false)
            }
        }
        .onChange(of: storage.settings.longestPerDayOnly) { _, _ in
            recomputeDisplayedEpisodes(syncWidget: true)
        }
        .onChange(of: activeFilter) { _, _ in
            recomputeDisplayedEpisodes(syncWidget: true)
        }
        .navigationDestination(isPresented: $navigateToPodcast) {
            if let podcast = selectedPodcast {
                EpisodeListView(podcast: podcast, isAudiobook: selectedIsAudiobook)
            }
        }
    }
    
    private func sectionCount(for section: FavoritesSection) -> Int {
        switch section {
        case .podcasts:
            return displayedEpisodes.count
        case .culture:
            return storage.favoritesForSubscriptionSection(.culture).count
        case .enfants:
            return storage.favoritesForSubscriptionSection(.enfants).count
        }
    }
    
    // MARK: - Section 1: Podcasts (Episodes Feed + Progress Bars)
    private var podcastsSectionContent: some View {
        VStack(spacing: 0) {
            // Auto-Download button & Filter picker
            HStack(spacing: 8) {
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
                    .padding(.vertical, 7)
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
            } else {
                if displayedEpisodes.isEmpty {
                    ScrollView {
                        VStack(spacing: 12) {
                            Spacer(minLength: 120)
                            Image(systemName: "square.stack.3d.up.slash")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary)
                            Text(storage.currentLanguage == .fr ? "Aucun épisode disponible" : "No episodes available")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(storage.currentLanguage == .fr ? "Glissez vers le bas pour actualiser vos podcasts favoris" : "Pull down to refresh your favorite podcasts")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Spacer(minLength: 120)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable {
                        await fetchEpisodesAsync(force: true)
                    }
                } else {
                    List(displayedEpisodes) { episode in
                        EpisodeRowView(
                            episode: episode,
                            isPlayed: storage.isPlayedEpisode(episode.trackId),
                            isDownloaded: storage.downloadedEpisodeIds.contains(episode.trackId)
                        )
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
                            selectedIsAudiobook = false
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
                    .refreshable {
                        await fetchEpisodesAsync(force: true)
                    }
                }
            }
        }
    }
    
    // MARK: - Sections 2 & 3: Culture & Enfants Favorites List + Filters & Sorts
    private func subscriptionFavoritesListContent(
        section: SubscriptionSection,
        activeFilter: Binding<SubscriptionFavoritesFilter>,
        activeSort: Binding<SubscriptionFavoritesSort>
    ) -> some View {
        let filteredItems = filteredAndSortedSubscriptionFavorites(
            section: section,
            filter: activeFilter.wrappedValue,
            sort: activeSort.wrappedValue
        )
        let isFr = storage.currentLanguage == .fr
        let availableFilters: [SubscriptionFavoritesFilter] = (section == .culture)
            ? [.all, .inProgress, .books, .podcasts]
            : [.all, .inProgress]
        
        return VStack(spacing: 0) {
            // Filter pills + Sort Menu bar (exclusively for Culture & Enfants sections)
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableFilters) { filterOpt in
                            let isFilterSelected = activeFilter.wrappedValue == filterOpt
                            Button(action: {
                                HapticManager.shared.trigger(.light)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    activeFilter.wrappedValue = filterOpt
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: filterOpt.icon)
                                        .font(.system(size: 10, weight: .bold))
                                    Text(filterOpt.label(for: storage.currentLanguage))
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 11)
                                .background(isFilterSelected ? storage.accentColorColor().opacity(0.9) : storage.subtleSurfaceColor)
                                .foregroundColor(isFilterSelected ? .white : storage.primaryTextColor)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isFilterSelected ? Color.white.opacity(0.2) : storage.cardBorderColor, lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                Spacer(minLength: 4)
                
                // Sort Menu
                Menu {
                    ForEach(SubscriptionFavoritesSort.allCases) { sortOpt in
                        Button(action: {
                            HapticManager.shared.trigger(.light)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeSort.wrappedValue = sortOpt
                            }
                        }) {
                            Label(
                                sortOpt.label(for: storage.currentLanguage),
                                systemImage: activeSort.wrappedValue == sortOpt ? "checkmark" : sortOpt.icon
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text(activeSort.wrappedValue.label(for: storage.currentLanguage))
                            .font(.system(size: 10.5, weight: .bold))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(storage.subtleSurfaceColor)
                    .foregroundColor(storage.accentColorColor())
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(storage.cardBorderColor, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: section.iconName)
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text(
                        isFr
                        ? "Aucun favori dans \(section.title(for: storage.currentLanguage))"
                        : "No favorites in \(section.title(for: storage.currentLanguage))"
                    )
                    .font(.headline)
                    .foregroundColor(.secondary)
                    Text(
                        isFr
                        ? "Ajoutez des contenus en favoris (♡) depuis l'onglet Découvrir • \(section.title(for: storage.currentLanguage)) pour les retrouver ici en liste."
                        : "Heart (♡) items in the Discover • \(section.title(for: storage.currentLanguage)) tab to see them listed here."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredItems) { item in
                        FavoriteSubscriptionRowView(
                            item: item,
                            section: section,
                            onOpenDetails: {
                                selectedPodcast = item
                                selectedIsAudiobook = true
                                navigateToPodcast = true
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(storage.cardBorderColor)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            let isPinned = storage.isPinnedSubscription(item.collectionId)
                            Button {
                                HapticManager.shared.trigger(.medium)
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    storage.togglePinnedSubscription(item.collectionId)
                                }
                            } label: {
                                Label(
                                    isPinned
                                        ? (isFr ? "Désépingler" : "Unpin")
                                        : (isFr ? "Épingler" : "Pin"),
                                    systemImage: isPinned ? "pin.slash.fill" : "pin.fill"
                                )
                            }
                            .tint(storage.accentColorColor())
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    storage.toggleFavoriteSubscription(item, section: section)
                                }
                            } label: {
                                Label(isFr ? "Retirer" : "Remove", systemImage: "heart.slash.fill")
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .background(Color.clear)
            }
        }
    }
    
    private func filteredAndSortedSubscriptionFavorites(
        section: SubscriptionSection,
        filter: SubscriptionFavoritesFilter,
        sort: SubscriptionFavoritesSort
    ) -> [Podcast] {
        var list = storage.favoritesForSubscriptionSection(section)
        
        switch filter {
        case .all:
            break
        case .inProgress:
            list = list.filter { storage.getInProgressState(for: $0) != nil }
        case .books:
            list = list.filter { LocalStorageManager.isAudiobookItem($0) }
        case .podcasts:
            list = list.filter { !LocalStorageManager.isAudiobookItem($0) }
        }
        
        switch sort {
        case .inProgressFirst:
            list.sort { a, b in
                let progA = storage.getInProgressState(for: a)
                let progB = storage.getInProgressState(for: b)
                if let pA = progA, let pB = progB {
                    return pA.updatedAt > pB.updatedAt
                }
                if progA != nil { return true }
                if progB != nil { return false }
                return a.collectionName.localizedCaseInsensitiveCompare(b.collectionName) == .orderedAscending
            }
        case .alphabetical:
            list.sort {
                $0.collectionName.localizedCaseInsensitiveCompare($1.collectionName) == .orderedAscending
            }
        case .durationDesc:
            list.sort {
                ($0.totalDurationMillis ?? 0) > ($1.totalDurationMillis ?? 0)
            }
        case .durationAsc:
            list.sort {
                ($0.totalDurationMillis ?? Int.max) < ($1.totalDurationMillis ?? Int.max)
            }
        }
        
        // Place pinned items at the very top of the list regardless of the active sort
        let pinnedOrder = storage.pinnedSubscriptionIds
        if !pinnedOrder.isEmpty {
            let pinnedSet = Set(pinnedOrder)
            let pinnedItems = pinnedOrder.compactMap { id in
                list.first(where: { $0.collectionId == id })
            }
            let unpinnedItems = list.filter { !pinnedSet.contains($0.collectionId) }
            return pinnedItems + unpinnedItems
        }
        
        return list
    }
    
    private func recomputeDisplayedEpisodes(syncWidget: Bool) {
        let computed = filteredEpisodes()
        self.displayedEpisodes = computed
        if syncWidget {
            storage.syncWidgetLatestEpisodes(from: computed)
        }
    }
    
    private func fetchEpisodes(force: Bool = false) {
        Task {
            await fetchEpisodesAsync(force: force)
        }
    }
    
    private func fetchEpisodesAsync(force: Bool = false) async {
        let favPodcasts = storage.favoritePodcasts.filter { !LocalStorageManager.isAudiobookItem($0) && !LocalStorageManager.isKidsOrEnfantsItem($0) }
        guard !favPodcasts.isEmpty else {
            await MainActor.run {
                self.episodes = []
                self.displayedEpisodes = []
                self.isLoading = false
                self.isRefreshing = false
                storage.syncWidgetLatestEpisodes(from: [])
            }
            return
        }
        
        let existingCached = await MainActor.run {
            !self.episodes.isEmpty ? self.episodes : storage.cachedEpisodes
        }
        let cachedPodcastIds = Set(existingCached.compactMap { $0.collectionId })
        let hasMissingPodcastEpisodes = favPodcasts.contains { !cachedPodcastIds.contains($0.collectionId) }
        
        if !force && !existingCached.isEmpty && !hasMissingPodcastEpisodes && !storage.shouldRefresh(lastFetch: storage.lastEpisodesFetchDate) {
            await MainActor.run {
                if self.episodes.isEmpty {
                    self.episodes = existingCached
                    self.recomputeDisplayedEpisodes(syncWidget: false)
                }
                self.isLoading = false
                self.isRefreshing = false
            }
            return
        }
        
        await MainActor.run {
            if self.episodes.isEmpty && !existingCached.isEmpty {
                self.episodes = existingCached
                self.recomputeDisplayedEpisodes(syncWidget: false)
            }
            self.isLoading = self.episodes.isEmpty
            self.isRefreshing = true
        }
        
        let fetched = (try? await APIService.shared.fetchEpisodesForPodcasts(favPodcasts, forceRefresh: force)) ?? []
        let latestCached = await MainActor.run {
            !storage.cachedEpisodes.isEmpty ? storage.cachedEpisodes : self.episodes
        }
        
        // When offline or network fails (fetched is empty), preserve the existing cached episodes instead of wiping the list!
        if fetched.isEmpty && !latestCached.isEmpty {
            let processedOffline = LocalStorageManager.processRecentFavoriteEpisodes([], from: favPodcasts, existingCached: latestCached)
            await MainActor.run {
                var feed = processedOffline.recentFeed.isEmpty ? latestCached : processedOffline.recentFeed
                if storage.settings.longestPerDayOnly {
                    feed = storage.applyLongestPerDayFilter(feed)
                }
                self.episodes = feed
                if storage.cachedEpisodes.isEmpty && !feed.isEmpty {
                    storage.cachedEpisodes = feed
                }
                self.recomputeDisplayedEpisodes(syncWidget: false)
                self.isLoading = false
                self.isRefreshing = false
            }
            return
        }
        
        let processed = LocalStorageManager.processRecentFavoriteEpisodes(fetched, from: favPodcasts, existingCached: latestCached)
        
        await MainActor.run {
            // Record accurate latest episode date per podcast so Podcasts tab badges & ordering match
            if !processed.allSorted.isEmpty {
                storage.updateLatestEpisodeDates(from: processed.allSorted)
            }
            
            var feed = processed.recentFeed
            if storage.settings.longestPerDayOnly {
                feed = storage.applyLongestPerDayFilter(feed)
            }
            
            if !feed.isEmpty {
                self.episodes = feed
                storage.cachedEpisodes = feed
                if !fetched.isEmpty {
                    storage.lastEpisodesFetchDate = Date()
                }
            } else if !latestCached.isEmpty {
                self.episodes = latestCached
            }
            self.recomputeDisplayedEpisodes(syncWidget: true)
            self.isLoading = false
            self.isRefreshing = false
            
            WatchSessionManager.shared.syncContextToWatch()
        }
    }
    
    private func filteredEpisodes() -> [Episode] {
        let dismissed = Set(storage.dismissedEpisodeIds)
        var list = episodes.filter { !dismissed.contains($0.trackId) }
        
        if activeFilter == .unplayed {
            let currentPlayingId = audioPlayer.playbackType == "podcast" ? audioPlayer.currentEpisode?.trackId : nil
            list = list.filter { ep in
                if ep.trackId == currentPlayingId { return false }
                return !storage.isEpisodeStartedOrPlayed(ep.trackId)
            }
        }
        
        if storage.settings.longestPerDayOnly {
            list = storage.applyLongestPerDayFilter(list)
        }
        
        return list
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

// MARK: - List Row for Culture & Enfants Favorites in Favoris Tab
struct FavoriteSubscriptionRowView: View {
    let item: Podcast
    let section: SubscriptionSection
    var onOpenDetails: () -> Void
    
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    private var inProgress: InProgressSubscriptionState? {
        storage.getInProgressState(for: item)
    }
    
    var body: some View {
        let prog = inProgress
        let isPlayingThis = audioPlayer.isSubscriptionPlaying(item)
        let isPinned = storage.isPinnedSubscription(item.collectionId)
        
        HStack(alignment: .center, spacing: 12) {
            SubscriptionArtworkView(book: item, section: section)
                .frame(width: 62, height: 62)
                .cornerRadius(14)
                .clipped()
                .onTapGesture {
                    HapticManager.shared.trigger(.light)
                    onOpenDetails()
                }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(storage.accentColorColor())
                            .rotationEffect(.degrees(45))
                    }
                    
                    if let src = item.source, !src.isEmpty {
                        Text(src.uppercased())
                            .font(.system(size: 8.5, weight: .black))
                            .foregroundColor(storage.accentColorColor())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(storage.accentColorColor().opacity(0.14))
                            .cornerRadius(5)
                    }
                    
                    if let durationText = item.formattedTotalDuration {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 8.5, weight: .bold))
                            Text(durationText)
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    if let epCount = item.episodeCount, epCount > 0 {
                        Text("• \(epCount) ép.")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(item.collectionName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(storage.primaryTextColor)
                    .lineLimit(2)
                
                Text(item.artistName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let prog = prog {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(storage.subtleSurfaceColor)
                                        .frame(height: 4)
                                    Capsule()
                                        .fill(Color.orange)
                                        .frame(width: max(8, geo.size.width * prog.progressFraction), height: 4)
                                }
                            }
                            .frame(height: 4)
                            
                            Text(prog.formattedPosition)
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                HapticManager.shared.trigger(.light)
                onOpenDetails()
            }
            
            Spacer(minLength: 4)
            
            // Play / Resume button only (unsubscribe heart button removed to avoid duplication with left-swipe)
            Button(action: {
                HapticManager.shared.trigger(.medium)
                audioPlayer.toggleSubscriptionPlayback(item)
            }) {
                Image(systemName: isPlayingThis ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(prog != nil || isPlayingThis ? .orange : storage.accentColorColor())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 6)
    }
}

struct EpisodeRowView: View {
    let episode: Episode
    var isPlayed: Bool? = nil
    var isDownloaded: Bool? = nil
    
    private var storage: LocalStorageManager { LocalStorageManager.shared }
    private var audioPlayer: AudioPlayerManager { AudioPlayerManager.shared }
    
    private var effectiveIsPlayed: Bool {
        isPlayed ?? storage.isPlayedEpisode(episode.trackId)
    }
    
    private var effectiveIsDownloaded: Bool {
        isDownloaded ?? storage.downloadedEpisodeIds.contains(episode.trackId)
    }
    
    private var isCurrentlyPlayingThisEpisode: Bool {
        audioPlayer.playbackType == "podcast" && audioPlayer.currentEpisode?.trackId == episode.trackId
    }
    
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
            
            VStack(alignment: .leading, spacing: 5) {
                let savedPos = storage.getSavedPosition(for: episode.trackId)
                let durSecs = Double(episode.trackTimeMillis ?? 0) / 1000.0
                let isTrulyCompleted = effectiveIsPlayed && (savedPos <= 1.0 || (durSecs > 0 && savedPos >= durSecs * 0.98))
                
                Text(episode.trackName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isTrulyCompleted ? .secondary : storage.primaryTextColor)
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
                
                // Episode playback progress bar (live for active episode, zero-cost static for all other rows)
                if isCurrentlyPlayingThisEpisode {
                    ActiveEpisodeProgressBar(episode: episode, isPlayed: false)
                        .padding(.top, 2)
                } else {
                    if savedPos >= 1.0 && !isTrulyCompleted {
                        let effectiveDur = durSecs > 0 ? durSecs : max(savedPos * 2.0, 1800.0)
                        let frac = min(0.99, max(0.03, savedPos / effectiveDur))
                        StaticEpisodeProgressBar(
                            fraction: frac,
                            positionSeconds: savedPos,
                            isPlayed: false,
                            isCurrentlyPlaying: false
                        )
                        .padding(.top, 2)
                    } else if isTrulyCompleted {
                        StaticEpisodeProgressBar(
                            fraction: 1.0,
                            positionSeconds: durSecs > 0 ? durSecs : savedPos,
                            isPlayed: true,
                            isCurrentlyPlaying: false
                        )
                        .padding(.top, 2)
                    }
                }
            }
            Spacer()
            
            if effectiveIsDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
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

private struct ActiveEpisodeProgressBar: View {
    let episode: Episode
    let isPlayed: Bool
    @ObservedObject private var progress = AudioPlayerManager.shared.progress
    
    var body: some View {
        let pos = max(progress.currentTime, LocalStorageManager.shared.getSavedPosition(for: episode.trackId))
        let dur = progress.duration > 0 ? progress.duration : Double(episode.trackTimeMillis ?? 0) / 1000.0
        let effectiveDur = dur > 0 ? dur : max(pos * 2.0, 1800.0)
        let frac = min(1.0, max(0.03, pos / effectiveDur))
        
        StaticEpisodeProgressBar(
            fraction: frac,
            positionSeconds: pos,
            isPlayed: isPlayed,
            isCurrentlyPlaying: true
        )
    }
}

private struct StaticEpisodeProgressBar: View {
    let fraction: Double
    let positionSeconds: Double
    let isPlayed: Bool
    let isCurrentlyPlaying: Bool
    
    private var storage: LocalStorageManager { LocalStorageManager.shared }
    
    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(storage.subtleSurfaceColor)
                        .frame(height: 4)
                    Capsule()
                        .fill(isCurrentlyPlaying ? Color.orange : (isPlayed ? Color.blue : storage.accentColorColor()))
                        .frame(width: max(6, geo.size.width * fraction), height: 4)
                }
            }
            .frame(height: 4)
            
            Text(formatLabel())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isCurrentlyPlaying ? .orange : .secondary)
                .lineLimit(1)
        }
    }
    
    private func formatLabel() -> String {
        let pct = Int(round(fraction * 100))
        let totalSecs = max(0, Int(positionSeconds))
        let hours = totalSecs / 3600
        let mins = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        let timeStr = hours > 0
            ? String(format: "%dh%02d", hours, mins)
            : String(format: "%d:%02d", mins, secs)
        return "\(timeStr) (\(pct)%)"
    }
}
