import SwiftUI

struct SearchView: View {
    var onClose: (() -> Void)? = nil
    
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    enum SearchSourceFilter: String, CaseIterable, Identifiable {
        case all, podcasts, culture, enfants
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .all: return "sparkles"
            case .podcasts: return "mic.fill"
            case .culture: return "building.columns.fill"
            case .enfants: return "teddybear.fill"
            }
        }
        
        func title(for lang: LangCode) -> String {
            let isFr = lang == .fr
            switch self {
            case .all:
                return isFr ? "Tous" : "All"
            case .podcasts:
                return isFr ? "Podcasts" : "Podcasts"
            case .culture:
                return SubscriptionSection.culture.title(for: lang)
            case .enfants:
                return SubscriptionSection.enfants.title(for: lang)
            }
        }
    }
    
    @State private var searchInput: String = ""
    @State private var activeSourceFilter: SearchSourceFilter = .all
    @State private var results: UnifiedSearchResults? = nil
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var selectedPodcastForNavigation: Podcast? = nil
    @State private var selectedIsAudiobookForNavigation: Bool = false
    @State private var isNavigatingToEpisodeList: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    
    private static var shortDateFormatters: [String: DateFormatter] = [:]
    
    private static func shortDateFormatter(for langCode: String) -> DateFormatter {
        if let existing = shortDateFormatters[langCode] {
            return existing
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: langCode)
        df.dateStyle = .medium
        df.timeStyle = .none
        shortDateFormatters[langCode] = df
        return df
    }
    
    private func formattedLastEpisodeDate(for item: Podcast) -> String? {
        let rawDate = storage.effectiveReleaseDateString(for: item) ?? item.releaseDate
        guard let date = DateFormatterUtility.parse(rawDate) else { return nil }
        let df = Self.shortDateFormatter(for: storage.currentLanguage.rawValue)
        return df.string(from: date)
    }
    
    private func sortedByMostRecent(_ list: [Podcast]) -> [Podcast] {
        return list.sorted { a, b in
            let dateA = DateFormatterUtility.parse(storage.effectiveReleaseDateString(for: a) ?? a.releaseDate) ?? .distantPast
            let dateB = DateFormatterUtility.parse(storage.effectiveReleaseDateString(for: b) ?? b.releaseDate) ?? .distantPast
            if dateA != dateB {
                return dateA > dateB
            }
            return a.collectionName.localizedCaseInsensitiveCompare(b.collectionName) == .orderedAscending
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Search Bar Header (auto-focused immediately on open)
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(storage.accentColorColor())
                        .font(.system(size: 15, weight: .bold))
                    
                    TextField(Translations.shared.t("search_placeholder", storage.currentLanguage), text: $searchInput)
                        .focused($isSearchFieldFocused)
                        .foregroundColor(storage.primaryTextColor)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit {
                            performSearch(term: searchInput, debounce: false)
                        }
                    
                    if !searchInput.isEmpty {
                        Button(action: {
                            searchInput = ""
                            results = nil
                            isSearchFieldFocused = true
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .background(storage.subtleSurfaceColor)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(storage.accentColorColor().opacity(0.45), lineWidth: 1.5)
                )
                
                // Close top panel button (chevron.up - inverse of player's chevron.down)
                if let onClose = onClose {
                    Button(action: {
                        HapticManager.shared.trigger(.light)
                        isSearchFieldFocused = false
                        onClose()
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(storage.primaryTextColor)
                            .frame(width: 40, height: 40)
                            .background(storage.subtleSurfaceColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Source filter bar: Tous / Podcasts / Culture / Enfants
            if results != nil || !searchInput.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 6) {
                    ForEach(SearchSourceFilter.allCases) { filterOpt in
                        let isSelected = activeSourceFilter == filterOpt
                        let count = sourceCount(for: filterOpt)
                        Button(action: {
                            HapticManager.shared.trigger(.light)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeSourceFilter = filterOpt
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: filterOpt.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(filterOpt.title(for: storage.currentLanguage))
                                    .font(.system(size: 11, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                if let c = count, c > 0 {
                                    Text("\(c)")
                                        .font(.system(size: 9.5, weight: .black))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(isSelected ? Color.white.opacity(0.22) : storage.cardBackgroundColor)
                                        .clipShape(Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 6)
                            .background(isSelected ? storage.accentColorColor() : storage.subtleSurfaceColor)
                            .foregroundColor(isSelected ? .white : storage.primaryTextColor)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color.white.opacity(0.25) : storage.cardBorderColor, lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.3)
                    .progressViewStyle(CircularProgressViewStyle(tint: storage.accentColorColor()))
                Spacer()
            } else if let searchResults = results {
                let showPodcasts = (activeSourceFilter == .all || activeSourceFilter == .podcasts) && !searchResults.podcasts.isEmpty
                let showCulture = (activeSourceFilter == .all || activeSourceFilter == .culture) && !searchResults.culture.isEmpty
                let showEnfants = (activeSourceFilter == .all || activeSourceFilter == .enfants) && !searchResults.enfants.isEmpty
                
                if !showPodcasts && !showCulture && !showEnfants {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(storage.currentLanguage == .fr ? "Aucun résultat dans cette section" : "No results in this section")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        // 1. Podcasts Source Section (sorted by most recent first)
                        if showPodcasts {
                            Section(
                                header: HStack(spacing: 6) {
                                    Image(systemName: "mic.fill")
                                    Text(SearchSourceFilter.podcasts.title(for: storage.currentLanguage))
                                }
                                .font(.headline)
                                .foregroundColor(storage.accentColorColor())
                            ) {
                                ForEach(sortedByMostRecent(searchResults.podcasts)) { podcast in
                                    searchResultRow(
                                        item: podcast,
                                        sourceType: .podcasts
                                    )
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(storage.cardBorderColor)
                        }
                        
                        // 2. Culture Source Section (sorted by most recent first)
                        if showCulture {
                            Section(
                                header: HStack(spacing: 6) {
                                    Image(systemName: "building.columns.fill")
                                    Text(SearchSourceFilter.culture.title(for: storage.currentLanguage))
                                }
                                .font(.headline)
                                .foregroundColor(storage.accentColorColor())
                            ) {
                                ForEach(sortedByMostRecent(searchResults.culture)) { item in
                                    searchResultRow(
                                        item: item,
                                        sourceType: .culture
                                    )
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(storage.cardBorderColor)
                        }
                        
                        // 3. Enfant Source Section (sorted by most recent first)
                        if showEnfants {
                            Section(
                                header: HStack(spacing: 6) {
                                    Image(systemName: "teddybear.fill")
                                    Text(SearchSourceFilter.enfants.title(for: storage.currentLanguage))
                                }
                                .font(.headline)
                                .foregroundColor(storage.accentColorColor())
                            ) {
                                ForEach(sortedByMostRecent(searchResults.enfants)) { item in
                                    searchResultRow(
                                        item: item,
                                        sourceType: .enfants
                                    )
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(storage.cardBorderColor)
                        }
                    }
                    .listStyle(PlainListStyle())
                    .scrollDismissesKeyboard(.immediately)
                    .background(Color.clear)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text(
                        storage.currentLanguage == .fr
                        ? "Recherchez par source : Podcasts, Culture ou Enfants"
                        : "Search across Podcasts, Culture & Kids"
                    )
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            }
            
            // Bottom grab handle for pulling the top-down panel back up
            if let onClose = onClose {
                VStack(spacing: 6) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 42, height: 5)
                        .padding(.vertical, 10)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    isSearchFieldFocused = false
                    onClose()
                }
            }
        }
        .ipadMaxWidth()
        .background(
            storage.mainBackgroundColor
                .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
                .ignoresSafeArea()
        )
        .offset(y: min(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height < -60 {
                        isSearchFieldFocused = false
                        onClose?()
                    }
                    withAnimation(.spring()) {
                        dragOffset = 0
                    }
                }
        )
        .onAppear {
            // Focus immediately so keyboard opens as the top panel slides down
            isSearchFieldFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isSearchFieldFocused = true
            }
        }
        .onChange(of: searchInput) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 2 {
                performSearch(term: trimmed, debounce: true)
            } else {
                searchTask?.cancel()
                self.results = nil
                self.isLoading = false
            }
        }
        .navigationDestination(isPresented: $isNavigatingToEpisodeList) {
            if let podcast = selectedPodcastForNavigation {
                EpisodeListView(podcast: podcast, isAudiobook: selectedIsAudiobookForNavigation)
            }
        }
    }
    
    private func sourceCount(for filter: SearchSourceFilter) -> Int? {
        guard let res = results else { return nil }
        switch filter {
        case .all:
            return res.podcasts.count + res.culture.count + res.enfants.count
        case .podcasts:
            return res.podcasts.count
        case .culture:
            return res.culture.count
        case .enfants:
            return res.enfants.count
        }
    }
    
    @ViewBuilder
    private func searchResultRow(item: Podcast, sourceType: SearchSourceFilter) -> some View {
        let isAudiobookView = (sourceType != .podcasts)
        let isFavorited: Bool = {
            switch sourceType {
            case .podcasts, .all:
                return storage.isFavoritePodcast(item.collectionId)
            case .culture:
                return storage.isFavoriteSubscription(item.collectionId, in: .culture)
            case .enfants:
                return storage.isFavoriteSubscription(item.collectionId, in: .enfants)
            }
        }()
        let lastEpisodeDateText = formattedLastEpisodeDate(for: item)
        
        HStack(spacing: 12) {
            Button(action: {
                isSearchFieldFocused = false
                selectedPodcastForNavigation = item
                selectedIsAudiobookForNavigation = isAudiobookView
                isNavigatingToEpisodeList = true
            }) {
                HStack(spacing: 12) {
                    if sourceType == .culture {
                        SubscriptionArtworkView(book: item, section: .culture)
                            .frame(width: 48, height: 48)
                            .cornerRadius(10)
                            .clipped()
                    } else if sourceType == .enfants {
                        SubscriptionArtworkView(book: item, section: .enfants)
                            .frame(width: 48, height: 48)
                            .cornerRadius(10)
                            .clipped()
                    } else {
                        CachedAsyncImage(url: URL(string: item.artworkUrl100 ?? item.artworkUrl600 ?? ""), maxPixelSize: 160) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.primary.opacity(0.07)
                        }
                        .frame(width: 48, height: 48)
                        .cornerRadius(10)
                        .clipped()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(
                                sourceType == .podcasts
                                ? "PODCAST"
                                : (item.source?.uppercased() ?? sourceType.title(for: storage.currentLanguage).uppercased())
                            )
                            .font(.system(size: 8.5, weight: .black))
                            .foregroundColor(storage.accentColorColor())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(storage.accentColorColor().opacity(0.14))
                            .cornerRadius(5)
                            
                            if let dateStr = lastEpisodeDateText {
                                HStack(spacing: 3) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 8.5, weight: .bold))
                                    Text(dateStr)
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.secondary)
                            }
                            
                            if let durationText = item.formattedTotalDuration {
                                Text(durationText)
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text(item.collectionName)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(storage.primaryTextColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Text(item.artistName)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                HapticManager.shared.trigger(.medium)
                switch sourceType {
                case .podcasts, .all:
                    storage.toggleFavoritePodcast(item)
                case .culture:
                    storage.toggleFavoriteSubscription(item, section: .culture)
                case .enfants:
                    storage.toggleFavoriteSubscription(item, section: .enfants)
                }
            }) {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isFavorited ? .red : .secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func performSearch(term: String, debounce: Bool = false) {
        searchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            self.results = nil
            self.isLoading = false
            return
        }
        
        isLoading = true
        searchTask = Task {
            do {
                if debounce {
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                
                let data = try await APIService.shared.searchAll(
                    term: trimmed,
                    country: storage.currentLanguage.itunes,
                    langCode: storage.currentLanguage.rawValue
                )
                
                if !Task.isCancelled {
                    await MainActor.run {
                        self.results = data
                        self.isLoading = false
                    }
                }
            } catch is CancellationError {
                // Ignore
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
            }
        }
    }
}
