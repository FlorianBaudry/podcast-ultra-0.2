import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    @State private var trendingPodcasts: [Podcast] = LocalStorageManager.shared.cachedTrendingPodcasts
    @State private var sortedFavorites: [Podcast] = []
    @State private var sortedRecommended: [Podcast] = []
    @State private var isLoading = LocalStorageManager.shared.cachedTrendingPodcasts.isEmpty
    @State private var isRefreshingDates = false
    @State private var activeCategory = LocalStorageManager.shared.lastTrendingCategory ?? "All"
    
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Inline Category Pills (matching Culture section style)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Translations.shared.getCategoriesList(storage.currentLanguage), id: \.key) { cat in
                                let isSelected = activeCategory == cat.key
                                Button(action: {
                                    HapticManager.shared.trigger(.light)
                                    activeCategory = cat.key
                                    recomputeLists()
                                    fetchTrending(force: true)
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: iconForCategory(cat.key))
                                            .font(.system(size: 10, weight: .bold))
                                        Text(cat.value)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                    }
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 12)
                                    .background(isSelected ? storage.accentColorColor().opacity(0.9) : storage.subtleSurfaceColor)
                                    .foregroundColor(isSelected ? .white : storage.primaryTextColor)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isSelected ? Color.white.opacity(0.2) : storage.cardBorderColor, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                
                if isLoading {
                    VStack {
                        Spacer(minLength: 50)
                        WeatherLoadingView()
                        Spacer(minLength: 50)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    // Favorites Section (Ordered by most recent episode first)
                    if !sortedFavorites.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                                Text(Translations.shared.t("your_favorites", storage.currentLanguage))
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(storage.primaryTextColor)
                            }
                            .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(sortedFavorites) { podcast in
                                        NavigationLink(destination: EpisodeListView(podcast: podcast)) {
                                            DiscoverPodcastCard(
                                                podcast: podcast,
                                                displayDateString: storage.effectiveReleaseDateString(for: podcast),
                                                isFav: true,
                                                lang: storage.currentLanguage
                                            )
                                            .frame(width: 150)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            Divider()
                                .background(storage.cardBorderColor)
                                .padding(.horizontal)
                                .padding(.top, 10)
                        }
                    }
                    
                    // Recommended Section
                    VStack(alignment: .leading, spacing: 16) {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(sortedRecommended) { podcast in
                                NavigationLink(destination: EpisodeListView(podcast: podcast)) {
                                    DiscoverPodcastCard(
                                        podcast: podcast,
                                        displayDateString: storage.effectiveReleaseDateString(for: podcast),
                                        isFav: false,
                                        lang: storage.currentLanguage
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .ipadMaxWidth()
            .padding(.bottom, 100)
            }
            .refreshable {
                await fetchTrendingAsync(force: true)
            }
            
            // Full-screen knowledge & productivity loading overlay during pull-to-refresh
            if isRefreshingDates {
                RefreshLoadingOverlay()
                    .zIndex(100)
            }
        }
        .onAppear {
            self.trendingPodcasts = storage.cachedTrendingPodcasts
            recomputeLists()
            if trendingPodcasts.isEmpty {
                fetchTrending(force: false)
            }
        }
        .onChange(of: storage.favoritePodcasts.count) { _, _ in
            recomputeLists()
        }
        .onChange(of: storage.currentLanguage) { _, _ in
            self.trendingPodcasts = []
            recomputeLists()
            fetchTrending(force: true)
        }
    }
    
    private func recomputeLists() {
        self.sortedFavorites = getFilteredFavorites()
        let favIds = Set(storage.favoritePodcasts.map { $0.collectionId })
        let rawCandidates = trendingPodcasts.filter {
            !favIds.contains($0.collectionId) &&
            !LocalStorageManager.isAudiobookItem($0) &&
            !LocalStorageManager.isKidsOrEnfantsItem($0)
        }
        let candidates = LanguageContentFilter.shared.filterPodcasts(rawCandidates, for: storage.currentLanguage)
        var parsedDates: [Int: Date] = [:]
        parsedDates.reserveCapacity(candidates.count)
        for p in candidates {
            if let d = DateFormatterUtility.parse(storage.effectiveReleaseDateString(for: p)) {
                parsedDates[p.collectionId] = d
            }
        }
        self.sortedRecommended = candidates.sorted { a, b in
            let dateA = parsedDates[a.collectionId] ?? Date(timeIntervalSince1970: 0)
            let dateB = parsedDates[b.collectionId] ?? Date(timeIntervalSince1970: 0)
            return dateA > dateB
        }
    }
    
    private func fetchTrending(force: Bool = false) {
        Task {
            await fetchTrendingAsync(force: force)
        }
    }
    
    private func fetchTrendingAsync(force: Bool = false) async {
        let categoryChanged = storage.lastTrendingCategory != activeCategory
        if !force && !categoryChanged && !trendingPodcasts.isEmpty && !storage.shouldRefresh(lastFetch: storage.lastTrendingFetchDate, minInterval: 30 * 60) {
            return
        }
        
        await MainActor.run {
            if trendingPodcasts.isEmpty {
                isLoading = true
            }
            isRefreshingDates = true
        }
        
        // 1. Refresh Favorite Podcasts' actual latest episode dates so badges & sorting are 100% accurate
        await refreshFavoriteEpisodeDates()
        
        // 2. Refresh Trending Podcasts
        do {
            let results = try await APIService.shared.getTrendingPodcasts(
                country: storage.currentLanguage.itunes,
                category: activeCategory
            )
            let cleanResults = ProfanityFilter.shared.filterCleanPodcasts(results)
                
            // Verify any trending podcast that claims "Today" so podcasts without a real episode today don't show a false "Aujourd'hui"
            var verifiedTrending = cleanResults
            let todayCandidates = cleanResults.filter { p in
                    guard let d = DateFormatterUtility.parse(p.releaseDate) else { return false }
                    return Calendar.current.isDateInToday(d)
                }
                
                if !todayCandidates.isEmpty {
                    let verifiedDates = await withTaskGroup(of: (Int, String?).self) { group -> [Int: String?] in
                        for p in todayCandidates.prefix(20) {
                            group.addTask {
                                if let eps = try? await APIService.shared.getPodcastEpisodes(
                                    collectionId: p.collectionId,
                                    preferredCountry: storage.currentLanguage.itunes,
                                    feedUrl: p.feedUrl
                                ) {
                                    let latestDate = eps
                                        .compactMap { ep -> (Date, String)? in
                                            guard let r = ep.releaseDate, let d = DateFormatterUtility.parse(r) else { return nil }
                                            return (d, DateFormatterUtility.formatISO8601(d))
                                        }
                                        .max(by: { $0.0 < $1.0 })?.1
                                    return (p.collectionId, latestDate)
                                }
                                return (p.collectionId, p.releaseDate)
                            }
                        }
                        var dict: [Int: String?] = [:]
                        for await (id, dateStr) in group {
                            dict[id] = dateStr
                        }
                        return dict
                    }
                    
                    for i in verifiedTrending.indices {
                        let id = verifiedTrending[i].collectionId
                        if let resolved = verifiedDates[id] {
                            verifiedTrending[i] = Podcast(
                                collectionId: verifiedTrending[i].collectionId,
                                artistName: verifiedTrending[i].artistName,
                                collectionName: verifiedTrending[i].collectionName,
                                artworkUrl100: verifiedTrending[i].artworkUrl100,
                                artworkUrl600: verifiedTrending[i].artworkUrl600,
                                feedUrl: verifiedTrending[i].feedUrl,
                                genres: verifiedTrending[i].genres,
                                primaryGenreName: verifiedTrending[i].primaryGenreName,
                                releaseDate: resolved,
                                country: verifiedTrending[i].country,
                                description: verifiedTrending[i].description,
                                source: verifiedTrending[i].source
                            )
                            if let validDate = resolved {
                                await MainActor.run {
                                    storage.podcastLatestEpisodeDates[id] = validDate
                                }
                            }
                        }
                    }
                }
                
                await MainActor.run {
                    self.trendingPodcasts = verifiedTrending
                    storage.cachedTrendingPodcasts = verifiedTrending
                    storage.lastTrendingFetchDate = Date()
                    storage.lastTrendingCategory = activeCategory
                    self.recomputeLists()
                    self.isLoading = false
                    self.isRefreshingDates = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.isRefreshingDates = false
                }
            }
        }
    
    private func refreshFavoriteEpisodeDates() async {
        let favs = storage.favoritePodcasts.filter { !LocalStorageManager.isAudiobookItem($0) && !LocalStorageManager.isKidsOrEnfantsItem($0) }
        guard !favs.isEmpty else { return }
        
        let fetched = (try? await APIService.shared.fetchEpisodesForPodcasts(favs, forceRefresh: true)) ?? []
        let existing = await MainActor.run { storage.cachedEpisodes }
        if fetched.isEmpty && !existing.isEmpty {
            await MainActor.run {
                self.recomputeLists()
            }
            return
        }
        let processed = LocalStorageManager.processRecentFavoriteEpisodes(fetched, from: favs, existingCached: existing)
        
        await MainActor.run {
            if !processed.allSorted.isEmpty {
                storage.updateLatestEpisodeDates(from: processed.allSorted)
            }
            var feed = processed.recentFeed
            if storage.settings.longestPerDayOnly {
                feed = storage.applyLongestPerDayFilter(feed)
            }
            if !feed.isEmpty {
                storage.cachedEpisodes = feed
                if !fetched.isEmpty {
                    storage.lastEpisodesFetchDate = Date()
                }
            }
            self.recomputeLists()
        }
    }
    
    private func getFilteredFavorites() -> [Podcast] {
        let filtered = storage.favoritePodcasts.filter { p in
            // 1. Never show audiobooks or kids/comptines items in Podcasts favorites
            if LocalStorageManager.isAudiobookItem(p) || LocalStorageManager.isKidsOrEnfantsItem(p) { return false }
            
            let genres = p.genres?.map { $0.lowercased() } ?? []
            let primary = p.primaryGenreName?.lowercased() ?? ""
            
            // 2. Filter true crime by active category
            let trueCrimeKeywords = ["true crime", "criminology", "criminologie", "faits divers"]
            let isTrueCrime = trueCrimeKeywords.contains { kw in genres.contains(where: { $0.contains(kw) }) || primary.contains(kw) }
            if activeCategory == "True Crime" {
                return isTrueCrime
            } else {
                return !isTrueCrime
            }
        }
        var parsedDates: [Int: Date] = [:]
        for p in filtered {
            if let d = DateFormatterUtility.parse(storage.effectiveReleaseDateString(for: p)) {
                parsedDates[p.collectionId] = d
            }
        }
        return filtered.sorted { a, b in
            let dateA = parsedDates[a.collectionId] ?? Date(timeIntervalSince1970: 0)
            let dateB = parsedDates[b.collectionId] ?? Date(timeIntervalSince1970: 0)
            if dateA != dateB {
                return dateA > dateB
            }
            return a.collectionName.localizedCaseInsensitiveCompare(b.collectionName) == .orderedAscending
        }
    }
    
    private func iconForCategory(_ key: String) -> String {
        switch key {
        case "All": return "sparkles"
        case "News": return "newspaper.fill"
        case "Comedy": return "face.smiling.fill"
        case "Technology": return "cpu.fill"
        case "Business": return "briefcase.fill"
        case "Society & Culture": return "globe.europe.africa.fill"
        case "True Crime": return "magnifyingglass"
        case "Health": return "heart.text.square.fill"
        case "Education": return "graduationcap.fill"
        case "History": return "building.columns.fill"
        case "Music": return "music.note"
        case "Science": return "atom"
        case "Sports": return "sportscourt.fill"
        default: return "mic.fill"
        }
    }
}

struct DiscoverPodcastCard: View {
    let podcast: Podcast
    var displayDateString: String? = nil
    let isFav: Bool
    let lang: LangCode
    @ObservedObject var storage = LocalStorageManager.shared
    
    private static var weekdayFormatters: [String: DateFormatter] = [:]
    private static var shortDateFormatters: [String: DateFormatter] = [:]
    
    private static func weekdayFormatter(for langCode: String) -> DateFormatter {
        if let existing = weekdayFormatters[langCode] {
            return existing
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: langCode)
        df.dateFormat = "EEEE"
        weekdayFormatters[langCode] = df
        return df
    }
    
    private static func shortDateFormatter(for langCode: String) -> DateFormatter {
        if let existing = shortDateFormatters[langCode] {
            return existing
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: langCode)
        df.dateFormat = "d MMM"
        shortDateFormatters[langCode] = df
        return df
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(url: URL(string: podcast.artworkUrl600 ?? podcast.artworkUrl100 ?? ""), maxPixelSize: 360) { image in
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.primary.opacity(0.07)
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                    .aspectRatio(1, contentMode: .fill)
                }
                .cornerRadius(18)
                .clipped()
                
                // Badges
                VStack(alignment: .trailing, spacing: 4) {
                    if let genre = podcast.primaryGenreName {
                        Text(genre)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(Color.black.opacity(0.65))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                    }
                    
                    if let badge = formatLastUpdated(dateString: displayDateString ?? podcast.releaseDate, lang: lang) {
                        HStack(spacing: 3) {
                            if badge.isToday {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 5, height: 5)
                            }
                            Image(systemName: "clock")
                                .font(.system(size: 7))
                            Text(badge.text)
                                .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(badge.color.opacity(0.88))
                        .cornerRadius(6)
                        .shadow(color: badge.isToday ? Color.red.opacity(0.4) : Color.clear, radius: 4)
                    }
                }
                .padding(6)
            }
            .overlay(
                Button(action: {
                    HapticManager.shared.trigger(.medium)
                    withAnimation {
                        storage.toggleFavoritePodcast(podcast)
                    }
                }) {
                    Image(systemName: storage.isFavoritePodcast(podcast.collectionId) ? "heart.fill" : "heart")
                        .font(.caption)
                        .foregroundColor(storage.isFavoritePodcast(podcast.collectionId) ? .red : .white)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .padding(8),
                alignment: .bottomTrailing
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.collectionName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(storage.primaryTextColor)
                    .lineLimit(1)
                
                Text(podcast.artistName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(storage.cardBackgroundColor)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(storage.cardBorderColor, lineWidth: 1)
        )
    }
    
    private func formatLastUpdated(dateString: String?, lang: LangCode) -> (text: String, color: Color, isToday: Bool)? {
        guard let date = DateFormatterUtility.parse(dateString) else { return nil }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return (lang == .fr ? "Aujourd'hui" : "Today", .red, true)
        } else if calendar.isDateInYesterday(date) {
            return (lang == .fr ? "Hier" : "Yesterday", .orange, false)
        } else {
            let startOfToday = calendar.startOfDay(for: Date())
            let startOfTarget = calendar.startOfDay(for: date)
            let diff = calendar.dateComponents([.day], from: startOfTarget, to: startOfToday).day ?? 7
            if diff > 0 && diff < 7 {
                let df = Self.weekdayFormatter(for: lang.rawValue)
                return (df.string(from: date).capitalized, .emeraldCustom, false)
            } else {
                let df = Self.shortDateFormatter(for: lang.rawValue)
                return (df.string(from: date), Color(red: 71/255, green: 85/255, blue: 105/255), false)
            }
        }
    }
}

struct WeatherLoadingView: View {
    @ObservedObject var weatherService = WeatherService.shared
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: storage.accentColorColor()))
            
            Text(storage.currentLanguage == .fr ? "Rafraîchissement des podcasts..." : "Refreshing podcasts...")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Text(storage.currentLanguage == .fr ? "MÉTÉO LOCALE" : "LOCAL WEATHER")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(storage.accentColorColor())
                    .tracking(1.5)
                
                HStack(spacing: 16) {
                    Image(systemName: weatherService.weatherIcon)
                        .font(.system(size: 40))
                        .foregroundColor(storage.accentColorColor())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(weatherService.cityName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(storage.primaryTextColor)
                        
                        Text(weatherService.weatherDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let temp = weatherService.temperature {
                    Text("\(Int(round(temp)))°C")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(storage.primaryTextColor)
                        .padding(.top, 4)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(storage.cardBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(storage.accentColorColor().opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            .padding(.horizontal, 32)
        }
        .onAppear {
            weatherService.requestLocation()
        }
    }
}
