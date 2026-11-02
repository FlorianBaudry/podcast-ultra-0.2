import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    @State private var activeTab: LibraryTab = .history
    
    enum LibraryTab: String, CaseIterable, Identifiable {
        case history, playlists
        var id: String { rawValue }
        
        func label(lang: LangCode) -> String {
            switch self {
            case .history: return Translations.shared.t("recent", lang)
            case .playlists: return Translations.shared.t("playlists", lang)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(Translations.shared.t("library", storage.currentLanguage))
                    .font(.system(size: 30, weight: .black))
                
                Spacer()
                
                Picker("", selection: $activeTab) {
                    ForEach(LibraryTab.allCases) { tab in
                        Text(tab.label(lang: storage.currentLanguage)).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 180)
            }
            .padding()
            
            if activeTab == .history {
                HistorySectionView()
            } else {
                PlaylistsSectionView()
            }
        }
        .ipadMaxWidth()
        .padding(.bottom, 80) // Space for player
    }
}

struct HistorySectionView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        Group {
            if storage.history.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text(storage.currentLanguage == .fr ? "Historique vide" : "History is empty")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(storage.currentLanguage == .fr ? "Vos épisodes écoutés s'afficheront ici." : "Episodes you listen to will appear here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(storage.history) { episode in
                    EpisodeRowView(episode: episode)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(storage.cardBorderColor)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    storage.history.removeAll(where: { $0.trackId == episode.trackId })
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onTapGesture {
                            audioPlayer.playEpisode(episode)
                        }
                }
                .listStyle(PlainListStyle())
                .background(Color.clear)
            }
        }
    }
}

struct PlaylistsSectionView: View {
    @ObservedObject var storage = LocalStorageManager.shared
    @State private var showingCreateAlert = false
    @State private var newPlaylistName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: {
                    showingCreateAlert = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text(Translations.shared.t("new_playlist", storage.currentLanguage))
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(storage.accentColorColor().opacity(0.15))
                    .foregroundColor(storage.accentColorColor())
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            
            if storage.playlists.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text(Translations.shared.t("my_playlists", storage.currentLanguage))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(storage.playlists) { playlist in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.name)
                                    .font(.headline)
                                    .foregroundColor(storage.primaryTextColor)
                                Text("\(playlist.episodeIds.count) Épisodes")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(storage.cardBorderColor)
                    }
                    .onDelete { indices in
                        storage.playlists.remove(atOffsets: indices)
                    }
                }
                .listStyle(PlainListStyle())
                .background(Color.clear)
            }
        }
        .sheet(isPresented: $showingCreateAlert) {
            VStack(spacing: 20) {
                Text(storage.currentLanguage == .fr ? "Nouvelle Liste" : "New Playlist")
                    .font(.headline)
                    .padding(.top)
                
                TextField(storage.currentLanguage == .fr ? "Nom de la liste" : "Playlist name", text: $newPlaylistName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                HStack(spacing: 20) {
                    Button(storage.currentLanguage == .fr ? "Annuler" : "Cancel") {
                        newPlaylistName = ""
                        showingCreateAlert = false
                    }
                    .foregroundColor(.secondary)
                    
                    Button(storage.currentLanguage == .fr ? "Créer" : "Create") {
                        if !newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty {
                            let pl = PlaylistModel(name: newPlaylistName, episodeIds: [])
                            storage.playlists.append(pl)
                            newPlaylistName = ""
                            showingCreateAlert = false
                        }
                    }
                    .foregroundColor(storage.accentColorColor())
                }
                .padding(.bottom)
            }
            .presentationDetents([.fraction(0.3)])
        }
    }
}
