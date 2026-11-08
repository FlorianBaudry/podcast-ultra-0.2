import Foundation
import NaturalLanguage

enum LangCode: String, Codable, CaseIterable, Identifiable {
    case en, zh, hi, es, fr, ar, bn, pt, ru, ur, id, de, ja, sw, mr, te, tr, ko, vi, it
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .en: return "English"
        case .zh: return "中文 (Mandarin)"
        case .hi: return "हिन्दी (Hindi)"
        case .es: return "Español"
        case .fr: return "Français"
        case .ar: return "العربية (Arabic)"
        case .bn: return "বাংলা (Bengali)"
        case .pt: return "Português"
        case .ru: return "Русский (Russian)"
        case .ur: return "اردو (Urdu)"
        case .id: return "Bahasa Indonesia"
        case .de: return "Deutsch"
        case .ja: return "日本語 (Japanese)"
        case .sw: return "Kiswahili (Swahili)"
        case .mr: return "मराठी (Marathi)"
        case .te: return "తెలుగు (Telugu)"
        case .tr: return "Türkçe"
        case .ko: return "한국어 (Korean)"
        case .vi: return "Tiếng Việt"
        case .it: return "Italiano"
        }
    }
    
    var itunes: String {
        switch self {
        case .en: return "us"
        case .zh: return "cn"
        case .hi: return "in"
        case .es: return "es"
        case .fr: return "fr"
        case .ar: return "sa"
        case .bn: return "in"
        case .pt: return "pt"
        case .ru: return "ru"
        case .ur: return "pk"
        case .id: return "id"
        case .de: return "de"
        case .ja: return "jp"
        case .sw: return "ke"
        case .mr: return "in"
        case .te: return "in"
        case .tr: return "tr"
        case .ko: return "kr"
        case .vi: return "vn"
        case .it: return "it"
        }
    }
    
    var radioSearch: String {
        switch self {
        case .en: return "english"
        case .zh: return "chinese"
        case .hi: return "hindi"
        case .es: return "spanish"
        case .fr: return "french"
        case .ar: return "arabic"
        case .bn: return "bengali"
        case .pt: return "portuguese"
        case .ru: return "russian"
        case .ur: return "urdu"
        case .id: return "indonesian"
        case .de: return "german"
        case .ja: return "japanese"
        case .sw: return "swahili"
        case .mr: return "marathi"
        case .te: return "telugu"
        case .tr: return "turkish"
        case .ko: return "korean"
        case .vi: return "vietnamese"
        case .it: return "italian"
        }
    }
    
    var nlLanguage: NLLanguage {
        switch self {
        case .en: return .english
        case .zh: return .simplifiedChinese
        case .hi: return .hindi
        case .es: return .spanish
        case .fr: return .french
        case .ar: return .arabic
        case .bn: return .bengali
        case .pt: return .portuguese
        case .ru: return .russian
        case .ur: return .urdu
        case .id: return .indonesian
        case .de: return .german
        case .ja: return .japanese
        case .sw: return NLLanguage(rawValue: "sw")
        case .mr: return .marathi
        case .te: return .telugu
        case .tr: return .turkish
        case .ko: return .korean
        case .vi: return .vietnamese
        case .it: return .italian
        }
    }
    
    static func fromItunesCountry(_ country: String) -> LangCode {
        let lower = country.lowercased()
        switch lower {
        case "fr", "be", "ch", "ca": return .fr
        case "us", "gb", "uk", "au", "nz", "ie": return .en
        case "cn", "tw", "hk", "sg": return .zh
        case "es", "mx", "ar", "co", "cl", "pe": return .es
        case "sa", "ae", "eg", "ma", "dz", "tn", "qa", "kw": return .ar
        case "bd": return .bn
        case "pt", "br": return .pt
        case "ru", "by", "kz": return .ru
        case "pk": return .ur
        case "id": return .id
        case "de", "at": return .de
        case "jp": return .ja
        case "ke", "tz": return .sw
        case "tr": return .tr
        case "kr": return .ko
        case "vn": return .vi
        case "it": return .it
        default:
            return LangCode.allCases.first(where: { $0.itunes == lower }) ?? .en
        }
    }
}

/// Détecteur et filtre linguistique intelligent pour éviter l'affichage de contenus étrangers (ex: russes, anglais, chinois...) quand une langue précise (ex: Français) est sélectionnée.
final class LanguageContentFilter: @unchecked Sendable {
    static let shared = LanguageContentFilter()
    
    private let cacheLock = NSLock()
    private var matchCache: [String: Bool] = [:]
    
    private static let cyrillicScalarRange = (0x0400...0x04FF)
    private static let arabicScalarRange = (0x0600...0x06FF)
    private static let devanagariScalarRange = (0x0900...0x097F)
    private static let bengaliScalarRange = (0x0980...0x09FF)
    private static let teluguScalarRange = (0x0C00...0x0C7F)
    private static let cjkScalarRange = (0x4E00...0x9FFF)
    private static let hiraganaKatakanaRange = (0x3040...0x30FF)
    private static let hangulScalarRange = (0xAC00...0xD7AF)
    
    /// Vérifie si le texte utilise un alphabet incompatible avec la langue sélectionnée (ex: cyrillique russe, arabe, CJK quand on est en français)
    func hasIncompatibleScript(text: String, targetLang: LangCode) -> Bool {
        var cyrillicCount = 0
        var arabicCount = 0
        var devanagariCount = 0
        var bengaliCount = 0
        var teluguCount = 0
        var cjkCount = 0
        var japaneseKanaCount = 0
        var hangulCount = 0
        
        for scalar in text.unicodeScalars {
            let v = Int(scalar.value)
            if Self.cyrillicScalarRange.contains(v) { cyrillicCount += 1 }
            else if Self.arabicScalarRange.contains(v) { arabicCount += 1 }
            else if Self.devanagariScalarRange.contains(v) { devanagariCount += 1 }
            else if Self.bengaliScalarRange.contains(v) { bengaliCount += 1 }
            else if Self.teluguScalarRange.contains(v) { teluguCount += 1 }
            else if Self.cjkScalarRange.contains(v) { cjkCount += 1 }
            else if Self.hiraganaKatakanaRange.contains(v) { japaneseKanaCount += 1 }
            else if Self.hangulScalarRange.contains(v) { hangulCount += 1 }
        }
        
        switch targetLang {
        case .ru:
            return arabicCount > 2 || devanagariCount > 2 || cjkCount > 2 || hangulCount > 2
        case .ar, .ur:
            return cyrillicCount > 2 || devanagariCount > 2 || cjkCount > 2 || hangulCount > 2
        case .hi, .mr:
            return cyrillicCount > 2 || arabicCount > 2 || cjkCount > 2 || hangulCount > 2
        case .bn:
            return cyrillicCount > 2 || arabicCount > 2 || cjkCount > 2 || hangulCount > 2
        case .te:
            return cyrillicCount > 2 || arabicCount > 2 || cjkCount > 2 || hangulCount > 2
        case .zh:
            return cyrillicCount > 2 || arabicCount > 2 || devanagariCount > 2 || hangulCount > 2
        case .ja:
            return cyrillicCount > 2 || arabicCount > 2 || devanagariCount > 2 || hangulCount > 2
        case .ko:
            return cyrillicCount > 2 || arabicCount > 2 || devanagariCount > 2
        default:
            // Langues à alphabet latin (.fr, .en, .es, .pt, .de, .it, .tr, .vi, .id, .sw)
            if cyrillicCount >= 2 || arabicCount >= 2 || devanagariCount >= 2 ||
               bengaliCount >= 2 || teluguCount >= 2 || cjkCount >= 2 ||
               japaneseKanaCount >= 2 || hangulCount >= 2 {
                return true
            }
            return false
        }
    }
    
    /// Détecte si un podcast correspond bien à la langue sélectionnée par l'utilisateur (résultat mis en cache en mémoire pour 0 latence UI)
    func matchesLanguage(_ podcast: Podcast, targetLang: LangCode) -> Bool {
        let cacheKey = "\(podcast.collectionId)|\(targetLang.rawValue)"
        cacheLock.lock()
        if let cached = matchCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        let result = computeMatchesLanguage(podcast, targetLang: targetLang)
        
        cacheLock.lock()
        matchCache[cacheKey] = result
        cacheLock.unlock()
        return result
    }
    
    private func computeMatchesLanguage(_ podcast: Podcast, targetLang: LangCode) -> Bool {
        let title = podcast.collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = (podcast.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = podcast.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = "\(title) \(artist) \(desc)"
        
        // 1. Rejet immédiat des alphabets étrangers incompatibles (ex: Russe cyrillique, Arabe, Chinois, etc. quand on est en Français)
        if hasIncompatibleScript(text: combined, targetLang: targetLang) {
            return false
        }
        
        // 2. Pour le Français : filtrage strict contre les podcasts en anglais, espagnol, allemand, russe translittéré, etc.
        if targetLang == .fr {
            let lowerTitle = title.lowercased()
            let lowerDesc = desc.lowercased()
            let lowerArtist = artist.lowercased()
            let fullLower = "\(lowerTitle) \(lowerArtist) \(lowerDesc)"
            
            // Sources françaises de confiance
            let trustedFrenchMarkers = [
                "france inter", "france culture", "france info", "radio france", "arte ", "arte radio",
                "ina ", "collège de france", "cnrs", "binge audio", "louie media", "nouvelles écoutes",
                "slate.fr", "slate podcasts", "littérature audio", "bayard", "quelle histoire",
                "l'école des loisirs", "albin michel", "choses à savoir", "futura", "les échos",
                "le monde", "rtl", "europe 1", "rmc", "loyal books", "gutenberg"
            ]
            if trustedFrenchMarkers.contains(where: { fullLower.contains($0) }) && !hasEnglishOnlyMarkers(lowerTitle, lowerDesc) {
                return true
            }
            
            // Rejet des marqueurs typiquement anglais dans les titres/descriptions
            if hasEnglishOnlyMarkers(lowerTitle, lowerDesc) {
                return false
            }
            
            // Analyse NLLanguageRecognizer sur le titre + description
            let sample = desc.count >= 25 ? "\(title). \(desc)" : title
            if sample.count >= 12 {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(sample)
                let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
                if let dominant = recognizer.dominantLanguage {
                    if dominant == .french {
                        return true
                    }
                    let frScore = hypotheses[.french] ?? 0.0
                    let domScore = hypotheses[dominant] ?? 0.0
                    // Si une autre langue (ex: anglais, russe, espagnol, allemand...) domine nettement et que le français est quasi absent
                    if dominant != .undetermined && domScore > 0.58 && frScore < 0.18 {
                        // Vérifier s'il y a quand même des mots/accents français explicites
                        if !containsExplicitFrenchSignals(fullLower) {
                            return false
                        }
                    }
                }
            }
            
            return true
        }
        
        // 3. Pour les autres langues : vérification via NLLanguageRecognizer quand suffisamment de texte est présent
        let sample = desc.count >= 30 ? "\(title). \(desc)" : title
        if sample.count >= 18 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(sample)
            if let dominant = recognizer.dominantLanguage, dominant != .undetermined {
                let targetNL = targetLang.nlLanguage
                if dominant == targetNL {
                    return true
                }
                if targetLang == .zh && (dominant == .simplifiedChinese || dominant == .traditionalChinese) {
                    return true
                }
                let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
                let targetScore = hypotheses[targetNL] ?? 0.0
                let domScore = hypotheses[dominant] ?? 0.0
                // Si le contenu est clairement dans une autre langue (score > 0.72) et pas dans la langue cible
                if domScore > 0.72 && targetScore < 0.12 {
                    return false
                }
            }
        }
        
        return true
    }
    
    private func hasEnglishOnlyMarkers(_ lowerTitle: String, _ lowerDesc: String) -> Bool {
        let englishTitlePhrases = [
            " the ", "the ", " with ", " for kids", "bedtime stories", "sleep tight",
            "podcast for ", "daily news", "true crime ", "stories podcast", "history of ",
            "how to ", "unabridged", "audiobook", "read by ", "narrated by ", "hosted by ",
            "full audiobook", "fairy tales", "nursery rhymes", "science podcast", "curious universe",
            "small steps, giant leaps", "we have a podcast", "hardcore history", "no such thing as"
        ]
        for marker in englishTitlePhrases {
            if lowerTitle.contains(marker) && !containsExplicitFrenchSignals(lowerTitle) {
                return true
            }
        }
        
        let paddedDesc = " \(lowerDesc) "
        let englishStopWords = [" the ", " and ", " with ", " from ", " this ", " that ", " your ", " about ", " episodes ", " listen ", " every week "]
        var engHits = 0
        for w in englishStopWords {
            if paddedDesc.contains(w) { engHits += 1 }
        }
        if engHits >= 3 && !containsExplicitFrenchSignals(lowerDesc) {
            return true
        }
        return false
    }
    
    private func containsExplicitFrenchSignals(_ lowerText: String) -> Bool {
        let frenchSignals = [
            " le ", " la ", " les ", " des ", " une ", " dans ", " pour ", " avec ", " sur ",
            " par ", " cette ", " sont ", " histoire", " épisode", " écoute", " découvrir",
            " aujourd'hui", " français", " livre audio", " chaque ", " au cœur", " émission"
        ]
        var hits = 0
        let padded = " \(lowerText) "
        for sig in frenchSignals {
            if padded.contains(sig) { hits += 1 }
        }
        let hasFrenchAccents = lowerText.contains("é") || lowerText.contains("è") || lowerText.contains("ê") || lowerText.contains("à") || lowerText.contains("ù") || lowerText.contains("œ") || lowerText.contains("ç")
        return hits >= 2 || (hits >= 1 && hasFrenchAccents)
    }
    
    func filterPodcasts(_ podcasts: [Podcast], for targetLang: LangCode) -> [Podcast] {
        let filtered = podcasts.filter { matchesLanguage($0, targetLang: targetLang) }
        // Si le filtre garde au moins quelques résultats, on les renvoie ; sinon on évite un écran vide tout en écartant les alphabets incompatibles
        if !filtered.isEmpty {
            return filtered
        }
        return podcasts.filter { !hasIncompatibleScript(text: "\($0.collectionName) \($0.artistName) \($0.description ?? "")", targetLang: targetLang) }
    }
}

class Translations {
    static let shared = Translations()
    
    private let data: [LangCode: [String: String]] = [
        .en: [
            "discover": "Podcasts",
            "episodes_feed": "Favorites",
            "subscriptions_btn": "Podcasts",
            "radio": "Radio",
            "audiobooks": "Discover",
            "recent": "History",
            "playlists": "Playlists",
            "library": "Library",
            "player": "Player",
            "search_placeholder": "Search podcasts, radio, books...",
            "recommended": "Popular",
            "see_all": "See All",
            "latest_from_favs": "Latest from Favorites",
            "episodes": "Episodes",
            "latest": "Latest",
            "subscribe": "Subscribe",
            "subscribed": "Subscribed",
            "ai_summary": "AI Summary",
            "add_to_playlist": "Add to Playlist",
            "play_next": "Play Next",
            "add_to_queue": "Add to Queue",
            "my_playlists": "My Playlists",
            "new_playlist": "New Playlist",
            "login": "Login",
            "login_google": "Continue with Google",
            "login_apple": "Continue with Apple",
            "logout": "Logout",
            "welcome": "Welcome back",
            "world_radio": "World Radio",
            "language": "Language",
            "settings": "Settings",
            "playback_speed": "Playback Speed",
            "skip_intro": "Skip Intro (30s)",
            "accent_color": "Accent Color",
            "appearance": "Appearance",
            "theme": "Theme",
            "theme_light": "Light",
            "theme_dark": "Dark",
            "theme_black": "OLED Black",
            "clear_cache": "Clear Data",
            "your_favorites": "Your Favorites",
            "results": "Results",
            "download": "Download",
            "downloading": "Downloading...",
            "remove_download": "Remove offline file",
            "offline": "Offline",
            "import_spotify": "Import from Spotify",
            "spotify_desc": "Import your followed podcasts from Spotify to your library.",
            "spotify_connect": "Connect Spotify",
            "spotify_syncing": "Syncing your podcasts...",
            "spotify_success": "podcasts successfully imported!",
            "filter_all": "All",
            "filter_unplayed": "Unplayed",
            "filter_downloaded": "Downloaded",
            "now_playing": "Now Playing",
            "up_next": "Up Next",
            "mark_played": "Mark as Played",
            "mark_unplayed": "Mark as Unplayed",
            "hide": "Hide"
        ],
        .fr: [
            "discover": "Podcasts",
            "episodes_feed": "Favoris",
            "subscriptions_btn": "Podcasts",
            "radio": "Radio",
            "audiobooks": "Découvrir",
            "recent": "Historique",
            "playlists": "Listes",
            "library": "Historique",
            "player": "Lecture",
            "search_placeholder": "Podcasts, radio, livres...",
            "recommended": "Populaires",
            "see_all": "Tout voir",
            "latest_from_favs": "Derniers favoris",
            "episodes": "Épisodes",
            "latest": "Dernier",
            "subscribe": "S'abonner",
            "subscribed": "Abonné",
            "ai_summary": "Résumé IA",
            "add_to_playlist": "Ajouter à la liste",
            "play_next": "Lire ensuite",
            "add_to_queue": "Ajouter à la file",
            "my_playlists": "Mes Listes",
            "new_playlist": "Nouvelle Liste",
            "login": "Connexion",
            "login_google": "Continuer avec Google",
            "login_apple": "Continuer avec Apple",
            "logout": "Déconnexion",
            "welcome": "Bon retour",
            "world_radio": "Radio Mondiale",
            "language": "Langue",
            "settings": "Paramètres",
            "playback_speed": "Vitesse de lecture",
            "skip_intro": "Passer l'intro (30s)",
            "accent_color": "Couleur d'accentuation",
            "appearance": "Apparence",
            "theme": "Thème",
            "theme_light": "Clair",
            "theme_dark": "Sombre",
            "theme_black": "Noir OLED",
            "clear_cache": "Effacer les données",
            "your_favorites": "Vos Favoris",
            "results": "Résultats",
            "download": "Télécharger",
            "downloading": "Téléchargement...",
            "remove_download": "Supprimer le fichier",
            "offline": "Hors-ligne",
            "import_spotify": "Importer de Spotify",
            "spotify_desc": "Importez vos podcasts suivis de Spotify vers votre bibliothèque.",
            "spotify_connect": "Connecter Spotify",
            "spotify_syncing": "Synchronisation en cours...",
            "spotify_success": "podcasts importés avec succès !",
            "filter_all": "Tout",
            "filter_unplayed": "Non lu",
            "filter_downloaded": "Téléchargé",
            "now_playing": "En lecture",
            "up_next": "À suivre",
            "mark_played": "Marquer comme lu",
            "mark_unplayed": "Marquer comme non lu",
            "hide": "Masquer"
        ],
        .es: [
            "discover": "Podcasts",
            "episodes_feed": "Favoritos",
            "subscriptions_btn": "Podcasts",
            "radio": "Radio",
            "audiobooks": "Descubrir",
            "recent": "Historial",
            "playlists": "Listas",
            "library": "Biblioteca",
            "player": "Reproductor",
            "search_placeholder": "Buscar podcasts o radio...",
            "recommended": "Populares",
            "see_all": "Ver todo",
            "latest_from_favs": "Últimos favoritos",
            "episodes": "Episodios",
            "latest": "Último",
            "subscribe": "Suscribirse",
            "subscribed": "Suscrito",
            "ai_summary": "Resumen IA",
            "add_to_playlist": "Añadir a lista",
            "play_next": "Reproducir siguiente",
            "add_to_queue": "Añadir a la cola",
            "my_playlists": "Mis Listas",
            "new_playlist": "Nueva Lista",
            "login": "Iniciar sesión",
            "login_google": "Continuar con Google",
            "login_apple": "Continuar con Apple",
            "logout": "Cerrar sesión",
            "welcome": "Bienvenido de nuevo",
            "world_radio": "Radio Mundial",
            "language": "Idioma",
            "settings": "Ajustes",
            "playback_speed": "Velocidad de reproducción",
            "skip_intro": "Saltar intro (30s)",
            "accent_color": "Color de énfasis",
            "appearance": "Apariencia",
            "theme": "Tema",
            "theme_light": "Claro",
            "theme_dark": "Oscuro",
            "theme_black": "Negro OLED",
            "clear_cache": "Limpiar datos",
            "your_favorites": "Tus Favoritos",
            "results": "Resultados",
            "download": "Descargar",
            "downloading": "Descargando...",
            "remove_download": "Eliminar archivo",
            "offline": "Desconectado",
            "import_spotify": "Importar de Spotify",
            "spotify_desc": "Importa tus podcasts seguidos de Spotify a tu biblioteca.",
            "spotify_connect": "Conectar Spotify",
            "spotify_syncing": "Sincronizando...",
            "spotify_success": "podcasts importados con éxito!",
            "filter_all": "Todos",
            "filter_unplayed": "No reproducido",
            "filter_downloaded": "Descargado",
            "now_playing": "Reproduciendo",
            "up_next": "A continuación",
            "mark_played": "Marcar como reproducido",
            "mark_unplayed": "Marcar como no reproducido",
            "hide": "Ocultar"
        ],
        .de: [
            "discover": "Podcasts",
            "episodes_feed": "Favoriten",
            "subscriptions_btn": "Podcasts",
            "radio": "Radio",
            "audiobooks": "Entdecken",
            "recent": "Verlauf",
            "playlists": "Playlists",
            "library": "Bibliothek",
            "player": "Player",
            "search_placeholder": "Podcasts oder Radio suchen...",
            "recommended": "Beliebt",
            "see_all": "Alle ansehen",
            "latest_from_favs": "Neueste von Favoriten",
            "episodes": "Folgen",
            "latest": "Neueste",
            "subscribe": "Abonnieren",
            "subscribed": "Abonniert",
            "ai_summary": "KI-Zusammenfassung",
            "add_to_playlist": "Zur Playlist hinzufügen",
            "play_next": "Als nächstes abspielen",
            "add_to_queue": "In die Warteschlange",
            "my_playlists": "Meine Playlists",
            "new_playlist": "Neue Playlist",
            "login": "Anmelden",
            "login_google": "Weiter mit Google",
            "login_apple": "Weiter mit Apple",
            "logout": "Abmelden",
            "welcome": "Willkommen zurück",
            "world_radio": "Weltradio",
            "language": "Sprache",
            "settings": "Einstellungen",
            "playback_speed": "Wiedergabegeschwindigkeit",
            "skip_intro": "Intro überspringen (30s)",
            "accent_color": "Akzentfarbe",
            "appearance": "Aussehen",
            "theme": "Thema",
            "theme_light": "Hell",
            "theme_dark": "Dunkel",
            "theme_black": "OLED Schwarz",
            "clear_cache": "Daten löschen",
            "your_favorites": "Deine Favoriten",
            "results": "Ergebnisse",
            "download": "Herunterladen",
            "downloading": "Herunterladen...",
            "remove_download": "Heruntergeladene Datei entfernen",
            "offline": "Offline",
            "import_spotify": "Von Spotify importieren",
            "spotify_desc": "Importiere deine gefolgten Podcasts von Spotify in deine Bibliothek.",
            "spotify_connect": "Spotify verbinden",
            "spotify_syncing": "Synchronisierung...",
            "spotify_success": "Podcasts erfolgreich importiert!",
            "filter_all": "Alle",
            "filter_unplayed": "Ungespielt",
            "filter_downloaded": "Heruntergeladen",
            "now_playing": "Läuft gerade",
            "up_next": "Nächste Titel",
            "mark_played": "Als gespielt markieren",
            "mark_unplayed": "Als ungespielt markieren",
            "hide": "Ausblenden"
        ],
        .it: [
            "discover": "Podcast",
            "episodes_feed": "Preferiti",
            "subscriptions_btn": "Podcast",
            "radio": "Radio",
            "audiobooks": "Scopri",
            "recent": "Cronologia",
            "playlists": "Playlist",
            "library": "Libreria",
            "player": "Player",
            "search_placeholder": "Cerca podcast o radio...",
            "recommended": "Popolari",
            "see_all": "Vedi tutti",
            "latest_from_favs": "Ultimi dai preferiti",
            "episodes": "Episodi",
            "latest": "Ultimo",
            "subscribe": "Iscriviti",
            "subscribed": "Iscritto",
            "ai_summary": "Riassunto IA",
            "add_to_playlist": "Aggiungi alla playlist",
            "play_next": "Riproduci dopo",
            "add_to_queue": "Aggiungi alla coda",
            "my_playlists": "Le mie Playlist",
            "new_playlist": "Nuova Playlist",
            "login": "Accedi",
            "login_google": "Continua con Google",
            "login_apple": "Continua con Apple",
            "logout": "Esci",
            "welcome": "Bentornato",
            "world_radio": "Radio Mondiale",
            "language": "Lingua",
            "settings": "Impostazioni",
            "playback_speed": "Velocità di riproduzione",
            "skip_intro": "Salta intro (30s)",
            "accent_color": "Colore d'accento",
            "appearance": "Aspetto",
            "theme": "Tema",
            "theme_light": "Chiaro",
            "theme_dark": "Scuro",
            "theme_black": "Nero OLED",
            "clear_cache": "Cancella dati",
            "your_favorites": "I tuoi Preferiti",
            "results": "Risultati",
            "download": "Scarica",
            "downloading": "Scaricando...",
            "remove_download": "Rimuovi download",
            "offline": "Offline",
            "import_spotify": "Importa da Spotify",
            "spotify_desc": "Importa i tuoi podcast seguiti da Spotify nella tua libreria.",
            "spotify_connect": "Connetti Spotify",
            "spotify_syncing": "Sincronizzazione...",
            "spotify_success": "podcast importati con successo!",
            "filter_all": "Tutti",
            "filter_unplayed": "Non riprodotto",
            "filter_downloaded": "Scaricato",
            "now_playing": "In riproduzione",
            "up_next": "In coda",
            "mark_played": "Segna come riprodotto",
            "mark_unplayed": "Segna come non riprodotto",
            "hide": "Nascondi"
        ],
        .pt: [
            "discover": "Podcasts",
            "episodes_feed": "Favoritos",
            "subscriptions_btn": "Podcasts",
            "radio": "Rádio",
            "audiobooks": "Descobrir",
            "recent": "Histórico",
            "playlists": "Playlists",
            "library": "Biblioteca",
            "player": "Player",
            "search_placeholder": "Pesquisar podcasts ou rádio...",
            "recommended": "Populares",
            "see_all": "Ver tudo",
            "latest_from_favs": "Últimos dos favoritos",
            "episodes": "Episódios",
            "latest": "Último",
            "subscribe": "Inscrever-se",
            "subscribed": "Inscrito",
            "ai_summary": "Resumo IA",
            "add_to_playlist": "Adicionar à playlist",
            "play_next": "Reproduzir a seguir",
            "add_to_queue": "Adicionar à fila",
            "my_playlists": "Minhas Playlists",
            "new_playlist": "Nova Playlist",
            "login": "Entrar",
            "login_google": "Continuar com Google",
            "login_apple": "Continuar com Apple",
            "logout": "Sair",
            "welcome": "Bem-vindo de volta",
            "world_radio": "Rádio Mundial",
            "language": "Idioma",
            "settings": "Configurações",
            "playback_speed": "Velocidade de reprodução",
            "skip_intro": "Pular intro (30s)",
            "accent_color": "Cor de destaque",
            "appearance": "Aparência",
            "theme": "Tema",
            "theme_light": "Claro",
            "theme_dark": "Escuro",
            "theme_black": "Preto OLED",
            "clear_cache": "Limpar dados",
            "your_favorites": "Seus Favoritos",
            "results": "Resultados",
            "download": "Baixar",
            "downloading": "Baixando...",
            "remove_download": "Remover download",
            "offline": "Offline",
            "import_spotify": "Importar do Spotify",
            "spotify_desc": "Importe os seus podcasts seguidos do Spotify para a sua biblioteca.",
            "spotify_connect": "Conectar Spotify",
            "spotify_syncing": "Sincronizando...",
            "spotify_success": "podcasts importados com sucesso!",
            "filter_all": "Todos",
            "filter_unplayed": "Não reproduzido",
            "filter_downloaded": "Baixado",
            "now_playing": "Reproduzindo agora",
            "up_next": "A seguir",
            "mark_played": "Marcar como reproduzido",
            "mark_unplayed": "Marcar como não reproduzido",
            "hide": "Ocultar"
        ],
        .ja: [
            "discover": "ポッドキャスト",
            "episodes_feed": "お気に入り",
            "subscriptions_btn": "ポッドキャスト",
            "radio": "ラジオ",
            "audiobooks": "見つける",
            "recent": "履歴",
            "playlists": "プレイリスト",
            "library": "ライブラリ",
            "player": "プレーヤー",
            "search_placeholder": "ポッドキャストやラジオを検索...",
            "recommended": "人気",
            "see_all": "すべて見る",
            "latest_from_favs": "お気に入りの最新エピソード",
            "episodes": "エピソード",
            "latest": "最新",
            "subscribe": "購読する",
            "subscribed": "購読中",
            "ai_summary": "AI要約",
            "add_to_playlist": "プレイリストに追加",
            "play_next": "次に再生",
            "add_to_queue": "キューに追加",
            "my_playlists": "マイプレイリスト",
            "new_playlist": "新しいプレイリスト",
            "login": "ログイン",
            "login_google": "Googleで続ける",
            "login_apple": "Appleで続ける",
            "logout": "ログアウト",
            "welcome": "おかえりなさい",
            "world_radio": "ワールドラジオ",
            "language": "言語",
            "settings": "設定",
            "playback_speed": "再生速度",
            "skip_intro": "イントロをスキップ (30秒)",
            "accent_color": "アクセントカラー",
            "appearance": "外観",
            "theme": "テーマ",
            "theme_light": "ライト",
            "theme_dark": "ダーク",
            "theme_black": "OLEDブラック",
            "clear_cache": "データを消去",
            "your_favorites": "お気に入り",
            "results": "検索結果",
            "download": "ダウンロード",
            "downloading": "ダウンロード中...",
            "remove_download": "ファイルを削除",
            "offline": "オフライン",
            "import_spotify": "Spotifyからインポート",
            "spotify_desc": "Spotifyでフォローしているポッドキャストをライブラリにインポートします。",
            "spotify_connect": "Spotifyと連携",
            "spotify_syncing": "同期中...",
            "spotify_success": "つのポッドキャストが正常にインポートされました！",
            "filter_all": "すべて",
            "filter_unplayed": "未再生",
            "filter_downloaded": "ダウンロード済み",
            "now_playing": "再生中",
            "up_next": "次はこちら",
            "mark_played": "再生済みにする",
            "mark_unplayed": "未再生にする",
            "hide": "非表示"
        ],
        .zh: [
            "discover": "播客", "episodes_feed": "收藏", "subscriptions_btn": "播客", "radio": "电台",
            "audiobooks": "发现", "recent": "历史", "playlists": "播放列表", "library": "媒体库",
            "player": "播放器", "search_placeholder": "搜索播客、电台、有声书...", "recommended": "热门",
            "see_all": "查看全部", "latest_from_favs": "最新收藏单集", "episodes": "单集", "latest": "最新",
            "subscribe": "订阅", "subscribed": "已订阅", "ai_summary": "AI 摘要", "add_to_playlist": "添加到列表",
            "play_next": "下一首播放", "add_to_queue": "加入队列", "my_playlists": "我的播放列表",
            "new_playlist": "新建播放列表", "world_radio": "世界电台", "language": "语言", "settings": "设置",
            "playback_speed": "播放速度", "skip_intro": "跳过片头 (30秒)", "accent_color": "主题色",
            "theme": "外观", "theme_light": "浅色", "theme_dark": "深色", "theme_black": "OLED 纯黑",
            "clear_cache": "清除缓存", "your_favorites": "您的收藏", "results": "结果", "download": "下载",
            "downloading": "下载中...", "remove_download": "删除离线文件", "offline": "离线",
            "filter_all": "全部", "filter_unplayed": "未播放", "now_playing": "正在播放", "up_next": "接下来播放"
        ],
        .hi: [
            "discover": "पॉडकास्ट", "episodes_feed": "पसंदीदा", "subscriptions_btn": "पॉडकास्ट", "radio": "रेडियो",
            "audiobooks": "खोजें", "recent": "इतिहास", "playlists": "प्लेलिस्ट", "library": "लाइब्रेरी",
            "player": "प्लेयर", "search_placeholder": "पॉडकास्ट, रेडियो, किताबें खोजें...", "recommended": "लोकप्रिय",
            "episodes": "एपिसोड", "subscribe": "सब्सक्राइब", "subscribed": "सब्सक्राइब्ड", "language": "भाषा",
            "settings": "सेटिंग्स", "playback_speed": "प्लेबैक गति", "skip_intro": "इंट्रो छोड़ें (30s)",
            "accent_color": "एक्सेंट रंग", "theme": "थीम", "your_favorites": "आपके पसंदीदा",
            "filter_all": "सभी", "filter_unplayed": "अनसुने", "now_playing": "अभी चल रहा है", "up_next": "अगला"
        ],
        .ar: [
            "discover": "بودكاست", "episodes_feed": "المفضلة", "subscriptions_btn": "بودكاست", "radio": "راديو",
            "audiobooks": "اكتشف", "recent": "السجل", "playlists": "قوائم التشغيل", "library": "المكتبة",
            "player": "المشغل", "search_placeholder": "ابحث عن بودكاست، راديو، كتب...", "recommended": "شائع",
            "episodes": "الحلقات", "subscribe": "اشتراك", "subscribed": "مشترك", "language": "اللغة",
            "settings": "الإعدادات", "playback_speed": "سرعة التشغيل", "skip_intro": "تخطي المقدمة (30ث)",
            "accent_color": "اللون المميز", "theme": "المظهر", "your_favorites": "مفضلاتك",
            "filter_all": "الكل", "filter_unplayed": "غير مشغل", "now_playing": "قيد التشغيل", "up_next": "التالي"
        ],
        .ru: [
            "discover": "Подкасты", "episodes_feed": "Избранное", "subscriptions_btn": "Подкасты", "radio": "Радио",
            "audiobooks": "Обзор", "recent": "История", "playlists": "Плейлисты", "library": "Библиотека",
            "player": "Плеер", "search_placeholder": "Поиск подкастов, радио, книг...", "recommended": "Популярное",
            "episodes": "Выпуски", "subscribe": "Подписаться", "subscribed": "В подписках", "language": "Язык",
            "settings": "Настройки", "playback_speed": "Скорость", "skip_intro": "Пропуск интро (30с)",
            "accent_color": "Цвет акцента", "theme": "Тема", "your_favorites": "Ваше избранное",
            "filter_all": "Все", "filter_unplayed": "Непрослушанные", "now_playing": "Сейчас играет", "up_next": "Далее"
        ],
        .tr: [
            "discover": "Podcast'ler", "episodes_feed": "Favoriler", "subscriptions_btn": "Podcast'ler", "radio": "Radyo",
            "audiobooks": "Keşfet", "recent": "Geçmiş", "playlists": "Çalma Listeleri", "library": "Kitaplık",
            "player": "Oynatıcı", "search_placeholder": "Podcast, radyo, kitap ara...", "recommended": "Popüler",
            "episodes": "Bölümler", "subscribe": "Abone Ol", "subscribed": "Abone Olundu", "language": "Dil",
            "settings": "Ayarlar", "playback_speed": "Oynatma Hızı", "skip_intro": "Girişi Atla (30sn)",
            "accent_color": "Vurgu Rengi", "theme": "Tema", "your_favorites": "Favorileriniz",
            "filter_all": "Tümü", "filter_unplayed": "Dinlenmedi", "now_playing": "Şimdi Çalıyor", "up_next": "Sıradaki"
        ],
        .ko: [
            "discover": "팟캐스트", "episodes_feed": "즐겨찾기", "subscriptions_btn": "팟캐스트", "radio": "라디오",
            "audiobooks": "탐색", "recent": "기록", "playlists": "재생목록", "library": "보관함",
            "player": "플레이어", "search_placeholder": "팟캐스트, 라디오, 오디오북 검색...", "recommended": "인기",
            "episodes": "에피소드", "subscribe": "구독", "subscribed": "구독 중", "language": "언어",
            "settings": "설정", "playback_speed": "재생 속도", "skip_intro": "인트로 건너뛰기 (30초)",
            "accent_color": "강조 색상", "theme": "테마", "your_favorites": "내 즐겨찾기",
            "filter_all": "전체", "filter_unplayed": "미재생", "now_playing": "재생 중", "up_next": "다음 재생"
        ],
        .vi: [
            "discover": "Podcast", "episodes_feed": "Yêu thích", "subscriptions_btn": "Podcast", "radio": "Radio",
            "audiobooks": "Khám phá", "recent": "Lịch sử", "playlists": "Danh sách phát", "library": "Thư viện",
            "player": "Trình phát", "search_placeholder": "Tìm podcast, radio, sách nói...", "recommended": "Phổ biến",
            "episodes": "Tập", "subscribe": "Theo dõi", "subscribed": "Đã theo dõi", "language": "Ngôn ngữ",
            "settings": "Cài đặt", "playback_speed": "Tốc độ phát", "skip_intro": "Bỏ qua mở đầu (30s)",
            "accent_color": "Màu nhấn", "theme": "Giao diện", "your_favorites": "Yêu thích của bạn",
            "filter_all": "Tất cả", "filter_unplayed": "Chưa nghe", "now_playing": "Đang phát", "up_next": "Tiếp theo"
        ],
        .id: [
            "discover": "Podcast", "episodes_feed": "Favorit", "subscriptions_btn": "Podcast", "radio": "Radio",
            "audiobooks": "Jelajahi", "recent": "Riwayat", "playlists": "Daftar Putar", "library": "Koleksi",
            "player": "Pemutar", "search_placeholder": "Cari podcast, radio, buku audio...", "recommended": "Populer",
            "episodes": "Episode", "subscribe": "Langganan", "subscribed": "Berlangganan", "language": "Bahasa",
            "settings": "Pengaturan", "playback_speed": "Kecepatan Putar", "skip_intro": "Lewati Intro (30d)",
            "accent_color": "Warna Aksen", "theme": "Tema", "your_favorites": "Favorit Anda",
            "filter_all": "Semua", "filter_unplayed": "Belum Diputar", "now_playing": "Sedang Diputar", "up_next": " Berikutnya"
        ]
    ]
    
    private let categories: [LangCode: [String: String]] = [
        .en: [
            "All": "All Categories",
            "News": "News",
            "Comedy": "Comedy",
            "Technology": "Technology",
            "Business": "Business",
            "Society & Culture": "Society & Culture",
            "True Crime": "True Crime",
            "Health": "Health",
            "Education": "Education",
            "History": "History",
            "Music": "Music",
            "Science": "Science",
            "Sports": "Sports"
        ],
        .fr: [
            "All": "Toutes les catégories",
            "News": "Actualités",
            "Comedy": "Humour",
            "Technology": "Technologie",
            "Business": "Affaires",
            "Society & Culture": "Société et culture",
            "True Crime": "Faits divers",
            "Health": "Santé",
            "Education": "Éducation",
            "History": "Histoire",
            "Music": "Musique",
            "Science": "Science",
            "Sports": "Sports"
        ],
        .es: [
            "All": "Todas las categorías",
            "News": "Noticias",
            "Comedy": "Comedia",
            "Technology": "Tecnología",
            "Business": "Negocios",
            "Society & Culture": "Sociedad y cultura",
            "True Crime": "Crímenes reales",
            "Health": "Salud",
            "Education": "Educación",
            "History": "Historia",
            "Music": "Música",
            "Science": "Ciencia",
            "Sports": "Deportes"
        ],
        .de: [
            "All": "Alle Kategorien",
            "News": "Nachrichten",
            "Comedy": "Comedy",
            "Technology": "Technologie",
            "Business": "Business",
            "Society & Culture": "Gesellschaft & Kultur",
            "True Crime": "True Crime",
            "Health": "Gesundheit",
            "Education": "Bildung",
            "History": "Geschichte",
            "Music": "Musik",
            "Science": "Wissenschaft",
            "Sports": "Sport"
        ],
        .it: [
            "All": "Tutte le categorie",
            "News": "Notizie",
            "Comedy": "Commedia",
            "Technology": "Tecnologia",
            "Business": "Business",
            "Society & Culture": "Società e cultura",
            "True Crime": "True Crime",
            "Health": "Salute",
            "Education": "Istruzione",
            "History": "Storia",
            "Music": "Musica",
            "Science": "Scienza",
            "Sports": "Sport"
        ],
        .pt: [
            "All": "Todas as categorias",
            "News": "Notícias",
            "Comedy": "Comédia",
            "Technology": "Tecnologia",
            "Business": "Negócios",
            "Society & Culture": "Sociedade e cultura",
            "True Crime": "True Crime",
            "Health": "Saúde",
            "Education": "Educação",
            "History": "História",
            "Music": "Música",
            "Science": "Ciência",
            "Sports": "Esportes"
        ],
        .ja: [
            "All": "すべてのカテゴリ",
            "News": "ニュース",
            "Comedy": "コメディ",
            "Technology": "テクノロジー",
            "Business": "ビジネス",
            "Society & Culture": "社会・文化",
            "True Crime": "実録犯罪",
            "Health": "健康",
            "Education": "教育",
            "History": "歴史",
            "Music": "音楽",
            "Science": "科学",
            "Sports": "スポーツ"
        ],
        .zh: [
            "All": "所有类别", "News": "新闻", "Comedy": "喜剧", "Technology": "科技",
            "Business": "商业", "Society & Culture": "社会与文化", "True Crime": "真实犯罪",
            "Health": "健康", "Education": "教育", "History": "历史", "Music": "音乐",
            "Science": "科学", "Sports": "体育"
        ],
        .ru: [
            "All": "Все категории", "News": "Новости", "Comedy": "Комедия", "Technology": "Технологии",
            "Business": "Бизнес", "Society & Culture": "Общество и культура", "True Crime": "Криминал",
            "Health": "Здоровье", "Education": "Образование", "History": "История", "Music": "Музыка",
            "Science": "Наука", "Sports": "Спорт"
        ],
        .ar: [
            "All": "جميع الفئات", "News": "أخبار", "Comedy": "كوميديا", "Technology": "تكنولوجيا",
            "Business": "أعمال", "Society & Culture": "المجتمع والثقافة", "True Crime": "جرائم حقيقية",
            "Health": "صحة", "Education": "تعليم", "History": "تاريخ", "Music": "موسيقى",
            "Science": "علوم", "Sports": "رياضة"
        ],
        .tr: [
            "All": "Tüm Kategoriler", "News": "Haberler", "Comedy": "Komedi", "Technology": "Teknoloji",
            "Business": "İş Dünyası", "Society & Culture": "Toplum ve Kültür", "True Crime": "Gerçek Suç",
            "Health": "Sağlık", "Education": "Eğitim", "History": "Tarih", "Music": "Müzik",
            "Science": "Bilim", "Sports": "Spor"
        ],
        .ko: [
            "All": "모든 카테고리", "News": "뉴스", "Comedy": "코미디", "Technology": "기술",
            "Business": "비즈니스", "Society & Culture": "사회 및 문화", "True Crime": "실제 범죄",
            "Health": "건강", "Education": "교육", "History": "역사", "Music": "음악",
            "Science": "과학", "Sports": "스포츠"
        ]
    ]

    private let bookCats: [LangCode: [String: String]] = [
        .en: [
            "all": "All Books",
            "fiction": "Fiction & Classics",
            "thriller": "Mystery & Thriller",
            "scifi": "Sci-Fi & Fantasy",
            "history": "History & Biography",
            "kids": "Kids & Teens",
            "growth": "Self-Help & Spirit",
            "arts": "Arts & Philosophy"
        ],
        .fr: [
            "all": "Tous",
            "fiction": "Romans & Classiques",
            "thriller": "Policier & Thriller",
            "scifi": "Sci-Fi & Fantasy",
            "history": "Histoire & Biographies",
            "kids": "Jeunesse",
            "growth": "Dév. Perso & Santé",
            "arts": "Arts & Philosophie"
        ],
        .es: [
            "all": "Todos",
            "scifi": "Ciencia Ficción",
            "thriller": "Thriller",
            "history": "Historia",
            "kids": "Niños",
            "personal_growth": "Crecimiento Personal",
            "classics": "Clásicos",
            "fiction": "Ficción"
        ],
        .de: [
            "all": "Alle",
            "scifi": "Sci-Fi",
            "thriller": "Thriller",
            "history": "Geschichte",
            "kids": "Kinder",
            "personal_growth": "Selbsthilfe",
            "classics": "Klassiker",
            "fiction": "Belletristik"
        ],
        .it: [
            "all": "Tutti",
            "scifi": "Fantascienza",
            "thriller": "Giallo",
            "history": "Storia",
            "kids": "Bambini",
            "personal_growth": "Crescita Personale",
            "classics": "Classici",
            "fiction": "Narrativa"
        ],
        .pt: [
            "all": "Todos",
            "scifi": "Ficção Científica",
            "thriller": "Suspense",
            "history": "História",
            "kids": "Crianças",
            "personal_growth": "Crescimento Pessoal",
            "classics": "Clássicos",
            "fiction": "Ficção"
        ],
        .ja: [
            "all": "すべて",
            "scifi": "SF",
            "thriller": "スリラー",
            "history": "歴史",
            "kids": "キッズ",
            "personal_growth": "自己啓発",
            "classics": "名作",
            "fiction": "フィクション"
        ]
    ]

    func t(_ key: String, _ lang: LangCode) -> String {
        return data[lang]?[key] ?? data[.en]?[key] ?? key
    }
    
    func category(_ key: String, _ lang: LangCode) -> String {
        return categories[lang]?[key] ?? categories[.en]?[key] ?? key
    }
    
    func bookCat(_ key: String, _ lang: LangCode) -> String {
        return bookCats[lang]?[key] ?? bookCats[.en]?[key] ?? key
    }
    
    func getCategoriesList(_ lang: LangCode) -> [(key: String, value: String)] {
        let dict = categories[lang] ?? categories[.en]!
        return dict.map { ($0.key, $0.value) }.sorted { a, b in
            if a.key == "All" { return true }
            if b.key == "All" { return false }
            return a.value < b.value
        }
    }
    
    func getBookCatsList(_ lang: LangCode) -> [(key: String, value: String)] {
        let dict = bookCats[lang] ?? bookCats[.en]!
        return dict.map { ($0.key, $0.value) }.sorted { a, b in
            if a.key == "all" { return true }
            if b.key == "all" { return false }
            return a.value < b.value
        }
    }
}
