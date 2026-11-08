import SwiftUI

struct RadioView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    @State private var popularStations: [RadioStation] = LocalStorageManager.shared.cachedRadioStations
    @State private var searchResults: [RadioStation] = []
    @State private var searchInput: String = ""
    @State private var isLoading = LocalStorageManager.shared.cachedRadioStations.isEmpty
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar (manual reload button removed as requested)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(storage.currentLanguage == .fr ? "Chercher des radios..." : "Search radio stations...", text: $searchInput)
                    .foregroundColor(storage.primaryTextColor)
                    .submitLabel(.search)
                    .onSubmit {
                        performSearch()
                    }
                if !searchInput.isEmpty {
                    Button(action: {
                        searchInput = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(storage.subtleSurfaceColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(storage.cardBorderColor, lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.3)
                    .progressViewStyle(CircularProgressViewStyle(tint: storage.accentColorColor()))
                Spacer()
            } else {
                List {
                    // 1. Horizontal Favorites Carousel (Same style as Podcasts & Books sections, only in Radio tab!)
                    let favoriteList = getFavoriteStations()
                    if !favoriteList.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(.red)
                                    Text(Translations.shared.t("your_favorites", storage.currentLanguage))
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(storage.primaryTextColor)
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(favoriteList) { station in
                                            RadioFavoriteCard(station: station)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    
                    // 2. Search results section if active
                    if !searchResults.isEmpty {
                        Section(header: Text(storage.currentLanguage == .fr ? "Résultats" : "Results").foregroundColor(.secondary)) {
                            ForEach(searchResults) { station in
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
                    
                    // 3. Stations list (without "Radio Mondiale" header text)
                    Section {
                        ForEach(popularStations) { station in
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
                .listStyle(PlainListStyle())
                .background(Color.clear)
                .refreshable {
                    await fetchPopularStationsAsync(force: true)
                }
            }
        }
        .ipadMaxWidth()
        .padding(.bottom, 80)
        .onAppear {
            self.popularStations = storage.cachedRadioStations
            let needsAdFreeUpgrade = popularStations.contains(where: { $0.url.contains("adwz") || $0.url.contains("streamer-01.rtl.fr") || $0.url.contains("franceinter-midfi") })
            if popularStations.isEmpty || needsAdFreeUpgrade {
                fetchPopularStations(force: true)
            }
        }
        .onChange(of: storage.currentLanguage) { _, _ in
            self.popularStations = []
            fetchPopularStations(force: true)
        }
    }
    
    private func fetchPopularStations(force: Bool = false) {
        Task {
            await fetchPopularStationsAsync(force: force)
        }
    }
    
    private func fetchPopularStationsAsync(force: Bool = false) async {
        if !force && !popularStations.isEmpty {
            return
        }
        
        await MainActor.run {
            isLoading = popularStations.isEmpty
        }
        do {
            let results = try await APIService.shared.getRadioStations(
                radioSearch: storage.currentLanguage.radioSearch,
                langCode: storage.currentLanguage.rawValue
            )
            await MainActor.run {
                self.popularStations = results
                storage.cachedRadioStations = results
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func performSearch() {
        guard !searchInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        Task {
            do {
                let results = try await APIService.shared.searchRadioStations(term: searchInput)
                await MainActor.run {
                    self.searchResults = results
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func getFavoriteStations() -> [RadioStation] {
        var favs: [RadioStation] = []
        var seen = Set<String>()
        
        for station in storage.favoriteRadioStations where !station.url.isEmpty {
            favs.append(station)
            seen.insert(station.id)
        }
        
        for stationId in storage.favoriteRadios where !seen.contains(stationId) {
            if let matched = popularStations.first(where: { $0.id == stationId }) {
                favs.append(matched)
                seen.insert(stationId)
            } else if let matched = searchResults.first(where: { $0.id == stationId }) {
                favs.append(matched)
                seen.insert(stationId)
            }
        }
        return favs
    }
}

struct RadioFavoriteCard: View {
    let station: RadioStation
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        let isCurrent = audioPlayer.currentRadio?.id == station.id
        Button(action: {
            HapticManager.shared.trigger(.light)
            audioPlayer.playRadio(station)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    RadioStationArtworkView(station: station, size: 118, cornerRadius: 18)
                    
                    Button(action: {
                        HapticManager.shared.trigger(.medium)
                        withAnimation {
                            storage.toggleFavoriteRadioStation(station)
                        }
                    }) {
                        Image(systemName: storage.isFavoriteRadio(station.id) ? "heart.fill" : "heart")
                            .font(.caption)
                            .foregroundColor(storage.isFavoriteRadio(station.id) ? .red : .white)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding(6)
                }
                
                Text(station.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isCurrent ? storage.accentColorColor() : storage.primaryTextColor)
                    .lineLimit(1)
                
                Text(station.country ?? "Radio")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 118)
            .padding(10)
            .background(storage.cardBackgroundColor)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isCurrent ? storage.accentColorColor() : storage.cardBorderColor, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct RadioRow: View {
    let station: RadioStation
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                HapticManager.shared.trigger(.light)
                audioPlayer.playRadio(station)
            }) {
                HStack(spacing: 12) {
                    RadioStationArtworkView(station: station, size: 44, cornerRadius: 10)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(storage.primaryTextColor)
                            .lineLimit(1)
                        
                        HStack {
                            if let country = station.country, !country.isEmpty {
                                Text(country)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            if let clickcount = station.clickcount, clickcount > 0 {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(clickcount) clicks")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Favorite Heart Button (Same direct favorite capability as Podcasts!)
            Button(action: {
                HapticManager.shared.trigger(.medium)
                withAnimation {
                    storage.toggleFavoriteRadioStation(station)
                }
            }) {
                Image(systemName: storage.isFavoriteRadio(station.id) ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(storage.isFavoriteRadio(station.id) ? .red : .secondary)
                    .frame(width: 34, height: 34)
                    .background(storage.subtleSurfaceColor)
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Play indicator
            Button(action: {
                HapticManager.shared.trigger(.light)
                audioPlayer.playRadio(station)
            }) {
                let isCurrent = audioPlayer.currentRadio?.id == station.id
                if isCurrent {
                    if audioPlayer.isPlaying {
                        PlayingEqualizerBars(color: storage.accentColorColor())
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "play.fill")
                            .foregroundColor(storage.accentColorColor())
                            .frame(width: 24, height: 24)
                    }
                } else {
                    Image(systemName: "play.circle")
                        .foregroundColor(.secondary.opacity(0.6))
                        .font(.title3)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}
