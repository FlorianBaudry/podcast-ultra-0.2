import Foundation

/// Filtre global pour écarter les flux, titres et contenus contenant du vocabulaire familier ou vulgaire.
struct ProfanityFilter {
    static let shared = ProfanityFilter()
    
    // Liste de racines et mots vulgaires / familiers (français et anglais)
    private let blocklist: Set<String> = [
        // Français
        "couille", "couilles", "couillonnade",
        "bite", "bites",
        "chatte", "chattes",
        "salope", "salopes", "salop", "salops",
        "pute", "putes", "putain", "taspé",
        "connard", "connards", "conasse", "connasse", "conasses", "connasses",
        "encule", "enculee", "enculer", "encules", "enculerie",
        "nique", "niquer", "niquez", "niquant",
        "foutre", "foutaise",
        "chier", "chieur", "chieuse", "chiasse",
        "merde", "merdeux", "merdique",
        "bordel",
        "trouduc", "trou du cul",
        "nichon", "nichons",
        "burnes",
        "branler", "branleur", "branlette",
        "porno", "pornographie", "sexe explicit", "hardcore",
        
        // Anglais
        "fuck", "fucking", "fucked", "fucker",
        "shit", "shitty", "bullshit",
        "bitch", "bitches",
        "cunt", "cunts",
        "dick", "dicks", "dickhead",
        "cock", "cocks",
        "asshole", "assholes", "bastard", "bastards",
        "pussy", "pussies",
        "wanker", "motherfucker"
    ]
    
    /// Normalise une chaîne (minuscules, sans accents, sans ponctuation excessive)
    private func normalize(_ string: String) -> String {
        string
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
    
    /// Détecte si un texte contient un terme inapproprié
    func isClean(_ text: String?) -> Bool {
        guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        
        let normalized = normalize(text)
        
        // Découpage en mots pour vérification exacte
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        for word in words {
            if blocklist.contains(word) {
                return false
            }
        }
        
        // Vérification par sous-chaînes critiques (pour expressions composées ou pluriels)
        for term in blocklist {
            if normalized.contains(term) {
                // S'assurer que ce n'est pas un faux positif sur un mot valide (ex: habituer contenant bite -> vérification de limites)
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(location: 0, length: normalized.utf16.count)
                    if regex.firstMatch(in: normalized, options: [], range: range) != nil {
                        return false
                    }
                }
            }
        }
        
        return true
    }
    
    /// Filtre une liste de podcasts pour ne conserver que les flux convenables
    func filterCleanPodcasts(_ podcasts: [Podcast]) -> [Podcast] {
        podcasts.filter { podcast in
            isClean(podcast.collectionName) &&
            isClean(podcast.artistName) &&
            isClean(podcast.description) &&
            isClean(podcast.feedUrl)
        }
    }
    
    /// Filtre une liste d'épisodes
    func filterCleanEpisodes(_ episodes: [Episode]) -> [Episode] {
        episodes.filter { ep in
            isClean(ep.trackName) &&
            isClean(ep.collectionName) &&
            isClean(ep.artistName) &&
            isClean(ep.description)
        }
    }
}

