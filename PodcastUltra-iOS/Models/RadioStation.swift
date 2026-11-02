import Foundation
import SwiftUI
import UIKit

struct RadioStation: Identifiable, Codable {
    let id: String
    let name: String
    let url: String
    let favicon: String?
    let tags: String?
    let country: String?
    let language: String?
    let clickcount: Int?
    var homepage: String? = nil
}

// MARK: - Smart Radio Icon Resolution & Custom Icon Generator
enum RadioIconHelper {
    /// Known radio brands mapped to their official domain for high-res PNG favicon lookup
    private static let brandDomains: [(keyword: String, domain: String)] = [
        ("france inter", "radiofrance.fr"),
        ("france info", "francetvinfo.fr"),
        ("franceinfo", "francetvinfo.fr"),
        ("france culture", "radiofrance.fr"),
        ("france musique", "radiofrance.fr"),
        ("france bleu", "francebleu.fr"),
        ("ici ", "francebleu.fr"),
        ("fip", "radiofrance.fr"),
        ("mouv", "radiofrance.fr"),
        ("rtl2", "rtl2.fr"),
        ("rtl", "rtl.fr"),
        ("fun radio", "funradio.fr"),
        ("europe 1", "europe1.fr"),
        ("europe 2", "europe2.fr"),
        ("virgin radio", "europe2.fr"),
        ("rmc", "rmc.bfmtv.com"),
        ("bfm business", "bfmtv.com"),
        ("bfm", "bfmtv.com"),
        ("nrj", "nrj.fr"),
        ("nostalgie", "nostalgie.fr"),
        ("cherie fm", "cheriefm.fr"),
        ("chérie fm", "cheriefm.fr"),
        ("rire et chansons", "rireetchansons.fr"),
        ("rire & chansons", "rireetchansons.fr"),
        ("skyrock", "skyrock.fm"),
        ("rfm", "rfm.fr"),
        ("radio classique", "radioclassique.fr"),
        ("radio nova", "nova.fr"),
        ("nova", "nova.fr"),
        ("tsf jazz", "tsfjazz.com"),
        ("sud radio", "sudradio.fr"),
        ("oui fm", "ouifm.fr"),
        ("ouï fm", "ouifm.fr"),
        ("radio fg", "radiofg.com"),
        ("fg.", "radiofg.com"),
        ("jazz radio", "jazzradio.fr"),
        ("m radio", "mradio.fr"),
        ("latina", "latina.fr"),
        ("alouette", "alouette.fr"),
        ("hit west", "hitwest.com"),
        ("vibration", "vibration.fr"),
        ("contact fm", "mycontact.fr"),
        ("radio scoop", "radioscoop.com"),
        ("wit fm", "witfm.fr"),
        ("chante france", "chantefrance.com"),
        ("tropiques fm", "tropiquesfm.com"),
        ("beur fm", "beurfm.net"),
        ("radio orient", "radioorient.com"),
        ("rcf", "rcf.fr"),
        ("generations", "generations.fr"),
        ("générations", "generations.fr"),
        ("ado fm", "adofm.fr"),
        ("voltage", "voltage.fr"),
        ("top music", "topmusic.fr"),
        ("mona fm", "monafm.fr"),
        ("bel rtl", "rtl.be"),
        ("radio contact", "radiocontact.be"),
        ("rtbf", "rtbf.be"),
        ("classic 21", "rtbf.be"),
        ("vivacite", "rtbf.be"),
        ("vivacité", "rtbf.be"),
        ("la première", "rtbf.be"),
        ("tipik", "rtbf.be"),
        ("rts", "rts.ch"),
        ("couleur 3", "rts.ch"),
        ("radio canada", "ici.radio-canada.ca"),
        ("bbc", "bbc.co.uk"),
        ("npr", "npr.org"),
        ("cnn", "cnn.com"),
        ("lbc", "lbc.co.uk"),
        ("classic fm", "classicfm.com"),
        ("capital fm", "capitalfm.com"),
        ("heart", "heart.co.uk"),
        ("kiss fm", "planetradio.co.uk"),
        ("kexp", "kexp.org"),
        ("wnyc", "wnyc.org"),
        ("cadena ser", "cadenaser.com"),
        ("cope", "cope.es"),
        ("rne", "rtve.es"),
        ("rai", "raiplaysound.it"),
        ("deutschlandfunk", "deutschlandfunk.de"),
        ("wdr", "wdr.de"),
        ("swr", "swr.de")
    ]
    
    static func isUsableImageUrl(_ raw: String?) -> Bool {
        guard let str = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty,
              let url = URL(string: str),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return false
        }
        let lower = str.lowercased()
        // UIImage cannot decode SVG URLs (including old dicebear SVG fallbacks)
        if lower.contains("dicebear.com") && lower.contains("/svg") { return false }
        if lower.hasSuffix(".svg") || lower.contains(".svg?") { return false }
        return true
    }
    
    static func googleFaviconUrl(forDomain domain: String) -> String {
        return "https://www.google.com/s2/favicons?sz=256&domain_url=https://\(domain)"
    }
    
    static func extractDomain(from urlString: String?) -> String? {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              let host = url.host,
              host.contains(".") else {
            return nil
        }
        return host
    }
    
    static func matchedDomain(forStationName name: String, homepage: String? = nil) -> String? {
        let lower = name.lowercased()
        for entry in brandDomains {
            if lower.contains(entry.keyword) {
                return entry.domain
            }
        }
        if let homeDomain = extractDomain(from: homepage) {
            return homeDomain
        }
        return nil
    }
    
    /// Ordered list of candidate PNG/JPG icon URLs to try for a station
    static func candidateIconURLs(for station: RadioStation) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        
        func appendUrl(_ str: String?) {
            guard isUsableImageUrl(str),
                  let clean = str?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !seen.contains(clean),
                  let u = URL(string: clean) else { return }
            seen.insert(clean)
            urls.append(u)
        }
        
        // 1. Original station favicon if valid PNG/JPG/ICO
        appendUrl(station.favicon)
        
        // 2. High-res Google Favicon from matched brand or homepage domain
        if let domain = matchedDomain(forStationName: station.name, homepage: station.homepage) {
            appendUrl(googleFaviconUrl(forDomain: domain))
        }
        
        // 3. Domain extracted from the favicon URL itself (in case the specific path is 404 but the domain has a favicon)
        if let favDomain = extractDomain(from: station.favicon) {
            appendUrl(googleFaviconUrl(forDomain: favDomain))
        }
        
        return urls
    }
    
    /// Preferred single icon URL string for storing in RadioStation.favicon
    static func resolvedFaviconString(name: String, rawFavicon: String?, homepage: String?) -> String? {
        if isUsableImageUrl(rawFavicon) {
            return rawFavicon?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let domain = matchedDomain(forStationName: name, homepage: homepage) {
            return googleFaviconUrl(forDomain: domain)
        }
        return nil
    }
    
    /// Short monogram (2-4 chars) for custom-generated station icon
    static func stationMonogram(for name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
            .components(separatedBy: " - ").first ?? name
        
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "FM" }
        
        let upper = trimmed.uppercased()
        // Known short acronyms (RTL, RMC, NRJ, FIP, BFM, RFM, BBC, NPR, RTS, RCF)
        let words = trimmed
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        if let first = words.first, first.count >= 2 && first.count <= 4 && first == first.uppercased() {
            return first
        }
        if words.count == 1 {
            let w = words[0].uppercased()
            return String(w.prefix(min(3, w.count)))
        }
        // Check if second word is a number (e.g. "Europe 1" -> "E1", "RTL 2" -> "RTL2")
        if words.count >= 2, let num = Int(words[1]), num < 100 {
            let p1 = words[0].count <= 3 ? words[0].uppercased() : String(words[0].prefix(1)).uppercased()
            return "\(p1)\(num)"
        }
        // Take initials of the first 2-3 significant words
        let stopWords: Set<String> = ["LA", "LE", "LES", "DE", "DU", "DES", "THE", "OF", "AND", "ET"]
        let significant = words.map { $0.uppercased() }.filter { !stopWords.contains($0) }
        let source = significant.isEmpty ? words.map { $0.uppercased() } : significant
        if source.count >= 2 {
            let firstInitial = String(source[0].prefix(1))
            let secondInitial = String(source[1].prefix(1))
            if source.count >= 3 && source[0] == "RADIO" {
                return String(source[1].prefix(1)) + String(source[2].prefix(1))
            }
            if source[0] == "RADIO" && source[1].count <= 4 {
                return source[1]
            }
            return firstInitial + secondInitial
        }
        return String(upper.prefix(3))
    }
    
    /// Deterministic vibrant color pair for a station name
    static func palette(for name: String) -> (Color, Color) {
        let palettes: [(Color, Color)] = [
            (Color(red: 99/255, green: 102/255, blue: 241/255), Color(red: 168/255, green: 85/255, blue: 247/255)),  // Indigo -> Purple
            (Color(red: 239/255, green: 68/255, blue: 68/255), Color(red: 249/255, green: 115/255, blue: 22/255)),   // Crimson -> Orange
            (Color(red: 16/255, green: 185/255, blue: 129/255), Color(red: 6/255, green: 182/255, blue: 212/255)),   // Emerald -> Cyan
            (Color(red: 37/255, green: 99/255, blue: 235/255), Color(red: 56/255, green: 189/255, blue: 248/255)),   // Royal Blue -> Sky
            (Color(red: 236/255, green: 72/255, blue: 153/255), Color(red: 244/255, green: 63/255, blue: 94/255)),   // Pink -> Rose
            (Color(red: 245/255, green: 158/255, blue: 11/255), Color(red: 234/255, green: 88/255, blue: 12/255)),   // Amber -> Deep Orange
            (Color(red: 139/255, green: 92/255, blue: 246/255), Color(red: 236/255, green: 72/255, blue: 153/255)),  // Violet -> Magenta
            (Color(red: 20/255, green: 184/255, blue: 166/255), Color(red: 59/255, green: 130/255, blue: 246/255))   // Teal -> Blue
        ]
        let hash = abs(name.lowercased().unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) })
        return palettes[hash % palettes.count]
    }
}

// MARK: - Reusable Radio Station Icon View (Multi-URL Fallback + Custom Generated Badge)
struct RadioStationArtworkView: View {
    let station: RadioStation
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 10
    
    @State private var loadedImage: UIImage? = nil
    @State private var didStartLoading = false
    
    init(station: RadioStation, size: CGFloat = 44, cornerRadius: CGFloat = 10) {
        self.station = station
        self.size = size
        self.cornerRadius = cornerRadius
        
        let candidates = RadioIconHelper.candidateIconURLs(for: station)
        for url in candidates {
            if let memImg = DecodedImageMemoryCache.shared.image(for: url) {
                _loadedImage = State(initialValue: memImg)
                _didStartLoading = State(initialValue: true)
                return
            }
        }
    }
    
    var body: some View {
        ZStack {
            if let img = loadedImage {
                Color.white
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.1)
            } else {
                GeneratedRadioBadgeView(stationName: station.name, size: size)
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(cornerRadius)
        .clipped()
        .onAppear {
            if loadedImage == nil && !didStartLoading {
                didStartLoading = true
                loadFirstAvailableIcon()
            }
        }
    }
    
    private func loadFirstAvailableIcon() {
        let candidates = RadioIconHelper.candidateIconURLs(for: station)
        guard !candidates.isEmpty else { return }
        let maxPx = max(120, size * 2.5)
        
        Task.detached(priority: .utility) {
            for url in candidates {
                if let cached = DecodedImageMemoryCache.shared.image(for: url) {
                    await MainActor.run {
                        self.loadedImage = cached
                    }
                    return
                }
                
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                request.timeoutInterval = 6
                
                if let cachedResp = URLCache.shared.cachedResponse(for: request),
                   let img = Self.decodeValidIcon(from: cachedResp.data, maxPx: maxPx) {
                    DecodedImageMemoryCache.shared.insert(img, for: url)
                    await MainActor.run {
                        self.loadedImage = img
                    }
                    return
                }
                
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   let http = response as? HTTPURLResponse,
                   (200...299).contains(http.statusCode),
                   let img = Self.decodeValidIcon(from: data, maxPx: maxPx) {
                    let cachedData = CachedURLResponse(response: response, data: data)
                    URLCache.shared.storeCachedResponse(cachedData, for: request)
                    DecodedImageMemoryCache.shared.insert(img, for: url)
                    await MainActor.run {
                        self.loadedImage = img
                    }
                    return
                }
            }
        }
    }
    
    nonisolated private static func decodeValidIcon(from data: Data, maxPx: CGFloat) -> UIImage? {
        guard data.count > 64, let raw = UIImage(data: data) else { return nil }
        // Ignore tiny 1x1 tracking pixels
        guard raw.size.width >= 12 && raw.size.height >= 12 else { return nil }
        let scale = max(raw.size.width, raw.size.height)
        if scale > maxPx {
            let ratio = maxPx / scale
            let target = CGSize(width: max(1, raw.size.width * ratio), height: max(1, raw.size.height * ratio))
            if let thumb = raw.preparingThumbnail(of: target) {
                return thumb
            }
        }
        return raw.preparingForDisplay() ?? raw
    }
}

struct GeneratedRadioBadgeView: View {
    let stationName: String
    let size: CGFloat
    
    var body: some View {
        let (c1, c2) = RadioIconHelper.palette(for: stationName)
        let monogram = RadioIconHelper.stationMonogram(for: stationName)
        
        ZStack {
            LinearGradient(
                colors: [c1, c2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Decorative concentric radio wave rings
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: max(1, size * 0.025))
                .frame(width: size * 0.86, height: size * 0.86)
            
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: max(1, size * 0.02))
                .frame(width: size * 0.64, height: size * 0.64)
            
            VStack(spacing: size * 0.02) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: max(8, size * 0.2), weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                
                Text(monogram)
                    .font(.system(size: max(10, size * (monogram.count >= 4 ? 0.24 : 0.3)), weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            }
        }
    }
}
