import WidgetKit
import SwiftUI
import AppIntents

struct WidgetEpisodeItem: Codable, Identifiable {
    var id: Int { trackId }
    let trackId: Int
    let trackName: String
    let collectionName: String
    let releaseDate: String?
    let artworkUrl: String?
    let previewUrl: String?
    let durationMinutes: Int?
}

struct WidgetSubscribedPodcastInfo: Codable {
    let collectionId: Int
    let collectionName: String
    let artworkUrl: String?
    let feedUrl: String?
    let country: String?
}

struct WidgetContentEntry: TimelineEntry {
    let date: Date
    let latestEpisodes: [WidgetEpisodeItem]
    let currentTrackName: String
    let currentSubtitle: String
    let isPlaying: Bool
}

// MARK: - Shared Storage Reader / Fetcher for Widget & AppIntent
enum WidgetSharedStore {
    static let appGroupId = "group.com.podcastultra.app"
    
    static func sharedEpisodesFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("widget_episodes.json")
    }
    
    static func sharedPodcastsFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("widget_podcasts.json")
    }
    
    static func loadSavedEpisodes() -> [WidgetEpisodeItem] {
        let decoder = JSONDecoder()
        
        // 1. Check App Group container file (most immediate across processes)
        if let fileURL = sharedEpisodesFileURL(),
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([WidgetEpisodeItem].self, from: data),
           !decoded.isEmpty {
            return Array(decoded.prefix(5))
        }
        
        // 2. Check App Group UserDefaults
        let sharedDefaults = UserDefaults(suiteName: appGroupId)
        if let data = sharedDefaults?.data(forKey: "widgetLatestEpisodes"),
           let decoded = try? decoder.decode([WidgetEpisodeItem].self, from: data),
           !decoded.isEmpty {
            return Array(decoded.prefix(5))
        }
        
        // 3. Check /tmp fallback (for Simulator / unsigned dev builds)
        let tmpURL = URL(fileURLWithPath: "/tmp/podcastultra_widget_episodes.json")
        if let data = try? Data(contentsOf: tmpURL),
           let decoded = try? decoder.decode([WidgetEpisodeItem].self, from: data),
           !decoded.isEmpty {
            return Array(decoded.prefix(5))
        }
        
        // 4. Legacy single-episode keys fallback
        if let fallbackTitle = sharedDefaults?.string(forKey: "latestEpisodeTitle"),
           !fallbackTitle.isEmpty {
            let fallbackSub = sharedDefaults?.string(forKey: "latestEpisodeSubtitle") ?? "Podcast"
            return [
                WidgetEpisodeItem(
                    trackId: 0,
                    trackName: fallbackTitle,
                    collectionName: fallbackSub,
                    releaseDate: nil,
                    artworkUrl: sharedDefaults?.string(forKey: "latestEpisodeArtworkUrl"),
                    previewUrl: nil,
                    durationMinutes: nil
                )
            ]
        }
        
        return []
    }
    
    static func loadSubscribedPodcasts() -> [WidgetSubscribedPodcastInfo] {
        let decoder = JSONDecoder()
        
        if let fileURL = sharedPodcastsFileURL(),
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([WidgetSubscribedPodcastInfo].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        
        if let sharedDefaults = UserDefaults(suiteName: appGroupId),
           let data = sharedDefaults.data(forKey: "widgetSubscribedPodcasts"),
           let decoded = try? decoder.decode([WidgetSubscribedPodcastInfo].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        
        let tmpURL = URL(fileURLWithPath: "/tmp/podcastultra_widget_podcasts.json")
        if let data = try? Data(contentsOf: tmpURL),
           let decoded = try? decoder.decode([WidgetSubscribedPodcastInfo].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        
        return []
    }
    
    static func saveEpisodes(_ episodes: [WidgetEpisodeItem]) {
        let top5 = Array(episodes.prefix(5))
        guard let encoded = try? JSONEncoder().encode(top5) else { return }
        if let sharedDefaults = UserDefaults(suiteName: appGroupId) {
            sharedDefaults.set(encoded, forKey: "widgetLatestEpisodes")
            sharedDefaults.synchronize()
        }
        if let fileURL = sharedEpisodesFileURL() {
            try? encoded.write(to: fileURL, options: .atomic)
        }
        try? encoded.write(to: URL(fileURLWithPath: "/tmp/podcastultra_widget_episodes.json"), options: .atomic)
    }
    
    static func fetchLiveEpisodesFromSubscriptions() async -> [WidgetEpisodeItem] {
        let subs = loadSubscribedPodcasts()
        guard !subs.isEmpty else { return [] }
        
        struct ITunesLookupResponse: Codable {
            struct Item: Codable {
                let wrapperType: String?
                let trackId: Int?
                let trackName: String?
                let collectionName: String?
                let releaseDate: String?
                let artworkUrl100: String?
                let previewUrl: String?
                let trackTimeMillis: Int?
            }
            let results: [Item]
        }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()
        
        func parseSafeDate(_ raw: String?) -> Date {
            guard let s = raw else { return .distantPast }
            if let d = isoFormatter.date(from: s) ?? isoFractional.date(from: s) {
                return d > now ? now : d
            }
            return .distantPast
        }
        
        var all: [(date: Date, item: WidgetEpisodeItem)] = []
        
        for sub in subs.prefix(8) {
            let country = sub.country ?? "fr"
            guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(sub.collectionId)&entity=podcastEpisode&limit=6&country=\(country)&_v=\(Int(now.timeIntervalSince1970))") else { continue }
            if let (respData, _) = try? await URLSession.shared.data(from: url),
               let lookup = try? JSONDecoder().decode(ITunesLookupResponse.self, from: respData) {
                // Keep longest per day per podcast to match the Episodes tab behavior
                var byDay: [String: (date: Date, millis: Int, item: WidgetEpisodeItem)] = [:]
                let dayFmt = DateFormatter()
                dayFmt.locale = Locale(identifier: "en_US_POSIX")
                dayFmt.dateFormat = "yyyy-MM-dd"
                
                for res in lookup.results.dropFirst() {
                    guard let tId = res.trackId, let tName = res.trackName else { continue }
                    let d = parseSafeDate(res.releaseDate)
                    let dayKey = dayFmt.string(from: d)
                    let millis = res.trackTimeMillis ?? 0
                    let epItem = WidgetEpisodeItem(
                        trackId: tId,
                        trackName: tName,
                        collectionName: res.collectionName ?? sub.collectionName,
                        releaseDate: isoFormatter.string(from: d),
                        artworkUrl: res.artworkUrl100 ?? sub.artworkUrl,
                        previewUrl: res.previewUrl,
                        durationMinutes: res.trackTimeMillis.map { max(1, $0 / 60000) }
                    )
                    if let existing = byDay[dayKey] {
                        if millis > existing.millis {
                            byDay[dayKey] = (d, millis, epItem)
                        }
                    } else {
                        byDay[dayKey] = (d, millis, epItem)
                    }
                }
                for val in byDay.values {
                    all.append((val.date, val.item))
                }
            }
        }
        
        let sorted = all.sorted { $0.date > $1.date }.map { $0.item }
        let top5 = Array(sorted.prefix(5))
        if !top5.isEmpty {
            saveEpisodes(top5)
        }
        return top5
    }
}

// MARK: - Interactive Refresh Intent for Widget Button (iOS 17+)
@available(iOS 17.0, *)
struct RefreshWidgetEpisodesIntent: AppIntent {
    static var title: LocalizedStringResource = "Actualiser les épisodes"
    static var description = IntentDescription("Actualise la liste des 5 derniers épisodes sur le widget.")
    
    init() {}
    
    func perform() async throws -> some IntentResult {
        let live = await WidgetSharedStore.fetchLiveEpisodesFromSubscriptions()
        if live.isEmpty {
            _ = WidgetSharedStore.loadSavedEpisodes()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct Provider: TimelineProvider {
    private static let sampleEpisodes: [WidgetEpisodeItem] = [
        WidgetEpisodeItem(trackId: 1, trackName: "Les Grosses Têtes - Intégrale du jour", collectionName: "Les Grosses Têtes", releaseDate: nil, artworkUrl: nil, previewUrl: nil, durationMinutes: 95),
        WidgetEpisodeItem(trackId: 2, trackName: "Hondelatte Raconte : L'affaire mystérieuse", collectionName: "Hondelatte Raconte", releaseDate: nil, artworkUrl: nil, previewUrl: nil, durationMinutes: 42),
        WidgetEpisodeItem(trackId: 3, trackName: "L'After Foot - Débrief complet", collectionName: "L'After Foot", releaseDate: nil, artworkUrl: nil, previewUrl: nil, durationMinutes: 60),
        WidgetEpisodeItem(trackId: 4, trackName: "Affaires Sensibles - Histoire contemporaine", collectionName: "Affaires Sensibles", releaseDate: nil, artworkUrl: nil, previewUrl: nil, durationMinutes: 52),
        WidgetEpisodeItem(trackId: 5, trackName: "Transfert - Récit de vie", collectionName: "Transfert", releaseDate: nil, artworkUrl: nil, previewUrl: nil, durationMinutes: 38)
    ]
    
    func placeholder(in context: Context) -> WidgetContentEntry {
        WidgetContentEntry(
            date: Date(),
            latestEpisodes: Self.sampleEpisodes,
            currentTrackName: "",
            currentSubtitle: "",
            isPlaying: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetContentEntry) -> ()) {
        let entry = loadEntryFromSharedDefaults()
        completion(entry.latestEpisodes.isEmpty ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            var entry = loadEntryFromSharedDefaults()
            if entry.latestEpisodes.isEmpty {
                let fetched = await WidgetSharedStore.fetchLiveEpisodesFromSubscriptions()
                if !fetched.isEmpty {
                    entry = WidgetContentEntry(
                        date: Date(),
                        latestEpisodes: Array(fetched.prefix(5)),
                        currentTrackName: entry.currentTrackName,
                        currentSubtitle: entry.currentSubtitle,
                        isPlaying: entry.isPlaying
                    )
                }
            }
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
    
    private func loadEntryFromSharedDefaults() -> WidgetContentEntry {
        let sharedDefaults = UserDefaults(suiteName: WidgetSharedStore.appGroupId)
        let isPlaying = sharedDefaults?.bool(forKey: "isPlaying") ?? false
        let currentTrackName = sharedDefaults?.string(forKey: "currentTrackName") ?? ""
        let currentSubtitle = sharedDefaults?.string(forKey: "currentSubtitle") ?? ""
        let episodes = WidgetSharedStore.loadSavedEpisodes()
        
        return WidgetContentEntry(
            date: Date(),
            latestEpisodes: episodes,
            currentTrackName: currentTrackName,
            currentSubtitle: currentSubtitle,
            isPlaying: isPlaying
        )
    }
}

// MARK: - Reusable Widget Refresh Button (Interactive AppIntent on iOS 17+ / Deep-Link on iOS 16)
struct WidgetRefreshButton: View {
    var compact: Bool = false
    
    var body: some View {
        if #available(iOS 17.0, *) {
            Button(intent: RefreshWidgetEpisodesIntent()) {
                refreshLabel
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: URL(string: "podcastultra://refresh-episodes")!) {
                refreshLabel
            }
        }
    }
    
    private var refreshLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: compact ? 8 : 9, weight: .black))
            if !compact {
                Text("Actualiser")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 3 : 3.5)
        .background(Color(red: 99/255, green: 102/255, blue: 241/255).opacity(0.35))
        .overlay(
            Capsule()
                .stroke(Color(red: 99/255, green: 102/255, blue: 241/255).opacity(0.6), lineWidth: 0.8)
        )
        .clipShape(Capsule())
    }
}

struct PodcastUltraWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            Color(red: 2/255, green: 6/255, blue: 23/255)
                .ignoresSafeArea()
            
            switch family {
            case .systemSmall:
                SmallEpisodesWidgetView(entry: entry)
            case .systemLarge:
                LargeEpisodesWidgetView(entry: entry)
            default:
                MediumEpisodesWidgetView(entry: entry)
            }
        }
    }
}

// MARK: - Small Widget (Compact 5 Latest Episodes List + Refresh Button)
struct SmallEpisodesWidgetView: View {
    let entry: WidgetContentEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                Text("5 DERNIERS")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                    .lineLimit(1)
                Spacer(minLength: 2)
                WidgetRefreshButton(compact: true)
            }
            .padding(.bottom, 1)
            
            if entry.latestEpisodes.isEmpty {
                Spacer()
                Text("Touchez ↻ ou ouvrez l'app pour charger vos 5 derniers épisodes.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
            } else {
                ForEach(Array(entry.latestEpisodes.prefix(5).enumerated()), id: \.offset) { idx, ep in
                    Link(destination: URL(string: "podcastultra://play-episode?id=\(ep.trackId)")!) {
                        HStack(spacing: 4) {
                            Text("\(idx + 1).")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                                .frame(width: 11, alignment: .leading)
                            Text(ep.trackName)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
    }
}

// MARK: - Medium Widget (Displays all 5 Latest Episodes from Episodes Tab + Refresh Button)
struct MediumEpisodesWidgetView: View {
    let entry: WidgetContentEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header with Refresh Button
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                    Text("5 DERNIERS ÉPISODES")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                        .tracking(0.4)
                }
                Spacer()
                if entry.isPlaying {
                    Link(destination: URL(string: "podcastultra://toggle-play")!) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                            Text("LECTURE")
                                .font(.system(size: 7.5, weight: .black))
                                .foregroundColor(.green)
                        }
                    }
                }
                WidgetRefreshButton(compact: false)
            }
            .padding(.bottom, 2)
            
            if entry.latestEpisodes.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 5) {
                        Image(systemName: "waveform.circle")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.4))
                        Text("Touchez Actualiser ou ouvrez Podcast Ultra pour afficher vos 5 derniers épisodes")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(entry.latestEpisodes.prefix(5).enumerated()), id: \.offset) { idx, ep in
                        Link(destination: URL(string: "podcastultra://play-episode?id=\(ep.trackId)")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                                
                                Text(ep.trackName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                Spacer(minLength: 4)
                                
                                Text(ep.collectionName)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.55))
                                    .lineLimit(1)
                                    .frame(maxWidth: 95, alignment: .trailing)
                            }
                            .padding(.vertical, 1.5)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Large Widget (Detailed 5 Latest Episodes with Podcast Name, Duration & Refresh Button)
struct LargeEpisodesWidgetView: View {
    let entry: WidgetContentEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                    Text("5 DERNIERS ÉPISODES")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                        .tracking(0.6)
                }
                Spacer()
                WidgetRefreshButton(compact: false)
                Link(destination: URL(string: "podcastultra://toggle-play")!) {
                    HStack(spacing: 4) {
                        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(entry.isPlaying ? "Pause" : "Lecture")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(red: 99/255, green: 102/255, blue: 241/255))
                    .cornerRadius(10)
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            if entry.latestEpisodes.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("Touchez Actualiser ou ouvrez Podcast Ultra pour charger vos 5 derniers épisodes.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                Spacer()
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(entry.latestEpisodes.prefix(5).enumerated()), id: \.offset) { index, ep in
                        Link(destination: URL(string: "podcastultra://play-episode?id=\(ep.trackId)")!) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 99/255, green: 102/255, blue: 241/255).opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ep.trackName)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 6) {
                                        Text(ep.collectionName)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                                            .lineLimit(1)
                                        
                                        if let mins = ep.durationMinutes {
                                            Text("• \(mins) min")
                                                .font(.system(size: 9))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
    }
}

@main
struct PodcastUltraWidget: Widget {
    let kind: String = "PodcastUltraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PodcastUltraWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Podcast Ultra • 5 Derniers Épisodes")
        .description("Affiche les 5 derniers épisodes tels qu'ils apparaissent dans votre onglet Épisodes avec bouton Actualiser.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
