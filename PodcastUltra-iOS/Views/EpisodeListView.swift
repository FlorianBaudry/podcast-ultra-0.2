import SwiftUI

struct EpisodeListView: View {
    let podcast: Podcast
    var isAudiobook: Bool = false

    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    @State private var episodes: [Episode] = []
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

    private var effectiveIsAudiobook: Bool {
        isAudiobook || LocalStorageManager.isAudiobookItem(podcast)
    }
    
    private var computedTotalDurationText: String? {
        let sumMillis = episodes.reduce(0) { $0 + max(0, $1.trackTimeMillis ?? 0) }
        let millis = sumMillis > 0 ? sumMillis : (podcast.totalDurationMillis ?? 0)
        guard millis > 0 else { return nil }
        let totalMinutes = max(1, millis / 60000)
        let hours = totalMinutes / 60
        let remMinutes = totalMinutes % 60
        if hours > 0 {
            return remMinutes > 0 ? "\(hours)h \(remMinutes)m" : "\(hours)h"
        } else {
            return "\(totalMinutes) min"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Area
                VStack(alignment: .center, spacing: 16) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if effectiveIsAudiobook {
                                SubscriptionArtworkView(book: podcast, section: storage.inferSubscriptionSection(for: podcast))
                            } else {
                                CachedAsyncImage(url: URL(string: podcast.artworkUrl600 ?? podcast.artworkUrl100 ?? ""), maxPixelSize: 400) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    ZStack {
                                        Color.primary.opacity(0.07)
                                        Image(systemName: "music.note")
                                            .font(.system(size: 50))
                                            .foregroundColor(.secondary.opacity(0.3))
                                    }
                                }
                            }
                        }
                        .frame(width: 200, height: 200)
                        .cornerRadius(20)
                        .clipped()
                        .shadow(color: Color.black.opacity(0.25), radius: 10, y: 5)
                        
                        // Heart button overlay on cover (same as Podcasts & Books cards)
                        Button(action: {
                            HapticManager.shared.trigger(.medium)
                            withAnimation {
                                if effectiveIsAudiobook {
                                    storage.toggleFavoriteAudiobook(podcast)
                                } else {
                                    storage.toggleFavoritePodcast(podcast)
                                }
                            }
                        }) {
                            let isFav = effectiveIsAudiobook
                                ? storage.isFavoriteAudiobook(podcast.collectionId)
                                : storage.isFavoritePodcast(podcast.collectionId)
                            Image(systemName: isFav ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(isFav ? .red : .white)
                                .frame(width: 38, height: 38)
                                .background(Color.black.opacity(0.65))
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .padding(10)
                    }
                    
                    VStack(spacing: 6) {
                        Text(podcast.collectionName)
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(storage.primaryTextColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Text(podcast.artistName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        if let totalDur = computedTotalDurationText {
                            HStack(spacing: 5) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(storage.currentLanguage == .fr ? "Durée totale : \(totalDur)" : "Total duration: \(totalDur)")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(storage.accentColorColor())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(storage.subtleSurfaceColor)
                            .cornerRadius(10)
                            .padding(.top, 2)
                        }
                        
                        // In-Progress Resume ("Reprendre") & Cancel ("Annuler") buttons
                        if let inProg = storage.getInProgressState(for: podcast) {
                            HStack(spacing: 10) {
                                Button(action: {
                                    HapticManager.shared.trigger(.medium)
                                    audioPlayer.resumeSubscription(podcast)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 12, weight: .black))
                                        Text(storage.currentLanguage == .fr ? "Reprendre (\(inProg.formattedPosition))" : "Resume (\(inProg.formattedPosition))")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.vertical, 9)
                                    .padding(.horizontal, 18)
                                    .background(storage.accentColorColor())
                                    .cornerRadius(12)
                                }
                                
                                Button(action: {
                                    HapticManager.shared.trigger(.light)
                                    withAnimation {
                                        storage.cancelInProgress(for: podcast)
                                    }
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12, weight: .bold))
                                        Text(storage.currentLanguage == .fr ? "Annuler" : "Cancel")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 9)
                                    .padding(.horizontal, 14)
                                    .background(storage.subtleSurfaceColor)
                                    .cornerRadius(12)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    // Only show "S'abonner" button for Podcasts (NOT for Audiobooks, which use the Favorite heart instead!)
                    if !effectiveIsAudiobook {
                        let isSubbed = storage.isFavoritePodcast(podcast.collectionId)
                        Button(action: {
                            HapticManager.shared.trigger(.medium)
                            withAnimation {
                                storage.toggleFavoritePodcast(podcast)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: isSubbed ? "checkmark" : "plus")
                                Text(isSubbed ? Translations.shared.t("subscribed", storage.currentLanguage) : Translations.shared.t("subscribe", storage.currentLanguage))
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isSubbed ? .secondary : .white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 24)
                            .background(isSubbed ? storage.subtleSurfaceColor : storage.accentColorColor())
                            .cornerRadius(12)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top)
                
                // Description Section
                if let desc = podcast.description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(storage.currentLanguage == .fr ? "À Propos" : "About")
                            .font(.headline)
                            .foregroundColor(storage.primaryTextColor)
                        Text(desc)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                    .background(storage.cardBorderColor)
                    .padding(.horizontal)
                
                // Episodes Header
                HStack {
                    Text(Translations.shared.t("episodes", storage.currentLanguage))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(storage.primaryTextColor)
                    Spacer()
                    Text("\(episodes.count) total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // Episode List
                if isLoading {
                    VStack {
                        Spacer(minLength: 50)
                        ProgressView()
                            .scaleEffect(1.2)
                            .progressViewStyle(CircularProgressViewStyle(tint: storage.accentColorColor()))
                        Spacer(minLength: 50)
                    }
                    .frame(maxWidth: .infinity)
                } else if episodes.isEmpty {
                    VStack {
                        Spacer(minLength: 50)
                        Text(storage.currentLanguage == .fr ? "Aucun épisode" : "No episodes found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 50)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(episodes) { episode in
                            EpisodeRowView(episode: episode)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    audioPlayer.playEpisode(episode)
                                }
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
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        storage.togglePlayedEpisode(episode.trackId)
                                    } label: {
                                        Label(storage.isPlayedEpisode(episode.trackId) ? "Unplay" : "Play", 
                                              systemImage: storage.isPlayedEpisode(episode.trackId) ? "gobackward" : "checkmark.circle.fill")
                                    }
                                    .tint(.blue)
                                }
                            
                            Divider()
                                .background(storage.cardBorderColor)
                                .padding(.leading, 74)
                                .padding(.trailing, 16)
                        }
                    }
                }
            }
            .ipadMaxWidth()
            .padding(.bottom, 100)
        }
        .background(storage.mainBackgroundColor.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchEpisodes()
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text(alertMessage))
        }
    }

    private func fetchEpisodes() {
        guard episodes.isEmpty else { return }
        isLoading = true
        Task {
            do {
                let result = try await APIService.shared.getPodcastEpisodes(collectionId: podcast.collectionId, preferredCountry: storage.currentLanguage.itunes, feedUrl: podcast.feedUrl)
                await MainActor.run {
                    self.episodes = result
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}
