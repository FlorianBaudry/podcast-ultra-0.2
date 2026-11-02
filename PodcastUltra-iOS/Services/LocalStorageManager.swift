import Foundation
import Combine
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

struct AppSettingsModel: Codable {
    var playbackSpeed: Double = 1.0
    var skipIntro: Bool = true
    var deleteAfterListening: Bool = false
    var longestPerDayOnly: Bool = true
    var accentColor: String = "indigo" // indigo, blue, emerald, rose, violet, amber
    var theme: String = "dark" // light, dark, black
    var spotifyClientId: String = ""
    var autoDownloadLatest: Bool = false
    
    init(
        playbackSpeed: Double = 1.0,
        skipIntro: Bool = true,
        deleteAfterListening: Bool = false,
        longestPerDayOnly: Bool = true,
        accentColor: String = "indigo",
        theme: String = "dark",
        spotifyClientId: String = "",
        autoDownloadLatest: Bool = false
    ) {
        self.playbackSpeed = playbackSpeed
        self.skipIntro = skipIntro
        self.deleteAfterListening = deleteAfterListening
        self.longestPerDayOnly = longestPerDayOnly
        self.accentColor = accentColor
        self.theme = theme
        self.spotifyClientId = spotifyClientId
        self.autoDownloadLatest = autoDownloadLatest
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.playbackSpeed = try container.decodeIfPresent(Double.self, forKey: .playbackSpeed) ?? 1.0
        self.skipIntro = try container.decodeIfPresent(Bool.self, forKey: .skipIntro) ?? true
        self.deleteAfterListening = try container.decodeIfPresent(Bool.self, forKey: .deleteAfterListening) ?? false
        self.longestPerDayOnly = try container.decodeIfPresent(Bool.self, forKey: .longestPerDayOnly) ?? true
        self.accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor) ?? "indigo"
        self.theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "dark"
        self.spotifyClientId = try container.decodeIfPresent(String.self, forKey: .spotifyClientId) ?? ""
        self.autoDownloadLatest = try container.decodeIfPresent(Bool.self, forKey: .autoDownloadLatest) ?? false
    }
}

struct WidgetEpisodePayload: Codable, Identifiable {
    var id: Int { trackId }
    let trackId: Int
    let trackName: String
    let collectionName: String
    let releaseDate: String?
    let artworkUrl: String?
    let previewUrl: String?
    let durationMinutes: Int?
}

struct WidgetPodcastFeedInfo: Codable {
    let collectionId: Int
    let collectionName: String
    let artworkUrl: String?
    let feedUrl: String?
    let country: String?
}

class LocalStorageManager: ObservableObject {
    static let shared = LocalStorageManager()
    
    private let saveQueue = DispatchQueue(label: "com.podcastultra.storage.save", qos: .utility)
    private var lastPositionSaveTime: Date = .distantPast
    private var isInitialized = false
    
    // Incremented every time the app opens or returns to foreground to trigger immediate episode refresh
    @Published var appOpenRefreshTrigger: Int = 0
    
    // Published properties for dynamic UI updates
    @Published var settings: AppSettingsModel {
        didSet {
            guard isInitialized else { return }
            save(settings, forKey: keys.settings)
            syncWidgetLatestEpisodes()
        }
    }
    
    @Published var currentLanguage: LangCode {
        didSet {
            guard isInitialized else { return }
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: keys.language)
            save(currentLanguage.rawValue, forKey: keys.language)
        }
    }
    
    @Published var favoritePodcasts: [Podcast] = [] {
        didSet {
            guard isInitialized else { return }
            save(favoritePodcasts, forKey: keys.favorites)
            syncWidgetSubscribedPodcasts()
            WatchSessionManager.shared.syncContextToWatch()
        }
    }
    
    @Published var favoriteAudiobooks: [Podcast] = [] {
        didSet {
            guard isInitialized else { return }
            save(favoriteAudiobooks, forKey: keys.favoriteAudiobooks)
        }
    }
    
    @Published var favoriteRadios: [String] = [] {
        didSet {
            guard isInitialized else { return }
            save(favoriteRadios, forKey: keys.favoriteRadios)
        }
    }
    
    @Published var favoriteRadioStations: [RadioStation] = [] {
        didSet {
            guard isInitialized else { return }
            save(favoriteRadioStations, forKey: keys.favoriteRadioStations)
            let ids = favoriteRadioStations.map { $0.id }
            if favoriteRadios != ids {
                favoriteRadios = ids
            }
            WatchSessionManager.shared.syncContextToWatch()
        }
    }
    
    @Published var podcastLatestEpisodeDates: [Int: String] = [:] {
        didSet {
            guard isInitialized else { return }
            save(podcastLatestEpisodeDates, forKey: keys.podcastLatestDates)
        }
    }
    
    @Published var playedEpisodeIds: [Int] = [] {
        didSet {
            guard isInitialized else { return }
            save(playedEpisodeIds, forKey: keys.playedIds)
        }
    }
    
    // Non-published to prevent full-app SwiftUI re-renders every 5s during playback
    var savedPositions: [String: Double] = [:]
    
    @Published var history: [Episode] = [] {
        didSet {
            guard isInitialized else { return }
            save(history, forKey: keys.history)
        }
    }
    
    @Published var playlists: [PlaylistModel] = [] {
        didSet {
            guard isInitialized else { return }
            save(playlists, forKey: keys.playlists)
        }
    }
    
    @Published var dismissedEpisodeIds: [Int] = [] {
        didSet {
            guard isInitialized else { return }
            save(dismissedEpisodeIds, forKey: keys.dismissedIds)
            syncWidgetLatestEpisodes()
        }
    }
    
    @Published var cachedEpisodes: [Episode] = [] {
        didSet {
            guard isInitialized else { return }
            save(cachedEpisodes, forKey: keys.cachedEpisodes)
            syncWidgetLatestEpisodes()
            WatchSessionManager.shared.syncContextToWatch()
        }
    }
    
    @Published var downloadedEpisodeIds: [Int] = [] {
        didSet {
            guard isInitialized else { return }
            save(downloadedEpisodeIds, forKey: keys.downloadedIds)
        }
    }
    
    @Published var cachedTrendingPodcasts: [Podcast] = [] {
        didSet {
            guard isInitialized else { return }
            save(cachedTrendingPodcasts, forKey: keys.cachedTrending)
        }
    }
    
    @Published var cachedAudiobooks: [Podcast] = [] {
        didSet {
            guard isInitialized else { return }
            save(cachedAudiobooks, forKey: keys.cachedAudiobooks)
        }
    }
    
    @Published var cachedRadioStations: [RadioStation] = [] {
        didSet {
            guard isInitialized else { return }
            save(cachedRadioStations, forKey: keys.cachedRadioStations)
        }
    }
    
    var lastEpisodesFetchDate: Date? {
        get { UserDefaults.standard.object(forKey: keys.lastEpisodesFetch) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: keys.lastEpisodesFetch) }
    }
    
    var lastTrendingFetchDate: Date? {
        get { UserDefaults.standard.object(forKey: keys.lastTrendingFetch) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: keys.lastTrendingFetch) }
    }
    
    var lastTrendingCategory: String? {
        get { UserDefaults.standard.string(forKey: keys.lastTrendingCategory) }
        set { UserDefaults.standard.set(newValue, forKey: keys.lastTrendingCategory) }
    }
    
    var lastAudiobooksCategory: String? {
        get { UserDefaults.standard.string(forKey: keys.lastAudiobooksCategory) }
        set { UserDefaults.standard.set(newValue, forKey: keys.lastAudiobooksCategory) }
    }
    
    /// Returns true if the last fetch is older than 24 hours or has never happened
    func shouldRefresh(lastFetch: Date?) -> Bool {
        guard let lastFetch = lastFetch else { return true }
        return Date().timeIntervalSince(lastFetch) > 24 * 60 * 60
    }
    
    private let keys = (
        settings: "voxstream_settings",
        language: "voxstream_lang",
        favorites: "voxstream_favs_v2",
        favoriteAudiobooks: "voxstream_fav_audiobooks",
        favoriteRadios: "voxstream_fav_radios",
        favoriteRadioStations: "voxstream_fav_radio_stations",
        podcastLatestDates: "voxstream_podcast_latest_dates",
        playedIds: "voxstream_played_ids",
        savedPositions: "voxstream_saved_positions",
        history: "voxstream_history",
        playlists: "voxstream_playlists",
        dismissedIds: "voxstream_dismissed_ids",
        cachedEpisodes: "voxstream_cached_episodes",
        downloadedIds: "voxstream_downloaded_ids",
        cachedTrending: "voxstream_cached_trending",
        cachedAudiobooks: "voxstream_cached_audiobooks",
        cachedRadioStations: "voxstream_cached_radio_stations",
        lastEpisodesFetch: "voxstream_last_episodes_fetch",
        lastTrendingFetch: "voxstream_last_trending_fetch",
        lastTrendingCategory: "voxstream_last_trending_category",
        lastAudiobooksCategory: "voxstream_last_audiobooks_category"
    )
    
    private init() {
        // Load settings
        if let data = UserDefaults.standard.data(forKey: "voxstream_settings"),
           let loaded = try? JSONDecoder().decode(AppSettingsModel.self, from: data) {
            self.settings = loaded
        } else {
            self.settings = AppSettingsModel()
        }
        
        // Load language
        if let rawLang = UserDefaults.standard.string(forKey: "voxstream_lang"),
           let loadedLang = LangCode(rawValue: rawLang) {
            self.currentLanguage = loadedLang
        } else if let data = UserDefaults.standard.data(forKey: "voxstream_lang"),
                  let decodedStr = try? JSONDecoder().decode(String.self, from: data),
                  let loadedLang = LangCode(rawValue: decodedStr) {
            self.currentLanguage = loadedLang
        } else {
            self.currentLanguage = .fr
        }
        
        // Load favorite audiobooks
        var loadedBooks: [Podcast] = []
        if let data = UserDefaults.standard.data(forKey: "voxstream_fav_audiobooks"),
           let loaded = try? JSONDecoder().decode([Podcast].self, from: data) {
            loadedBooks = loaded
        }
        
        // Load favorites and separate any audiobooks so book favorites only appear in the Books tab
        if let data = UserDefaults.standard.data(forKey: "voxstream_favs_v2"),
           let loaded = try? JSONDecoder().decode([Podcast].self, from: data) {
            var purePodcasts: [Podcast] = []
            for item in loaded {
                if Self.isAudiobookItem(item) {
                    if !loadedBooks.contains(where: { $0.collectionId == item.collectionId }) {
                        loadedBooks.append(item)
                    }
                } else {
                    purePodcasts.append(item)
                }
            }
            self.favoritePodcasts = purePodcasts
        }
        self.favoriteAudiobooks = loadedBooks
        
        // Load favorite radios & full radio stations
        if let data = UserDefaults.standard.data(forKey: "voxstream_fav_radios"),
           let loaded = try? JSONDecoder().decode([String].self, from: data) {
            self.favoriteRadios = loaded
        }
        if let data = UserDefaults.standard.data(forKey: "voxstream_fav_radio_stations"),
           let loaded = try? JSONDecoder().decode([RadioStation].self, from: data) {
            self.favoriteRadioStations = loaded
        }
        
        // Load latest episode dates per podcast
        if let data = UserDefaults.standard.data(forKey: "voxstream_podcast_latest_dates"),
           let loaded = try? JSONDecoder().decode([Int: String].self, from: data) {
            self.podcastLatestEpisodeDates = loaded
        }
        
        // Load played episode IDs
        if let data = UserDefaults.standard.data(forKey: "voxstream_played_ids"),
           let loaded = try? JSONDecoder().decode([Int].self, from: data) {
            self.playedEpisodeIds = loaded
        }
        
        // Load saved positions
        if let data = UserDefaults.standard.data(forKey: "voxstream_saved_positions"),
           let loaded = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.savedPositions = loaded
        }
        
        // Load history
        if let data = UserDefaults.standard.data(forKey: "voxstream_history"),
           let loaded = try? JSONDecoder().decode([Episode].self, from: data) {
            self.history = loaded
        }
        
        // Load playlists
        if let data = UserDefaults.standard.data(forKey: "voxstream_playlists"),
           let loaded = try? JSONDecoder().decode([PlaylistModel].self, from: data) {
            self.playlists = loaded
        }
        
        // Load dismissed episode IDs
        if let data = UserDefaults.standard.data(forKey: "voxstream_dismissed_ids"),
           let loaded = try? JSONDecoder().decode([Int].self, from: data) {
            self.dismissedEpisodeIds = loaded
        }
        
        // Load cached episodes and sanitize any future/corrupted dates
        if let data = UserDefaults.standard.data(forKey: "voxstream_cached_episodes"),
           let loaded = try? JSONDecoder().decode([Episode].self, from: data) {
            self.cachedEpisodes = Self.sanitizeEpisodesDates(loaded)
        }
        
        // Load downloaded episode IDs
        if let data = UserDefaults.standard.data(forKey: "voxstream_downloaded_ids"),
           let loaded = try? JSONDecoder().decode([Int].self, from: data) {
            self.downloadedEpisodeIds = loaded
        }
        
        // Load cached trending podcasts
        if let data = UserDefaults.standard.data(forKey: "voxstream_cached_trending"),
           let loaded = try? JSONDecoder().decode([Podcast].self, from: data) {
            self.cachedTrendingPodcasts = loaded
        }
        
        // Load cached audiobooks
        if let data = UserDefaults.standard.data(forKey: "voxstream_cached_audiobooks"),
           let loaded = try? JSONDecoder().decode([Podcast].self, from: data) {
            self.cachedAudiobooks = loaded
        }
        
        // Load cached radio stations
        if let data = UserDefaults.standard.data(forKey: "voxstream_cached_radio_stations"),
           let loaded = try? JSONDecoder().decode([RadioStation].self, from: data) {
            self.cachedRadioStations = loaded
        }
        
        // Hydrate favoriteRadioStations from cachedRadioStations if needed
        if favoriteRadioStations.isEmpty && !favoriteRadios.isEmpty {
            let hydrated = favoriteRadios.compactMap { id in
                cachedRadioStations.first(where: { $0.id == id })
            }
            if !hydrated.isEmpty {
                self.favoriteRadioStations = hydrated
            }
        }
        
        // Mark initialization complete BEFORE triggering any external syncs
        self.isInitialized = true
        
        // Sync widget & Watch asynchronously on the next runloop tick so LocalStorageManager.shared dispatch_once has returned
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.syncWidgetSubscribedPodcasts()
            self.syncWidgetLatestEpisodes()
            WatchSessionManager.shared.syncContextToWatch()
        }
    }
    
    static func isAudiobookItem(_ podcast: Podcast) -> Bool {
        if let src = podcast.source?.lowercased(),
           ["librivox", "openlibrary", "archive", "litteratureaudio", "storynory"].contains(src) {
            return true
        }
        if podcast.collectionId >= 10_000_000 && podcast.collectionId < 40_000_000 {
            return true
        }
        let primary = podcast.primaryGenreName?.lowercased() ?? ""
        let genres = (podcast.genres ?? []).map { $0.lowercased() }
        let bookKeywords = ["audiobook", "livre audio", "livres audio"]
        return bookKeywords.contains { kw in
            primary.contains(kw) || genres.contains(where: { $0.contains(kw) })
        }
    }
    
    // Saved positions helpers (non-blocking)
    func getSavedPosition(for episodeId: Int) -> Double {
        savedPositions[String(episodeId)] ?? 0.0
    }
    
    func setSavedPosition(_ position: Double, for episodeId: Int, flushImmediately: Bool = false) {
        savedPositions[String(episodeId)] = position
        let now = Date()
        if flushImmediately || now.timeIntervalSince(lastPositionSaveTime) >= 15.0 {
            lastPositionSaveTime = now
            let snapshot = savedPositions
            let key = keys.savedPositions
            saveQueue.async {
                if let data = try? JSONEncoder().encode(snapshot) {
                    UserDefaults.standard.set(data, forKey: key)
                }
            }
        }
    }
    
    // Helper save methods on background queue to keep main thread 100% responsive
    private func save<T: Encodable>(_ value: T, forKey key: String) {
        saveQueue.async {
            if let data = try? JSONEncoder().encode(value) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
    
    // MARK: - App Open Refresh & Episode Sanitization
    func triggerAppOpenEpisodesRefresh() {
        DispatchQueue.main.async {
            self.appOpenRefreshTrigger += 1
        }
    }
    
    static func sanitizeEpisodesDates(_ episodes: [Episode]) -> [Episode] {
        return episodes.map { ep in
            guard let raw = ep.releaseDate,
                  let validDate = DateFormatterUtility.parse(raw) else {
                return ep
            }
            let normalized = DateFormatterUtility.formatISO8601(validDate)
            if normalized == raw {
                return ep
            }
            return Episode(
                trackId: ep.trackId,
                trackName: ep.trackName,
                description: ep.description,
                releaseDate: normalized,
                previewUrl: ep.previewUrl,
                trackTimeMillis: ep.trackTimeMillis,
                artworkUrl60: ep.artworkUrl60,
                artworkUrl160: ep.artworkUrl160,
                artworkUrl600: ep.artworkUrl600,
                collectionName: ep.collectionName,
                collectionId: ep.collectionId,
                artistName: ep.artistName
            )
        }
    }
    
    func applyLongestPerDayFilter(_ input: [Episode]) -> [Episode] {
        var grouped: [String: Episode] = [:]
        for ep in input {
            guard let collectionId = ep.collectionId,
                  let releaseStr = ep.releaseDate,
                  let date = DateFormatterUtility.parse(releaseStr) else { continue }
            
            let dateStr = DateFormatterUtility.formatKey(date)
            let key = "\(collectionId)-\(dateStr)"
            let time = ep.trackTimeMillis ?? 0
            
            if let existing = grouped[key] {
                if time > (existing.trackTimeMillis ?? 0) {
                    grouped[key] = ep
                }
            } else {
                grouped[key] = ep
            }
        }
        return Array(grouped.values).sorted { a, b in
            let dateA = DateFormatterUtility.parse(a.releaseDate) ?? .distantPast
            let dateB = DateFormatterUtility.parse(b.releaseDate) ?? .distantPast
            return dateA > dateB
        }
    }
    
    // MARK: - Widget Synchronization (Top 5 Latest Subscribed Episodes)
    private static func sharedWidgetEpisodesFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.podcastultra.app")?
            .appendingPathComponent("widget_episodes.json")
    }
    
    private static func sharedWidgetPodcastsFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.podcastultra.app")?
            .appendingPathComponent("widget_podcasts.json")
    }
    
    func syncWidgetSubscribedPodcasts() {
        let infos = favoritePodcasts.prefix(15).map { p in
            WidgetPodcastFeedInfo(
                collectionId: p.collectionId,
                collectionName: p.collectionName,
                artworkUrl: p.artworkUrl600 ?? p.artworkUrl100,
                feedUrl: p.feedUrl,
                country: p.country ?? currentLanguage.itunes
            )
        }
        guard let encoded = try? JSONEncoder().encode(infos) else { return }
        if let sharedDefaults = UserDefaults(suiteName: "group.com.podcastultra.app") {
            sharedDefaults.set(encoded, forKey: "widgetSubscribedPodcasts")
            sharedDefaults.synchronize()
        }
        if let groupFile = Self.sharedWidgetPodcastsFileURL() {
            try? encoded.write(to: groupFile, options: .atomic)
        }
        try? encoded.write(to: URL(fileURLWithPath: "/tmp/podcastultra_widget_podcasts.json"), options: .atomic)
    }
    
    func syncWidgetLatestEpisodes(from customList: [Episode]? = nil) {
        let rawSource = customList ?? cachedEpisodes
        let dismissed = Set(dismissedEpisodeIds)
        
        // Apply the exact same filtering & ordering as the Episodes tab!
        var validEpisodes = rawSource.filter { !dismissed.contains($0.trackId) }
        if customList == nil && settings.longestPerDayOnly {
            validEpisodes = applyLongestPerDayFilter(validEpisodes)
        }
        
        let sorted = validEpisodes.sorted { a, b in
            let dateA = DateFormatterUtility.parse(a.releaseDate) ?? .distantPast
            let dateB = DateFormatterUtility.parse(b.releaseDate) ?? .distantPast
            return dateA > dateB
        }
        
        let top5 = Array(sorted.prefix(5)).map { ep -> WidgetEpisodePayload in
            let artwork = ep.artworkUrl160 ?? ep.artworkUrl60 ?? ep.artworkUrl600
                ?? favoritePodcasts.first(where: { $0.collectionId == ep.collectionId })?.artworkUrl100
            let mins: Int? = ep.trackTimeMillis.map { max(1, $0 / 60000) }
            let cleanDate = DateFormatterUtility.parse(ep.releaseDate).map { DateFormatterUtility.formatISO8601($0) } ?? ep.releaseDate
            return WidgetEpisodePayload(
                trackId: ep.trackId,
                trackName: ep.trackName,
                collectionName: ep.collectionName ?? ep.artistName ?? "Podcast",
                releaseDate: cleanDate,
                artworkUrl: artwork,
                previewUrl: ep.previewUrl,
                durationMinutes: mins
            )
        }
        
        guard let encoded = try? JSONEncoder().encode(top5) else { return }
        
        // Write synchronously to App Group UserDefaults + App Group container file + /tmp fallback
        if let sharedDefaults = UserDefaults(suiteName: "group.com.podcastultra.app") {
            sharedDefaults.set(encoded, forKey: "widgetLatestEpisodes")
            if let first = top5.first {
                sharedDefaults.set(first.trackName, forKey: "latestEpisodeTitle")
                sharedDefaults.set(first.collectionName, forKey: "latestEpisodeSubtitle")
                sharedDefaults.set(first.artworkUrl ?? "", forKey: "latestEpisodeArtworkUrl")
            }
            sharedDefaults.synchronize()
        }
        if let groupFile = Self.sharedWidgetEpisodesFileURL() {
            try? encoded.write(to: groupFile, options: .atomic)
        }
        try? encoded.write(to: URL(fileURLWithPath: "/tmp/podcastultra_widget_episodes.json"), options: .atomic)
        
        #if canImport(WidgetKit) && os(iOS)
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
    
    // Update accurate latest episode dates per podcast
    func updateLatestEpisodeDates(from episodes: [Episode]) {
        var latestByPodcast: [Int: (date: Date, raw: String)] = [:]
        for ep in episodes {
            guard let colId = ep.collectionId,
                  !isDismissedEpisode(ep.trackId),
                  let releaseStr = ep.releaseDate,
                  let parsed = DateFormatterUtility.parse(releaseStr) else { continue }
            if let existing = latestByPodcast[colId] {
                if parsed > existing.date {
                    latestByPodcast[colId] = (parsed, DateFormatterUtility.formatISO8601(parsed))
                }
            } else {
                latestByPodcast[colId] = (parsed, DateFormatterUtility.formatISO8601(parsed))
            }
        }
        
        var updatedMap = podcastLatestEpisodeDates
        for (colId, info) in latestByPodcast {
            updatedMap[colId] = info.raw
        }
        if updatedMap != podcastLatestEpisodeDates {
            podcastLatestEpisodeDates = updatedMap
        }
        
        // Also update favoritePodcasts releaseDate in-place so sorting & badges stay 100% accurate
        var updatedFavs = favoritePodcasts
        var favsChanged = false
        for idx in updatedFavs.indices {
            let colId = updatedFavs[idx].collectionId
            if let accurateDate = updatedMap[colId], updatedFavs[idx].releaseDate != accurateDate {
                updatedFavs[idx] = Podcast(
                    collectionId: updatedFavs[idx].collectionId,
                    artistName: updatedFavs[idx].artistName,
                    collectionName: updatedFavs[idx].collectionName,
                    artworkUrl100: updatedFavs[idx].artworkUrl100,
                    artworkUrl600: updatedFavs[idx].artworkUrl600,
                    feedUrl: updatedFavs[idx].feedUrl,
                    genres: updatedFavs[idx].genres,
                    primaryGenreName: updatedFavs[idx].primaryGenreName,
                    releaseDate: accurateDate,
                    country: updatedFavs[idx].country,
                    description: updatedFavs[idx].description,
                    source: updatedFavs[idx].source
                )
                favsChanged = true
            }
        }
        if favsChanged {
            favoritePodcasts = updatedFavs
        }
    }
    
    func effectiveReleaseDateString(for podcast: Podcast) -> String? {
        if let mapped = podcastLatestEpisodeDates[podcast.collectionId] {
            return mapped
        }
        // Check if we have episodes for this podcast in cachedEpisodes
        let matchingDates = cachedEpisodes
            .filter { $0.collectionId == podcast.collectionId && !isDismissedEpisode($0.trackId) }
            .compactMap { ep -> (Date, String)? in
                guard let r = ep.releaseDate, let d = DateFormatterUtility.parse(r) else { return nil }
                return (d, r)
            }
        if let newest = matchingDates.max(by: { $0.0 < $1.0 }) {
            return newest.1
        }
        // If it's a favorite podcast and cachedEpisodes has already been fetched,
        // avoid claiming "Today" if there is no today episode in the Episodes feed!
        if isFavoritePodcast(podcast.collectionId), !cachedEpisodes.isEmpty {
            if let raw = podcast.releaseDate, let d = DateFormatterUtility.parse(raw), Calendar.current.isDateInToday(d) {
                return nil
            }
        }
        return podcast.releaseDate
    }
    
    // Clear cache
    func clearAllData() {
        UserDefaults.standard.removeObject(forKey: keys.settings)
        UserDefaults.standard.removeObject(forKey: keys.language)
        UserDefaults.standard.removeObject(forKey: keys.favorites)
        UserDefaults.standard.removeObject(forKey: keys.favoriteAudiobooks)
        UserDefaults.standard.removeObject(forKey: keys.favoriteRadios)
        UserDefaults.standard.removeObject(forKey: keys.favoriteRadioStations)
        UserDefaults.standard.removeObject(forKey: keys.podcastLatestDates)
        UserDefaults.standard.removeObject(forKey: keys.playedIds)
        UserDefaults.standard.removeObject(forKey: keys.savedPositions)
        UserDefaults.standard.removeObject(forKey: keys.history)
        UserDefaults.standard.removeObject(forKey: keys.playlists)
        UserDefaults.standard.removeObject(forKey: keys.dismissedIds)
        UserDefaults.standard.removeObject(forKey: keys.cachedEpisodes)
        UserDefaults.standard.removeObject(forKey: keys.downloadedIds)
        UserDefaults.standard.removeObject(forKey: keys.cachedTrending)
        UserDefaults.standard.removeObject(forKey: keys.cachedAudiobooks)
        UserDefaults.standard.removeObject(forKey: keys.cachedRadioStations)
        UserDefaults.standard.removeObject(forKey: keys.lastEpisodesFetch)
        UserDefaults.standard.removeObject(forKey: keys.lastTrendingFetch)
        UserDefaults.standard.removeObject(forKey: keys.lastTrendingCategory)
        UserDefaults.standard.removeObject(forKey: keys.lastAudiobooksCategory)
        
        // Reset local variables
        self.settings = AppSettingsModel()
        self.currentLanguage = .fr
        self.favoritePodcasts = []
        self.favoriteAudiobooks = []
        self.favoriteRadios = []
        self.favoriteRadioStations = []
        self.podcastLatestEpisodeDates = [:]
        self.playedEpisodeIds = []
        self.savedPositions = [:]
        self.history = []
        self.playlists = []
        self.dismissedEpisodeIds = []
        self.cachedEpisodes = []
        self.cachedDownloadedPodcastsCleanup()
        self.cachedTrendingPodcasts = []
        self.cachedAudiobooks = []
        self.cachedRadioStations = []
    }
    
    private func cachedDownloadedPodcastsCleanup() {
        self.downloadedEpisodeIds = []
    }
    
    // Toggle Favorite Podcast (Only non-audiobook podcasts)
    func toggleFavoritePodcast(_ podcast: Podcast) {
        if Self.isAudiobookItem(podcast) {
            toggleFavoriteAudiobook(podcast)
            return
        }
        if favoritePodcasts.contains(where: { $0.collectionId == podcast.collectionId }) {
            favoritePodcasts.removeAll(where: { $0.collectionId == podcast.collectionId })
        } else {
            favoritePodcasts.append(podcast)
        }
    }
    
    func isFavoritePodcast(_ podcastId: Int) -> Bool {
        return favoritePodcasts.contains(where: { $0.collectionId == podcastId })
    }
    
    // Toggle Favorite Audiobook (Only appears in Books tab)
    func toggleFavoriteAudiobook(_ book: Podcast) {
        if favoriteAudiobooks.contains(where: { $0.collectionId == book.collectionId }) {
            favoriteAudiobooks.removeAll(where: { $0.collectionId == book.collectionId })
        } else {
            favoriteAudiobooks.append(book)
        }
    }
    
    func isFavoriteAudiobook(_ bookId: Int) -> Bool {
        return favoriteAudiobooks.contains(where: { $0.collectionId == bookId })
    }
    
    // Toggle Favorite Radio (Only appears in Radio tab)
    func toggleFavoriteRadio(_ stationId: String) {
        if favoriteRadios.contains(stationId) {
            favoriteRadios.removeAll(where: { $0 == stationId })
            favoriteRadioStations.removeAll(where: { $0.id == stationId })
        } else {
            favoriteRadios.append(stationId)
            if let station = cachedRadioStations.first(where: { $0.id == stationId }) {
                if !favoriteRadioStations.contains(where: { $0.id == stationId }) {
                    favoriteRadioStations.append(station)
                }
            }
        }
    }
    
    func toggleFavoriteRadioStation(_ station: RadioStation) {
        if isFavoriteRadio(station.id) {
            favoriteRadios.removeAll(where: { $0 == station.id })
            favoriteRadioStations.removeAll(where: { $0.id == station.id })
        } else {
            if !favoriteRadios.contains(station.id) {
                favoriteRadios.append(station.id)
            }
            if !favoriteRadioStations.contains(where: { $0.id == station.id }) {
                favoriteRadioStations.append(station)
            }
        }
    }
    
    func isFavoriteRadio(_ stationId: String) -> Bool {
        return favoriteRadios.contains(stationId) || favoriteRadioStations.contains(where: { $0.id == stationId })
    }
    
    // Toggle Played Episode ID
    func togglePlayedEpisode(_ episodeId: Int) {
        if playedEpisodeIds.contains(episodeId) {
            playedEpisodeIds.removeAll(where: { $0 == episodeId })
        } else {
            playedEpisodeIds.append(episodeId)
        }
    }
    
    func isPlayedEpisode(_ episodeId: Int) -> Bool {
        return playedEpisodeIds.contains(episodeId)
    }
    
    func markPlayedEpisode(_ episodeId: Int) {
        if !playedEpisodeIds.contains(episodeId) {
            playedEpisodeIds.append(episodeId)
        }
    }
    
    // Add to history
    func addToHistory(_ episode: Episode) {
        history.removeAll(where: { $0.trackId == episode.trackId })
        history.insert(episode, at: 0)
        if history.count > 50 {
            history = Array(history.prefix(50))
        }
    }
    
    // MARK: - Theme & Accent Color Helpers
    var isLightTheme: Bool {
        settings.theme == "light"
    }
    
    var primaryTextColor: Color {
        isLightTheme ? Color(red: 15/255, green: 23/255, blue: 42/255) : .white
    }
    
    var mainBackgroundColor: Color {
        switch settings.theme {
        case "light":
            return Color(red: 248/255, green: 250/255, blue: 252/255) // Slate-50
        case "black":
            return Color.black
        default:
            return Color(red: 2/255, green: 6/255, blue: 23/255) // Slate-950
        }
    }
    
    var cardBackgroundColor: Color {
        isLightTheme ? Color.white : Color.white.opacity(0.04)
    }
    
    var subtleSurfaceColor: Color {
        isLightTheme ? Color.black.opacity(0.05) : Color.white.opacity(0.07)
    }
    
    var cardBorderColor: Color {
        isLightTheme ? Color.black.opacity(0.08) : Color.white.opacity(0.06)
    }
    
    func accentColorColor() -> Color {
        switch settings.accentColor {
        case "blue": return .blue
        case "emerald": return .emeraldCustom
        case "rose": return .rose
        case "violet": return .purple
        case "amber": return .orange
        default: return .indigo
        }
    }
    
    // Dismiss / Hide episodes
    func dismissEpisode(_ episodeId: Int) {
        if !dismissedEpisodeIds.contains(episodeId) {
            dismissedEpisodeIds.append(episodeId)
        }
    }
    
    func isDismissedEpisode(_ episodeId: Int) -> Bool {
        return dismissedEpisodeIds.contains(episodeId)
    }
    
    // MARK: - Backup & Restore (Export / Import)
    struct BackupPayload: Codable {
        var version: String = "0.2"
        var exportDate: String
        var settings: AppSettingsModel
        var lang: String
        var favs: [Podcast]
        var favBooks: [Podcast]?
        var radios: [String]
        var radioStations: [RadioStation]?
        var podcastLatestDates: [Int: String]?
        var playlists: [PlaylistModel]
        var played: [Int]
        var positions: [String: Double]
        var history: [Episode]
        var dismissed: [Int]
        var lastTrendingCategory: String?
        var lastAudiobooksCategory: String?
    }
    
    func exportBackupJSONString() -> String? {
        let payload = BackupPayload(
            version: "0.2",
            exportDate: DateFormatterUtility.iso8601.string(from: Date()),
            settings: self.settings,
            lang: self.currentLanguage.rawValue,
            favs: self.favoritePodcasts,
            favBooks: self.favoriteAudiobooks,
            radios: self.favoriteRadios,
            radioStations: self.favoriteRadioStations,
            podcastLatestDates: self.podcastLatestEpisodeDates,
            playlists: self.playlists,
            played: self.playedEpisodeIds,
            positions: self.savedPositions,
            history: self.history,
            dismissed: self.dismissedEpisodeIds,
            lastTrendingCategory: self.lastTrendingCategory,
            lastAudiobooksCategory: self.lastAudiobooksCategory
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func importBackupData(_ data: Data) -> Bool {
        guard let rawObj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = rawObj as? [String: Any] else {
            return false
        }
        
        func decodeField<T: Decodable>(_ type: T.Type, keys: [String]) -> T? {
            for key in keys {
                guard let val = dict[key], !(val is NSNull) else { continue }
                if let str = val as? String, let strData = str.data(using: .utf8) {
                    if let decoded = try? JSONDecoder().decode(T.self, from: strData) {
                        return decoded
                    }
                } else if JSONSerialization.isValidJSONObject(val),
                          let objData = try? JSONSerialization.data(withJSONObject: val, options: []),
                          let decoded = try? JSONDecoder().decode(T.self, from: objData) {
                    return decoded
                }
            }
            return nil
        }
        
        var didRestoreAnything = false
        
        if let restoredSettings = decodeField(AppSettingsModel.self, keys: ["settings"]) {
            self.settings = restoredSettings
            didRestoreAnything = true
        }
        
        if let restoredFavBooks = decodeField([Podcast].self, keys: ["favBooks", "favoriteAudiobooks"]) {
            self.favoriteAudiobooks = restoredFavBooks
            didRestoreAnything = true
        }
        
        if let restoredFavs = decodeField([Podcast].self, keys: ["favs", "favorites", "favoritePodcasts"]) {
            var purePodcasts: [Podcast] = []
            var extraBooks = self.favoriteAudiobooks
            for item in restoredFavs {
                if Self.isAudiobookItem(item) {
                    if !extraBooks.contains(where: { $0.collectionId == item.collectionId }) {
                        extraBooks.append(item)
                    }
                } else {
                    purePodcasts.append(item)
                }
            }
            self.favoritePodcasts = purePodcasts
            self.favoriteAudiobooks = extraBooks
            didRestoreAnything = true
        }
        
        if let restoredRadioStations = decodeField([RadioStation].self, keys: ["radioStations", "favoriteRadioStations"]) {
            self.favoriteRadioStations = restoredRadioStations
            didRestoreAnything = true
        }
        
        if let restoredRadios = decodeField([String].self, keys: ["radios", "favoriteRadios"]) {
            self.favoriteRadios = restoredRadios
            didRestoreAnything = true
        }
        
        if let restoredDates = decodeField([Int: String].self, keys: ["podcastLatestDates"]) {
            self.podcastLatestEpisodeDates = restoredDates
            didRestoreAnything = true
        }
        
        if let restoredPlaylists = decodeField([PlaylistModel].self, keys: ["playlists"]) {
            self.playlists = restoredPlaylists
            didRestoreAnything = true
        }
        
        if let restoredPlayed = decodeField([Int].self, keys: ["played", "playedEpisodeIds"]) {
            self.playedEpisodeIds = restoredPlayed
            didRestoreAnything = true
        }
        
        if let restoredPositions = decodeField([String: Double].self, keys: ["positions", "savedPositions"]) {
            self.savedPositions = restoredPositions
            save(restoredPositions, forKey: keys.savedPositions)
            didRestoreAnything = true
        }
        
        if let restoredHistory = decodeField([Episode].self, keys: ["history"]) {
            self.history = restoredHistory
            didRestoreAnything = true
        }
        
        if let restoredDismissed = decodeField([Int].self, keys: ["dismissed", "dismissedEpisodeIds"]) {
            self.dismissedEpisodeIds = restoredDismissed
            didRestoreAnything = true
        }
        
        for key in ["lang", "language"] {
            guard let val = dict[key], !(val is NSNull) else { continue }
            var langCandidate: String? = nil
            if let str = val as? String {
                if let strData = str.data(using: .utf8),
                   let langObj = try? JSONSerialization.jsonObject(with: strData) as? [String: Any],
                   let code = langObj["code"] as? String {
                    langCandidate = code
                } else {
                    langCandidate = str
                }
            } else if let langObj = val as? [String: Any], let code = langObj["code"] as? String {
                langCandidate = code
            }
            if let candidate = langCandidate {
                let normalized = candidate.hasPrefix("fr") ? "fr" : candidate
                if let code = LangCode(rawValue: normalized) {
                    self.currentLanguage = code
                    didRestoreAnything = true
                    break
                }
            }
        }
        
        if let cat = dict["lastTrendingCategory"] as? String {
            self.lastTrendingCategory = cat
            didRestoreAnything = true
        }
        if let audioCat = dict["lastAudiobooksCategory"] as? String {
            self.lastAudiobooksCategory = audioCat
            didRestoreAnything = true
        }
        
        return didRestoreAnything
    }
}

// Custom structure for Playlists
struct PlaylistModel: Codable, Identifiable {
    var id = UUID()
    var name: String
    var episodeIds: [Int] = []
}

// Extends Color for custom colors if needed
extension Color {
    static let emeraldCustom = Color(red: 16/255, green: 185/255, blue: 129/255)
    static let rose = Color(red: 244/255, green: 63/255, blue: 94/255)
}

struct DateFormatterUtility {
    private static let lock = NSLock()
    
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    static let formatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss",
            "EEE, d MMM yyyy HH:mm:ss",
            "EEE, dd MMM yy HH:mm:ss Z",
            "EEE, d MMM yy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss zzz",
            "d MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss",
            "d MMM yyyy HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
            "dd/MM/yyyy HH:mm:ss",
            "dd/MM/yyyy HH:mm",
            "dd/MM/yyyy",
            "dd-MM-yyyy HH:mm:ss",
            "dd-MM-yyyy"
        ]
        var list: [DateFormatter] = []
        for fmt in formats {
            let posix = DateFormatter()
            posix.locale = Locale(identifier: "en_US_POSIX")
            posix.dateFormat = fmt
            list.append(posix)
            
            let french = DateFormatter()
            french.locale = Locale(identifier: "fr_FR")
            french.dateFormat = fmt
            list.append(french)
        }
        return list
    }()
    
    static let keyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    static let outputFormatters: [String: DateFormatter] = {
        var dict: [String: DateFormatter] = [:]
        for lang in LangCode.allCases {
            let df = DateFormatter()
            df.locale = Locale(identifier: lang.rawValue)
            if lang.rawValue.hasPrefix("fr") {
                df.dateFormat = "d MMM yyyy 'à' HH:mm"
            } else {
                df.dateFormat = "d MMM yyyy, HH:mm"
            }
            dict[lang.rawValue] = df
        }
        return dict
    }()
    
    static func formatISO8601(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return iso8601.string(from: date)
    }
    
    static func formatKey(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return keyFormatter.string(from: date)
    }
    
    static func formatOutput(_ date: Date, lang: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let df = outputFormatters[lang] ?? outputFormatters["fr"]!
        return df.string(from: date)
    }
    
    static func parse(_ dateStr: String?) -> Date? {
        guard let raw = dateStr else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        
        lock.lock()
        var parsed: Date? = iso8601.date(from: cleaned) ?? iso8601Fractional.date(from: cleaned)
        if parsed == nil {
            for formatter in formatters {
                if let d = formatter.date(from: cleaned) {
                    parsed = d
                    break
                }
            }
        }
        lock.unlock()
        
        guard let rawDate = parsed else { return nil }
        return sanitizeFutureDate(rawDate)
    }
    
    /// Ensures no episode ever has a publication date or time in the future
    static func sanitizeFutureDate(_ date: Date) -> Date {
        let now = Date()
        guard date > now else { return date }
        
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        
        // 1. Check if Day and Month were inverted (e.g. 02/11 vs 11/02 when both <= 12)
        if let day = comps.day, let month = comps.month,
           day <= 12, month <= 12, day != month {
            var swappedComps = comps
            swappedComps.day = month
            swappedComps.month = day
            if let swappedDate = cal.date(from: swappedComps),
               swappedDate <= now,
               now.timeIntervalSince(swappedDate) <= 120 * 86400 {
                return swappedDate
            }
        }
        
        // 2. Check if the feed tagged local time as UTC/GMT (within 14h ahead of now)
        let diff = date.timeIntervalSince(now)
        if diff <= 14 * 3600 {
            let tzOffset = TimeInterval(TimeZone.current.secondsFromGMT(for: date))
            if tzOffset > 0 {
                let tzCorrected = date.addingTimeInterval(-tzOffset)
                if tzCorrected <= now {
                    return tzCorrected
                }
            }
            // If it's a scheduled broadcast hour later today (e.g. 18:00 when it's 16:00),
            // shift back by whole hours so it stays on today's date <= now with deterministic minutes
            let hoursAhead = ceil(diff / 3600.0)
            let shifted = date.addingTimeInterval(-hoursAhead * 3600.0)
            return min(shifted, now)
        }
        
        // 3. Check if the year was mistyped (+1 year ahead, while month/day in previous year is <= now)
        if let year = comps.year {
            var prevYearComps = comps
            prevYearComps.year = year - 1
            if let prevYearDate = cal.date(from: prevYearComps),
               prevYearDate <= now,
               now.timeIntervalSince(prevYearDate) <= 366 * 86400 {
                return prevYearDate
            }
        }
        
        // 4. Fallback for future-dated avant-première / scheduled episodes: project onto today at a time <= now
        let nowComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        var todayComps = nowComps
        if let epHour = comps.hour, let epMin = comps.minute, let curHour = nowComps.hour {
            if epHour < curHour {
                todayComps.hour = epHour
                todayComps.minute = epMin
            }
        }
        if let clampedToday = cal.date(from: todayComps), clampedToday <= now {
            return clampedToday
        }
        return now
    }
}
