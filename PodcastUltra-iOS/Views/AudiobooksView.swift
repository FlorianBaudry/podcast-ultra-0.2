import SwiftUI

struct AudiobooksView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    @State private var books: [Podcast] = LocalStorageManager.shared.cachedAudiobooks
    @State private var isLoading = LocalStorageManager.shared.cachedAudiobooks.isEmpty
    @State private var activeCategory = LocalStorageManager.shared.lastAudiobooksCategory ?? "all"
    
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Book Categories Scroll list
                HStack(spacing: 12) {
                    // Manual Refresh Button
                    Button(action: {
                        HapticManager.shared.trigger(.light)
                        fetchBooks(force: true)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(storage.accentColorColor())
                            .frame(width: 36, height: 36)
                            .background(storage.subtleSurfaceColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.leading)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Translations.shared.getBookCatsList(storage.currentLanguage), id: \.key) { cat in
                                Button(action: {
                                    HapticManager.shared.trigger(.light)
                                    activeCategory = cat.key
                                    fetchBooks(force: true)
                                }) {
                                    Text(cat.value)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 14)
                                        .background(activeCategory == cat.key ? storage.accentColorColor() : storage.subtleSurfaceColor)
                                        .foregroundColor(activeCategory == cat.key ? .white : storage.primaryTextColor)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(activeCategory == cat.key ? Color.white.opacity(0.2) : storage.cardBorderColor, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.trailing)
                    }
                }
                
                // Favorite Audiobooks Section (Only appears in the Books tab!)
                if !storage.favoriteAudiobooks.isEmpty {
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
                                ForEach(storage.favoriteAudiobooks) { book in
                                    NavigationLink(destination: EpisodeListView(podcast: book, isAudiobook: true)) {
                                        BookCard(book: book)
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
                
                if isLoading {
                    VStack {
                        Spacer(minLength: 50)
                        ProgressView()
                            .scaleEffect(1.3)
                            .progressViewStyle(CircularProgressViewStyle(tint: storage.accentColorColor()))
                        Spacer(minLength: 50)
                    }
                    .frame(maxWidth: .infinity)
                } else if books.isEmpty {
                    VStack(spacing: 12) {
                        Spacer(minLength: 50)
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text(storage.currentLanguage == .fr ? "Aucun livre trouvé" : "No books found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 50)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    let validBooks = books.filter { book in
                        if storage.isFavoriteAudiobook(book.collectionId) { return false }
                        if let count = book.episodeCount, count <= 0 { return false }
                        if let millis = book.totalDurationMillis, millis < 30 * 60 * 1000 { return false }
                        return true
                    }
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(validBooks) { book in
                            NavigationLink(destination: EpisodeListView(podcast: book, isAudiobook: true)) {
                                BookCard(book: book)
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
        .onAppear {
            let validCached = storage.cachedAudiobooks.filter { book in
                guard let count = book.episodeCount, count > 0,
                      let millis = book.totalDurationMillis, millis >= 30 * 60 * 1000 else {
                    return false
                }
                return true
            }
            self.books = validCached
            if validCached.isEmpty || validCached.count != storage.cachedAudiobooks.count {
                fetchBooks(force: true)
            }
            enrichFavoriteAudiobooksIfNeeded()
        }
        .onChange(of: storage.currentLanguage) { _ in
            fetchBooks(force: true)
        }
    }
    
    private func enrichFavoriteAudiobooksIfNeeded() {
        let favsNeedingDuration = storage.favoriteAudiobooks.filter { $0.totalDurationMillis == nil }
        guard !favsNeedingDuration.isEmpty else { return }
        let country = storage.currentLanguage.itunes
        Task {
            let enriched = await APIService.shared.enrichAndFilterAudiobooks(storage.favoriteAudiobooks, country: country)
            if !enriched.isEmpty {
                await MainActor.run {
                    var updated = storage.favoriteAudiobooks
                    for item in enriched {
                        if let idx = updated.firstIndex(where: { $0.collectionId == item.collectionId }) {
                            updated[idx] = item
                        }
                    }
                    storage.favoriteAudiobooks = updated
                }
            }
        }
    }
    
    private func fetchBooks(force: Bool = false) {
        let categoryChanged = storage.lastAudiobooksCategory != activeCategory
        if !force && !categoryChanged && !books.isEmpty {
            return
        }
        
        isLoading = books.isEmpty
        Task {
            let results = await APIService.shared.getAudiobooks(
                country: storage.currentLanguage.itunes,
                categoryKey: activeCategory
            )
            
            await MainActor.run {
                self.books = results
                storage.cachedAudiobooks = results
                storage.lastAudiobooksCategory = activeCategory
                self.isLoading = false
            }
        }
    }
}

struct BookCard: View {
    let book: Podcast
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Book Cover (cached for smooth scrolling)
                CachedAsyncImage(url: URL(string: book.artworkUrl600 ?? book.artworkUrl100 ?? ""), maxPixelSize: 360) { image in
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.primary.opacity(0.07)
                        Image(systemName: "book.fill")
                            .font(.largeTitle)
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                    .aspectRatio(1, contentMode: .fill)
                }
                .cornerRadius(18)
                .clipped()
                
                // Top badges: Total Duration + Source
                HStack(spacing: 4) {
                    if let durationText = book.formattedTotalDuration {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 7, weight: .bold))
                            Text(durationText)
                                .font(.system(size: 8, weight: .black))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(storage.accentColorColor().opacity(0.9))
                        .cornerRadius(6)
                    }
                    
                    Spacer(minLength: 0)
                    
                    if let src = book.source {
                        Text(src.uppercased())
                            .font(.system(size: 7, weight: .black))
                            .foregroundColor(.white)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(Color.black.opacity(0.65))
                            .cornerRadius(4)
                    }
                }
                .padding(6)
            }
            .overlay(
                // Same Favorite heart button as Podcasts section
                Button(action: {
                    HapticManager.shared.trigger(.medium)
                    withAnimation {
                        storage.toggleFavoriteAudiobook(book)
                    }
                }) {
                    Image(systemName: storage.isFavoriteAudiobook(book.collectionId) ? "heart.fill" : "heart")
                        .font(.caption)
                        .foregroundColor(storage.isFavoriteAudiobook(book.collectionId) ? .red : .white)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.6))
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
                            Text("• \(epCount) \(epCount > 1 ? "ép." : "ép.")")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(storage.accentColorColor())
                    .padding(.top, 1)
                }
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
}
