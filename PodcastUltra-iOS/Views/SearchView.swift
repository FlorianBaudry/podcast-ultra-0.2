import SwiftUI

struct SearchView: View {
    var onClose: (() -> Void)? = nil
    
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    @State private var searchInput: String = ""
    @State private var results: UnifiedSearchResults? = nil
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var dragOffset: CGFloat = 0
    @FocusState private var isSearchFieldFocused: Bool
    
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
            .padding(.bottom, 10)
            
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.3)
                    .progressViewStyle(CircularProgressViewStyle(tint: storage.accentColorColor()))
                Spacer()
            } else if let searchResults = results {
                List {
                    // 1. Podcasts Section
                    if !searchResults.podcasts.isEmpty {
                        Section(header: Text("Podcasts").font(.headline).foregroundColor(storage.accentColorColor())) {
                            ForEach(searchResults.podcasts) { podcast in
                                NavigationLink(destination: EpisodeListView(podcast: podcast)) {
                                    HStack(spacing: 12) {
                                        CachedAsyncImage(url: URL(string: podcast.artworkUrl100 ?? ""), maxPixelSize: 160) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Color.primary.opacity(0.07)
                                        }
                                        .frame(width: 46, height: 46)
                                        .cornerRadius(10)
                                        .clipped()
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(podcast.collectionName)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(storage.primaryTextColor)
                                                .lineLimit(1)
                                            Text(podcast.artistName)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            HapticManager.shared.trigger(.medium)
                                            storage.toggleFavoritePodcast(podcast)
                                        }) {
                                            Image(systemName: storage.isFavoritePodcast(podcast.collectionId) ? "heart.fill" : "heart")
                                                .foregroundColor(storage.isFavoritePodcast(podcast.collectionId) ? .red : .secondary)
                                                .padding(6)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    isSearchFieldFocused = false
                                    onClose?()
                                })
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(storage.cardBorderColor)
                    }
                    
                    // 2. Radio Section
                    if !searchResults.radio.isEmpty {
                        Section(header: Text(Translations.shared.t("radio", storage.currentLanguage)).font(.headline).foregroundColor(storage.accentColorColor())) {
                            ForEach(searchResults.radio) { station in
                                RadioRow(station: station)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button {
                                            storage.toggleFavoriteRadioStation(station)
                                        } label: {
                                            Label(storage.isFavoriteRadio(station.id) ? "Unfav" : "Fav",
                                                  systemImage: storage.isFavoriteRadio(station.id) ? "heart.slash.fill" : "heart.fill")
                                        }
                                        .tint(storage.isFavoriteRadio(station.id) ? .red : .gray)
                                    }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(storage.cardBorderColor)
                    }
                    
                    // 3. Episodes Section
                    if !searchResults.episodes.isEmpty {
                        Section(header: Text(Translations.shared.t("episodes", storage.currentLanguage)).font(.headline).foregroundColor(storage.accentColorColor())) {
                            ForEach(searchResults.episodes) { episode in
                                EpisodeRowView(episode: episode)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button {
                                            audioPlayer.playEpisode(episode)
                                        } label: {
                                            Label("Play", systemImage: "play.fill")
                                        }
                                        .tint(storage.accentColorColor())
                                        
                                        Button {
                                            audioPlayer.addToQueue(episode)
                                        } label: {
                                            Label("Queue", systemImage: "plus.circle.fill")
                                        }
                                        .tint(.green)
                                    }
                                    .onTapGesture {
                                        isSearchFieldFocused = false
                                        audioPlayer.playEpisode(episode)
                                    }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(storage.cardBorderColor)
                    }
                }
                .listStyle(PlainListStyle())
                .scrollDismissesKeyboard(.immediately)
                .background(Color.clear)
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text(storage.currentLanguage == .fr ? "Tapez pour rechercher podcasts, radios ou épisodes" : "Type to search podcasts, radios or episodes")
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
        .onChange(of: searchInput) { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 2 {
                performSearch(term: trimmed, debounce: true)
            } else {
                searchTask?.cancel()
                self.results = nil
                self.isLoading = false
            }
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
