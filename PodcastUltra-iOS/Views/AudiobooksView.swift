import SwiftUI
import UIKit

struct SubscriptionFilterOption: Identifiable, Equatable {
    let key: String
    let labelFr: String
    let labelEn: String
    let icon: String
    
    var id: String { key }
    
    func label(for lang: LangCode) -> String {
        lang == .fr ? labelFr : labelEn
    }
}

struct AudiobooksView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    @State private var isPodcastsSectionSelected: Bool = true
    @State private var activeSection: SubscriptionSection = .culture
    @State private var activeFilterBySection: [SubscriptionSection: String] = [
        .culture: "all",
        .enfants: "all"
    ]
    @State private var itemsByKey: [String: [Podcast]] = [:]
    @State private var isLoading = false
    @State private var isRefreshing = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 155), spacing: 16)
    ]
    
    private var activeFilter: String {
        activeFilterBySection[activeSection] ?? "all"
    }
    
    private func cacheKey(section: SubscriptionSection, filter: String) -> String {
        "\(section.rawValue)_\(filter)"
    }
    
    private var currentItems: [Podcast] {
        let key = cacheKey(section: activeSection, filter: activeFilter)
        if let loaded = itemsByKey[key], !loaded.isEmpty {
            return LanguageContentFilter.shared.filterPodcasts(loaded, for: storage.currentLanguage)
        }
        if let cached = storage.cachedSubscriptionsBySection[key], !cached.isEmpty {
            return LanguageContentFilter.shared.filterPodcasts(cached, for: storage.currentLanguage)
        }
        if activeFilter == "all", let fallback = storage.cachedSubscriptionsBySection[activeSection.rawValue], !fallback.isEmpty {
            return LanguageContentFilter.shared.filterPodcasts(fallback, for: storage.currentLanguage)
        }
        return []
    }
    
    private func filters(for section: SubscriptionSection) -> [SubscriptionFilterOption] {
        switch section {
        case .culture, .livres:
            return [
                SubscriptionFilterOption(key: "all", labelFr: "Tous", labelEn: "All", icon: "sparkles"),
                SubscriptionFilterOption(key: "books_classics", labelFr: "Romans & Livres", labelEn: "Books & Novels", icon: "book.fill"),
                SubscriptionFilterOption(key: "society", labelFr: "Société & Récits", labelEn: "Society & Stories", icon: "person.3.fill"),
                SubscriptionFilterOption(key: "history", labelFr: "Histoire", labelEn: "History", icon: "scroll.fill"),
                SubscriptionFilterOption(key: "science_nasa", labelFr: "Sciences & Espace", labelEn: "Science & Space", icon: "atom"),
                SubscriptionFilterOption(key: "media_debates", labelFr: "Idées & Philo", labelEn: "Ideas & Philo", icon: "lightbulb.fill"),
                SubscriptionFilterOption(key: "arts_archive", labelFr: "Arts & Lettres", labelEn: "Arts & Letters", icon: "building.columns.fill"),
                SubscriptionFilterOption(key: "thriller_scifi", labelFr: "Polar & Sci-Fi", labelEn: "Mystery & Sci-Fi", icon: "moon.stars.fill")
            ]
        case .enfants:
            return [
                SubscriptionFilterOption(key: "all", labelFr: "Tous", labelEn: "All", icon: "teddybear.fill"),
                SubscriptionFilterOption(key: "stories", labelFr: "Contes", labelEn: "Stories", icon: "book.closed.fill"),
                SubscriptionFilterOption(key: "music_kids", labelFr: "Comptines", labelEn: "Songs", icon: "music.quarternote.3"),
                SubscriptionFilterOption(key: "bedtime", labelFr: "Dormir", labelEn: "Sleep", icon: "moon.zzz.fill"),
                SubscriptionFilterOption(key: "adventure", labelFr: "Aventure", labelEn: "Adventure", icon: "safari.fill"),
                SubscriptionFilterOption(key: "nature", labelFr: "Sciences", labelEn: "Science", icon: "pawprint.fill")
            ]
        }
    }
    
    private func isValidSubscription(_ item: Podcast) -> Bool {
        if APIService.shared.isRadioSourceOrStation(item) {
            return false
        }
        guard let count = item.episodeCount, count > 0,
              let millis = item.totalDurationMillis, millis >= 30 * 60 * 1000 else {
            return false
        }
        return true
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. Sub-sections selector: Podcasts, Culture, Enfants (fixed non-scrollable bar, full-width without line wrap)
            HStack(spacing: 8) {
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        isPodcastsSectionSelected = true
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(Translations.shared.t("subscriptions_btn", storage.currentLanguage))
                            .font(.system(size: 13, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                    .background(
                        isPodcastsSectionSelected
                            ? AnyView(storage.accentColorColor())
                            : AnyView(storage.cardBackgroundColor)
                    )
                    .foregroundColor(isPodcastsSectionSelected ? .white : storage.primaryTextColor)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isPodcastsSectionSelected ? Color.white.opacity(0.25) : storage.cardBorderColor, lineWidth: 1)
                    )
                    .shadow(color: isPodcastsSectionSelected ? storage.accentColorColor().opacity(0.3) : .clear, radius: 6, y: 3)
                }
                .buttonStyle(PlainButtonStyle())
                
                ForEach(SubscriptionSection.visibleCases) { section in
                    let isSelected = !isPodcastsSectionSelected && activeSection == section
                    Button(action: {
                        HapticManager.shared.trigger(.light)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            isPodcastsSectionSelected = false
                            activeSection = section
                        }
                        fetchSectionItems(section: section, force: false)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: section.iconName)
                                .font(.system(size: 12, weight: .bold))
                            Text(section.title(for: storage.currentLanguage))
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
            .padding(.top, 4)
            .padding(.bottom, 8)
            .ipadMaxWidth()
            
            if isPodcastsSectionSelected {
                DiscoverView()
            } else {
                ZStack {
                    ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 2. Section-specific filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters(for: activeSection)) { filter in
                                let isFilterSelected = activeFilter == filter.key
                                Button(action: {
                                    HapticManager.shared.trigger(.light)
                                    activeFilterBySection[activeSection] = filter.key
                                    if activeSection == .livres {
                                        storage.lastAudiobooksCategory = filter.key
                                    }
                                    fetchSectionItems(section: activeSection, force: false)
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: filter.icon)
                                            .font(.system(size: 10, weight: .bold))
                                        Text(filter.label(for: storage.currentLanguage))
                                            .font(.caption)
                                            .fontWeight(.bold)
                                    }
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 12)
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
                        .padding(.horizontal)
                    }
                
                // 3. Favorites for active section (in-progress items placed on the left!)
                let sectionFavorites = storage.sortedFavorites(for: activeSection)
                if !sectionFavorites.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                            Text("\(Translations.shared.t("your_favorites", storage.currentLanguage)) • \(activeSection.title(for: storage.currentLanguage))")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(storage.primaryTextColor)
                            
                            Spacer()
                            
                            let inProgressCount = sectionFavorites.filter { storage.getInProgressState(for: $0) != nil }.count
                            if inProgressCount > 0 {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 6, height: 6)
                                    Text(storage.currentLanguage == .fr ? "\(inProgressCount) en cours à gauche" : "\(inProgressCount) in progress on left")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.orange)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.14))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(sectionFavorites) { item in
                                    NavigationLink(destination: EpisodeListView(podcast: item, isAudiobook: true)) {
                                        BookCard(book: item, section: activeSection)
                                            .frame(width: 170)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        Divider()
                            .background(storage.cardBorderColor)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                }
                
                // 4. Main Grid for active section (All items >= 30 min & non-radio)
                let gridItems = currentItems.filter { item in
                    if storage.isFavoriteSubscription(item.collectionId, in: activeSection) {
                        return false
                    }
                    return isValidSubscription(item)
                }
                
                if isLoading && gridItems.isEmpty {
                    VStack {
                        Spacer(minLength: 50)
                        ProgressView()
                            .scaleEffect(1.3)
                            .progressViewStyle(CircularProgressViewStyle(tint: storage.accentColorColor()))
                        Spacer(minLength: 50)
                    }
                    .frame(maxWidth: .infinity)
                } else if gridItems.isEmpty {
                    VStack(spacing: 12) {
                        Spacer(minLength: 50)
                        Image(systemName: activeSection.iconName)
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text(storage.currentLanguage == .fr ? "Aucun abonnement (> 30 min) trouvé" : "No subscriptions (> 30 min) found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 50)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(gridItems) { item in
                            NavigationLink(destination: EpisodeListView(podcast: item, isAudiobook: true)) {
                                BookCard(book: item, section: activeSection)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .ipadMaxWidth()
            .padding(.bottom, 100)
            }
            .refreshable {
                await fetchSectionItemsAsync(section: activeSection, force: true)
            }
            
            // Full-screen knowledge & productivity loading overlay during pull-to-refresh
            if isRefreshing {
                RefreshLoadingOverlay()
                    .zIndex(100)
            }
        }
        }
        }
        .onAppear {
            for (k, cached) in storage.cachedSubscriptionsBySection {
                let validCached = cached.filter { isValidSubscription($0) }
                if !validCached.isEmpty {
                    itemsByKey[k] = validCached
                }
            }
            if !isPodcastsSectionSelected && currentItems.isEmpty {
                fetchSectionItems(section: activeSection, force: false)
            }
            enrichFavoritesIfNeeded()
        }
        .onChange(of: storage.currentLanguage) { _, _ in
            itemsByKey = [:]
            fetchSectionItems(section: activeSection, force: true)
        }
    }
    
    private func enrichFavoritesIfNeeded() {
        let country = storage.currentLanguage.itunes
        for sec in SubscriptionSection.visibleCases {
            let favs = storage.favoritesForSubscriptionSection(sec)
            let needingDuration = favs.filter { $0.totalDurationMillis == nil }
            guard !needingDuration.isEmpty else { continue }
            Task {
                let enriched = await APIService.shared.enrichAndFilterAudiobooks(favs, country: country)
                if !enriched.isEmpty {
                    await MainActor.run {
                        var updated = storage.favoritesForSubscriptionSection(sec)
                        for item in enriched {
                            if let idx = updated.firstIndex(where: { $0.collectionId == item.collectionId }) {
                                updated[idx] = item
                            }
                        }
                        var dict = storage.favoriteSubscriptionsBySection
                        dict[sec.rawValue] = updated
                        storage.favoriteSubscriptionsBySection = dict
                        if sec == .livres {
                            storage.favoriteAudiobooks = updated
                        }
                    }
                }
            }
        }
    }
    
    private func fetchSectionItems(section: SubscriptionSection, force: Bool) {
        Task {
            await fetchSectionItemsAsync(section: section, force: force)
        }
    }
    
    private func fetchSectionItemsAsync(section: SubscriptionSection, force: Bool) async {
        let filterKey = activeFilterBySection[section] ?? "all"
        let key = cacheKey(section: section, filter: filterKey)
        let existingValid = (itemsByKey[key] ?? storage.cachedSubscriptionsBySection[key] ?? []).filter { isValidSubscription($0) }
        
        if !force && !existingValid.isEmpty && !storage.shouldAutoRefreshSubscriptions(forKey: key) {
            await MainActor.run {
                if itemsByKey[key] == nil {
                    itemsByKey[key] = existingValid
                }
            }
            return
        }
        
        await MainActor.run {
            self.isLoading = existingValid.isEmpty
            self.isRefreshing = true
        }
        let country = storage.currentLanguage.itunes
        
        let results = await APIService.shared.getSubscriptionItems(
            section: section,
            filterKey: filterKey,
            country: country
        )
        let cleanResults = ProfanityFilter.shared.filterCleanPodcasts(results)
        
        await MainActor.run {
            self.itemsByKey[key] = cleanResults
            storage.registerSubscriptionSection(section, for: cleanResults)
            storage.markSubscriptionFetched(forKey: key)
            var cachedDict = storage.cachedSubscriptionsBySection
            cachedDict[key] = cleanResults
            if filterKey == "all" {
                cachedDict[section.rawValue] = cleanResults
            }
            storage.cachedSubscriptionsBySection = cachedDict
            if section == .livres && filterKey == "all" {
                storage.cachedAudiobooks = cleanResults
            }
            self.isLoading = false
            self.isRefreshing = false
        }
    }
}

struct BookCard: View {
    let book: Podcast
    var section: SubscriptionSection? = nil
    
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    private var effectiveSection: SubscriptionSection {
        section ?? storage.inferSubscriptionSection(for: book)
    }
    
    private var inProgressState: InProgressSubscriptionState? {
        storage.getInProgressState(for: book)
    }
    
    var body: some View {
        let inProgress = inProgressState
        let isFav = storage.isFavoriteSubscription(book.collectionId, in: effectiveSection)
        
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Multi-fallback Subscription Cover (guarantees a visual on EVERY card!)
                SubscriptionArtworkView(book: book, section: effectiveSection)
                    .aspectRatio(1, contentMode: .fill)
                    .cornerRadius(18)
                    .clipped()
                
                // Top badges: Total Duration (always shown on vignette!) + In-Progress / Source
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if let durationText = book.formattedTotalDuration {
                            HStack(spacing: 3) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 7, weight: .bold))
                                Text(durationText)
                                    .font(.system(size: 8, weight: .black))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(storage.accentColorColor().opacity(0.92))
                            .cornerRadius(6)
                        }
                        
                        Spacer(minLength: 0)
                        
                        if let src = book.source {
                            Text(src.uppercased())
                                .font(.system(size: 7, weight: .black))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                                .background(Color.black.opacity(0.68))
                                .cornerRadius(4)
                        }
                    }
                    
                    if let prog = inProgress {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                            Text(storage.currentLanguage == .fr ? "EN COURS • \(prog.formattedPosition)" : "IN PROGRESS • \(prog.formattedPosition)")
                                .font(.system(size: 7.5, weight: .black))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Color.orange.opacity(0.95))
                        .cornerRadius(6)
                    }
                }
                .padding(6)
            }
            .overlay(
                // Favorite Heart Button
                Button(action: {
                    HapticManager.shared.trigger(.medium)
                    withAnimation {
                        storage.toggleFavoriteSubscription(book, section: effectiveSection)
                    }
                }) {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.caption)
                        .foregroundColor(isFav ? .red : .white)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.62))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .padding(8),
                alignment: .bottomTrailing
            )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(book.collectionName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(storage.primaryTextColor)
                    .lineLimit(1)
                
                Text(book.artistName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let durationText = book.formattedTotalDuration {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))
                        Text(durationText)
                            .font(.system(size: 10, weight: .bold))
                        if let epCount = book.episodeCount, epCount > 0 {
                            Text("• \(epCount) ép.")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(storage.accentColorColor())
                    .padding(.top, 1)
                }
                
                // In-progress bar + "Reprendre" and "Annuler" buttons
                if let prog = inProgress {
                    VStack(alignment: .leading, spacing: 6) {
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
                        .padding(.top, 2)
                        
                        HStack(spacing: 6) {
                            let isThisPlaying = audioPlayer.isSubscriptionPlaying(book)
                            
                            // "Reprendre / Pause" button: toggles playback
                            Button(action: {
                                HapticManager.shared.trigger(.medium)
                                audioPlayer.toggleSubscriptionPlayback(book)
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 8, weight: .black))
                                    Text(isThisPlaying
                                         ? (storage.currentLanguage == .fr ? "Pause" : "Pause")
                                         : (storage.currentLanguage == .fr ? "Reprendre" : "Resume"))
                                        .font(.system(size: 9.5, weight: .black))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(isThisPlaying ? Color.orange : storage.accentColorColor())
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // "Annuler" button: cancels in-progress status
                            Button(action: {
                                HapticManager.shared.trigger(.light)
                                withAnimation {
                                    storage.cancelInProgress(for: book)
                                }
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .black))
                                    Text(storage.currentLanguage == .fr ? "Annuler" : "Cancel")
                                        .font(.system(size: 9, weight: .bold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(storage.subtleSurfaceColor)
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(storage.cardBackgroundColor)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(inProgress != nil ? Color.orange.opacity(0.55) : storage.cardBorderColor, lineWidth: inProgress != nil ? 1.5 : 1)
        )
    }
}

// MARK: - Multi-Fallback Subscription Cover View + Rich Illustrated Cover Generator
struct SubscriptionArtworkView: View {
    let book: Podcast
    let section: SubscriptionSection
    
    @State private var loadedImage: UIImage? = nil
    @State private var didStartLoading = false
    
    init(book: Podcast, section: SubscriptionSection) {
        self.book = book
        self.section = section
        
        let candidates = Self.candidateURLs(for: book)
        for url in candidates {
            if let memImg = DecodedImageMemoryCache.shared.image(for: url) {
                _loadedImage = State(initialValue: memImg)
                _didStartLoading = State(initialValue: true)
                return
            }
        }
    }
    
    var body: some View {
        ZStack {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else {
                GeneratedSubscriptionCoverView(book: book, section: section)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .onAppear {
            if loadedImage == nil && !didStartLoading {
                didStartLoading = true
                loadFirstValidArtwork()
            }
        }
    }
    
    static func candidateURLs(for book: Podcast) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        
        func add(_ raw: String?) {
            guard let clean = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !clean.isEmpty,
                  !clean.contains("librivox-logo.png"),
                  !clean.contains("litteratureaudio.com/wp-content"),
                  !seen.contains(clean),
                  let u = URL(string: clean) else { return }
            seen.insert(clean)
            urls.append(u)
        }
        
        add(book.artworkUrl600)
        add(book.artworkUrl100)
        
        if let eps = APIService.shared.getCachedBookEpisodes(for: book.collectionId) {
            for ep in eps.prefix(3) {
                add(ep.artworkUrl600)
                add(ep.artworkUrl160)
                add(ep.artworkUrl60)
            }
        }
        
        return urls
    }
    
    private func loadFirstValidArtwork() {
        let candidates = Self.candidateURLs(for: book)
        guard !candidates.isEmpty else { return }
        
        Task.detached(priority: .utility) {
            for url in candidates {
                if let mem = DecodedImageMemoryCache.shared.image(for: url) {
                    await MainActor.run {
                        self.loadedImage = mem
                    }
                    return
                }
                
                var req = URLRequest(url: url)
                req.cachePolicy = .returnCacheDataElseLoad
                req.timeoutInterval = 8
                
                if let cached = URLCache.shared.cachedResponse(for: req),
                   let img = Self.decodeCover(data: cached.data) {
                    DecodedImageMemoryCache.shared.insert(img, for: url)
                    await MainActor.run {
                        self.loadedImage = img
                    }
                    return
                }
                
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse,
                   (200...299).contains(http.statusCode),
                   let img = Self.decodeCover(data: data) {
                    URLCache.shared.storeCachedResponse(CachedURLResponse(response: resp, data: data), for: req)
                    DecodedImageMemoryCache.shared.insert(img, for: url)
                    await MainActor.run {
                        self.loadedImage = img
                    }
                    return
                }
            }
        }
    }
    
    nonisolated private static func decodeCover(data: Data) -> UIImage? {
        guard data.count > 256, let raw = UIImage(data: data) else { return nil }
        guard raw.size.width >= 32 && raw.size.height >= 32 else { return nil }
        let maxSide: CGFloat = 360
        let longest = max(raw.size.width, raw.size.height)
        if longest > maxSide {
            let ratio = maxSide / longest
            let sz = CGSize(width: max(1, raw.size.width * ratio), height: max(1, raw.size.height * ratio))
            if let thumb = raw.preparingThumbnail(of: sz) {
                return thumb
            }
        }
        return raw.preparingForDisplay() ?? raw
    }
}

struct GeneratedSubscriptionCoverView: View {
    let book: Podcast
    let section: SubscriptionSection
    
    var body: some View {
        let (c1, c2) = RadioIconHelper.palette(for: book.collectionName)
        
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                LinearGradient(
                    colors: [c1, c2],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Decorative ambient glow circles
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: w * 0.72, height: w * 0.72)
                    .offset(x: w * 0.25, y: -w * 0.25)
                
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                    .frame(width: w * 0.82, height: w * 0.82)
                
                VStack(spacing: 8) {
                    Spacer(minLength: 18)
                    
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.22))
                            .frame(width: max(36, w * 0.34), height: max(36, w * 0.34))
                        
                        Image(systemName: section.iconName)
                            .font(.system(size: max(18, w * 0.16), weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Text(book.collectionName)
                        .font(.system(size: max(11, w * 0.085), weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 10)
                    
                    Text(book.artistName)
                        .font(.system(size: max(8, w * 0.06), weight: .bold))
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                    
                    Spacer(minLength: 14)
                }
            }
        }
    }
}
