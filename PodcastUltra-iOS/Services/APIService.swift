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
        var langParam = ""
        if country.lowercased() == "fr" || country.lowercased() == "be" {
            langParam = "&lang=fr_fr"
        } else if country.lowercased() == "jp" {
            langParam = "&lang=ja_jp"
        }
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(iTunesSearchURL)?term=\(encodedTerm)&entity=podcast&limit=150&country=\(country)\(langParam)") else {
            return []
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ITunesResponse<Podcast>.self, from: data)
        let clean = ProfanityFilter.shared.filterCleanPodcasts(response.results)
        let targetLang = await MainActor.run { LocalStorageManager.shared.currentLanguage }
        if targetLang.itunes.lowercased() == country.lowercased() {
            return LanguageContentFilter.shared.filterPodcasts(clean, for: targetLang)
        }
        return LanguageContentFilter.shared.filterPodcasts(clean, for: LangCode.fromItunesCountry(country))
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
        return ProfanityFilter.shared.filterCleanPodcasts(response.results)
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
        let curated = curatedTopRadioStations(for: langCode)
        let langName = radioSearch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        var fetchedStations: [RadioStation] = []
        if let url = URL(string: "\(radioAPIBase)/bylanguage/\(langName)?limit=100&order=clickcount&reverse=true"),
           let (data, _) = try? await URLSession.shared.data(from: url) {
            fetchedStations = parseRadioJSON(data)
        }
        
        let sortedDynamic = sortRadioStations(fetchedStations, langCode: langCode)
        var combined: [RadioStation] = []
        var seenNames = Set<String>()
        
        func normKey(_ name: String) -> String {
            name.lowercased()
                .components(separatedBy: " - ")[0]
                .components(separatedBy: " (")[0]
                .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        }
        
        for st in curated {
            seenNames.insert(normKey(st.name))
            combined.append(st)
        }
        for st in sortedDynamic {
            let key = normKey(st.name)
            if !key.isEmpty && !seenNames.contains(key) {
                seenNames.insert(key)
                combined.append(st)
            }
        }
        return combined
    }
    
    private func curatedTopRadioStations(for langCode: String) -> [RadioStation] {
        func makeStation(id: String, name: String, url: String, domain: String, country: String, language: String, clicks: Int) -> RadioStation {
            RadioStation(
                id: id,
                name: name,
                url: url,
                favicon: RadioIconHelper.googleFaviconUrl(forDomain: domain),
                tags: language,
                country: country,
                language: language,
                clickcount: clicks,
                homepage: "https://\(domain)"
            )
        }
        
        switch langCode {
        case "en":
            return [
                makeStation(id: "curated-en-bbc-ws", name: "BBC World Service", url: "http://stream.live.vc.bbcmedia.co.uk/bbc_world_service", domain: "bbc.co.uk", country: "United Kingdom", language: "english", clicks: 98000),
                makeStation(id: "curated-en-bbc-r1", name: "BBC Radio 1", url: "http://as-hls-ww-live.akamaized.net/pool_01505109/live/ww/bbc_radio_one/bbc_radio_one.isml/bbc_radio_one-audio%3d96000.norewind.m3u8", domain: "bbc.co.uk", country: "United Kingdom", language: "english", clicks: 92000),
                makeStation(id: "curated-en-bbc-r2", name: "BBC Radio 2", url: "http://as-hls-ww-live.akamaized.net/pool_74208725/live/ww/bbc_radio_two/bbc_radio_two.isml/bbc_radio_two-audio%3d96000.norewind.m3u8", domain: "bbc.co.uk", country: "United Kingdom", language: "english", clicks: 89000),
                makeStation(id: "curated-en-bbc-r4", name: "BBC Radio 4", url: "http://as-hls-ww-live.akamaized.net/pool_55057080/live/ww/bbc_radio_fourfm/bbc_radio_fourfm.isml/bbc_radio_fourfm-audio%3d96000.norewind.m3u8", domain: "bbc.co.uk", country: "United Kingdom", language: "english", clicks: 86000),
                makeStation(id: "curated-en-bbc-6m", name: "BBC Radio 6 Music", url: "http://as-hls-ww-live.akamaized.net/pool_81827798/live/ww/bbc_6music/bbc_6music.isml/bbc_6music-audio%3d96000.norewind.m3u8", domain: "bbc.co.uk", country: "United Kingdom", language: "english", clicks: 82000),
                makeStation(id: "curated-en-npr", name: "NPR Live", url: "https://npr-ice.streamguys1.com/live.mp3", domain: "npr.org", country: "United States", language: "english", clicks: 80000),
                makeStation(id: "curated-en-lbc", name: "LBC London", url: "https://media-ice.musicradio.com/LBCUKMP3Low", domain: "lbc.co.uk", country: "United Kingdom", language: "english", clicks: 75000),
                makeStation(id: "curated-en-capital", name: "Capital FM UK", url: "https://media-ice.musicradio.com/CapitalUKMP3", domain: "capitalfm.com", country: "United Kingdom", language: "english", clicks: 72000),
                makeStation(id: "curated-en-heart", name: "Heart UK", url: "https://media-ice.musicradio.com/HeartUKMP3", domain: "heart.co.uk", country: "United Kingdom", language: "english", clicks: 70000),
                makeStation(id: "curated-en-classicfm", name: "Classic FM UK", url: "https://media-ice.musicradio.com/ClassicFMMP3", domain: "classicfm.com", country: "United Kingdom", language: "english", clicks: 68000),
                makeStation(id: "curated-en-wnyc", name: "WNYC 93.9 FM New York", url: "https://fm939.wnyc.org/wnycfm", domain: "wnyc.org", country: "United States", language: "english", clicks: 65000),
                makeStation(id: "curated-en-kexp", name: "KEXP 90.3 FM Seattle", url: "https://kexp-mp3-128.streamguys1.com/kexp128.mp3", domain: "kexp.org", country: "United States", language: "english", clicks: 63000)
            ]
        case "fr":
            return [
                // 100% Direct Ad-Free Public & Independent Icecast / HLS Streams (Zero 30s pre-roll ads!)
                makeStation(id: "curated-fr-inter", name: "France Inter", url: "https://icecast.radiofrance.fr/franceinter-hifi.aac", domain: "radiofrance.fr", country: "France • Sans Pub", language: "french", clicks: 99500),
                makeStation(id: "curated-fr-info", name: "France Info", url: "https://icecast.radiofrance.fr/franceinfo-hifi.aac", domain: "francetvinfo.fr", country: "France • Sans Pub", language: "french", clicks: 97000),
                makeStation(id: "curated-fr-culture", name: "France Culture", url: "https://icecast.radiofrance.fr/franceculture-hifi.aac", domain: "radiofrance.fr", country: "France • Sans Pub", language: "french", clicks: 94000),
                makeStation(id: "curated-fr-fip", name: "FIP", url: "https://icecast.radiofrance.fr/fip-hifi.aac", domain: "radiofrance.fr", country: "France • Sans Pub", language: "french", clicks: 91000),
                makeStation(id: "curated-fr-musique", name: "France Musique", url: "https://icecast.radiofrance.fr/francemusique-hifi.aac", domain: "radiofrance.fr", country: "France • Sans Pub", language: "french", clicks: 89000),
                makeStation(id: "curated-fr-mouv", name: "Mouv'", url: "https://icecast.radiofrance.fr/mouv-hifi.aac", domain: "radiofrance.fr", country: "France • Sans Pub", language: "french", clicks: 87000),
                makeStation(id: "curated-fr-rfi", name: "RFI Monde", url: "https://rfimonde64k.ice.infomaniak.ch/rfimonde-64.mp3", domain: "rfi.fr", country: "France • Direct", language: "french", clicks: 85000),
                makeStation(id: "curated-fr-nova", name: "Radio Nova", url: "https://novazz.ice.infomaniak.ch/novazz-128.mp3", domain: "nova.fr", country: "France • Direct", language: "french", clicks: 83000),
                makeStation(id: "curated-fr-tsf", name: "TSF Jazz", url: "https://tsfjazz.ice.infomaniak.ch/tsfjazz-high.mp3", domain: "tsfjazz.com", country: "France • Direct", language: "french", clicks: 81000),
                makeStation(id: "curated-fr-classique", name: "Radio Classique", url: "https://radioclassique.ice.infomaniak.ch/radioclassique-high.mp3", domain: "radioclassique.fr", country: "France • Direct", language: "french", clicks: 79000),
                // Major French Stations via Direct Icecast / HLS Mountpoints (bypassing adwz2 redirects)
                makeStation(id: "curated-fr-rtl", name: "RTL", url: "https://icecast.rtl.fr/rtl-1-44-128", domain: "rtl.fr", country: "France", language: "french", clicks: 78000),
                makeStation(id: "curated-fr-rmc", name: "RMC", url: "https://audio.bfmtv.com/rmcradio_128.mp3", domain: "rmc.bfmtv.com", country: "France", language: "french", clicks: 76000),
                makeStation(id: "curated-fr-europe1", name: "Europe 1", url: "https://e1-live-mp3-128.scdn.arkena.com/europe1.mp3", domain: "europe1.fr", country: "France", language: "french", clicks: 74000),
                makeStation(id: "curated-fr-rtl2", name: "RTL2", url: "https://icecast.rtl2.fr/rtl2-1-44-128", domain: "rtl2.fr", country: "France", language: "french", clicks: 72000),
                makeStation(id: "curated-fr-fun", name: "Fun Radio", url: "https://icecast.funradio.fr/fun-1-44-128", domain: "funradio.fr", country: "France", language: "french", clicks: 70000),
                makeStation(id: "curated-fr-skyrock", name: "Skyrock", url: "https://icecast.skyrock.net/s/natio_aac_128k", domain: "skyrock.fm", country: "France", language: "french", clicks: 68000),
                makeStation(id: "curated-fr-ouifm", name: "Ouï FM", url: "https://ouifm.ice.infomaniak.ch/ouifm-high.mp3", domain: "ouifm.fr", country: "France", language: "french", clicks: 66000),
                makeStation(id: "curated-fr-fip-rock", name: "FIP Rock", url: "https://icecast.radiofrance.fr/fiprock-hifi.aac", domain: "radiofrance.fr", country: "France • Sans Pub", language: "french", clicks: 65000),
                makeStation(id: "curated-fr-fip-groove", name: "FIP Groove", url: "https://icecast.radiofrance.fr/fipgroove-hifi.aac", domain: "radiofrance.fr", country: "France • Sans Pub", language: "french", clicks: 64000),
                makeStation(id: "curated-fr-fip-electro", name: "FIP Electro", url: "https://icecast.radiofrance.fr/fipelectro-hifi.aac", domain: "radiofrance.fr", country: "France • Sans Pub", language: "french", clicks: 63000)
            ]
        case "es":
            return [
                makeStation(id: "curated-es-ser", name: "Cadena SER", url: "https://playerservices.streamtheworld.com/api/livestream-redirect/CADENASER.mp3", domain: "cadenaser.com", country: "Spain", language: "spanish", clicks: 90000),
                makeStation(id: "curated-es-rne", name: "RNE Radio Nacional", url: "https://rtvelivestream.akamaized.net/rtvesec/rne/rne_r1_main.m3u8", domain: "rtve.es", country: "Spain", language: "spanish", clicks: 85000),
                makeStation(id: "curated-es-los40", name: "LOS40", url: "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40.mp3", domain: "los40.com", country: "Spain", language: "spanish", clicks: 82000),
                makeStation(id: "curated-es-cope", name: "Cadena COPE", url: "https://net1-cope-rrcast.flumotion.com/cope/net1-low.mp3", domain: "cope.es", country: "Spain", language: "spanish", clicks: 79000)
            ]
        case "de":
            return [
                makeStation(id: "curated-de-dlf", name: "Deutschlandfunk", url: "https://st01.sslstream.dlf.de/dlf/01/128/mp3/stream.mp3", domain: "deutschlandfunk.de", country: "Germany", language: "german", clicks: 91000),
                makeStation(id: "curated-de-wdr2", name: "WDR 2", url: "https://wdr-wdr2-rheinland.icecastssl.wdr.de/wdr/wdr2/rheinland/mp3/128/stream.mp3", domain: "wdr.de", country: "Germany", language: "german", clicks: 86000),
                makeStation(id: "curated-de-swr3", name: "SWR3", url: "https://liveradio.swr.de/sw282p3/swr3/play.mp3", domain: "swr3.de", country: "Germany", language: "german", clicks: 84000),
                makeStation(id: "curated-de-1live", name: "1LIVE", url: "https://wdr-1live-live.icecastssl.wdr.de/wdr/1live/live/mp3/128/stream.mp3", domain: "wdr.de", country: "Germany", language: "german", clicks: 81000)
            ]
        case "it":
            return [
                makeStation(id: "curated-it-rai1", name: "Rai Radio 1", url: "https://icestreaming.rai.it/1.mp3", domain: "raiplaysound.it", country: "Italy", language: "italian", clicks: 90000),
                makeStation(id: "curated-it-rai2", name: "Rai Radio 2", url: "https://icestreaming.rai.it/2.mp3", domain: "raiplaysound.it", country: "Italy", language: "italian", clicks: 85000),
                makeStation(id: "curated-it-deejay", name: "Radio Deejay", url: "https://4c4b867c89244861ac216426883d1ad0.msvdn.net/radiodeejay/radiodeejay/master_ma.m3u8", domain: "deejay.it", country: "Italy", language: "italian", clicks: 82000)
            ]
        case "pt":
            return [
                makeStation(id: "curated-pt-antena1", name: "Antena 1 RTP", url: "https://streaming-live.rtp.pt/liveradio/antena180a/playlist.m3u8", domain: "rtp.pt", country: "Portugal", language: "portuguese", clicks: 88000),
                makeStation(id: "curated-pt-comercial", name: "Rádio Comercial", url: "https://stream-icy.bauermedia.pt/comercial.mp3", domain: "radiocomercial.pt", country: "Portugal", language: "portuguese", clicks: 84000),
                makeStation(id: "curated-pt-rfm", name: "RFM Portugal", url: "https://playerservices.streamtheworld.com/api/livestream-redirect/RFM.mp3", domain: "rfm.sapo.pt", country: "Portugal", language: "portuguese", clicks: 80000)
            ]
        default:
            return []
        }
    }
    
    /// Rewrites French radio stream URLs to direct Icecast / AAC mountpoints to bypass Adswizz (adwz) 30s pre-roll ad injection
    func cleanAdFreeRadioURL(name: String, rawURL: String) -> String {
        let lowerName = name.lowercased()
        let lowerURL = rawURL.lowercased()
        
        if lowerName.contains("france inter") || lowerURL.contains("franceinter") {
            return "https://icecast.radiofrance.fr/franceinter-hifi.aac"
        }
        if lowerName.contains("france info") || lowerName.contains("franceinfo") || lowerURL.contains("franceinfo") {
            return "https://icecast.radiofrance.fr/franceinfo-hifi.aac"
        }
        if lowerName.contains("france culture") || lowerURL.contains("franceculture") {
            return "https://icecast.radiofrance.fr/franceculture-hifi.aac"
        }
        if lowerName == "fip" || lowerName == "fip radio" {
            return "https://icecast.radiofrance.fr/fip-hifi.aac"
        }
        if lowerName.contains("france musique") || lowerURL.contains("francemusique") {
            return "https://icecast.radiofrance.fr/francemusique-hifi.aac"
        }
        if lowerName.contains("mouv") || lowerURL.contains("mouv-") {
            return "https://icecast.radiofrance.fr/mouv-hifi.aac"
        }
        if lowerName.contains("rfi") && !lowerName.contains("afrique") {
            return "https://rfimonde64k.ice.infomaniak.ch/rfimonde-64.mp3"
        }
        if lowerName.contains("radio nova") || lowerName == "nova" {
            return "https://novazz.ice.infomaniak.ch/novazz-128.mp3"
        }
        if lowerName.contains("tsf jazz") {
            return "https://tsfjazz.ice.infomaniak.ch/tsfjazz-high.mp3"
        }
        if lowerName.contains("radio classique") {
            return "https://radioclassique.ice.infomaniak.ch/radioclassique-high.mp3"
        }
        if lowerName.contains("oui fm") || lowerName.contains("ouï fm") {
            return "https://ouifm.ice.infomaniak.ch/ouifm-high.mp3"
        }
        if lowerName == "rtl" || lowerURL.contains("streamer-01.rtl.fr/rtl-") {
            return "https://icecast.rtl.fr/rtl-1-44-128"
        }
        if lowerName == "rtl2" || lowerName == "rtl 2" || lowerURL.contains("streamer-01.rtl.fr/rtl2-") {
            return "https://icecast.rtl2.fr/rtl2-1-44-128"
        }
        if lowerName.contains("fun radio") || lowerURL.contains("streamer-01.rtl.fr/fun-") {
            return "https://icecast.funradio.fr/fun-1-44-128"
        }
        if lowerName.contains("europe 1") || lowerURL.contains("stream.europe1.fr") {
            return "https://e1-live-mp3-128.scdn.arkena.com/europe1.mp3"
        }
        if lowerName.contains("skyrock") {
            return "https://icecast.skyrock.net/s/natio_aac_128k"
        }
        // Strip Adswizz aggregator tracking query strings if present
        if let qIndex = rawURL.firstIndex(of: "?"),
           (lowerURL.contains("adwz") || lowerURL.contains("aw_0") || lowerURL.contains("aggregator=")) {
            return String(rawURL[..<qIndex])
        }
        return rawURL
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
            let directURL = cleanAdFreeRadioURL(name: response.name, rawURL: response.url_resolved)
            return RadioStation(
                id: response.stationuuid,
                name: response.name,
                url: directURL,
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
        // Deduplicate stations by normalized name prefix and filter out incompatible scripts
        let targetLang = LangCode(rawValue: langCode) ?? .en
        var seenBrands = [String: RadioStation]()
        for station in stations {
            if LanguageContentFilter.shared.hasIncompatibleScript(text: "\(station.name) \(station.country ?? "")", targetLang: targetLang) {
                continue
            }
            if targetLang == .fr {
                let cLower = (station.country ?? "").lowercased()
                if cLower.contains("russia") || cLower.contains("ukraine") || cLower.contains("belarus") || cLower.contains("china") {
                    continue
                }
            }
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
            "fr": ["France Inter", "RTL", "RTL2", "Fun Radio", "France Info", "France Culture", "Europe 1", "Europe 2", "RFM", "RMC", "NRJ", "Nostalgie", "Skyrock", "FIP"],
            "en": ["BBC", "BBC World Service", "BBC Radio 1", "BBC Radio 2", "BBC Radio 4", "BBC Radio 6", "NPR", "LBC", "Capital FM", "Heart", "Classic FM", "WNYC", "KEXP", "CNN"],
            "es": ["Cadena SER", "RNE", "LOS40", "COPE", "Onda Cero"],
            "de": ["Deutschlandfunk", "WDR", "SWR3", "1LIVE", "Bayern"],
            "it": ["Rai Radio", "Radio Deejay", "RTL 102.5", "Radio 105", "RDS"],
            "pt": ["Antena 1", "Rádio Comercial", "RFM", "TSF", "Jovem Pan"],
            "ja": ["NHK", "J-Wave", "Tokyo FM", "Shonan Beach"]
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
    
    /// Deterministic 62-bit hash so episode IDs from different RSS feeds never collide
    private static func stableEpisodeId(collectionId: Int, previewUrl: String, index: Int) -> Int {
        let key = "\(collectionId)|\(previewUrl)|\(index)"
        var hash: UInt64 = 14695981039346656037 // FNV-1a 64-bit offset basis
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(hash & 0x3FFFFFFFFFFFFFFF)
    }

    private func parseRSSFeed(xmlText: String, collectionId: Int, maxItems: Int = 50) -> [Episode] {
        var episodes = [Episode]()
        
        // Slice XML to the first `maxItems` <item> blocks so huge feeds (5-15 MB) parse in < 3ms without CPU lag
        let boundedXml: String = {
            var searchRange = xmlText.startIndex..<xmlText.endIndex
            var count = 0
            while count < maxItems, let found = xmlText.range(of: "</item>", options: [.caseInsensitive], range: searchRange) {
                count += 1
                searchRange = found.upperBound..<xmlText.endIndex
                if count == maxItems {
                    return String(xmlText[..<found.upperBound])
                }
            }
            return xmlText
        }()
        
        var channelTitle = "Podcast"
        if let channelTitleRange = boundedXml.range(of: "<channel>[\\s\\S]*?<title>([\\s\\S]*?)</title>", options: .regularExpression) {
            let matched = String(boundedXml[channelTitleRange])
            if let startRange = matched.range(of: "<title>"), let endRange = matched.range(of: "</title>") {
                channelTitle = decodeHTMLEntities(
                    String(matched[startRange.upperBound..<endRange.lowerBound])
                        .replacingOccurrences(of: "<![CDATA[", with: "")
                        .replacingOccurrences(of: "]]>", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        
        // Extract channel-level cover image (<itunes:image> or <image><url>) as fallback for all episodes
        var channelArtworkUrl = ""
        let headerSubstring: String = {
            if let firstItemRange = boundedXml.range(of: "<item") {
                return String(boundedXml[..<firstItemRange.lowerBound])
            }
            return String(boundedXml.prefix(8000))
        }()
        let nsHeader = headerSubstring as NSString
        if let chImgRegex = try? NSRegularExpression(pattern: "<itunes:image[^>]+href=\"([^\"]+)\"", options: [.caseInsensitive]),
           let chMatch = chImgRegex.firstMatch(in: headerSubstring, options: [], range: NSRange(location: 0, length: nsHeader.length)),
           chMatch.range(at: 1).location != NSNotFound {
            channelArtworkUrl = nsHeader.substring(with: chMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let stdImgRegex = try? NSRegularExpression(pattern: "<image>[\\s\\S]*?<url>([^<]+)</url>[\\s\\S]*?</image>", options: [.caseInsensitive]),
                  let stdMatch = stdImgRegex.firstMatch(in: headerSubstring, options: [], range: NSRange(location: 0, length: nsHeader.length)),
                  stdMatch.range(at: 1).location != NSNotFound {
            channelArtworkUrl = nsHeader.substring(with: stdMatch.range(at: 1))
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let itemPattern = "<item>([\\s\\S]*?)</item>"
        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: []) else { return [] }
        let nsString = boundedXml as NSString
        let matches = regex.matches(in: boundedXml, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for (index, match) in matches.prefix(maxItems).enumerated() {
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
            if let encRegex = try? NSRegularExpression(pattern: "<enclosure[^>]+url=[\"']([^\"']+)[\"']", options: [.caseInsensitive]),
               let encMatch = encRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)) {
                let range = encMatch.range(at: 1)
                if range.location != NSNotFound {
                    previewUrl = nsBlock.substring(with: range)
                }
            }
            if previewUrl.isEmpty {
                if let mediaRegex = try? NSRegularExpression(pattern: "<media:content[^>]+url=[\"']([^\"']+)[\"']", options: [.caseInsensitive]),
                   let mediaMatch = mediaRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)) {
                    let range = mediaMatch.range(at: 1)
                    if range.location != NSNotFound {
                        previewUrl = nsBlock.substring(with: range)
                    }
                }
            }
            previewUrl = decodeHTMLEntities(previewUrl).trimmingCharacters(in: .whitespacesAndNewlines)
            
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
            if artworkUrl.isEmpty {
                artworkUrl = channelArtworkUrl
            }
            
            let trackId = Self.stableEpisodeId(collectionId: collectionId, previewUrl: previewUrl, index: index)
            
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
    
    private func fetchFeed(feedUrl: String, forceRefresh: Bool = false) async -> String? {
        guard let url = URL(string: feedUrl) else { return nil }
        do {
            var request = URLRequest(url: url)
            if forceRefresh {
                request.cachePolicy = .reloadIgnoringLocalCacheData
            }
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
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
    func getPodcastEpisodes(collectionId: Int, preferredCountry: String? = nil, feedUrl: String? = nil, forceRefresh: Bool = false) async throws -> [Episode] {
        if !forceRefresh, let cached = getCachedBookEpisodes(for: collectionId), !cached.isEmpty {
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

        // B. Handler for Internet Archive / Project Gutenberg metadata JSON (archive.org/metadata/<identifier>)
        if let fUrl = resolvedFeedUrl, fUrl.hasPrefix("https://archive.org/metadata/") {
            let identifier = fUrl.replacingOccurrences(of: "https://archive.org/metadata/", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let metaURL = URL(string: "https://archive.org/metadata/\(identifier)"),
               let (data, _) = try? await URLSession.shared.data(from: metaURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let files = json["files"] as? [[String: Any]] {
                let metaDict = json["metadata"] as? [String: Any]
                let colTitle = (metaDict?["title"] as? String) ?? identifier
                let creator = (metaDict?["creator"] as? String) ?? "Internet Archive"
                let coverURL = "https://archive.org/services/img/\(identifier)"
                
                var iaEpisodes: [Episode] = []
                for (idx, file) in files.enumerated() {
                    guard let name = file["name"] as? String else { continue }
                    let lower = name.lowercased()
                    guard lower.hasSuffix(".mp3") || lower.hasSuffix(".m4a") else { continue }
                    // Avoid duplicate 64kbps derivative if 128kbps or original mp3 exists
                    if lower.hasSuffix("_64kb.mp3") && files.contains(where: { (($0["name"] as? String) ?? "").lowercased().hasSuffix(".mp3") && !(($0["name"] as? String) ?? "").lowercased().hasSuffix("_64kb.mp3") }) {
                        continue
                    }
                    let rawTitle = (file["title"] as? String) ?? name.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: "_", with: " ")
                    var durMillis = 1800 * 1000
                    if let lenStr = file["length"] as? String {
                        if lenStr.contains(":") {
                            let parts = lenStr.split(separator: ":").compactMap { Double($0) }
                            if parts.count == 3 {
                                durMillis = Int((parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000)
                            } else if parts.count == 2 {
                                durMillis = Int((parts[0] * 60 + parts[1]) * 1000)
                            }
                        } else if let secs = Double(lenStr) {
                            durMillis = Int(secs * 1000)
                        }
                    }
                    guard let encodedFile = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { continue }
                    let streamURL = "https://archive.org/download/\(identifier)/\(encodedFile)"
                    let trackId = collectionId &+ idx &+ 1
                    iaEpisodes.append(Episode(
                        trackId: trackId,
                        trackName: rawTitle,
                        description: (metaDict?["description"] as? String)?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
                        releaseDate: metaDict?["publicdate"] as? String,
                        previewUrl: streamURL,
                        trackTimeMillis: max(60_000, durMillis),
                        artworkUrl60: coverURL,
                        artworkUrl160: coverURL,
                        artworkUrl600: coverURL,
                        collectionName: colTitle,
                        collectionId: collectionId,
                        artistName: creator
                    ))
                }
                if !iaEpisodes.isEmpty {
                    setCachedBookEpisodes(iaEpisodes, for: collectionId)
                    return iaEpisodes
                }
            }
        }
        
        // C. Handler for Hearthis.at JSON API feeds
        if let fUrl = resolvedFeedUrl, fUrl.hasPrefix("https://api-v2.hearthis.at/") {
            if let url = URL(string: fUrl),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var htEpisodes: [Episode] = []
                for (idx, item) in arr.enumerated() {
                    guard let streamUrl = item["stream_url"] as? String, !streamUrl.isEmpty else { continue }
                    let title = (item["title"] as? String) ?? "Mix #\(idx + 1)"
                    let desc = (item["description"] as? String) ?? title
                    let durSecs = Int((item["duration"] as? String) ?? "") ?? (item["duration"] as? Int) ?? 3600
                    let thumb = (item["artwork_url"] as? String) ?? (item["thumb"] as? String)
                    let userDict = item["user"] as? [String: Any]
                    let artist = (userDict?["username"] as? String) ?? "Hearthis DJ"
                    let idVal = Int((item["id"] as? String) ?? "") ?? (collectionId + idx + 1)
                    htEpisodes.append(Episode(
                        trackId: idVal,
                        trackName: title,
                        description: desc,
                        releaseDate: item["created_at"] as? String,
                        previewUrl: streamUrl,
                        trackTimeMillis: max(60_000, durSecs * 1000),
                        artworkUrl60: thumb,
                        artworkUrl160: thumb,
                        artworkUrl600: thumb,
                        collectionName: artist,
                        collectionId: collectionId,
                        artistName: artist
                    ))
                }
                if !htEpisodes.isEmpty {
                    setCachedBookEpisodes(htEpisodes, for: collectionId)
                    return htEpisodes
                }
            }
        }

        let isCustomNonItunesId = collectionId >= 10_000_000 && collectionId < 60_000_000
        if isCustomNonItunesId, let urlToFetch = resolvedFeedUrl, !urlToFetch.isEmpty {
            if let xml = await fetchFeed(feedUrl: urlToFetch, forceRefresh: forceRefresh) {
                let parsed = parseRSSFeed(xmlText: xml, collectionId: collectionId)
                if !parsed.isEmpty {
                    setCachedBookEpisodes(parsed, for: collectionId)
                    return parsed
                }
            }
        }

        func attempt(country: String?) async throws -> [Episode]? {
            var urlString = "\(iTunesLookupURL)?id=\(collectionId)&entity=podcastEpisode&limit=60"
            if let c = country {
                urlString += "&country=\(c.lowercased())"
            }
            if forceRefresh {
                urlString += "&_t=\(Int(Date().timeIntervalSince1970))"
            }
            guard let url = URL(string: urlString) else { return nil }
            var request = URLRequest(url: url)
            if forceRefresh {
                request.cachePolicy = .reloadIgnoringLocalCacheData
            }
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            
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
                let episodeUrl: String?
                let feedUrl: String?
            }
            
            let response = try JSONDecoder().decode(LookupResponse.self, from: data)
            if let first = response.results.first, let fUrl = first.feedUrl, resolvedFeedUrl == nil {
                resolvedFeedUrl = fUrl
            }
            
            if response.results.count > 1 {
                let parsedEpisodes = response.results.suffix(from: 1).compactMap { res -> Episode? in
                    let playableAudio = res.episodeUrl ?? res.previewUrl
                    guard let audio = playableAudio, !audio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    let normalizedDate = DateFormatterUtility.parse(res.releaseDate).map { DateFormatterUtility.formatISO8601($0) } ?? res.releaseDate
                    return Episode(
                        trackId: res.trackId,
                        trackName: res.trackName ?? "",
                        description: res.description,
                        releaseDate: normalizedDate,
                        previewUrl: audio.trimmingCharacters(in: .whitespacesAndNewlines),
                        trackTimeMillis: res.trackTimeMillis,
                        artworkUrl60: res.artworkUrl60,
                        artworkUrl160: res.artworkUrl100,
                        artworkUrl600: res.artworkUrl600,
                        collectionName: res.collectionName,
                        collectionId: collectionId,
                        artistName: res.artistName
                    )
                }
                return parsedEpisodes.isEmpty ? nil : parsedEpisodes
            } else if response.results.count == 1 && response.results[0].wrapperType == "audiobook" {
                let b = response.results[0]
                let playableAudio = b.episodeUrl ?? b.previewUrl
                guard let audio = playableAudio, !audio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                let normalizedDate = DateFormatterUtility.parse(b.releaseDate).map { DateFormatterUtility.formatISO8601($0) } ?? b.releaseDate
                return [Episode(
                    trackId: b.collectionId ?? 0,
                    trackName: b.collectionName ?? "",
                    description: b.description ?? b.collectionName,
                    releaseDate: normalizedDate,
                    previewUrl: audio.trimmingCharacters(in: .whitespacesAndNewlines),
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
        
        if !isCustomNonItunesId {
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
                let clean = ProfanityFilter.shared.filterCleanEpisodes(results)
                if !clean.isEmpty {
                    setCachedBookEpisodes(clean, for: collectionId)
                    return clean
                }
            }
        }
        
        // Lookup failed or returned no episodes, try RSS feed parsing
        var rssUrl = resolvedFeedUrl
        if rssUrl == nil && !isCustomNonItunesId {
            rssUrl = await extractRssFromApplePodcasts(collectionId: collectionId)
        }
        
        if let urlToFetch = rssUrl, !urlToFetch.isEmpty {
            if let xml = await fetchFeed(feedUrl: urlToFetch, forceRefresh: forceRefresh) {
                let parsed = parseRSSFeed(xmlText: xml, collectionId: collectionId)
                let clean = ProfanityFilter.shared.filterCleanEpisodes(parsed)
                if !clean.isEmpty {
                    setCachedBookEpisodes(clean, for: collectionId)
                    return clean
                }
            }
        }
        
        return []
    }
    
    // Batch fetch episodes for multiple podcasts concurrently
    func fetchEpisodesForPodcasts(_ podcasts: [Podcast], forceRefresh: Bool = true) async throws -> [Episode] {
        let country = LocalStorageManager.shared.currentLanguage.itunes
        return await withTaskGroup(of: [Episode].self) { group -> [Episode] in
            for p in podcasts {
                group.addTask {
                    do {
                        let eps = try await self.getPodcastEpisodes(
                            collectionId: p.collectionId,
                            preferredCountry: country,
                            feedUrl: p.feedUrl,
                            forceRefresh: forceRefresh
                        )
                        return eps.map { ep in
                            Episode(
                                trackId: ep.trackId,
                                trackName: ep.trackName,
                                description: ep.description,
                                releaseDate: ep.releaseDate,
                                previewUrl: ep.previewUrl,
                                trackTimeMillis: ep.trackTimeMillis,
                                artworkUrl60: ep.artworkUrl60 ?? p.artworkUrl100,
                                artworkUrl160: ep.artworkUrl160 ?? p.artworkUrl100 ?? p.artworkUrl600,
                                artworkUrl600: ep.artworkUrl600 ?? p.artworkUrl600 ?? p.artworkUrl100,
                                collectionName: (ep.collectionName?.isEmpty == false && ep.collectionName != "Podcast") ? ep.collectionName : p.collectionName,
                                collectionId: p.collectionId,
                                artistName: ep.artistName ?? p.artistName
                            )
                        }
                    } catch {
                        return []
                    }
                }
            }
            
            var allEpisodes = [Episode]()
            for await eps in group {
                allEpisodes.append(contentsOf: eps)
            }
            return allEpisodes
        }
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
        
        let cleanPodcasts = ProfanityFilter.shared.filterCleanPodcasts(validPodcasts)
            .filter { !LocalStorageManager.isAudiobookItem($0) && !LocalStorageManager.isKidsOrEnfantsItem($0) }
        let targetLang = await MainActor.run { LocalStorageManager.shared.currentLanguage }
        let effectiveLang = (targetLang.itunes.lowercased() == country.lowercased()) ? targetLang : LangCode.fromItunesCountry(country)
        return LanguageContentFilter.shared.filterPodcasts(cleanPodcasts, for: effectiveLang)
    }
    
    // Exclude any radio station or radio network from the Subscriptions ("Abonnements") tab
    func isRadioSourceOrStation(_ p: Podcast) -> Bool {
        let combined = [
            p.source ?? "",
            p.artistName,
            p.collectionName,
            p.feedUrl ?? ""
        ].joined(separator: " ").lowercased()
        
        let radioPatterns = [
            "radio france", "radiofrance", "france inter", "franceinter", "france culture", "franceculture",
            "france info", "franceinfo", "france musique", "france bleu", "fip", "mouv'",
            "rtl.fr", "rtl ", " rtl", "rtl2", "fun radio", "funradio",
            "europe 1", "europe1", "europe 2", "europe2", "virgin radio",
            "rmc", "bfm", "rfi",
            "bbc", "bbci.co.uk", "npr", "wnyc", "wbur", "kexp",
            "somafm", "icecast", "radio garden", "radiogarden",
            "nrj", "nostalgie", "skyrock", "cherie fm", "chérie fm", "rfm",
            "sud radio", "radio classique", "radioclassique", "radio nova", "tsf jazz",
            "oui fm", "ouï fm", "cadena ser", "cope", "rne", "deutschlandfunk", "wdr", "swr", "rai radio"
        ]
        for pat in radioPatterns {
            if combined.contains(pat) {
                return true
            }
        }
        return false
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
                        for b in books where !isRadioSourceOrStation(b) {
                            seenIds.insert(b.collectionId)
                            seenTitles.insert(b.collectionName.lowercased())
                            allResults.append(b)
                        }
                    }
                }
            }
        }
        
        // 2. iTunes Search Audiobooks localized by language/country
        let categoryTerms: [String: String] = {
            switch country {
            case "fr":
                return [
                    "fiction": "Romans Classiques Livre Audio",
                    "thriller": "Policier Thriller Livre Audio",
                    "scifi": "Science Fiction Fantasy Livre Audio",
                    "history": "Histoire Biographie Livre Audio",
                    "kids": "Enfants Jeunesse Livre Audio",
                    "growth": "Développement Personnel Livre Audio",
                    "arts": "Philosophie Poésie Littérature Livre Audio",
                    "all": "Livre Audio Intégral Roman"
                ]
            case "es":
                return [
                    "fiction": "Novelas Clásicos Audiolibro",
                    "thriller": "Misterio Thriller Audiolibro",
                    "scifi": "Ciencia Ficción Fantasía Audiolibro",
                    "history": "Historia Biografía Audiolibro",
                    "growth": "Desarrollo Personal Audiolibro",
                    "arts": "Filosofía Literatura Audiolibro",
                    "all": "Audiolibro Español"
                ]
            case "de":
                return [
                    "fiction": "Romane Klassiker Hörbuch",
                    "thriller": "Krimi Thriller Hörbuch",
                    "scifi": "Science Fiction Fantasy Hörbuch",
                    "history": "Geschichte Biografie Hörbuch",
                    "growth": "Persönlichkeitsentwicklung Hörbuch",
                    "arts": "Philosophie Literatur Hörbuch",
                    "all": "Hörbuch Komplett"
                ]
            case "it":
                return [
                    "fiction": "Romanzi Classici Audiolibro",
                    "thriller": "Giallo Thriller Audiolibro",
                    "scifi": "Fantascienza Fantasy Audiolibro",
                    "history": "Storia Biografia Audiolibro",
                    "growth": "Crescita Personale Audiolibro",
                    "arts": "Filosofia Letteratura Audiolibro",
                    "all": "Audiolibro Italiano"
                ]
            case "pt":
                return [
                    "fiction": "Romances Clássicos Audiolivro",
                    "thriller": "Suspense Policial Audiolivro",
                    "scifi": "Ficção Científica Fantasia Audiolivro",
                    "history": "História Biografia Audiolivro",
                    "growth": "Desenvolvimento Pessoal Audiolivro",
                    "arts": "Filosofia Literatura Audiolivro",
                    "all": "Audiolivro Português"
                ]
            default:
                return [
                    "fiction": "Fiction Classics Full Audiobook",
                    "thriller": "Mystery Thriller Full Audiobook",
                    "scifi": "Sci-Fi Fantasy Full Audiobook",
                    "history": "History Biography Full Audiobook",
                    "kids": "Kids Teens Audiobook",
                    "growth": "Self Help Mindset Audiobook",
                    "arts": "Philosophy Literature Drama Audiobook",
                    "all": "Full Audiobook Classics"
                ]
            }
        }()
        
        let termsToRun: [String] = {
            if categoryKey == "all" {
                return ["all", "fiction", "thriller", "scifi", "history", "growth", "arts"].compactMap { categoryTerms[$0] }
            }
            return [categoryTerms[categoryKey] ?? categoryTerms["all"] ?? "Audiobook"]
        }()
        
        let searchedLists = await withTaskGroup(of: [Podcast].self) { group -> [Podcast] in
            for term in termsToRun {
                group.addTask {
                    (try? await self.searchPodcasts(term: term, country: country)) ?? []
                }
            }
            var combined: [Podcast] = []
            for await list in group {
                combined.append(contentsOf: list)
            }
            return combined
        }
        
        for p in searchedLists where !isRadioSourceOrStation(p) {
            let titleLower = p.collectionName.lowercased()
            if !seenIds.contains(p.collectionId) && !seenTitles.contains(titleLower) {
                seenIds.insert(p.collectionId)
                seenTitles.insert(titleLower)
                allResults.append(p)
            }
        }
        
        // 3. LibriVox Books API Integration (language-matched)
        let lvGenreMap: [String: String] = [
            "fiction": "Fiction",
            "thriller": "Detective Fiction",
            "scifi": "Science Fiction",
            "history": "History",
            "kids": "Children",
            "growth": "Self-Help",
            "arts": "Philosophy"
        ]
        
        let currentLang = await MainActor.run { LocalStorageManager.shared.currentLanguage }
        let lvLanguage = (currentLang.itunes.lowercased() == country.lowercased()) ? currentLang.radioSearch : LangCode.fromItunesCountry(country).radioSearch
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
                        let coverFallback = openLibraryCoverURL(forTitle: b.title)
                        
                        allResults.append(Podcast(
                            collectionId: bookId,
                            artistName: authorName,
                            collectionName: b.title,
                            artworkUrl100: coverFallback,
                            artworkUrl600: coverFallback,
                            feedUrl: b.url_rss,
                            genres: [b.genre ?? "Audiobook"],
                            primaryGenreName: "Audiobook",
                            releaseDate: b.copyright_year,
                            country: country,
                            description: b.description,
                            source: "LibriVox",
                            totalDurationMillis: lvDurationMillis,
                            episodeCount: nil
                        ))
                    }
                }
            }
        }
        
        // 4. French Wordpress LitteratureAudio posts API integration (only when French is selected)
        if country == "fr" && (categoryKey == "all" || categoryKey == "fiction") {
            if let laUrl = URL(string: "https://www.litteratureaudio.com/wp-json/wp/v2/posts?per_page=16"),
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
                        let coverFallback = openLibraryCoverURL(forTitle: cleanedTitle)
                        
                        if !seenIds.contains(laId) {
                            seenIds.insert(laId)
                            allResults.append(Podcast(
                                collectionId: laId,
                                artistName: "Littérature Audio",
                                collectionName: cleanedTitle,
                                artworkUrl100: coverFallback,
                                artworkUrl600: coverFallback,
                                feedUrl: "\(post.link)feed/",
                                genres: ["Livre Audio"],
                                primaryGenreName: "Audiobook",
                                releaseDate: post.date,
                                country: country,
                                description: cleanedDesc,
                                source: "Littérature Audio"
                            ))
                        }
                    }
                }
            }
        }
        
        // 5. Loyal Books & Project Gutenberg curated RSS / Archive feeds matched to language
        let loyalAndGutenbergBooks: [(id: Int, title: String, author: String, cover: String, feed: String, source: String, cat: String, lang: String)] = [
            (25_000_001, "Le Comte de Monte-Cristo (Intégrale)", "Alexandre Dumas • Loyal Books", "https://archive.org/services/img/le_comte_de_monte-cristo_tome_1_1701_librivox", "https://www.loyalbooks.com/book/le-comte-de-monte-cristo-by-alexandre-dumas/feed", "Loyal Books", "fiction", "fr"),
            (25_000_002, "Vingt mille lieues sous les mers", "Jules Verne • Loyal Books", "https://archive.org/services/img/vingt_mille_lieues_sous_les_mers_1309_librivox", "https://www.loyalbooks.com/book/vingt-mille-lieues-sous-les-mers-by-jules-verne/feed", "Loyal Books", "scifi", "fr"),
            (25_000_003, "Le Tour du monde en quatre-vingts jours", "Jules Verne • Loyal Books", "https://archive.org/services/img/tour_du_monde_en_80_jours_1006_librivox", "https://www.loyalbooks.com/book/le-tour-du-monde-en-quatre-vingts-jours-jules-verne/feed", "Loyal Books", "fiction", "fr"),
            (25_000_004, "Arsène Lupin, gentleman-cambrioleur", "Maurice Leblanc • Projet Gutenberg", "https://archive.org/services/img/arsene_lupin_gentleman_cambrioleur_librivox", "https://www.loyalbooks.com/book/arsene-lupin-gentleman-cambrioleur-by-maurice-leblanc/feed", "Gutenberg", "thriller", "fr"),
            (25_000_005, "Le Mystère de la Chambre Jaune", "Gaston Leroux • Projet Gutenberg", "https://archive.org/services/img/mystere_de_la_chambre_jaune_0810_librivox", "https://www.loyalbooks.com/book/le-mystere-de-la-chambre-jaune-by-gaston-leroux/feed", "Gutenberg", "thriller", "fr"),
            (25_000_006, "Candide, ou l'Optimisme", "Voltaire • Loyal Books", "https://archive.org/services/img/candide_1506_librivox", "https://www.loyalbooks.com/book/candide-ou-loptimisme-by-voltaire/feed", "Loyal Books", "arts", "fr"),
            (25_000_007, "The Adventures of Sherlock Holmes", "Arthur Conan Doyle • Project Gutenberg", "https://archive.org/services/img/adventures_holmes_rg_librivox", "https://www.loyalbooks.com/book/the-adventures-of-sherlock-holmes-by-sir-arthur-conan-doyle/feed", "Gutenberg", "thriller", "us"),
            (25_000_008, "Pride and Prejudice", "Jane Austen • Loyal Books", "https://archive.org/services/img/pride_and_prejudice_librivox", "https://www.loyalbooks.com/book/pride-and-prejudice-by-jane-austen/feed", "Loyal Books", "fiction", "us"),
            (25_000_009, "The Count of Monte Cristo", "Alexandre Dumas • Loyal Books", "https://archive.org/services/img/count_monte_cristo_0711_librivox", "https://www.loyalbooks.com/book/the-count-of-monte-cristo-by-alexandre-dumas/feed", "Loyal Books", "fiction", "us"),
            (25_000_010, "Frankenstein", "Mary Shelley • Project Gutenberg", "https://archive.org/services/img/frankenstein_shelley_librivox", "https://www.loyalbooks.com/book/frankenstein-by-mary-shelley/feed", "Gutenberg", "scifi", "us")
        ]
        for item in loyalAndGutenbergBooks {
            let langMatches = (country == "fr" && item.lang == "fr") || (country == "us" && item.lang == "us")
            if langMatches && (categoryKey == "all" || categoryKey == item.cat) {
                if !seenIds.contains(item.id) {
                    seenIds.insert(item.id)
                    allResults.append(Podcast(
                        collectionId: item.id,
                        artistName: item.author,
                        collectionName: item.title,
                        artworkUrl100: item.cover,
                        artworkUrl600: item.cover,
                        feedUrl: item.feed,
                        genres: ["Livre Audio", item.source],
                        primaryGenreName: "Audiobook",
                        releaseDate: nil,
                        country: country,
                        description: "\(item.title) — Livre audio complet du domaine public (\(item.source)).",
                        source: item.source
                    ))
                }
            }
        }
        
        // 6. Verify episodes & compute total duration for every candidate book.
        // Filter out books with 0 episodes inside or total duration < 30 minutes (1,800,000 ms).
        return await enrichAndFilterAudiobooks(allResults, country: country)
    }
    
    private func openLibraryCoverURL(forTitle rawTitle: String) -> String {
        let clean = rawTitle
            .components(separatedBy: " – ").first?
            .components(separatedBy: " - ").first?
            .components(separatedBy: " (").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawTitle
        let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "book"
        return "https://covers.openlibrary.org/b/title/\(encoded)-L.jpg?default=false"
    }
    
    // MARK: - Unified "Découvrir" Tab Fetcher (Culture [including Livres] & Enfants)
    func getSubscriptionItems(section: SubscriptionSection, filterKey: String, country: String) async -> [Podcast] {
        switch section {
        case .culture, .livres:
            switch filterKey {
            case "books_classics", "fiction":
                return await getAudiobooks(country: country, categoryKey: "fiction")
            case "thriller_scifi":
                async let thrillers = getAudiobooks(country: country, categoryKey: "thriller")
                async let scifis = getAudiobooks(country: country, categoryKey: "scifi")
                let (tList, sList) = await (thrillers, scifis)
                var merged: [Podcast] = []
                var seen = Set<Int>()
                for item in tList + sList {
                    if !seen.contains(item.collectionId) {
                        seen.insert(item.collectionId)
                        merged.append(item)
                    }
                }
                return merged
            case "thriller", "scifi", "growth":
                return await getAudiobooks(country: country, categoryKey: filterKey)
            case "history":
                async let cultureItems = getCultureSubscriptionItems(filterKey: "history", country: country)
                async let bookItems = getAudiobooks(country: country, categoryKey: "history")
                let (cList, bList) = await (cultureItems, bookItems)
                var merged = cList
                var seen = Set(cList.map { $0.collectionId })
                for item in bList where !seen.contains(item.collectionId) {
                    seen.insert(item.collectionId)
                    merged.append(item)
                }
                return merged
            case "arts_archive", "arts":
                async let cultureItems = getCultureSubscriptionItems(filterKey: "arts_archive", country: country)
                async let bookItems = getAudiobooks(country: country, categoryKey: "arts")
                let (cList, bList) = await (cultureItems, bookItems)
                var merged = cList
                var seen = Set(cList.map { $0.collectionId })
                for item in bList where !seen.contains(item.collectionId) {
                    seen.insert(item.collectionId)
                    merged.append(item)
                }
                return merged
            case "all":
                async let cultureItems = getCultureSubscriptionItems(filterKey: "all", country: country)
                async let bookItems = getAudiobooks(country: country, categoryKey: "all")
                let (cList, bList) = await (cultureItems, bookItems)
                var merged = cList
                var seen = Set(cList.map { $0.collectionId })
                for item in bList where !seen.contains(item.collectionId) {
                    seen.insert(item.collectionId)
                    merged.append(item)
                }
                return merged
            default:
                return await getCultureSubscriptionItems(filterKey: filterKey, country: country)
            }
        case .enfants:
            return await getKidsSubscriptionItems(filterKey: filterKey, country: country)
        }
    }
    
    private struct CuratedFeedSeed {
        let id: Int
        let title: String
        let artist: String
        let artwork: String
        let feedUrl: String?
        let source: String
        let filterTag: String
        let description: String
        var lang: String = "all" // "fr", "en", or "all"
        var defaultEpisodes: [Episode]? = nil
    }
    
    // MARK: 1. CULTURE & GRANDS MÉDIAS (ARTE, INA, Collège de France, France TV, Le Monde, Les Échos, CNRS, Binge Audio, Louie Media, Nouvelles Écoutes, Slate, NASA, Internet Archive — NO Radio Stations!)
    private func getCultureSubscriptionItems(filterKey: String, country: String) async -> [Podcast] {
        let seeds: [CuratedFeedSeed] = [
            // --- 1. GRANDS MÉDIAS & INSTITUTIONS CULTURELLES EN PREMIER (ARTE, INA, Collège de France, France TV, Le Monde, Les Échos, CNRS...) ---
            CuratedFeedSeed(
                id: 1300409986,
                title: "Un Podcast à soi • ARTE Radio",
                artist: "ARTE Radio • Charlotte Bienaimé",
                artwork: "",
                feedUrl: "https://feeds.arteradio.com/un_podcast_a_soi_rss",
                source: "ARTE",
                filterTag: "society",
                description: "Documentaires engagés et intimes sur le genre, le féminisme et la société par ARTE Radio.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1499564552,
                title: "Bookmakers • ARTE Radio",
                artist: "ARTE Radio • Richard Gaitet",
                artwork: "",
                feedUrl: "https://feeds.arteradio.com/bookmakers_rss",
                source: "ARTE",
                filterTag: "arts_archive",
                description: "Les grands écrivains racontent en profondeur leurs secrets de fabrication littéraire au micro d'ARTE Radio.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1455270778,
                title: "Vivons heureux avant la fin du monde • ARTE",
                artist: "ARTE Radio • Delphine Saltel",
                artwork: "",
                feedUrl: "https://feeds.arteradio.com/vivons_heureux_avant_la_fin_du_monde_rss",
                source: "ARTE",
                filterTag: "society",
                description: "Enquêtes documentaires sur nos contradictions contemporaines et l'écologie par ARTE Radio.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1095479100,
                title: "Profils • ARTE Radio",
                artist: "ARTE Radio",
                artwork: "",
                feedUrl: "https://feeds.arteradio.com/profils_rss",
                source: "ARTE",
                filterTag: "society",
                description: "Portraits documentaires immersifs de personnalités ordinaires ou hors du commun signés ARTE Radio.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1589701479,
                title: "Le Dessous des Cartes • ARTE",
                artist: "ARTE • Émilie Aubry",
                artwork: "",
                feedUrl: nil,
                source: "ARTE",
                filterTag: "history",
                description: "Comprendre la géopolitique, l'histoire et le monde contemporain par les cartes avec ARTE.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1564428625,
                title: "Les Idées Larges • ARTE",
                artist: "ARTE • Laura Raim",
                artwork: "",
                feedUrl: nil,
                source: "ARTE",
                filterTag: "media_debates",
                description: "Grands entretiens philosophiques et politiques sur les idées qui transforment notre époque par ARTE.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1480853277,
                title: "INA • Les Archives de l'Histoire",
                artist: "INA (Institut National de l'Audiovisuel)",
                artwork: "",
                feedUrl: nil,
                source: "INA",
                filterTag: "history",
                description: "Plongez dans les grandes archives sonores et historiques de l'Institut National de l'Audiovisuel.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1050606431,
                title: "Collège de France • Grands Cours",
                artist: "Collège de France",
                artwork: "",
                feedUrl: nil,
                source: "Collège de France",
                filterTag: "science_nasa",
                description: "Les leçons inaugurales, cours et conférences des chaires du Collège de France.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1436404237,
                title: "La Grande Librairie",
                artist: "France Télévisions • Augustin Trapenard",
                artwork: "",
                feedUrl: nil,
                source: "France TV",
                filterTag: "arts_archive",
                description: "Le grand rendez-vous littéraire et culturel autour des livres et des écrivains.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1185950039,
                title: "C dans l'air",
                artist: "France Télévisions",
                artwork: "",
                feedUrl: nil,
                source: "France TV",
                filterTag: "media_debates",
                description: "Décryptage quotidien des grands sujets d'actualité nationale et internationale par des experts.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1559617847,
                title: "L'Heure du Monde",
                artist: "Le Monde",
                artwork: "",
                feedUrl: nil,
                source: "Le Monde",
                filterTag: "media_debates",
                description: "Chaque jour, un grand reportage ou une enquête approfondie avec les journalistes du Monde.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1458559138,
                title: "La Story • Les Échos",
                artist: "Les Échos",
                artwork: "",
                feedUrl: nil,
                source: "Les Échos",
                filterTag: "media_debates",
                description: "L'actualité économique, géopolitique et technologique racontée par la rédaction des Échos.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1647292488,
                title: "Qu'est-ce que tu cherches ? • CNRS",
                artist: "CNRS (Centre National de la Recherche Scientifique)",
                artwork: "",
                feedUrl: nil,
                source: "CNRS",
                filterTag: "science_nasa",
                description: "Les scientifiques du CNRS expliquent leurs découvertes et leurs recherches.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1562865884,
                title: "Futura Sciences • Découvertes & Savoirs",
                artist: "Futura",
                artwork: "",
                feedUrl: nil,
                source: "Futura",
                filterTag: "science_nasa",
                description: "Explorez les sciences, l'espace, la nature et l'histoire avec Futura.",
                lang: "fr"
            ),
            // --- 2. GRANDS STUDIOS DOCUMENTAIRES & CULTURELS (Binge Audio, Louie Media, Nouvelles Écoutes, Slate...) ---
            CuratedFeedSeed(
                id: 1162201829,
                title: "Programme B",
                artist: "Binge Audio • Thomas Rozec",
                artwork: "",
                feedUrl: "https://feeds.acast.com/public/shows/programme-b",
                source: "Binge Audio",
                filterTag: "media_debates",
                description: "Tous les jours, comprendre l'actualité et les grands enjeux de société avec Binge Audio.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1478523360,
                title: "La Terre au Carré",
                artist: "France Inter • Mathieu Vidard",
                artwork: "",
                feedUrl: "https://radiofrance-podcast.net/podcast09/rss_10078.xml",
                source: "Grands Médias",
                filterTag: "science_nasa",
                description: "Le grand magazine quotidien des sciences, du climat et de la nature.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1434061192,
                title: "Kiffe ta race",
                artist: "Binge Audio • Rokhaya Diallo & Grace Ly",
                artwork: "",
                feedUrl: "https://feeds.acast.com/public/shows/kiffe-ta-race",
                source: "Binge Audio",
                filterTag: "society",
                description: "Conversations culturelles et sociétales signées Binge Audio.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1556742725,
                title: "Le Cœur sur la table",
                artist: "Binge Audio • Victoire Tuaillon",
                artwork: "",
                feedUrl: "https://feeds.acast.com/public/shows/le-coeur-sur-la-table",
                source: "Binge Audio",
                filterTag: "society",
                description: "Récits et documentaires sur nos relations affectives et l'amour.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1347400908,
                title: "Émotions",
                artist: "Louie Media",
                artwork: "",
                feedUrl: "https://feeds.acast.com/public/shows/emotions",
                source: "Louie Media",
                filterTag: "society",
                description: "Comprendre pourquoi vous ressentez ce que vous ressentez, par le studio Louie Media.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1455269923,
                title: "Passages",
                artist: "Louie Media",
                artwork: "",
                feedUrl: "https://feeds.acast.com/public/shows/passages",
                source: "Louie Media",
                filterTag: "society",
                description: "Le récit d'un moment charnière qui a fait basculer une vie.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1490003711,
                title: "Travail (en cours)",
                artist: "Louie Media",
                artwork: "",
                feedUrl: "https://feeds.acast.com/public/shows/travail-en-cours",
                source: "Louie Media",
                filterTag: "media_debates",
                description: "Comment le travail transforme nos vies et notre société.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1181931018,
                title: "La Poudre",
                artist: "Nouvelles Écoutes • Lauren Bastide",
                artwork: "",
                feedUrl: nil,
                source: "Nouvelles Écoutes",
                filterTag: "arts_archive",
                description: "Grands entretiens intimes et culturels avec des artistes, écrivaines et penseuses.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1357766702,
                title: "Splash",
                artist: "Nouvelles Écoutes",
                artwork: "",
                feedUrl: nil,
                source: "Nouvelles Écoutes",
                filterTag: "media_debates",
                description: "Décryptage alerte et accessible de l'économie et des faits de société.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 589182365,
                title: "Transfert",
                artist: "Slate Podcasts",
                artwork: "",
                feedUrl: "https://feeds.audiomeans.fr/feed/b568b5b9-24f4-4c6f-be55-f1e0e532b1d7.xml",
                source: "Slate",
                filterTag: "society",
                description: "Des histoires vraies, intimes et extraordinaires racontées par ceux qui les ont vécues.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1210190903,
                title: "Peak TV",
                artist: "Slate Podcasts",
                artwork: "",
                feedUrl: nil,
                source: "Slate",
                filterTag: "arts_archive",
                description: "Le podcast culturel de Slate dédié aux séries et à la pop culture.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1048372492,
                title: "Choses à Savoir • Culture Générale",
                artist: "Choses à Savoir • Louis Boetinger",
                artwork: "",
                feedUrl: "https://feeds.acast.com/public/shows/choses-a-savoir",
                source: "Choses à Savoir",
                filterTag: "science_nasa",
                description: "Développez votre culture générale tous les jours.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1476186832,
                title: "Le Précepteur • Philosophie & Culture",
                artist: "Ausha • Charles Robin",
                artwork: "",
                feedUrl: nil,
                source: "Philosophie",
                filterTag: "arts_archive",
                description: "Podcast de philosophie et d'analyse des grands penseurs.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1465423969,
                title: "Nota Bene • Histoire",
                artist: "Nota Bene • Benjamin Brillaud",
                artwork: "",
                feedUrl: nil,
                source: "Nota Bene",
                filterTag: "history",
                description: "Les grandes épopées et anecdotes de l'Histoire racontées avec passion.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1538606694,
                title: "Paroles d'Histoire",
                artist: "André Loez • Histoire",
                artwork: "",
                feedUrl: nil,
                source: "Histoire",
                filterTag: "history",
                description: "Entretiens approfondis avec des historiens sur toutes les périodes de l'Histoire.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1270366751,
                title: "Génération Do It Yourself",
                artist: "Matthieu Stefani",
                artwork: "",
                feedUrl: nil,
                source: "GDIY",
                filterTag: "media_debates",
                description: "Conversations au long cours avec des créateurs, auteurs, artistes et entrepreneurs.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1677469170,
                title: "LEGEND",
                artist: "Guillaume Pley",
                artwork: "",
                feedUrl: nil,
                source: "LEGEND",
                filterTag: "society",
                description: "Entretiens longs avec des personnalités aux parcours hors normes.",
                lang: "fr"
            ),
            // --- 3. NASA & INTERNET ARCHIVE & GRANDS MÉDIAS INTERNATIONAUX ---
            CuratedFeedSeed(
                id: 1505624059,
                title: "NASA's Curious Universe",
                artist: "NASA Official",
                artwork: "",
                feedUrl: "https://www.nasa.gov/feeds/curious-universe-feed/",
                source: "NASA",
                filterTag: "science_nasa",
                description: "Explore the cosmos, space missions, and scientific discoveries with NASA astronauts and scientists.",
                lang: "all"
            ),
            CuratedFeedSeed(
                id: 1252829147,
                title: "Houston We Have a Podcast",
                artist: "NASA Johnson Space Center",
                artwork: "",
                feedUrl: nil,
                source: "NASA",
                filterTag: "science_nasa",
                description: "The official podcast of the NASA Johnson Space Center in Houston, Texas.",
                lang: "all"
            ),
            CuratedFeedSeed(
                id: 1405660398,
                title: "NASA • Small Steps, Giant Leaps",
                artist: "NASA APPEL Knowledge Services",
                artwork: "",
                feedUrl: nil,
                source: "NASA",
                filterTag: "science_nasa",
                description: "Space engineering, technical innovations, and behind-the-scenes stories of NASA missions.",
                lang: "all"
            ),
            CuratedFeedSeed(
                id: 52_000_001,
                title: "Internet Archive • Apollo 11 & Space Audio Archives",
                artist: "Internet Archive • NASA Audio Collection",
                artwork: "https://archive.org/services/img/Apollo11Audio",
                feedUrl: "https://archive.org/metadata/Apollo11Audio",
                source: "Internet Archive",
                filterTag: "science_nasa",
                description: "Historic space mission audio recordings preserved by the Internet Archive.",
                lang: "all"
            ),
            CuratedFeedSeed(
                id: 394775318,
                title: "99% Invisible",
                artist: "Simplecast • Roman Mars",
                artwork: "",
                feedUrl: "https://feeds.simplecast.com/BqbsxVfO",
                source: "Simplecast",
                filterTag: "arts_archive",
                description: "Architecture, design, and the hidden history of the built world.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 659155419,
                title: "Philosophize This!",
                artist: "Megaphone • Stephen West",
                artwork: "",
                feedUrl: nil,
                source: "Megaphone",
                filterTag: "arts_archive",
                description: "The ideas that shaped our world explained from antiquity to modern philosophy.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 1119389968,
                title: "Revisionist History",
                artist: "Pushkin / Omny Studio • Malcolm Gladwell",
                artwork: "",
                feedUrl: nil,
                source: "Omny Studio",
                filterTag: "history",
                description: "Malcolm Gladwell re-examines something from the past—an event, a person, an idea.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 173001861,
                title: "Dan Carlin's Hardcore History",
                artist: "Dan Carlin • Independent",
                artwork: "",
                feedUrl: nil,
                source: "Culture",
                filterTag: "history",
                description: "Epic, long-form historical narratives exploring pivotal moments in human history.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 840986946,
                title: "No Such Thing As A Fish",
                artist: "Audioboom • QI Elves",
                artwork: "",
                feedUrl: nil,
                source: "Audioboom",
                filterTag: "science_nasa",
                description: "Fascinating facts, science, history, and culture discovered by the QI researchers.",
                lang: "en"
            )
        ]
        
        let activeLang = await MainActor.run { LocalStorageManager.shared.currentLanguage }
        let effectiveLang = (activeLang.itunes.lowercased() == country.lowercased()) ? activeLang : LangCode.fromItunesCountry(country)
        let langSeeds = seeds.filter { seed in
            guard filterKey == "all" || seed.filterTag == filterKey else { return false }
            if effectiveLang == .fr { return seed.lang == "fr" }
            if effectiveLang == .en { return seed.lang == "en" || seed.lang == "all" }
            return false
        }
        var candidates = await materializeSeeds(langSeeds, country: country)
        
        // Supplement with language-matched non-radio Culture & Major Media podcasts across all relevant categories
        let searchTerms: [String: String] = {
            switch country {
            case "fr":
                return [
                    "all": "ARTE Radio INA Collège de France Culture Documentaire",
                    "society": "ARTE Radio Binge Audio Louie Media Société Récit",
                    "history": "INA Histoire Collège de France Civilisations Patrimoine",
                    "science_nasa": "CNRS Collège de France Sciences Espace Découverte",
                    "media_debates": "ARTE Idées Débat Philosophie Économie Le Monde",
                    "arts_archive": "ARTE Bookmakers INA Arts Cinéma Littérature Philosophie"
                ]
            case "es":
                return [
                    "all": "Cultura Historia Ciencia Filosofía Documental",
                    "society": "Sociedad Documental Historias",
                    "history": "Historia Civilizaciones Documental",
                    "science_nasa": "Ciencia Espacio Astronomía NASA",
                    "media_debates": "Debate Ideas Filosofía Economía",
                    "arts_archive": "Arte Cine Literatura Filosofía"
                ]
            case "de":
                return [
                    "all": "ARTE Kultur Geschichte Wissenschaft Philosophie",
                    "society": "Gesellschaft Geschichten Dokumentation",
                    "history": "Geschichte Zeitgeschichte Epochen",
                    "science_nasa": "Wissenschaft Weltraum Astronomie",
                    "media_debates": "Debatte Ideen Philosophie Wirtschaft",
                    "arts_archive": "Kunst Literatur Film Philosophie"
                ]
            default:
                return [
                    "all": "Smithsonian Oxford History Science Philosophy Documentary",
                    "society": "Society Culture Documentary Storytelling",
                    "history": "History Civilizations Deep Dive",
                    "science_nasa": "Space Astronomy NASA Science",
                    "media_debates": "Ideas Philosophy Economics Debate",
                    "arts_archive": "Arts Literature Cinema Design Architecture"
                ]
            }
        }()
        
        let termsToQuery: [String] = {
            if filterKey == "all" {
                return ["all", "society", "history", "science_nasa", "media_debates", "arts_archive"].compactMap { searchTerms[$0] }
            }
            return [searchTerms[filterKey] ?? "Culture"]
        }()
        
        let searchedLists = await withTaskGroup(of: [Podcast].self) { group -> [Podcast] in
            for term in termsToQuery {
                group.addTask {
                    (try? await self.searchPodcasts(term: term, country: country)) ?? []
                }
            }
            var combined: [Podcast] = []
            for await list in group {
                combined.append(contentsOf: list)
            }
            return combined
        }
        
        var existingIds = Set(candidates.map { $0.collectionId })
        var existingTitles = Set(candidates.map { $0.collectionName.lowercased() })
        for p in searchedLists where !existingIds.contains(p.collectionId) && !isRadioSourceOrStation(p) {
            let tLower = p.collectionName.lowercased()
            guard !existingTitles.contains(tLower) else { continue }
            existingIds.insert(p.collectionId)
            existingTitles.insert(tLower)
            var tagged = p
            if tagged.source == nil {
                let artistLow = p.artistName.lowercased()
                if artistLow.contains("arte") { tagged.source = "ARTE" }
                else if artistLow.contains("ina") { tagged.source = "INA" }
                else if artistLow.contains("collège de france") { tagged.source = "Collège de France" }
                else if artistLow.contains("binge") { tagged.source = "Binge Audio" }
                else if artistLow.contains("louie") { tagged.source = "Louie Media" }
                else if artistLow.contains("slate") { tagged.source = "Slate" }
                else if artistLow.contains("cnrs") { tagged.source = "CNRS" }
                else { tagged.source = "Culture" }
            }
            candidates.append(tagged)
        }
        
        return await enrichAndFilterAudiobooks(candidates, country: country)
    }
    
    // MARK: 3. ENFANTS (Rich Kids Stories, Playlists de Comptines, Histoires pour Dormir, Aventures, Sciences Junior — NO Radio Stations!)
    private func getKidsSubscriptionItems(filterKey: String, country: String) async -> [Podcast] {
        let frSeeds: [CuratedFeedSeed] = [
            // Histoires & Contes (FR)
            CuratedFeedSeed(
                id: 1460863676,
                title: "Encore une Histoire",
                artist: "Binge Audio / Acast • Céline Kallmann",
                artwork: "",
                feedUrl: "https://feeds.acast.com/public/shows/encore-une-histoire",
                source: "Binge Audio",
                filterTag: "stories",
                description: "Les meilleurs albums de littérature jeunesse lus et mis en musique pour les enfants.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1348573222,
                title: "Taleming • Histoires pour enfants",
                artist: "Taleming / Acast",
                artwork: "",
                feedUrl: "https://feeds.acast.com/public/shows/taleming",
                source: "Taleming",
                filterTag: "stories",
                description: "Des histoires originales pleines d'humour et d'émotion pour les 5-10 ans.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1503981533,
                title: "Lis-moi une histoire • Albin Michel Jeunesse",
                artist: "Albin Michel Jeunesse • Ausha",
                artwork: "",
                feedUrl: nil,
                source: "Jeunesse",
                filterTag: "stories",
                description: "Des histoires merveilleuses lues par leurs auteurs pour faire rêver les enfants.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1373960340,
                title: "La Grande Histoire de Pomme d'Api",
                artist: "Bayard Jeunesse",
                artwork: "",
                feedUrl: nil,
                source: "Bayard Jeunesse",
                filterTag: "stories",
                description: "Chaque mois, la grande histoire du magazine Pomme d'Api à écouter en famille.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1504641094,
                title: "Les Histoires de Loulou • L'École des Loisirs",
                artist: "L'École des Loisirs",
                artwork: "",
                feedUrl: nil,
                source: "École des Loisirs",
                filterTag: "stories",
                description: "Les héros préférés de l'École des Loisirs prennent vie en audio pour les enfants.",
                lang: "fr"
            ),
            // Aventures & Mythologie (FR)
            CuratedFeedSeed(
                id: 1438050126,
                title: "Mythes et Légendes • Quelle Histoire",
                artist: "Quelle Histoire / Acast",
                artwork: "",
                feedUrl: "https://feeds.acast.com/public/shows/mythes-et-legendes",
                source: "Quelle Histoire",
                filterTag: "adventure",
                description: "Ulysse, Hercule, le Roi Arthur et les grands héros de la mythologie pour les enfants.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1512046610,
                title: "Au Cœur de l'Histoire Junior • Quelle Histoire",
                artist: "Quelle Histoire / Unique Heritage",
                artwork: "",
                feedUrl: nil,
                source: "Quelle Histoire",
                filterTag: "adventure",
                description: "Découvrir les grands personnages et aventures de l'Histoire dès 6 ans.",
                lang: "fr"
            ),
            // Animaux & Sciences Junior (FR)
            CuratedFeedSeed(
                id: 1350615095,
                title: "Petits Curieux • Choses à Savoir Junior",
                artist: "Acast • Découverte Enfants",
                artwork: "",
                feedUrl: nil,
                source: "Acast",
                filterTag: "nature",
                description: "Réponses simples et amusantes aux grandes questions des enfants sur les animaux et la nature.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1643627098,
                title: "Curieux de Sciences • Bayard Jeunesse",
                artist: "Bayard Jeunesse & Muséum d'Histoire Naturelle",
                artwork: "",
                feedUrl: nil,
                source: "Bayard Jeunesse",
                filterTag: "nature",
                description: "Les enfants partent à la découverte des animaux, de la Terre et des étoiles.",
                lang: "fr"
            ),
            CuratedFeedSeed(
                id: 1481020030,
                title: "Qui, Quand, Quoi ? • Images Doc",
                artist: "Bayard Jeunesse",
                artwork: "",
                feedUrl: nil,
                source: "Bayard Jeunesse",
                filterTag: "nature",
                description: "Sciences, nature et histoire expliquées aux enfants de 8 à 12 ans.",
                lang: "fr"
            )
        ]
        
        let enSeeds: [CuratedFeedSeed] = [
            CuratedFeedSeed(
                id: 79911740,
                title: "Storynory • Audio Stories for Kids",
                artist: "Storynory",
                artwork: "",
                feedUrl: "https://feeds.feedburner.com/storynory",
                source: "Storynory",
                filterTag: "stories",
                description: "Classic fairy tales, fables, myths, and original children's stories.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 944090921,
                title: "Stories Podcast: A Bedtime Show for Kids",
                artist: "Wondery Kids",
                artwork: "",
                feedUrl: nil,
                source: "Wondery Kids",
                filterTag: "stories",
                description: "Original children's stories and fairy tales for kids of all ages.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 1438263204,
                title: "Sleep Tight Stories • Bedtime Stories for Kids",
                artist: "Sleep Tight Media",
                artwork: "",
                feedUrl: nil,
                source: "Bedtime",
                filterTag: "bedtime",
                description: "Calming bedtime stories designed to help kids fall asleep peacefully.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 1515659472,
                title: "Sleep Tight Relax • Bedtime Music & Calm for Kids",
                artist: "Sleep Tight Media",
                artwork: "",
                feedUrl: nil,
                source: "Bedtime",
                filterTag: "bedtime",
                description: "Soothing bedtime meditations, lullabies, and relaxing stories for children.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 1617501656,
                title: "Koala Moon • Kids Bedtime Stories & Meditations",
                artist: "Koala Shine",
                artwork: "",
                feedUrl: nil,
                source: "Bedtime",
                filterTag: "bedtime",
                description: "Magical bedtime stories and sleep meditations for children.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 1176096732,
                title: "Peace Out • Relaxation Stories for Kids",
                artist: "Bedtime FM",
                artwork: "",
                feedUrl: nil,
                source: "Bedtime",
                filterTag: "bedtime",
                description: "Short stories that help children calm down and relax through visualization and breathing.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 1648863535,
                title: "Super Simple Podcast • Kids Songs & Rhymes",
                artist: "Super Simple",
                artwork: "",
                feedUrl: nil,
                source: "Kids Music",
                filterTag: "music_kids",
                description: "Sing-along songs, nursery rhymes, and musical adventures for little ones.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 1484888369,
                title: "Clap for Classics! • Music & Rhymes for Kids",
                artist: "Clap for Classics",
                artwork: "",
                feedUrl: nil,
                source: "Kids Music",
                filterTag: "music_kids",
                description: "Nursery rhymes, kids songs, and classical music appreciation for young children.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 1483233279,
                title: "Greeking Out from National Geographic Kids",
                artist: "National Geographic Kids",
                artwork: "",
                feedUrl: nil,
                source: "NatGeo Kids",
                filterTag: "adventure",
                description: "Action-packed retellings of the greatest myths and legends of ancient Greece for kids.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 1321899935,
                title: "Bedtime History • Inspirational Stories for Kids",
                artist: "Bedtime History",
                artwork: "",
                feedUrl: nil,
                source: "Adventure",
                filterTag: "adventure",
                description: "Inspiring true stories from history told in a calm, kid-friendly way.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 984771479,
                title: "Tumble Science Podcast for Kids",
                artist: "Tumble Media",
                artwork: "",
                feedUrl: nil,
                source: "Kids Science",
                filterTag: "nature",
                description: "Science stories for curious kids and the whole family.",
                lang: "en"
            ),
            CuratedFeedSeed(
                id: 1532635650,
                title: "Who Smarted? • Science & Nature for Kids",
                artist: "Atomic Entertainment",
                artwork: "",
                feedUrl: nil,
                source: "Kids Science",
                filterTag: "nature",
                description: "Fun, Bite-sized science, animals, and history facts for curious kids.",
                lang: "en"
            )
        ]
        
        let activeLang = await MainActor.run { LocalStorageManager.shared.currentLanguage }
        let effectiveLang = (activeLang.itunes.lowercased() == country.lowercased()) ? activeLang : LangCode.fromItunesCountry(country)
        let baseSeeds: [CuratedFeedSeed] = {
            switch effectiveLang {
            case .fr: return frSeeds
            case .en: return enSeeds
            default: return []
            }
        }()
        let activeSeeds = baseSeeds.filter {
            filterKey == "all" || $0.filterTag == filterKey
        }
        var candidates = await materializeSeeds(activeSeeds, country: country)
        
        // Multi-query dynamic searches for Kids (Playlists de comptines, Histoires pour dormir, Contes, Aventures, Animaux)
        let queriesByFilter: [String: [String]] = {
            switch country {
            case "fr":
                return [
                    "all": [
                        "Histoires pour enfants contes jeunesse",
                        "Comptines chansons bébés enfants",
                        "Histoires pour dormir enfants calme soir",
                        "Mythologie aventures enfants"
                    ],
                    "stories": [
                        "Contes et histoires pour enfants",
                        "Histoires jeunesse album audio enfant",
                        "Contes de fées fables enfants"
                    ],
                    "music_kids": [
                        "Comptines et chansons pour enfants",
                        "Berceuses comptines bébé maternelle",
                        "Chansons pour enfants éveil musical",
                        "Contes musicaux musiques enfants"
                    ],
                    "bedtime": [
                        "Histoires pour dormir enfants",
                        "Histoire du soir enfant sommeil calme",
                        "Méditation relaxation sommeil enfant",
                        "Berceuses histoire pour s'endormir enfant"
                    ],
                    "adventure": [
                        "Mythologie enfants mythes et légendes",
                        "Histoire racontée aux enfants aventure",
                        "Aventures jeunesse exploration enfants"
                    ],
                    "nature": [
                        "Animaux nature sciences enfants",
                        "Découverte sciences junior enfants",
                        "Pourquoi comment enfants animaux"
                    ]
                ]
            case "es":
                return [
                    "all": ["Cuentos infantiles para niños", "Canciones infantiles nanas para dormir"],
                    "stories": ["Cuentos infantiles audio niños"],
                    "music_kids": ["Canciones infantiles música para niños"],
                    "bedtime": ["Cuentos para dormir niños relajación"],
                    "adventure": ["Aventuras mitología historia para niños"],
                    "nature": ["Ciencia animales naturaleza para niños"]
                ]
            case "de":
                return [
                    "all": ["Kindergeschichten Hörspiel Kinder", "Kinderlieder Einschlafgeschichten"],
                    "stories": ["Kindergeschichten Märchen für Kinder"],
                    "music_kids": ["Kinderlieder Schlaflieder Musik für Kinder"],
                    "bedtime": ["Gute Nacht Geschichten Einschlafen Kinder"],
                    "adventure": ["Abenteuer Geschichte für Kinder"],
                    "nature": ["Wissen Tiere Natur für Kinder"]
                ]
            default:
                return [
                    "all": [
                        "Kids bedtime stories fairy tales",
                        "Nursery rhymes kids songs lullabies",
                        "Kids sleep meditation bedtime stories",
                        "Science adventure stories for kids"
                    ],
                    "stories": [
                        "Stories for kids fairy tales fables",
                        "Children audio stories storytelling"
                    ],
                    "music_kids": [
                        "Nursery rhymes kids songs sing along",
                        "Baby lullabies children music playlist",
                        "Toddler songs musical stories kids"
                    ],
                    "bedtime": [
                        "Bedtime stories for kids sleep",
                        "Kids sleep meditation calm bedtime",
                        "Soothing bedtime stories lullabies kids"
                    ],
                    "adventure": [
                        "Mythology adventure stories for kids",
                        "History stories for kids heroes"
                    ],
                    "nature": [
                        "Science nature animals podcast for kids",
                        "Curious kids science animals space"
                    ]
                ]
            }
        }()
        
        let queries = queriesByFilter[filterKey] ?? queriesByFilter["all"] ?? ["Kids stories"]
        let searchedLists = await withTaskGroup(of: [Podcast].self) { group -> [Podcast] in
            for q in queries {
                group.addTask {
                    (try? await self.searchPodcasts(term: q, country: country)) ?? []
                }
            }
            var combined: [Podcast] = []
            for await list in group {
                combined.append(contentsOf: list)
            }
            return combined
        }
        
        var existingIds = Set(candidates.map { $0.collectionId })
        var existingTitles = Set(candidates.map { $0.collectionName.lowercased() })
        for p in searchedLists where !isRadioSourceOrStation(p) {
            let titleLow = p.collectionName.lowercased()
            guard !existingIds.contains(p.collectionId), !existingTitles.contains(titleLow) else { continue }
            existingIds.insert(p.collectionId)
            existingTitles.insert(titleLow)
            var tagged = p
            if tagged.source == nil {
                switch filterKey {
                case "music_kids": tagged.source = country == "fr" ? "Comptines" : "Kids Music"
                case "bedtime": tagged.source = country == "fr" ? "Histoire du Soir" : "Bedtime"
                default: tagged.source = country == "fr" ? "Enfants" : "Kids"
                }
            }
            candidates.append(tagged)
            if candidates.count >= 65 { break }
        }
        
        return await enrichAndFilterAudiobooks(candidates, country: country)
    }
    
    private func materializeSeeds(_ seeds: [CuratedFeedSeed], country: String) async -> [Podcast] {
        // Lookup real iTunes IDs (< 50_000_000_000 and not in custom ranges 25M..60M) in batch for high-res artwork & feedUrl
        let itunesIds = seeds.map { $0.id }.filter { $0 < 25_000_000 || $0 >= 60_000_000 }
        var itunesMap: [Int: Podcast] = [:]
        if !itunesIds.isEmpty {
            if let lookedUp = try? await getPodcastsByIds(ids: itunesIds, country: country) {
                for p in lookedUp {
                    itunesMap[p.collectionId] = p
                }
            }
            let missingIds = itunesIds.filter { itunesMap[$0] == nil }
            if !missingIds.isEmpty, let lookedUpFR = try? await getPodcastsByIds(ids: missingIds, country: "fr") {
                for p in lookedUpFR {
                    itunesMap[p.collectionId] = p
                }
            }
            let stillMissingIds = itunesIds.filter { itunesMap[$0] == nil }
            if !stillMissingIds.isEmpty, let lookedUpUS = try? await getPodcastsByIds(ids: stillMissingIds, country: "us") {
                for p in lookedUpUS {
                    itunesMap[p.collectionId] = p
                }
            }
        }
        
        var materialized: [Podcast] = []
        for seed in seeds {
            if let eps = seed.defaultEpisodes, !eps.isEmpty {
                setCachedBookEpisodes(eps, for: seed.id)
                let totalMillis = eps.reduce(0) { $0 + ($1.trackTimeMillis ?? 0) }
                materialized.append(Podcast(
                    collectionId: seed.id,
                    artistName: seed.artist,
                    collectionName: seed.title,
                    artworkUrl100: seed.artwork,
                    artworkUrl600: seed.artwork,
                    feedUrl: seed.feedUrl,
                    genres: [seed.source],
                    primaryGenreName: seed.source,
                    releaseDate: nil,
                    country: country,
                    description: seed.description,
                    source: seed.source,
                    totalDurationMillis: totalMillis,
                    episodeCount: eps.count
                ))
            } else if let found = itunesMap[seed.id] {
                materialized.append(Podcast(
                    collectionId: found.collectionId,
                    artistName: seed.artist.isEmpty ? found.artistName : seed.artist,
                    collectionName: found.collectionName,
                    artworkUrl100: found.artworkUrl100 ?? (seed.artwork.isEmpty ? nil : seed.artwork),
                    artworkUrl600: found.artworkUrl600 ?? (seed.artwork.isEmpty ? nil : seed.artwork),
                    feedUrl: seed.feedUrl ?? found.feedUrl,
                    genres: found.genres,
                    primaryGenreName: found.primaryGenreName,
                    releaseDate: found.releaseDate,
                    country: found.country ?? country,
                    description: seed.description.isEmpty ? found.description : seed.description,
                    source: seed.source,
                    totalDurationMillis: found.totalDurationMillis,
                    episodeCount: found.episodeCount,
                    trackCount: found.trackCount
                ))
            } else {
                materialized.append(Podcast(
                    collectionId: seed.id,
                    artistName: seed.artist,
                    collectionName: seed.title,
                    artworkUrl100: seed.artwork.isEmpty ? nil : seed.artwork,
                    artworkUrl600: seed.artwork.isEmpty ? nil : seed.artwork,
                    feedUrl: seed.feedUrl,
                    genres: [seed.source],
                    primaryGenreName: seed.source,
                    releaseDate: nil,
                    country: country,
                    description: seed.description,
                    source: seed.source
                ))
            }
        }
        return materialized
    }
    
    func enrichAndFilterAudiobooks(_ candidates: [Podcast], country: String) async -> [Podcast] {
        let minDurationMillis = 30 * 60 * 1000 // 30 minutes minimum for ALL subscriptions
        let nonRadioCandidates = candidates.filter { !isRadioSourceOrStation($0) }
        let cappedCandidates = Array(nonRadioCandidates.prefix(90))
        
        let verifiedMap = await withTaskGroup(of: (Int, Podcast?).self) { group -> [Int: Podcast] in
            for (index, book) in cappedCandidates.enumerated() {
                group.addTask {
                    // Fast path 1: If episodes are already cached or totalDurationMillis + episodeCount already verified
                    if let existingMillis = book.totalDurationMillis, existingMillis >= minDurationMillis,
                       let existingCount = book.episodeCount, existingCount > 0 {
                        return (index, book)
                    }
                    
                    // Fast path 2: If iTunes Search/Lookup already provided trackCount >= 3 and valid artwork + feedUrl,
                    // we can verify the top 24 items via episode lookup and estimate remaining items instantaneously to avoid network congestion
                    let isStandardItunes = (book.collectionId < 10_000_000 || book.collectionId >= 60_000_000)
                    if index >= 24, isStandardItunes,
                       let knownTrackCount = book.trackCount, knownTrackCount >= 3,
                       let art = book.artworkUrl600 ?? book.artworkUrl100, !art.isEmpty {
                        let estimatedDuration = max(minDurationMillis, knownTrackCount * 22 * 60 * 1000)
                        let fastEnriched = Podcast(
                            collectionId: book.collectionId,
                            artistName: book.artistName,
                            collectionName: book.collectionName,
                            artworkUrl100: book.artworkUrl100 ?? art,
                            artworkUrl600: book.artworkUrl600 ?? art,
                            feedUrl: book.feedUrl,
                            genres: book.genres,
                            primaryGenreName: book.primaryGenreName,
                            releaseDate: book.releaseDate,
                            country: book.country,
                            description: book.description,
                            source: book.source,
                            totalDurationMillis: estimatedDuration,
                            episodeCount: knownTrackCount,
                            trackCount: knownTrackCount
                        )
                        return (index, fastEnriched)
                    }
                    
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
                    
                    // Exclude subscriptions with 0 playable episodes inside
                    guard !playableEpisodes.isEmpty else {
                        return (index, nil)
                    }
                    
                    let computedDuration = playableEpisodes.reduce(0) { sum, ep in
                        sum + max(0, ep.trackTimeMillis ?? 0)
                    }
                    let finalDuration = max(computedDuration, book.totalDurationMillis ?? 0)
                    
                    // Exclude subscriptions whose total duration is under 30 minutes
                    guard finalDuration >= minDurationMillis else {
                        return (index, nil)
                    }
                    
                    self.setCachedBookEpisodes(playableEpisodes, for: book.collectionId)
                    
                    // Ensure artworkUrl600 / artworkUrl100 is populated from episodes if missing on the parent Podcast
                    let epArtwork = playableEpisodes.lazy.compactMap { $0.artworkUrl600 ?? $0.artworkUrl160 ?? $0.artworkUrl60 }.first { !$0.isEmpty }
                    let resolvedArt600: String? = {
                        if let existing = book.artworkUrl600, !existing.isEmpty,
                           !existing.contains("librivox-logo.png"),
                           !existing.contains("litteratureaudio.com/wp-content") {
                            return existing
                        }
                        return epArtwork ?? book.artworkUrl100 ?? self.openLibraryCoverURL(forTitle: book.collectionName)
                    }()
                    let resolvedArt100 = book.artworkUrl100 ?? resolvedArt600
                    
                    let enriched = Podcast(
                        collectionId: book.collectionId,
                        artistName: book.artistName,
                        collectionName: book.collectionName,
                        artworkUrl100: resolvedArt100,
                        artworkUrl600: resolvedArt600,
                        feedUrl: book.feedUrl,
                        genres: book.genres,
                        primaryGenreName: book.primaryGenreName,
                        releaseDate: book.releaseDate,
                        country: book.country,
                        description: book.description,
                        source: book.source,
                        totalDurationMillis: finalDuration,
                        episodeCount: max(playableEpisodes.count, book.trackCount ?? 0),
                        trackCount: book.trackCount
                    )
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
        
        let verifiedList = cappedCandidates.indices.compactMap { verifiedMap[$0] }
        let cleanList = ProfanityFilter.shared.filterCleanPodcasts(verifiedList)
        let activeLang = await MainActor.run { LocalStorageManager.shared.currentLanguage }
        let effectiveLang = (activeLang.itunes.lowercased() == country.lowercased()) ? activeLang : LangCode.fromItunesCountry(country)
        return LanguageContentFilter.shared.filterPodcasts(cleanList, for: effectiveLang)
    }
    
    // Unified Search separated by source: Podcast, Culture, Enfant
    func searchAll(term: String, country: String = "us", langCode: String = "en") async throws -> UnifiedSearchResults {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return UnifiedSearchResults(podcasts: [], culture: [], enfants: [])
        }
        
        let isFr = country.lowercased() == "fr" || langCode.lowercased().hasPrefix("fr")
        let cultureQuery = isFr ? "\(trimmed) culture histoire livre audio documentaire" : "\(trimmed) audiobook history culture documentary"
        let enfantsQuery = isFr ? "\(trimmed) enfants jeunesse histoire contes comptines" : "\(trimmed) kids children stories nursery rhymes"
        
        async let generalTask = searchPodcasts(term: trimmed, country: country)
        async let cultureTask = searchPodcasts(term: cultureQuery, country: country)
        async let enfantsTask = searchPodcasts(term: enfantsQuery, country: country)
        
        let (generalResults, rawCultureResults, rawEnfantsResults) = await (
            (try? generalTask) ?? [],
            (try? cultureTask) ?? [],
            (try? enfantsTask) ?? []
        )
        
        let normQuery = normalizeMatchString(trimmed)
        let queryTokens = normQuery.split(separator: " ").map(String.init).filter { $0.count >= 2 }
        
        func matchesUserTerm(_ p: Podcast) -> Bool {
            guard !queryTokens.isEmpty else { return true }
            let haystack = normalizeMatchString("\(p.collectionName) \(p.artistName) \(p.description ?? "") \(p.primaryGenreName ?? "") \(p.source ?? "")")
            if haystack.contains(normQuery) { return true }
            return queryTokens.allSatisfy { haystack.contains($0) }
        }
        
        // Also match against cached/favorite Culture & Enfants catalogs for instant rich results (LibriVox, ARTE, INA, Bayard, Taleming, etc.)
        let cachedSubs = await MainActor.run { LocalStorageManager.shared.cachedSubscriptionsBySection }
        let favCulture = await MainActor.run { LocalStorageManager.shared.favoritesForSubscriptionSection(.culture) }
        let favEnfants = await MainActor.run { LocalStorageManager.shared.favoritesForSubscriptionSection(.enfants) }
        let cachedBooks = await MainActor.run { LocalStorageManager.shared.cachedAudiobooks }
        
        var localCulturePool: [Podcast] = favCulture + cachedBooks
        var localEnfantsPool: [Podcast] = favEnfants
        for (key, list) in cachedSubs {
            if key.hasPrefix(SubscriptionSection.enfants.rawValue) {
                localEnfantsPool.append(contentsOf: list)
            } else {
                localCulturePool.append(contentsOf: list)
            }
        }
        
        var podcastsList: [Podcast] = []
        var cultureList: [Podcast] = []
        var enfantsList: [Podcast] = []
        var seenIds = Set<Int>()
        var seenTitles = Set<String>()
        
        func appendUnique(_ item: Podcast, to bucket: inout [Podcast], defaultSource: String? = nil) {
            let titleKey = item.collectionName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seenIds.contains(item.collectionId), !seenTitles.contains(titleKey) else { return }
            seenIds.insert(item.collectionId)
            seenTitles.insert(titleKey)
            var copy = item
            if (copy.source == nil || copy.source?.isEmpty == true), let src = defaultSource {
                copy.source = src
            }
            bucket.append(copy)
        }
        
        // 1. Local cached/curated Enfants & Culture matches first
        for item in localEnfantsPool where matchesUserTerm(item) {
            appendUnique(item, to: &enfantsList, defaultSource: isFr ? "Enfants" : "Kids")
        }
        for item in localCulturePool where matchesUserTerm(item) && !LocalStorageManager.isKidsOrEnfantsItem(item) {
            appendUnique(item, to: &cultureList, defaultSource: "Culture")
        }
        
        // 2. Classify general search results into Podcasts, Culture, or Enfants
        for item in generalResults {
            if LocalStorageManager.isKidsOrEnfantsItem(item) {
                appendUnique(item, to: &enfantsList, defaultSource: isFr ? "Enfants" : "Kids")
            } else if LocalStorageManager.isCultureItem(item) {
                appendUnique(item, to: &cultureList, defaultSource: "Culture")
            } else {
                appendUnique(item, to: &podcastsList, defaultSource: "Podcast")
            }
        }
        
        // 3. Add targeted Enfants search results
        for item in rawEnfantsResults where !isRadioSourceOrStation(item) {
            if LocalStorageManager.isKidsOrEnfantsItem(item) || matchesUserTerm(item) {
                appendUnique(item, to: &enfantsList, defaultSource: isFr ? "Enfants" : "Kids")
            }
        }
        
        // 4. Add targeted Culture search results
        for item in rawCultureResults where !isRadioSourceOrStation(item) && !LocalStorageManager.isKidsOrEnfantsItem(item) {
            if LocalStorageManager.isCultureItem(item) || matchesUserTerm(item) {
                appendUnique(item, to: &cultureList, defaultSource: "Culture")
            }
        }
        
        // Register section mappings so favoriting from Search routes to the right Favoris section
        let finalCulture = Array(cultureList.prefix(35))
        let finalEnfants = Array(enfantsList.prefix(35))
        let finalPodcasts = Array(podcastsList.prefix(40))
        
        await MainActor.run {
            LocalStorageManager.shared.registerSubscriptionSection(.culture, for: finalCulture)
            LocalStorageManager.shared.registerSubscriptionSection(.enfants, for: finalEnfants)
        }
        
        return UnifiedSearchResults(
            podcasts: finalPodcasts,
            culture: finalCulture,
            enfants: finalEnfants
        )
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
