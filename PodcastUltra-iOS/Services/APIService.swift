import Foundation

class APIService {
    static let shared = APIService()
    
    private let iTunesSearchURL = "https://itunes.apple.com/search"
    
    // In-memory cache of verified audiobook episodes so opening a book is instant
    private let bookEpisodesLock = NSLock()
    private var cachedBookEpisodes: [Int: [Episode]] = [:]
    
    func getCachedBookEpisodes(for collectionId: Int) -> [Episode]? {
        bookEpisodesLock.lock()
        defer { bookEpisodesLock.unlock() }
        return cachedBookEpisodes[collectionId]
    }
    
    func setCachedBookEpisodes(_ episodes: [Episode], for collectionId: Int) {
        bookEpisodesLock.lock()
        cachedBookEpisodes[collectionId] = episodes
        bookEpisodesLock.unlock()
    }
    private let iTunesLookupURL = "https://itunes.apple.com/lookup"
    private let radioAPIBase = "https://de1.api.radio-browser.info/json/stations"
    
    // Genres mapping
    private let podcastGenres: [String: String] = [
        "News": "1489",
        "Comedy": "1303",
        "Technology": "1318",
        "Business": "1321",
        "Society & Culture": "1324",
        "True Crime": "1488",
        "Health": "1512",
        "Education": "1304",
        "History": "1487",
        "Music": "1310",
        "Science": "1533",
        "Sports": "1323"
    ]
    
    // Top French podcasts IDs for priority load (matching React TOP_IDS)
    private let frenchMarketTopIds = [
        369369012,  // Les Grosses Têtes
        1146402624, // Hondelatte Raconte
        140644703,  // L'After Foot
        912451024,  // Affaires Sensibles
        357494553,  // L'heure du crime
        1684814320, // Passé sous silence
        589182365,  // Transfert
        1546899313  // Home(icides)
    ]
    
    struct ITunesResponse<T: Codable>: Codable {
        let results: [T]
    }
    
    // Search podcasts on iTunes
    func searchPodcasts(term: String, country: String = "us") async throws -> [Podcast] {
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(iTunesSearchURL)?term=\(encodedTerm)&entity=podcast&limit=150&country=\(country)") else {
            return []
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ITunesResponse<Podcast>.self, from: data)
        return response.results
    }
    
    // Lookup multiple podcasts by their iTunes IDs
    func getPodcastsByIds(ids: [Int], country: String = "us") async throws -> [Podcast] {
        guard !ids.isEmpty else { return [] }
        let idsString = ids.map { String($0) }.joined(separator: ",")
        guard let url = URL(string: "\(iTunesLookupURL)?id=\(idsString)&country=\(country)&_v=\(Date().timeIntervalSince1970)") else {
            return []
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ITunesResponse<Podcast>.self, from: data)
        return response.results
    }
    
    // Search radio stations from radio-browser
    func searchRadioStations(term: String) async throws -> [RadioStation] {
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(radioAPIBase)/byname/\(encodedTerm)?limit=50&order=clickcount&reverse=true") else {
            return []
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return parseRadioJSON(data)
    }
    
    // Fetch radio stations by language / query
    func getRadioStations(radioSearch: String, langCode: String) async throws -> [RadioStation] {
        let langName = radioSearch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard let url = URL(string: "\(radioAPIBase)/bylanguage/\(langName)?limit=100&order=clickcount&reverse=true") else {
            return []
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let stations = parseRadioJSON(data)
        
        // Dynamic deduplication & sorting matching TypeScript
        return sortRadioStations(stations, langCode: langCode)
    }
    
    private func parseRadioJSON(_ data: Data) -> [RadioStation] {
        struct RadioAPIResponse: Codable {
            let stationuuid: String
            let name: String
            let url_resolved: String
            let favicon: String?
            let homepage: String?
            let tags: String?
            let country: String?
            let language: String?
            let clickcount: Int?
        }
        
        guard let apiResponses = try? JSONDecoder().decode([RadioAPIResponse].self, from: data) else {
            return []
        }
        
        return apiResponses.map { response in
            let fav = RadioIconHelper.resolvedFaviconString(
                name: response.name,
                rawFavicon: response.favicon,
                homepage: response.homepage
            )
            return RadioStation(
                id: response.stationuuid,
                name: response.name,
                url: response.url_resolved,
                favicon: fav,
                tags: response.tags,
                country: response.country,
                language: response.language,
                clickcount: response.clickcount,
                homepage: response.homepage
            )
        }
    }
    
    private func sortRadioStations(_ stations: [RadioStation], langCode: String) -> [RadioStation] {
        // Deduplicate stations by normalized name prefix
        var seenBrands = [String: RadioStation]()
        for station in stations {
            let normalized = station.name.lowercased()
                .components(separatedBy: " - ")[0]
                .components(separatedBy: " (")[0]
                .components(separatedBy: " [")[0]
                .replacingOccurrences(of: "\\d+kbps", with: "", options: .regularExpression)
                .replacingOccurrences(of: "fm$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let existing = seenBrands[normalized] {
                if (station.clickcount ?? 0) > (existing.clickcount ?? 0) {
                    seenBrands[normalized] = station
                }
            } else {
                seenBrands[normalized] = station
            }
        }
        
        let deduplicated = Array(seenBrands.values)
        
        let topRadios: [String: [String]] = [
            "fr": ["RTL", "RTL2", "Fun Radio", "France Inter", "France Info", "France Culture", "Europe 1", "Europe 2", "RFM", "RMC", "NRJ", "Nostalgie", "Skyrock", "FIP"],
            "en": ["BBC World Service", "NPR", "CNN", "WNYC"]
        ]
        
        let tops = topRadios[langCode] ?? []
        return deduplicated.sorted { a, b in
            let aName = a.name.lowercased()
            let bName = b.name.lowercased()
            
            let aPriority = tops.firstIndex(where: { aName.contains($0.lowercased()) }) ?? -1
            let bPriority = tops.firstIndex(where: { bName.contains($0.lowercased()) }) ?? -1
            
            if aPriority != -1 && bPriority != -1 {
                return aPriority < bPriority
            }
            if aPriority != -1 { return true }
            if bPriority != -1 { return false }
            
            return (b.clickcount ?? 0) < (a.clickcount ?? 0)
        }
    }
    
    private func parseRSSDate(_ dateStr: String) -> Date? {
        return DateFormatterUtility.parse(dateStr)
    }
    
    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities = [
            "&amp;": "&",
            "&apos;": "'",
            "&quot;": "\"",
            "&lt;": "<",
            "&gt;": ">",
            "&#39;": "'",
            "&#039;": "'",
            "&#x27;": "'",
            "&nbsp;": " ",
            "&rdquo;": "”",
            "&ldquo;": "“",
            "&lsquo;": "‘",
            "&rsquo;": "’",
            "&ndash;": "–",
            "&mdash;": "—",
            "&#8211;": "–",
            "&#8217;": "’",
            "&#8216;": "‘",
            "&#8220;": "“",
            "&#8221;": "”"
        ]
        
        for (entity, val) in entities {
            result = result.replacingOccurrences(of: entity, with: val)
        }
        
        return result
    }
    
    private func parseRSSFeed(xmlText: String, collectionId: Int) -> [Episode] {
        var episodes = [Episode]()
        
        var channelTitle = "Podcast"
        if let channelTitleRange = xmlText.range(of: "<channel>[\\s\\S]*?<title>([\\s\\S]*?)</title>", options: .regularExpression) {
            let matched = String(xmlText[channelTitleRange])
            if let startRange = matched.range(of: "<title>"), let endRange = matched.range(of: "</title>") {
                channelTitle = decodeHTMLEntities(
                    String(matched[startRange.upperBound..<endRange.lowerBound])
                        .replacingOccurrences(of: "<![CDATA[", with: "")
                        .replacingOccurrences(of: "]]>", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        
        let itemPattern = "<item>([\\s\\S]*?)</item>"
        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: []) else { return [] }
        let nsString = xmlText as NSString
        let matches = regex.matches(in: xmlText, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for (index, match) in matches.enumerated() {
            let block = nsString.substring(with: match.range(at: 1))
            let nsBlock = block as NSString
            
            func extractTag(_ tag: String) -> String {
                let patterns = [
                    "<\(tag)>([\\s\\S]*?)</\(tag)>",
                    "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
                ]
                for pat in patterns {
                    if let r = try? NSRegularExpression(pattern: pat, options: []),
                       let m = r.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)) {
                        let range = m.range(at: 1)
                        if range.location != NSNotFound {
                            return nsBlock.substring(with: range)
                                .replacingOccurrences(of: "<![CDATA[", with: "")
                                .replacingOccurrences(of: "]]>", with: "")
                                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        }
                    }
                }
                return ""
            }
            
            var title = extractTag("title")
            if title.isEmpty { title = extractTag("itunes:title") }
            
            var description = extractTag("description")
            if description.isEmpty { description = extractTag("itunes:summary") }
            if description.isEmpty { description = extractTag("content:encoded") }
            description = description.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            
            let pubDate = extractTag("pubDate")
            var releaseDateStr: String? = nil
            if !pubDate.isEmpty, let parsedDate = parseRSSDate(pubDate) {
                releaseDateStr = DateFormatterUtility.formatISO8601(parsedDate)
            }
            
            var artistName = extractTag("itunes:author")
            if artistName.isEmpty { artistName = extractTag("author") }
            
            var previewUrl = ""
            if let encRegex = try? NSRegularExpression(pattern: "<enclosure[^>]+url=\"([^\"]+)\"", options: [.caseInsensitive]),
               let encMatch = encRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)) {
                let range = encMatch.range(at: 1)
                if range.location != NSNotFound {
                    previewUrl = nsBlock.substring(with: range)
                }
            }
            
            let durationStr = extractTag("itunes:duration")
            var trackTimeMillis = 0
            if !durationStr.isEmpty {
                if durationStr.contains(":") {
                    let parts = durationStr.split(separator: ":").compactMap { Double($0) }
                    if parts.count == 3 {
                        trackTimeMillis = Int(((parts[0] * 3600) + (parts[1] * 60) + parts[2]) * 1000)
                    } else if parts.count == 2 {
                        trackTimeMillis = Int(((parts[0] * 60) + parts[1]) * 1000)
                    }
                } else if let secs = Double(durationStr) {
                    trackTimeMillis = Int(secs * 1000)
                }
            }
            if trackTimeMillis == 0 {
                trackTimeMillis = 1800 * 1000
            }
            
            var artworkUrl = ""
            if let imgRegex = try? NSRegularExpression(pattern: "<itunes:image[^>]+href=\"([^\"]+)\"", options: [.caseInsensitive]),
               let imgMatch = imgRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)) {
                let range = imgMatch.range(at: 1)
                if range.location != NSNotFound {
                    artworkUrl = nsBlock.substring(with: range)
                }
            }
            
            var trackId = collectionId * 1000 + index
            if !previewUrl.isEmpty {
                trackId = previewUrl.unicodeScalars.reduce(0) { $0 + Int($1.value) } + index
            }
            
            if !previewUrl.isEmpty {
                let ep = Episode(
                    trackId: trackId,
                    trackName: decodeHTMLEntities(title),
                    description: decodeHTMLEntities(description),
                    releaseDate: releaseDateStr,
                    previewUrl: previewUrl,
                    trackTimeMillis: trackTimeMillis,
                    artworkUrl60: artworkUrl.isEmpty ? nil : artworkUrl,
                    artworkUrl160: artworkUrl.isEmpty ? nil : artworkUrl,
                    artworkUrl600: artworkUrl.isEmpty ? nil : artworkUrl,
                    collectionName: channelTitle,
                    collectionId: collectionId,
                    artistName: artistName.isEmpty ? nil : decodeHTMLEntities(artistName)
                )
                episodes.append(ep)
            }
        }
        
        return episodes
    }
    
    private func fetchFeed(feedUrl: String) async -> String? {
        guard let url = URL(string: feedUrl) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error fetching RSS feed: \(error)")
            return nil
        }
    }
    
    private func extractRssFromApplePodcasts(collectionId: Int) async -> String? {
        let urlString = "https://podcasts.apple.com/podcast/id\(collectionId)"
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let html = String(data: data, encoding: .utf8) {
                let patterns = [
                    "\"feedUrl\"\\s*:\\s*\"([^\"]+)\"",
                    "<link[^>]+type=\"application/rss\\+xml\"[^>]+href=\"([^\"]+)\"",
                    "href=\"([^\"]+)\"[^>]+type=\"application/rss\\+xml\""
                ]
                let nsHtml = html as NSString
                for pat in patterns {
                    if let r = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]),
                       let m = r.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length)) {
                        let range = m.range(at: 1)
                        if range.location != NSNotFound {
                            return nsHtml.substring(with: range)
                        }
                    }
                }
            }
        } catch {
            print("Error fetching Apple Podcast page: \(error)")
        }
        return nil
    }

    // Fetch episodes for a podcast
    func getPodcastEpisodes(collectionId: Int, preferredCountry: String? = nil, feedUrl: String? = nil) async throws -> [Episode] {
        if let cached = getCachedBookEpisodes(for: collectionId), !cached.isEmpty {
            return cached
        }
        
        // A. Custom handler for Litterature Audio (30000000...40000000)
        if collectionId >= 30000000 && collectionId < 40000000 {
            let postId = collectionId - 30000000
            guard let postUrl = URL(string: "https://www.litteratureaudio.com/wp-json/wp/v2/posts/\(postId)") else { return [] }
            
            struct WPPost: Codable {
                struct RenderedText: Codable {
                    let rendered: String
                }
                struct WPMeta: Codable {
                    let type: String?
                    let post: String?
                    let items: [String]?
                    let stream: String?
                    let download_url: String?
                    let duration: Int?
                }
                let id: Int
                let date: String
                let title: RenderedText
                let excerpt: RenderedText
                let meta: WPMeta?
            }
            
            do {
                let (postData, _) = try await URLSession.shared.data(from: postUrl)
                let post = try JSONDecoder().decode(WPPost.self, from: postData)
                let meta = post.meta
                let colName = post.title.rendered
                    .replacingOccurrences(of: "&#8211;", with: "-")
                    .replacingOccurrences(of: "&#8217;", with: "'")
                
                if meta?.type == "playlist" {
                    var ids = [Int]()
                    if let postStr = meta?.post, !postStr.isEmpty {
                        ids = postStr.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    } else if let items = meta?.items {
                        ids = items.compactMap { item in
                            let parts = item.split(separator: ":")
                            if let first = parts.first {
                                return Int(first.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            return nil
                        }
                    }
                    
                    if !ids.isEmpty {
                        let idsString = ids.map { String($0) }.joined(separator: ",")
                        if let childrenUrl = URL(string: "https://www.litteratureaudio.com/wp-json/wp/v2/posts?include=\(idsString)&per_page=100") {
                            let (childrenData, _) = try await URLSession.shared.data(from: childrenUrl)
                            let children = try JSONDecoder().decode([WPPost].self, from: childrenData)
                            
                            // Map child posts to Episode, sorting in original ID order
                            return ids.compactMap { id in
                                guard let child = children.first(where: { $0.id == id }) else { return nil }
                                let streamUrl = child.meta?.stream ?? child.meta?.download_url ?? ""
                                guard !streamUrl.isEmpty else { return nil }
                                let rawDur = child.meta?.duration ?? 1800000
                                let duration = (rawDur > 0 && rawDur < 86400) ? (rawDur * 1000) : rawDur
                                
                                let cleanTitle = child.title.rendered
                                    .replacingOccurrences(of: "&#8211;", with: "-")
                                    .replacingOccurrences(of: "&#8217;", with: "'")
                                let cleanDesc = child.excerpt.rendered
                                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                                    .replacingOccurrences(of: "&#8211;", with: "-")
                                    .replacingOccurrences(of: "&#8217;", with: "'")
                                
                                return Episode(
                                    trackId: child.id,
                                    trackName: cleanTitle,
                                    description: cleanDesc,
                                    releaseDate: child.date,
                                    previewUrl: streamUrl,
                                    trackTimeMillis: duration,
                                    artworkUrl60: "https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png",
                                    artworkUrl160: "https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png",
                                    artworkUrl600: "https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png",
                                    collectionName: colName,
                                    collectionId: collectionId,
                                    artistName: "Littérature Audio"
                                )
                            }
                        }
                    }
                } else {
                    // Single file
                    if let streamUrl = meta?.stream ?? meta?.download_url, !streamUrl.isEmpty {
                        let rawDur = meta?.duration ?? 1800000
                        let duration = (rawDur > 0 && rawDur < 86400) ? (rawDur * 1000) : rawDur
                        let cleanTitle = post.title.rendered
                            .replacingOccurrences(of: "&#8211;", with: "-")
                            .replacingOccurrences(of: "&#8217;", with: "'")
                        let cleanDesc = post.excerpt.rendered
                            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                            .replacingOccurrences(of: "&#8211;", with: "-")
                            .replacingOccurrences(of: "&#8217;", with: "'")
                        
                        return [Episode(
                            trackId: post.id,
                            trackName: cleanTitle,
                            description: cleanDesc,
                            releaseDate: post.date,
                            previewUrl: streamUrl,
                            trackTimeMillis: duration,
                            artworkUrl60: "https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png",
                            artworkUrl160: "https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png",
                            artworkUrl600: "https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png",
                            collectionName: colName,
                            collectionId: collectionId,
                            artistName: "Littérature Audio"
                        )]
                    }
                }
            } catch {
                print("Error loading Litterature Audio podcast episodes: \(error)")
            }
        }

        var resolvedFeedUrl = feedUrl

        if let urlToFetch = resolvedFeedUrl, !urlToFetch.isEmpty {
            if let xml = await fetchFeed(feedUrl: urlToFetch) {
                let parsed = parseRSSFeed(xmlText: xml, collectionId: collectionId)
                if !parsed.isEmpty {
                    return parsed
                }
            }
        }

        func attempt(country: String?) async throws -> [Episode]? {
            var urlString = "\(iTunesLookupURL)?id=\(collectionId)&entity=podcastEpisode&limit=200&_v=\(Date().timeIntervalSince1970)"
            if let c = country {
                urlString += "&country=\(c.lowercased())"
            }
            guard let url = URL(string: urlString) else { return nil }
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Decodes standard lookup results
            struct LookupResponse: Codable {
                let results: [LookupResult]
            }
            struct LookupResult: Codable {
                let wrapperType: String?
                let collectionId: Int?
                let collectionName: String?
                let trackId: Int
                let trackName: String?
                let description: String?
                let releaseDate: String?
                let trackTimeMillis: Int?
                let artworkUrl60: String?
                let artworkUrl100: String?
                let artworkUrl600: String?
                let artistName: String?
                let previewUrl: String?
                let feedUrl: String?
            }
            
            let response = try JSONDecoder().decode(LookupResponse.self, from: data)
            if let first = response.results.first, let fUrl = first.feedUrl {
                resolvedFeedUrl = fUrl
            }
            
            if response.results.count > 1 {
                return response.results.suffix(from: 1).map { res in
                    let normalizedDate = DateFormatterUtility.parse(res.releaseDate).map { DateFormatterUtility.formatISO8601($0) } ?? res.releaseDate
                    return Episode(
                        trackId: res.trackId,
                        trackName: res.trackName ?? "",
                        description: res.description,
                        releaseDate: normalizedDate,
                        previewUrl: res.previewUrl,
                        trackTimeMillis: res.trackTimeMillis,
                        artworkUrl60: res.artworkUrl60,
                        artworkUrl160: res.artworkUrl100,
                        artworkUrl600: res.artworkUrl600,
                        collectionName: res.collectionName,
                        collectionId: collectionId,
                        artistName: res.artistName
                    )
                }
            } else if response.results.count == 1 && response.results[0].wrapperType == "audiobook" {
                let b = response.results[0]
                let normalizedDate = DateFormatterUtility.parse(b.releaseDate).map { DateFormatterUtility.formatISO8601($0) } ?? b.releaseDate
                return [Episode(
                    trackId: b.collectionId ?? 0,
                    trackName: b.collectionName ?? "",
                    description: b.description ?? b.collectionName,
                    releaseDate: normalizedDate,
                    previewUrl: b.previewUrl,
                    trackTimeMillis: b.trackTimeMillis ?? 0,
                    artworkUrl60: b.artworkUrl60,
                    artworkUrl160: b.artworkUrl100,
                    artworkUrl600: b.artworkUrl600,
                    collectionName: b.collectionName,
                    collectionId: b.collectionId,
                    artistName: b.artistName
                )]
            }
            return nil
        }
        
        var iTunesResults: [Episode]? = nil
        if let country = preferredCountry {
            iTunesResults = try? await attempt(country: country)
        }
        if iTunesResults == nil {
            iTunesResults = try? await attempt(country: nil)
        }
        if iTunesResults == nil, preferredCountry != "fr" {
            iTunesResults = try? await attempt(country: "fr")
        }
        if iTunesResults == nil, preferredCountry != "us" {
            iTunesResults = try? await attempt(country: "us")
        }
        
        if let results = iTunesResults, !results.isEmpty {
            return results
        }
        
        // Lookup failed or returned no episodes, try global RSS parsing
        var rssUrl = resolvedFeedUrl
        let isCustomBook = collectionId >= 10000000 && collectionId < 40000000
        if rssUrl == nil && !isCustomBook {
            rssUrl = await extractRssFromApplePodcasts(collectionId: collectionId)
        }
        
        if let urlToFetch = rssUrl {
            if let xml = await fetchFeed(feedUrl: urlToFetch) {
                let parsed = parseRSSFeed(xmlText: xml, collectionId: collectionId)
                if !parsed.isEmpty {
                    return parsed
                }
            }
        }
        
        return []
    }
    
    // Fetch Trending Podcasts (Apple RSS Feed Top Charts + optional Genre Filter)
    func getTrendingPodcasts(country: String = "us", category: String = "All") async throws -> [Podcast] {
        var validPodcasts = [Podcast]()
        var manualIds = Set<Int>()
        let genreId = category != "All" ? podcastGenres[category] : nil
        
        // 1. Hardcoded ACPM Premium for France/Belgium
        if country == "fr" || country == "be" {
            if let mResults = try? await getPodcastsByIds(ids: frenchMarketTopIds, country: country) {
                var mFound = mResults
                if genreId != nil {
                    mFound = mFound.filter { p in
                        let genres = p.genres?.map { $0.lowercased() } ?? []
                        return genres.contains(where: {
                            $0.contains(category.lowercased()) ||
                            (category == "Comedy" && $0.contains("humour")) ||
                            (category == "News" && $0.contains("actualit"))
                        })
                    }
                }
                for p in mFound {
                    validPodcasts.append(p)
                    manualIds.insert(p.collectionId)
                }
            }
        }
        
        // 2. Fetch Apple Top Podcasts RSS Feed
        do {
            let limit = 150
            var rssUrlString = "https://itunes.apple.com/\(country)/rss/toppodcasts/limit=\(limit)/json"
            if let genre = genreId {
                rssUrlString = "https://itunes.apple.com/\(country)/rss/toppodcasts/limit=\(limit)/genre=\(genre)/json"
            }
            
            if let rssUrl = URL(string: rssUrlString) {
                let (data, _) = try await URLSession.shared.data(from: rssUrl)
                
                struct RSSResponse: Codable {
                    let feed: FeedEntry?
                }
                struct FeedEntry: Codable {
                    let entry: [EntryItem]?
                }
                struct EntryItem: Codable {
                    let id: IdAttr?
                }
                struct IdAttr: Codable {
                    let attributes: AttributesAttr?
                }
                struct AttributesAttr: Codable {
                    let imId: String
                    enum CodingKeys: String, CodingKey {
                        case imId = "im:id"
                    }
                }
                
                if let rssResponse = try? JSONDecoder().decode(RSSResponse.self, from: data),
                   let entries = rssResponse.feed?.entry {
                    let ids = entries.compactMap { Int($0.id?.attributes?.imId ?? "") }
                    let filteredIds = ids.filter { !manualIds.contains($0) }
                    
                    if !filteredIds.isEmpty {
                        let chunkPodcasts = try await getPodcastsByIds(ids: filteredIds, country: country)
                        for p in chunkPodcasts {
                            if !manualIds.contains(p.collectionId) {
                                validPodcasts.append(p)
                                manualIds.insert(p.collectionId)
                            }
                        }
                    }
                }
            }
        } catch {
            print("RSS Top Charts fetch failed: \(error)")
        }
        
        // 3. Fallback to iTunes Search
        if validPodcasts.count < 10 {
            let searchTerm = category == "All" ? (country == "fr" ? "podcast populaire" : "trending") : category
            if let results = try? await searchPodcasts(term: searchTerm, country: country) {
                for p in results {
                    if !manualIds.contains(p.collectionId) {
                        validPodcasts.append(p)
                        manualIds.insert(p.collectionId)
                    }
                }
            }
        }
        
        if category != "True Crime" {
            validPodcasts = validPodcasts.filter { p in
                let genres = (p.genres ?? []).map { $0.lowercased() }
                let primaryGenre = (p.primaryGenreName ?? "").lowercased()
                let keywords = ["true crime", "criminology", "criminologie", "faits divers"]
                
                let isCriminology = keywords.contains { kw in
                    primaryGenre.contains(kw) || genres.contains { $0.contains(kw) }
                }
                return !isCriminology
            }
        }
        
        return validPodcasts
    }
    
    // Fetch categorized audiobooks (iTunes + LibriVox + Archive.org + LitteratureAudio)
    func getAudiobooks(country: String = "us", categoryKey: String = "all") async -> [Podcast] {
        var allResults = [Podcast]()
        var seenIds = Set<Int>()
        var seenTitles = Set<String>()
        
        // 1. iTunes RSS Top Audiobooks (only for 'all')
        if categoryKey == "all" {
            let rssUrlString = "https://itunes.apple.com/\(country)/rss/topaudiobooks/limit=25/json"
            if let rssUrl = URL(string: rssUrlString),
               let (data, _) = try? await URLSession.shared.data(from: rssUrl) {
                
                struct RSSResponse: Codable {
                    let feed: FeedEntry?
                }
                struct FeedEntry: Codable {
                    let entry: [EntryItem]?
                }
                struct EntryItem: Codable {
                    let id: IdAttr?
                }
                struct IdAttr: Codable {
                    let attributes: AttributesAttr?
                }
                struct AttributesAttr: Codable {
                    let imId: String
                    enum CodingKeys: String, CodingKey {
                        case imId = "im:id"
                    }
                }
                
                if let rssResponse = try? JSONDecoder().decode(RSSResponse.self, from: data),
                   let entries = rssResponse.feed?.entry {
                    let ids = entries.compactMap { Int($0.id?.attributes?.imId ?? "") }
                    if !ids.isEmpty,
                       let books = try? await getPodcastsByIds(ids: ids, country: country) {
                        for b in books {
                            seenIds.insert(b.collectionId)
                            seenTitles.insert(b.collectionName.lowercased())
                            allResults.append(b)
                        }
                    }
                }
            }
        }
        
        // 2. iTunes Search Audiobooks
        let categoryTerms: [String: String] = [
            "fiction": country == "fr" ? "Romans Classiques Livre Audio" : "Fiction Classics Audiobook",
            "thriller": country == "fr" ? "Policier Thriller Livre Audio" : "Mystery Thriller Audiobook",
            "scifi": country == "fr" ? "Science Fiction Fantasy Livre Audio" : "Sci-Fi Fantasy Audiobook",
            "history": country == "fr" ? "Histoire Biographie Livre Audio" : "History Biography Audiobook",
            "kids": country == "fr" ? "Enfants Jeunesse Livre Audio" : "Kids Teens Audiobook",
            "growth": country == "fr" ? "Développement Spiritualité Livre Audio" : "Self Help Spiritual Audiobook",
            "arts": country == "fr" ? "Arts Philosophie Poésie Théâtre" : "Arts Philosophy Poetry Drama",
            "all": country == "fr" ? "Livre Audio" : "Audiobook"
        ]
        
        let mainTerm = categoryTerms[categoryKey] ?? "Audiobook"
        if let searchResults = try? await searchPodcasts(term: mainTerm, country: country) {
            for p in searchResults {
                let titleLower = p.collectionName.lowercased()
                if !seenIds.contains(p.collectionId) && !seenTitles.contains(titleLower) {
                    seenIds.insert(p.collectionId)
                    seenTitles.insert(titleLower)
                    allResults.append(p)
                }
            }
        }
        
        // 3. LibriVox Books API Integration
        let lvGenreMap: [String: String] = [
            "fiction": "Fiction",
            "thriller": "Detective Fiction",
            "scifi": "Science Fiction",
            "history": "History",
            "kids": "Children",
            "growth": "Self-Help",
            "arts": "Poetry"
        ]
        
        let lvLanguage = country == "fr" ? "french" : "english"
        let lvGenre = lvGenreMap[categoryKey] ?? ""
        var lvUrlString = "https://librivox.org/api/feed/audiobooks?format=json&limit=20&language=\(lvLanguage)"
        if !lvGenre.isEmpty, let encodedGenre = lvGenre.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            lvUrlString += "&genre=\(encodedGenre)"
        }
        
        if let lvUrl = URL(string: lvUrlString),
           let (lvData, _) = try? await URLSession.shared.data(from: lvUrl) {
            
            struct LibriVoxResponse: Codable {
                let books: [LibriVoxBook]?
            }
            struct LibriVoxBook: Codable {
                let id: String
                let title: String
                let description: String?
                let url_rss: String?
                let copyright_year: String?
                let genre: String?
                let totaltimesecs: Int?
                let authors: [LibriVoxAuthor]?
            }
            struct LibriVoxAuthor: Codable {
                let first_name: String
                let last_name: String
            }
            
            if let lvResponse = try? JSONDecoder().decode(LibriVoxResponse.self, from: lvData),
               let books = lvResponse.books {
                for b in books {
                    let bookId = (Int(b.id) ?? 0) + 10000000
                    let titleLower = b.title.lowercased()
                    if !seenIds.contains(bookId) && !seenTitles.contains(titleLower) {
                        seenIds.insert(bookId)
                        seenTitles.insert(titleLower)
                        
                        let authorName = b.authors?.map { "\($0.first_name) \($0.last_name)" }.joined(separator: ", ") ?? "LibriVox"
                        let lvDurationMillis = b.totaltimesecs.map { $0 * 1000 }
                        
                        allResults.append(Podcast(
                            collectionId: bookId,
                            artistName: authorName,
                            collectionName: b.title,
                            artworkUrl100: "https://librivox.org/images/librivox-logo.png",
                            artworkUrl600: "https://librivox.org/images/librivox-logo.png",
                            feedUrl: b.url_rss,
                            genres: [b.genre ?? "Audiobook"],
                            primaryGenreName: "Audiobook",
                            releaseDate: b.copyright_year,
                            country: country,
                            description: b.description,
                            source: "librivox",
                            totalDurationMillis: lvDurationMillis,
                            episodeCount: nil
                        ))
                    }
                }
            }
        }
        
        // 4. French Wordpress LitteratureAudio posts API integration
        if country == "fr" && (categoryKey == "all" || categoryKey == "fiction") {
            if let laUrl = URL(string: "https://www.litteratureaudio.com/wp-json/wp/v2/posts?per_page=20"),
               let (laData, _) = try? await URLSession.shared.data(from: laUrl) {
                
                struct LitteratureAudioPost: Codable {
                    let id: Int
                    let link: String
                    let title: RenderedText
                    let excerpt: RenderedText
                    let date: String
                }
                struct RenderedText: Codable {
                    let rendered: String
                }
                
                if let posts = try? JSONDecoder().decode([LitteratureAudioPost].self, from: laData) {
                    for post in posts {
                        let laId = post.id + 30000000
                        let cleanedTitle = post.title.rendered
                            .replacingOccurrences(of: "&#8211;", with: "-")
                            .replacingOccurrences(of: "&#8217;", with: "'")
                        let cleanedDesc = post.excerpt.rendered.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
                        
                        if !seenIds.contains(laId) {
                            seenIds.insert(laId)
                            allResults.append(Podcast(
                                collectionId: laId,
                                artistName: "Littérature Audio",
                                collectionName: cleanedTitle,
                                artworkUrl100: "https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png",
                                artworkUrl600: "https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png",
                                feedUrl: "\(post.link)feed/",
                                genres: ["Livre Audio"],
                                primaryGenreName: "Audiobook",
                                releaseDate: post.date,
                                country: country,
                                description: cleanedDesc,
                                source: "litteratureaudio"
                            ))
                        }
                    }
                }
            }
        }
        
        // 5. Verify episodes & compute total duration for every candidate book.
        // Filter out books with 0 episodes inside or total duration < 30 minutes (1,800,000 ms).
        return await enrichAndFilterAudiobooks(allResults, country: country)
    }
    
    func enrichAndFilterAudiobooks(_ candidates: [Podcast], country: String) async -> [Podcast] {
        let minDurationMillis = 30 * 60 * 1000 // 30 minutes minimum
        let cappedCandidates = Array(candidates.prefix(48))
        
        let verifiedMap = await withTaskGroup(of: (Int, Podcast?).self) { group -> [Int: Podcast] in
            for (index, book) in cappedCandidates.enumerated() {
                group.addTask {
                    let rawEpisodes = (try? await self.getPodcastEpisodes(
                        collectionId: book.collectionId,
                        preferredCountry: country,
                        feedUrl: book.feedUrl
                    )) ?? []
                    
                    let playableEpisodes = rawEpisodes.filter { ep in
                        guard let url = ep.previewUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !url.isEmpty else { return false }
                        return true
                    }
                    
                    // Exclude books with 0 playable episodes inside
                    guard !playableEpisodes.isEmpty else {
                        return (index, nil)
                    }
                    
                    let computedDuration = playableEpisodes.reduce(0) { sum, ep in
                        sum + max(0, ep.trackTimeMillis ?? 0)
                    }
                    let finalDuration = max(computedDuration, book.totalDurationMillis ?? 0)
                    
                    // Exclude books whose total duration is under 30 minutes
                    guard finalDuration >= minDurationMillis else {
                        return (index, nil)
                    }
                    
                    self.setCachedBookEpisodes(playableEpisodes, for: book.collectionId)
                    
                    var enriched = book
                    enriched.totalDurationMillis = finalDuration
                    enriched.episodeCount = playableEpisodes.count
                    return (index, enriched)
                }
            }
            
            var resultDict: [Int: Podcast] = [:]
            for await (idx, verifiedBook) in group {
                if let valid = verifiedBook {
                    resultDict[idx] = valid
                }
            }
            return resultDict
        }
        
        return cappedCandidates.indices.compactMap { verifiedMap[$0] }
    }
    
    // Unified Search podcasts, radio, episodes
    func searchAll(term: String, country: String = "us", langCode: String = "en") async throws -> UnifiedSearchResults {
        var langParam = ""
        if country == "fr" {
            langParam = "&lang=fr_FR"
        }
        
        async let podcastTask = searchPodcasts(term: term, country: country)
        
        // Fetch Radio Stations
        let escapedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let radUrlString = "\(radioAPIBase)/byname/\(escapedTerm)?limit=30&order=clickcount&reverse=true"
        async let radioTask: [RadioStation] = {
            guard let url = URL(string: radUrlString),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
            let stations = parseRadioJSON(data)
            return sortRadioStations(stations, langCode: langCode)
        }()
        
        // Fetch Episode results
        let epUrlString = "\(iTunesSearchURL)?term=\(escapedTerm)&entity=podcastEpisode&limit=20&country=\(country)\(langParam)&_v=\(Date().timeIntervalSince1970)"
        async let episodeTask: [Episode] = {
            guard let url = URL(string: epUrlString),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
            let response = try? JSONDecoder().decode(ITunesResponse<Episode>.self, from: data)
            return response?.results ?? []
        }()
        
        let (podcasts, radio, episodes) = try await (podcastTask, radioTask, episodeTask)
        return UnifiedSearchResults(podcasts: podcasts, radio: radio, episodes: episodes)
    }
    
    // MARK: - Smart Podcast Matching (for Spotify & Library Import)
    private func normalizeMatchString(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let cleaned = folded
            .replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return cleaned
    }
    
    func matchPodcastOnItunes(name: String, publisher: String?, country: String = "fr") async -> Podcast? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        let normName = normalizeMatchString(cleanName)
        let normPub = normalizeMatchString(publisher ?? "")
        let shortTitle = cleanName.components(separatedBy: " - ").first?.components(separatedBy: " : ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? cleanName
        
        var queries: [(term: String, country: String)] = [
            (cleanName, country)
        ]
        if let pub = publisher, !pub.isEmpty {
            queries.append(("\(cleanName) \(pub)", country))
        }
        if shortTitle.count >= 3 && shortTitle != cleanName {
            queries.append((shortTitle, country))
        }
        if country != "fr" {
            queries.append((cleanName, "fr"))
        }
        if country != "us" {
            queries.append((cleanName, "us"))
        }
        
        var candidates: [Podcast] = []
        var seenIds = Set<Int>()
        
        for q in queries {
            if let found = try? await searchPodcasts(term: q.term, country: q.country) {
                for p in found {
                    if !seenIds.contains(p.collectionId) {
                        seenIds.insert(p.collectionId)
                        candidates.append(p)
                    }
                }
                // If we already have an exact title match, no need to run fallback queries
                if candidates.contains(where: { normalizeMatchString($0.collectionName) == normName }) {
                    break
                }
            }
        }
        
        guard !candidates.isEmpty else { return nil }
        
        func score(_ candidate: Podcast) -> Int {
            let candTitle = normalizeMatchString(candidate.collectionName)
            let candArtist = normalizeMatchString(candidate.artistName)
            var pts = 0
            
            if candTitle == normName {
                pts += 100
            } else if !normName.isEmpty && (candTitle.hasPrefix(normName) || normName.hasPrefix(candTitle)) {
                pts += 75
            } else if !normName.isEmpty && (candTitle.contains(normName) || normName.contains(candTitle)) {
                pts += 50
            }
            
            if !normPub.isEmpty {
                if candArtist == normPub {
                    pts += 40
                } else if candArtist.contains(normPub) || normPub.contains(candArtist) {
                    pts += 25
                }
            }
            return pts
        }
        
        let ranked = candidates.sorted { score($0) > score($1) }
        return ranked.first
    }
}
