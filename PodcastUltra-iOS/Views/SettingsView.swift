import SwiftUI
import AuthenticationServices
import UniformTypeIdentifiers
import CryptoKit

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var jsonText: String
    
    init(jsonText: String = "{}") {
        self.jsonText = jsonText
    }
    
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            self.jsonText = text
        } else {
            self.jsonText = "{}"
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = jsonText.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    @ObservedObject var watchSession = WatchSessionManager.shared
    
    @State private var showingSpotifyAlert = false
    @State private var spotifyAlertTitle = "Spotify"
    @State private var spotifyAlertMessage = ""
    @State private var spotifyBtnText = ""
    @State private var isSpotifySyncing = false
    @State private var spotifyQuickQuery = ""
    @State private var isQuickImporting = false
    
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var backupDocument = BackupFileDocument()
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showingBackupAlert = false
    @State private var showingWatchCompanion = false
    @State private var isWatchSectionExpanded = false
    @State private var isHelpSectionExpanded = false
    @State private var expandedHelpTopicId: String? = nil
    @State private var isKnowledgeWeatherExpanded = false
    @State private var isSpotifySectionExpanded = false
    
    private let speeds = [0.5, 0.8, 1.0, 1.2, 1.5, 1.8, 2.0, 2.5]
    private let accentColors = ["indigo", "blue", "cyan", "emerald", "mint", "amber", "gold", "coral", "rose", "violet"]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text(Translations.shared.t("settings", storage.currentLanguage))
                    .font(.system(size: 30, weight: .black))
                    .foregroundColor(storage.primaryTextColor)
                    .padding(.horizontal)
                
                VStack(spacing: 16) {
                    // 1. Language Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Label(Translations.shared.t("language", storage.currentLanguage), systemImage: "globe")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $storage.currentLanguage) {
                            ForEach(LangCode.allCases) { lang in
                                Text(lang.name).tag(lang)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity)
                        .padding(6)
                        .background(storage.subtleSurfaceColor)
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(storage.cardBackgroundColor)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
                    
                    // 2. Accent Colors (10 high-contrast choices)
                    VStack(alignment: .leading, spacing: 10) {
                        Label(Translations.shared.t("accent_color", storage.currentLanguage), systemImage: "paintpalette")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                            ForEach(accentColors, id: \.self) { color in
                                Circle()
                                    .fill(getColorForName(color))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle()
                                            .stroke(storage.primaryTextColor, lineWidth: storage.settings.accentColor == color ? 2.5 : 0)
                                    )
                                    .scaleEffect(storage.settings.accentColor == color ? 1.15 : 1.0)
                                    .opacity(storage.settings.accentColor == color ? 1.0 : 0.72)
                                    .onTapGesture {
                                        HapticManager.shared.trigger(.light)
                                        withAnimation {
                                            storage.settings.accentColor = color
                                        }
                                    }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(storage.cardBackgroundColor)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
                    
                    // 3. Themes (8 readable themes with guaranteed contrast)
                    VStack(alignment: .leading, spacing: 10) {
                        Label(Translations.shared.t("theme", storage.currentLanguage), systemImage: "sun.max")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        let isFr = storage.currentLanguage == .fr
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ThemeButton(
                                id: "light",
                                label: Translations.shared.t("theme_light", storage.currentLanguage),
                                icon: "sun.max.fill",
                                previewColor: Color(red: 248/255, green: 250/255, blue: 252/255)
                            )
                            ThemeButton(
                                id: "cream",
                                label: isFr ? "Sépia" : "Cream",
                                icon: "book.fill",
                                previewColor: Color(red: 249/255, green: 245/255, blue: 235/255)
                            )
                            ThemeButton(
                                id: "dark",
                                label: Translations.shared.t("theme_dark", storage.currentLanguage),
                                icon: "moon.fill",
                                previewColor: Color(red: 15/255, green: 23/255, blue: 42/255)
                            )
                            ThemeButton(
                                id: "black",
                                label: Translations.shared.t("theme_black", storage.currentLanguage),
                                icon: "circle.fill",
                                previewColor: Color.black
                            )
                            ThemeButton(
                                id: "midnight",
                                label: isFr ? "Bleu Nuit" : "Midnight",
                                icon: "sparkles",
                                previewColor: Color(red: 10/255, green: 20/255, blue: 45/255)
                            )
                            ThemeButton(
                                id: "ocean",
                                label: isFr ? "Océan" : "Ocean",
                                icon: "water.waves",
                                previewColor: Color(red: 8/255, green: 29/255, blue: 38/255)
                            )
                            ThemeButton(
                                id: "forest",
                                label: isFr ? "Forêt" : "Forest",
                                icon: "leaf.fill",
                                previewColor: Color(red: 11/255, green: 28/255, blue: 22/255)
                            )
                            ThemeButton(
                                id: "bordeaux",
                                label: isFr ? "Bordeaux" : "Bordeaux",
                                icon: "drop.fill",
                                previewColor: Color(red: 32/255, green: 12/255, blue: 22/255)
                            )
                        }
                    }
                    .padding()
                    .background(storage.cardBackgroundColor)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
                    
                    // 4. Playback speed
                    VStack(alignment: .leading, spacing: 10) {
                        Label(Translations.shared.t("playback_speed", storage.currentLanguage), systemImage: "speedometer")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(speeds, id: \.self) { speed in
                                Button(action: {
                                    storage.settings.playbackSpeed = speed
                                }) {
                                    Text("\(String(format: "%.1f", speed))x")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(storage.settings.playbackSpeed == speed ? .white : storage.primaryTextColor)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(storage.settings.playbackSpeed == speed ? storage.accentColorColor() : storage.subtleSurfaceColor)
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(storage.cardBackgroundColor)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
                    
                    // 5. General toggles
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: $storage.settings.skipIntro) {
                            Text(Translations.shared.t("skip_intro", storage.currentLanguage))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(storage.primaryTextColor)
                        }
                        .tint(storage.accentColorColor())
                        
                        Toggle(isOn: $storage.settings.longestPerDayOnly) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(storage.currentLanguage == .fr ? "Épisode le plus long par jour" : "Longest episode per day only")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(storage.primaryTextColor)
                                Text(storage.currentLanguage == .fr ? "Filtre les clips courts quotidiens" : "Filters short daily clips")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tint(storage.accentColorColor())
                    }
                    .padding()
                    .background(storage.cardBackgroundColor)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
                    
                    // 6. Spotify Quick Import (Minimized by default, no Full Account Sync)
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: {
                            HapticManager.shared.trigger(.light)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                isSpotifySectionExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green.opacity(0.16))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "music.note")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.green)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Spotify")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(storage.primaryTextColor)
                                    Text(storage.currentLanguage == .fr ? "Import rapide de podcasts par lien ou nom (touchez pour afficher)" : "Quick podcast import by URL or name (tap to expand)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Image(systemName: isSpotifySectionExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(storage.accentColorColor())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if isSpotifySectionExpanded {
                            Divider()
                                .background(storage.cardBorderColor)
                                .padding(.vertical, 2)
                            
                            Text(Translations.shared.t("spotify_desc", storage.currentLanguage))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Instant import via Spotify Show Link(s) or Podcast Name(s)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(storage.currentLanguage == .fr ? "Import rapide (Lien Spotify ou noms de podcasts)" : "Quick Import (Spotify Show URL or podcast names)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(storage.primaryTextColor)
                                
                                HStack(spacing: 8) {
                                    TextField(
                                        storage.currentLanguage == .fr ? "Collez un lien open.spotify.com/show/... ou nom" : "Paste open.spotify.com/show/... link or name",
                                        text: $spotifyQuickQuery
                                    )
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .padding(10)
                                    .background(storage.subtleSurfaceColor)
                                    .cornerRadius(10)
                                    .foregroundColor(storage.primaryTextColor)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    
                                    Button(action: triggerQuickSpotifyImport) {
                                        if isQuickImporting {
                                            ProgressView()
                                                .tint(.white)
                                                .frame(width: 24, height: 24)
                                        } else {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.green)
                                    .cornerRadius(10)
                                    .disabled(isQuickImporting || spotifyQuickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                                
                                Text(
                                    storage.currentLanguage == .fr
                                    ? "Astuce : collez directement un ou plusieurs liens Spotify (séparés par des virgules) ou titres de podcasts pour les ajouter à vos favoris sans configuration."
                                    : "Tip: paste one or more Spotify links (comma-separated) or podcast titles to add them to your favorites without setup."
                                )
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .background(storage.cardBackgroundColor)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
                    
                    // 7. Backup & Restore (Export / Import)
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            storage.currentLanguage == .fr ? "Sauvegarde & Restauration" : "Backup & Restore",
                            systemImage: "externaldrive.badge.icloud"
                        )
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        
                        Text(
                            storage.currentLanguage == .fr
                            ? "Exportez vos réglages, favoris, options sélectionnées et historique pour les conserver entre deux versions majeures."
                            : "Export your settings, favorites, selected options and history to keep them across major versions."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                if let json = storage.exportBackupJSONString() {
                                    backupDocument = BackupFileDocument(jsonText: json)
                                    isExportingBackup = true
                                } else {
                                    backupAlertTitle = storage.currentLanguage == .fr ? "Erreur" : "Error"
                                    backupAlertMessage = storage.currentLanguage == .fr ? "Impossible de préparer la sauvegarde." : "Could not prepare backup."
                                    showingBackupAlert = true
                                }
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text(storage.currentLanguage == .fr ? "Exporter" : "Export")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(storage.accentColorColor())
                                .cornerRadius(12)
                            }
                            
                            Button(action: {
                                isImportingBackup = true
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text(storage.currentLanguage == .fr ? "Importer" : "Import")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(storage.primaryTextColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(storage.subtleSurfaceColor)
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding()
                    .background(storage.cardBackgroundColor)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
                    
                    // 8. 5 Dernières Informations de Connaissance (Savoirs récents — minimisé par défaut)
                    KnowledgeAndWeeklyWeatherSettingsSection(isExpanded: $isKnowledgeWeatherExpanded)
                    
                    // 9. Discrete Collapsible Apple Watch Configuration & Companion
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: {
                            HapticManager.shared.trigger(.light)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                isWatchSectionExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(storage.accentColorColor().opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "applewatch")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(storage.accentColorColor())
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Apple Watch")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(storage.primaryTextColor)
                                    Text(storage.currentLanguage == .fr ? "Configuration & synchronisation montre (touchez pour afficher)" : "Watch configuration & sync (tap to expand)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Image(systemName: isWatchSectionExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(storage.accentColorColor())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if isWatchSectionExpanded {
                            Divider()
                                .background(storage.cardBorderColor)
                                .padding(.vertical, 2)
                            
                            Text(
                                storage.currentLanguage == .fr
                                ? "Synchronisez vos derniers épisodes et radios favorites avec l'application Apple Watch ou ouvrez l'aperçu Apple Watch."
                                : "Sync your latest episodes and favorite radios with the Apple Watch app or open the Apple Watch companion interface."
                            )
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            
                            HStack(spacing: 10) {
                                Button(action: {
                                    HapticManager.shared.trigger(.medium)
                                    watchSession.syncLatestPodcastsToWatch()
                                }) {
                                    HStack(spacing: 6) {
                                        if watchSession.isSyncingPodcasts {
                                            ProgressView()
                                                .scaleEffect(0.75)
                                        } else {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                        }
                                        Text(
                                            watchSession.isSyncingPodcasts
                                            ? (storage.currentLanguage == .fr ? "Synchronisation..." : "Syncing...")
                                            : (storage.currentLanguage == .fr ? "Synchroniser" : "Sync Watch")
                                        )
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(storage.primaryTextColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(storage.subtleSurfaceColor)
                                    .cornerRadius(10)
                                }
                                .disabled(watchSession.isSyncingPodcasts)
                                
                                Button(action: {
                                    HapticManager.shared.trigger(.light)
                                    showingWatchCompanion = true
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "applewatch.watchface")
                                        Text(storage.currentLanguage == .fr ? "Configurer / Aperçu" : "Configure / Preview")
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(storage.accentColorColor())
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(storage.cardBackgroundColor)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
                    
                    // 9. Compact Expandable App Guide & Explanations (Onglets, Fonctions, Widget, Watch)
                    AppGuideSettingsSection(
                        isSectionExpanded: $isHelpSectionExpanded,
                        expandedTopicId: $expandedHelpTopicId
                    )
                    
                    // 10. Dangerous Zone
                    Button(action: {
                        storage.clearAllData()
                    }) {
                        Text(Translations.shared.t("clear_cache", storage.currentLanguage))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .padding(.top, 6)
                    
                    // 11. Dedicated 5-Day Weather Forecast & Ephemeris Section at the Very Bottom
                    WeeklyWeatherSettingsSection()
                }
                .padding(.horizontal)
            }
            .ipadMaxWidth()
            .padding(.bottom, 100)
        }
        .background(storage.mainBackgroundColor.ignoresSafeArea())
        .preferredColorScheme(storage.isLightTheme ? .light : .dark)
        .sheet(isPresented: $showingWatchCompanion) {
            WatchCompanionView()
                .environmentObject(audioPlayer)
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "podcast-ultra-backup-\(DateFormatterUtility.formatKey(Date())).json"
        ) { result in
            switch result {
            case .success:
                backupAlertTitle = storage.currentLanguage == .fr ? "Export réussi" : "Export Successful"
                backupAlertMessage = storage.currentLanguage == .fr
                    ? "Vos réglages et favoris ont bien été exportés."
                    : "Your settings and favorites have been exported."
                showingBackupAlert = true
            case .failure(let error):
                backupAlertTitle = storage.currentLanguage == .fr ? "Erreur d'export" : "Export Error"
                backupAlertMessage = error.localizedDescription
                showingBackupAlert = true
            }
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                if let data = try? Data(contentsOf: url), storage.importBackupData(data) {
                    backupAlertTitle = storage.currentLanguage == .fr ? "Restauration réussie" : "Restore Successful"
                    backupAlertMessage = storage.currentLanguage == .fr
                        ? "Vos réglages, favoris et options ont été restaurés avec succès."
                        : "Your settings, favorites and options have been restored."
                } else {
                    backupAlertTitle = storage.currentLanguage == .fr ? "Fichier invalide" : "Invalid File"
                    backupAlertMessage = storage.currentLanguage == .fr
                        ? "Le fichier sélectionné n'est pas une sauvegarde Podcast Ultra valide."
                        : "The selected file is not a valid Podcast Ultra backup."
                }
                showingBackupAlert = true
            case .failure(let error):
                backupAlertTitle = storage.currentLanguage == .fr ? "Erreur d'import" : "Import Error"
                backupAlertMessage = error.localizedDescription
                showingBackupAlert = true
            }
        }
        .alert(backupAlertTitle, isPresented: $showingBackupAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(backupAlertMessage)
        }
        .alert(spotifyAlertTitle, isPresented: $showingSpotifyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(spotifyAlertMessage)
        }
        .onAppear {
            spotifyBtnText = Translations.shared.t("spotify_connect", storage.currentLanguage)
        }
    }
    
    private func getColorForName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "cyan": return Color(red: 6/255, green: 182/255, blue: 212/255)
        case "emerald": return .emeraldCustom
        case "mint": return Color(red: 20/255, green: 184/255, blue: 166/255)
        case "rose": return .rose
        case "coral": return Color(red: 249/255, green: 115/255, blue: 22/255)
        case "violet": return .purple
        case "amber": return .orange
        case "gold": return Color(red: 234/255, green: 179/255, blue: 8/255)
        default: return .indigo
        }
    }
    
    // MARK: - Quick Spotify URL / Title Import (Zero-config)
    private func triggerQuickSpotifyImport() {
        let rawInput = spotifyQuickQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return }
        
        isQuickImporting = true
        let entries = rawInput
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        Task {
            var importedPodcasts: [Podcast] = []
            for entry in entries {
                var showTitleToSearch = entry
                var showAuthor: String? = nil
                
                // If it's a Spotify URL (e.g. https://open.spotify.com/show/...), resolve title via public Spotify oEmbed API
                if entry.lowercased().contains("spotify.com/") {
                    if let encoded = entry.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let oembedURL = URL(string: "https://open.spotify.com/oembed?url=\(encoded)"),
                       let (data, _) = try? await URLSession.shared.data(from: oembedURL),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let title = json["title"] as? String, !title.isEmpty {
                        showTitleToSearch = title
                        showAuthor = json["author_name"] as? String
                    }
                }
                
                if let matched = await APIService.shared.matchPodcastOnItunes(
                    name: showTitleToSearch,
                    publisher: showAuthor,
                    country: storage.currentLanguage.itunes
                ) {
                    importedPodcasts.append(matched)
                }
            }
            
            await MainActor.run {
                isQuickImporting = false
                if !importedPodcasts.isEmpty {
                    var addedCount = 0
                    for p in importedPodcasts {
                        if !storage.isFavoritePodcast(p.collectionId) {
                            storage.toggleFavoritePodcast(p)
                            addedCount += 1
                        }
                    }
                    spotifyQuickQuery = ""
                    let names = importedPodcasts.map { $0.collectionName }.joined(separator: ", ")
                    spotifyAlertTitle = storage.currentLanguage == .fr ? "Import Spotify réussi" : "Spotify Import Successful"
                    spotifyAlertMessage = storage.currentLanguage == .fr
                        ? "\(importedPodcasts.count) podcast(s) trouvé(s) et ajouté(s) à vos favoris : \(names)"
                        : "\(importedPodcasts.count) podcast(s) matched and added to your favorites: \(names)"
                    showingSpotifyAlert = true
                } else {
                    spotifyAlertTitle = storage.currentLanguage == .fr ? "Aucun podcast trouvé" : "No Podcast Found"
                    spotifyAlertMessage = storage.currentLanguage == .fr
                        ? "Aucun podcast correspondant n'a été trouvé sur le catalogue Apple Podcasts."
                        : "No matching podcast was found in the Apple Podcasts catalog."
                    showingSpotifyAlert = true
                }
            }
        }
    }
}

struct ThemeButton: View {
    let id: String
    let label: String
    let icon: String
    var previewColor: Color = .clear
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        let isSelected = storage.settings.theme == id
        Button(action: {
            HapticManager.shared.trigger(.light)
            withAnimation(.easeInOut(duration: 0.2)) {
                storage.settings.theme = id
            }
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(previewColor)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? storage.accentColorColor() : Color.secondary.opacity(0.35), lineWidth: 1.5)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor((id == "light" || id == "cream") ? Color(red: 15/255, green: 23/255, blue: 42/255) : .white)
                }
                Text(label)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(isSelected ? storage.primaryTextColor : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 4)
            .background(isSelected ? storage.accentColorColor().opacity(0.14) : storage.subtleSurfaceColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? storage.accentColorColor() : storage.cardBorderColor, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Compact Expandable App Guide & Feature Explanations
struct AppGuideTopic: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let details: [String]
}

// MARK: - Dedicated Bottom 5-Day Weather Forecast & Ephemeris Section in Settings
struct WeeklyWeatherSettingsSection: View {
    @ObservedObject var storage = LocalStorageManager.shared
    @ObservedObject var weatherService = WeatherService.shared
    
    private static let inputDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    private static var dayFormatters: [String: DateFormatter] = [:]
    
    private static func dayFormatter(for langCode: String) -> DateFormatter {
        if let existing = dayFormatters[langCode] {
            return existing
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: langCode)
        df.dateFormat = "EEE d"
        dayFormatters[langCode] = df
        return df
    }
    
    private func formattedDayLabel(_ dateStr: String, index: Int) -> String {
        let isFr = storage.currentLanguage == .fr
        if index == 0 {
            return isFr ? "Auj." : "Today"
        }
        guard let date = Self.inputDateFormatter.date(from: dateStr) else {
            return dateStr
        }
        let df = Self.dayFormatter(for: storage.currentLanguage.rawValue)
        return df.string(from: date).capitalized
    }
    
    var body: some View {
        let isFr = storage.currentLanguage == .fr
        let zodiac = WeatherService.currentZodiacSign(isFrench: isFr)
        let fete = WeatherService.feteDuJour()
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    isFr ? "Météo 5 Jours • \(weatherService.cityName)" : "5-Day Weather • \(weatherService.cityName)",
                    systemImage: weatherService.weatherIcon
                )
                .font(.system(size: 12, weight: .black))
                .foregroundColor(storage.accentColorColor())
                
                Spacer()
                
                if let currentTemp = weatherService.temperature {
                    Text("\(Int(round(currentTemp)))°C • \(weatherService.weatherDescription)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(storage.primaryTextColor)
                }
            }
            
            // 5-Day Forecast Row
            HStack(spacing: 8) {
                ForEach(Array(weatherService.weeklyForecast.prefix(5).enumerated()), id: \.element.id) { index, day in
                    VStack(spacing: 6) {
                        Text(formattedDayLabel(day.dateString, index: index))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(index == 0 ? storage.accentColorColor() : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        Image(systemName: day.icon)
                            .font(.system(size: 18))
                            .foregroundColor(storage.accentColorColor())
                            .frame(height: 22)
                        
                        VStack(spacing: 1) {
                            Text("\(Int(round(day.tempMax)))°")
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(storage.primaryTextColor)
                            Text("\(Int(round(day.tempMin)))°")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(index == 0 ? storage.accentColorColor().opacity(0.12) : storage.subtleSurfaceColor)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(index == 0 ? storage.accentColorColor().opacity(0.4) : storage.cardBorderColor, lineWidth: 1)
                    )
                }
            }
            
            // Ephemeris Grid: Sunrise/Sunset, Fête du jour, Signe Astral
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    // Lever du soleil
                    HStack(spacing: 6) {
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(isFr ? "Lever" : "Sunrise")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(weatherService.sunriseTimeString)
                                .font(.system(size: 11.5, weight: .black))
                                .foregroundColor(storage.primaryTextColor)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(storage.subtleSurfaceColor)
                    .cornerRadius(10)
                    
                    // Coucher du soleil
                    HStack(spacing: 6) {
                        Image(systemName: "sunset.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.pink)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(isFr ? "Coucher" : "Sunset")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(weatherService.sunsetTimeString)
                                .font(.system(size: 11.5, weight: .black))
                                .foregroundColor(storage.primaryTextColor)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(storage.subtleSurfaceColor)
                    .cornerRadius(10)
                }
                
                HStack(spacing: 8) {
                    // Fête du jour
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13))
                            .foregroundColor(storage.accentColorColor())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(isFr ? "Fête du jour" : "Name Day")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text("St(e) \(fete)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(storage.primaryTextColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(storage.subtleSurfaceColor)
                    .cornerRadius(10)
                    
                    // Signe astral en cours
                    HStack(spacing: 6) {
                        Text(zodiac.symbol)
                            .font(.system(size: 15))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(isFr ? "Signe astral" : "Zodiac Sign")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(zodiac.name)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(storage.primaryTextColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(storage.subtleSurfaceColor)
                    .cornerRadius(10)
                }
            }
        }
        .padding(14)
        .background(storage.cardBackgroundColor)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
        .onAppear {
            weatherService.requestLocation()
        }
    }
}

struct KnowledgeAndWeeklyWeatherSettingsSection: View {
    @Binding var isExpanded: Bool
    @ObservedObject var storage = LocalStorageManager.shared
    @ObservedObject var factsService = KnowledgeFactsService.shared
    
    var body: some View {
        let isFr = storage.currentLanguage == .fr
        let recentFacts = factsService.recentFacts
        
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                HapticManager.shared.trigger(.light)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(storage.accentColorColor().opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(storage.accentColorColor())
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isFr ? "Savoirs Récents" : "Recent Knowledge")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(storage.primaryTextColor)
                        Text(isFr ? "Les 5 dernières clés affichées (touchez pour afficher)" : "Last 5 displayed facts (tap to expand)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(storage.accentColorColor())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                Divider()
                    .background(storage.cardBorderColor)
                    .padding(.vertical, 2)
                
                // Last 5 Displayed Knowledge Facts
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(
                            isFr ? "5 dernières informations de connaissance" : "Last 5 displayed knowledge facts",
                            systemImage: "brain.head.profile"
                        )
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(storage.accentColorColor())
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                    
                    ForEach(Array(recentFacts.prefix(5).enumerated()), id: \.element.id) { idx, fact in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("#\(idx + 1)")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(storage.accentColorColor())
                                    .cornerRadius(6)
                                
                                Image(systemName: fact.icon)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(storage.accentColorColor())
                                
                                Text(fact.category.uppercased())
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundColor(storage.accentColorColor())
                                
                                Spacer()
                            }
                            
                            Text(fact.title(for: storage.currentLanguage))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(storage.primaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Text(fact.text(for: storage.currentLanguage))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(storage.subtleSurfaceColor)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(storage.cardBorderColor, lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(storage.cardBackgroundColor)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
    }
}

struct AppGuideSettingsSection: View {
    @Binding var isSectionExpanded: Bool
    @Binding var expandedTopicId: String?
    @ObservedObject var storage = LocalStorageManager.shared
    
    private var topics: [AppGuideTopic] {
        let isFr = storage.currentLanguage == .fr
        return [
            AppGuideTopic(
                id: "tabs",
                icon: "square.grid.2x2.fill",
                title: isFr ? "Les 4 Onglets de l'application" : "The 4 App Tabs",
                subtitle: isFr ? "Épisodes, Podcasts, Apprendre & Radio" : "Episodes, Podcasts, Learn & Radio",
                details: isFr ? [
                    "• Épisodes (1er onglet) : S'ouvre par défaut et affiche les épisodes des 7 derniers jours de vos podcasts favoris (actualisation optimisée toutes les 30 minutes max). Glissez à droite pour ajouter à la file d'attente, à gauche pour masquer, ou maintenez appuyé pour ouvrir le podcast.",
                    "• Podcasts : Retrouvez vos podcasts favoris triés par l'épisode le plus récent en premier, ainsi que les classements tendances par catégorie.",
                    "• Apprendre : Regroupe 3 sous-sections dédiées (Culture avec les grands médias Arte, INA, Collège de France..., Livres et Enfants) avec filtres courts, favoris par section, placement automatique à gauche des favoris en cours d'écoute et bouton « Reprendre ».",
                    "• Radio : Écoutez vos stations en direct sur des flux directs sans pub pré-roll avec icônes dédiées, recherche rapide et favoris propres à l'onglet Radio."
                ] : [
                    "• Episodes (1st tab): Opens by default and shows the last 7 days of episodes from your favorite podcasts (throttled to 30m auto-refresh). Swipe right to queue, left to hide, or long-press to open the show.",
                    "• Podcasts: Your favorite shows ordered by most recent episode first, plus top trending charts by genre.",
                    "• Learn: Features 3 sub-sections (Culture with major media proposals, Books, Kids) with short category filters, section favorites, in-progress items placed on the left, and 'Resume' right where you left off.",
                    "• Radio: Direct ad-free live radio streams with custom/resolved icons, instant search, and dedicated Radio favorites."
                ]
            ),
            AppGuideTopic(
                id: "player",
                icon: "play.circle.fill",
                title: isFr ? "Lecteur, Diffuser & Infos (i)" : "Player, Cast & Info (i)",
                subtitle: isFr ? "AirPlay/Chromecast unifié, Fiche détaillée & Hors-ligne" : "Unified AirPlay/Chromecast, Item Info & Offline",
                details: isFr ? [
                    "• Lecteur & Nom cliquable : Vitesse ajustable (0.5x à 2.5x), saut automatique des intros (30s) et reprise automatique. Touchez le nom du podcast ou livre sous le titre pour ouvrir directement tous ses épisodes.",
                    "• Bouton (i) : Affiche toutes les informations récupérées sur le média en cours de lecture (description complète, auteur, date, durée, genre, source et flux).",
                    "• Bouton « Diffuser » unifié : Regroupe Apple AirPlay (HomePod, Apple TV, AirPods) et Google Cast / Chromecast dans un seul panneau.",
                    "• Mode Hors-ligne : Le bouton « Charger » dans l'onglet Épisodes télécharge automatiquement les 10 derniers épisodes."
                ] : [
                    "• Player & Clickable Show Name: Adjustable speed (0.5x to 2.5x), automatic 30s intro skip, and position memory. Tap the podcast or book name below the title to open all its episodes.",
                    "• Info (i) Button: Displays all metadata retrieved for the currently playing item (full description, author, release date, duration, genre, source, and stream URL).",
                    "• Unified 'Cast' Button: Combines Apple AirPlay and Google Cast / Chromecast in a single control.",
                    "• Offline Mode: The 'Download' button in Episodes caches the 10 latest episodes for offline listening."
                ]
            ),
            AppGuideTopic(
                id: "widget",
                icon: "rectangle.3.group.fill",
                title: isFr ? "Widget iOS (5 Derniers Épisodes)" : "iOS Widget (5 Latest Episodes)",
                subtitle: isFr ? "Synchronisation directe & bouton Actualiser" : "Direct sync & Refresh button",
                details: isFr ? [
                    "• 3 tailles disponibles (Petit, Moyen, Grand) sur votre écran d'accueil iPhone.",
                    "• Affiche exactement les 5 derniers épisodes tels qu'ils apparaissent dans votre onglet Épisodes.",
                    "• Touchez n'importe quel épisode du widget pour lancer immédiatement sa lecture dans Podcast Ultra.",
                    "• Bouton Actualiser (↻) intégré en haut à droite du widget pour mettre à jour la liste directement."
                ] : [
                    "• Available in Small, Medium, and Large sizes on your iPhone Home Screen.",
                    "• Mirrors the exact top 5 latest episodes displayed in your Episodes tab.",
                    "• Tap any episode row on the widget to start playing it immediately.",
                    "• Built-in Refresh button (↻) in the widget header to reload episodes anytime."
                ]
            ),
            AppGuideTopic(
                id: "watch",
                icon: "applewatch.watchface",
                title: isFr ? "Compagnon Apple Watch" : "Apple Watch Companion",
                subtitle: isFr ? "Contrôle au poignet & vue montre intégrée" : "Wrist control & built-in Watch view",
                details: isFr ? [
                    "• Accessible à tout moment via l'icône Montre en haut à droite de l'écran principal ou depuis les Réglages.",
                    "• Comprend 3 écrans dédiés : À l'écoute (Play/Pause, ±15s/30s), 5 Derniers Épisodes et Radios Favorites.",
                    "• Synchronisation automatique via WatchConnectivity avec votre Apple Watch jumelée."
                ] : [
                    "• Accessible anytime via the Watch icon in the top header or from Settings.",
                    "• Features 3 screens: Now Playing controls, 5 Latest Episodes, and Favorite Radios.",
                    "• Automatically syncs via WatchConnectivity with your paired Apple Watch."
                ]
            )
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Compact clickable header so the section takes minimal space when collapsed
            Button(action: {
                HapticManager.shared.trigger(.light)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isSectionExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(storage.accentColorColor().opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(storage.accentColorColor())
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(storage.currentLanguage == .fr ? "Fonctionnement & Guide de l'app" : "How the App Works & Guide")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(storage.primaryTextColor)
                        Text(storage.currentLanguage == .fr ? "Onglets, fonctions, Widget, Apple Watch (touchez pour afficher)" : "Tabs, features, Widget, Apple Watch (tap to expand)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isSectionExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(storage.accentColorColor())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            if isSectionExpanded {
                Divider()
                    .background(storage.cardBorderColor)
                    .padding(.vertical, 2)
                
                VStack(spacing: 8) {
                    ForEach(topics) { topic in
                        let isExpanded = expandedTopicId == topic.id
                        VStack(alignment: .leading, spacing: 0) {
                            Button(action: {
                                HapticManager.shared.trigger(.light)
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    expandedTopicId = isExpanded ? nil : topic.id
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: topic.icon)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(storage.accentColorColor())
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(topic.title)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(storage.primaryTextColor)
                                        Text(topic.subtitle)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if isExpanded {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(topic.details, id: \.self) { line in
                                        Text(line)
                                            .font(.system(size: 11))
                                            .foregroundColor(storage.primaryTextColor.opacity(0.88))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .lineSpacing(2)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 10)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .background(storage.subtleSurfaceColor)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isExpanded ? storage.accentColorColor().opacity(0.4) : storage.cardBorderColor, lineWidth: 1)
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(storage.cardBackgroundColor)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage.cardBorderColor, lineWidth: 1))
    }
}
