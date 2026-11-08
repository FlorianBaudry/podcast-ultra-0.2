import Foundation
import CoreLocation

struct DailyWeatherForecast: Identifiable, Codable {
    var id: String { dateString }
    let dateString: String
    let weatherCode: Int
    let tempMax: Double
    let tempMin: Double
    let icon: String
}

struct WeatherData: Decodable {
    let current_weather: CurrentWeather
    let daily: DailyData?
    
    struct CurrentWeather: Decodable {
        let temperature: Double
        let weathercode: Int
    }
    
    struct DailyData: Decodable {
        let time: [String]?
        let weathercode: [Int]?
        let temperature_2m_max: [Double]?
        let temperature_2m_min: [Double]?
        let sunrise: [String]?
        let sunset: [String]?
    }
}

final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = WeatherService()
    
    @Published var temperature: Double?
    @Published var weatherDescription: String
    @Published var weatherIcon: String
    @Published var cityName: String
    @Published var sunriseTimeString: String
    @Published var sunsetTimeString: String
    @Published var weeklyForecast: [DailyWeatherForecast] = []
    
    private let locationManager = CLLocationManager()
    private var hasFetchedThisSession = false
    
    override init() {
        let savedTemp = UserDefaults.standard.object(forKey: "voxstream_weather_temp") as? Double
        self.temperature = savedTemp ?? 19.0
        self.weatherDescription = UserDefaults.standard.string(forKey: "voxstream_weather_desc") ?? "Partiellement nuageux"
        self.weatherIcon = UserDefaults.standard.string(forKey: "voxstream_weather_icon") ?? "cloud.sun.fill"
        self.cityName = UserDefaults.standard.string(forKey: "voxstream_weather_city") ?? "Paris"
        self.sunriseTimeString = UserDefaults.standard.string(forKey: "voxstream_weather_sunrise") ?? "07:45"
        self.sunsetTimeString = UserDefaults.standard.string(forKey: "voxstream_weather_sunset") ?? "17:20"
        super.init()
        if let savedWeeklyData = UserDefaults.standard.data(forKey: "voxstream_weather_weekly"),
           let decoded = try? JSONDecoder().decode([DailyWeatherForecast].self, from: savedWeeklyData),
           !decoded.isEmpty {
            self.weeklyForecast = decoded
        } else {
            self.weeklyForecast = Self.defaultWeeklyForecast()
        }
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        // Deferred background weather fetch so app launch is never delayed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }
            let lat = UserDefaults.standard.object(forKey: "voxstream_weather_lat") as? Double ?? 48.8566
            let lon = UserDefaults.standard.object(forKey: "voxstream_weather_lon") as? Double ?? 2.3522
            self.fetchWeather(latitude: lat, longitude: lon)
        }
    }
    
    func requestLocation() {
        guard !hasFetchedThisSession else { return }
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.requestLocation()
        } else {
            fetchWeather(latitude: 48.8566, longitude: 2.3522)
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        UserDefaults.standard.set(location.coordinate.latitude, forKey: "voxstream_weather_lat")
        UserDefaults.standard.set(location.coordinate.longitude, forKey: "voxstream_weather_lon")
        fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        resolveCityName(location: location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let lat = UserDefaults.standard.object(forKey: "voxstream_weather_lat") as? Double ?? 48.8566
        let lon = UserDefaults.standard.object(forKey: "voxstream_weather_lon") as? Double ?? 2.3522
        fetchWeather(latitude: lat, longitude: lon)
    }
    
    private func fetchWeather(latitude: Double, longitude: Double) {
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current_weather=true&daily=weathercode,temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto&forecast_days=5") else { return }
        hasFetchedThisSession = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(WeatherData.self, from: data)
                
                var parsedForecast: [DailyWeatherForecast] = []
                var resolvedSunrise: String? = nil
                var resolvedSunset: String? = nil
                
                if let daily = response.daily {
                    if let firstRise = daily.sunrise?.first {
                        resolvedSunrise = Self.extractHourMinute(from: firstRise)
                    }
                    if let firstSet = daily.sunset?.first {
                        resolvedSunset = Self.extractHourMinute(from: firstSet)
                    }
                    if let times = daily.time,
                       let codes = daily.weathercode,
                       let maxs = daily.temperature_2m_max,
                       let mins = daily.temperature_2m_min {
                        let count = min(5, min(times.count, min(codes.count, min(maxs.count, mins.count))))
                        for i in 0..<count {
                            let code = codes[i]
                            parsedForecast.append(DailyWeatherForecast(
                                dateString: times[i],
                                weatherCode: code,
                                tempMax: maxs[i],
                                tempMin: mins[i],
                                icon: Self.iconForWeatherCode(code)
                            ))
                        }
                    }
                }
                
                let finalForecast = parsedForecast
                let finalSunrise = resolvedSunrise
                let finalSunset = resolvedSunset
                await MainActor.run {
                    self.temperature = response.current_weather.temperature
                    self.parseWeatherCode(response.current_weather.weathercode)
                    if let rise = finalSunrise, !rise.isEmpty {
                        self.sunriseTimeString = rise
                        UserDefaults.standard.set(rise, forKey: "voxstream_weather_sunrise")
                    }
                    if let set = finalSunset, !set.isEmpty {
                        self.sunsetTimeString = set
                        UserDefaults.standard.set(set, forKey: "voxstream_weather_sunset")
                    }
                    if !finalForecast.isEmpty {
                        self.weeklyForecast = finalForecast
                        if let encoded = try? JSONEncoder().encode(finalForecast) {
                            UserDefaults.standard.set(encoded, forKey: "voxstream_weather_weekly")
                        }
                    }
                    UserDefaults.standard.set(response.current_weather.temperature, forKey: "voxstream_weather_temp")
                    UserDefaults.standard.set(self.weatherDescription, forKey: "voxstream_weather_desc")
                    UserDefaults.standard.set(self.weatherIcon, forKey: "voxstream_weather_icon")
                }
            } catch {
                // Keep cached/default weather values so UI is always visible
            }
        }
    }
    
    private static func extractHourMinute(from isoString: String) -> String {
        if let tRange = isoString.range(of: "T") {
            let afterT = String(isoString[tRange.upperBound...])
            return String(afterT.prefix(5))
        }
        return isoString
    }
    
    static func iconForWeatherCode(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2, 3: return "cloud.sun.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 71, 73, 75: return "snowflake"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
    
    private static func defaultWeeklyForecast() -> [DailyWeatherForecast] {
        let cal = Calendar.current
        let today = Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let sampleCodes = [1, 0, 2, 61, 1]
        let sampleMax: [Double] = [20, 22, 19, 17, 19]
        let sampleMin: [Double] = [12, 13, 11, 10, 11]
        return (0..<5).map { offset in
            let d = cal.date(byAdding: .day, value: offset, to: today) ?? today
            let code = sampleCodes[offset % sampleCodes.count]
            return DailyWeatherForecast(
                dateString: df.string(from: d),
                weatherCode: code,
                tempMax: sampleMax[offset % sampleMax.count],
                tempMin: sampleMin[offset % sampleMin.count],
                icon: iconForWeatherCode(code)
            )
        }
    }
    
    // MARK: - Ephemeris Helpers: Zodiac Sign & French Saint / Fête du Jour
    static func currentZodiacSign(for date: Date = Date(), isFrench: Bool = true) -> (symbol: String, name: String) {
        let comps = Calendar.current.dateComponents([.month, .day], from: date)
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let md = m * 100 + d
        
        switch md {
        case 321...419:
            return ("♈︎", isFrench ? "Bélier" : "Aries")
        case 420...520:
            return ("♉︎", isFrench ? "Taureau" : "Taurus")
        case 521...620:
            return ("♊︎", isFrench ? "Gémeaux" : "Gemini")
        case 621...722:
            return ("♋︎", isFrench ? "Cancer" : "Cancer")
        case 723...822:
            return ("♌︎", isFrench ? "Lion" : "Leo")
        case 823...922:
            return ("♍︎", isFrench ? "Vierge" : "Virgo")
        case 923...1022:
            return ("♎︎", isFrench ? "Balance" : "Libra")
        case 1023...1121:
            return ("♏︎", isFrench ? "Scorpion" : "Scorpio")
        case 1122...1221:
            return ("♐︎", isFrench ? "Sagittaire" : "Sagittarius")
        case 120...218:
            return ("♒︎", isFrench ? "Verseau" : "Aquarius")
        case 219...320:
            return ("♓︎", isFrench ? "Poissons" : "Pisces")
        default:
            return ("♑︎", isFrench ? "Capricorne" : "Capricorn")
        }
    }
    
    static func feteDuJour(for date: Date = Date()) -> String {
        let comps = Calendar.current.dateComponents([.month, .day], from: date)
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        guard m >= 1 && m <= 12, d >= 1 && d <= 31 else { return "Saint du jour" }
        let table: [[String]] = [
            // 1. Janvier
            ["Jour de l'An", "Basile", "Geneviève", "Odilon", "Édouard", "Mélaine", "Raymond", "Lucien", "Alix", "Guillaume", "Paulin", "Tatiana", "Yvette", "Nina", "Rémi", "Marcel", "Roseline", "Prisca", "Marius", "Sébastien", "Agnès", "Vincent", " Barnard", "François de Sales", "Conversion de Paul", "Paule", "Angèle", "Thomas d'Aquin", "Gildas", "Martine", "Marcelle"],
            // 2. Février
            ["Ella", "Présentation", "Blaise", "Véronique", "Agathe", "Gaston", "Eugénie", "Jacqueline", "Apolline", "Arnaud", "N.-D. de Lourdes", "Félix", "Béatrice", "Valentin", "Claude", "Julienne", "Alexis", "Bernadette", "Gabin", "Aimée", "Pierre-Damien", "Isabelle", "Lazare", "Modeste", "Roméo", "Nestor", "Honorine", "Romain", "Auguste"],
            // 3. Mars
            ["Aubin", "Charles le Bon", "Guénolé", "Casimir", "Olive", "Colette", "Félicité", "Jean de Dieu", "Françoise", "Vivien", "Rosine", "Justine", "Rodrigue", "Mathilde", "Louise", "Bénédicte", "Patrice", "Cyrille", "Joseph", "Printemps", "Clémence", "Léa", "Victorien", "Catherine de Suède", "Annonciation", "Larissa", "Habib", "Gontran", "Gwladys", "Amédée", "Benjamin"],
            // 4. Avril
            ["Hugues", "Sandrine", "Richard", "Isidore", "Irène", "Marcellin", "Jean-Baptiste de la Salle", "Julie", "Gautier", "Fulbert", "Stanislas", "Jules", "Ida", "Maxime", "Paterne", "Benoît-Joseph", "Anicet", "Parfait", "Emma", "Odette", "Anselme", "Alexandre", "Georges", "Fidèle", "Marc", "Alida", "Zita", "Valérie", "Catherine de Sienne", "Robert"],
            // 5. Mai
            ["Fête du Travail", "Boris", "Philippe", "Sylvain", "Judith", "Prudence", "Gisèle", "Victoire 1945", "Pacôme", "Solange", "Estelle", "Achille", "Rolande", "Matthias", "Denise", "Honoré", "Pascal", "Éric", "Yves", "Bernardin", "Constantin", "Émile", "Didier", "Donatien", "Sophie", "Bérenger", "Augustin", "Germain", "Aymar", "Ferdinand", "Visitation"],
            // 6. Juin
            ["Justin", "Blandine", "Kévin", "Clotilde", "Igor", "Norbert", "Gilbert", "Médard", "Diane", "Landry", "Barnabé", "Guy", "Antoine de Padoue", "Élisée", "Germaine", "Jean-François Régis", "Hervé", "Léonce", "Romuald", "Silvère", "Été • Rodolphe", "Alban", "Audrey", "Jean-Baptiste", "Prosper", "Anthelme", "Fernand", "Irénée", "Pierre et Paul", "Martial"],
            // 7. Juillet
            ["Thierry", "Martinien", "Thomas", "Florent", "Antoine", "Mariette", "Raoul", "Thibaut", "Amandine", "Ulrich", "Benoît", "Olivier", "Henri et Joël", "Fête Nationale • Camille", "Donald", "N.-D. du Mont-Carmel", "Charlotte", "Frédéric", "Arsène", "Marina", "Victor", "Marie-Madeleine", "Brigitte", "Christine", "Jacques", "Anne et Joachim", "Nathalie", "Samson", "Marthe", "Juliette", "Ignace de Loyola"],
            // 8. Août
            ["Alphonse", "Julien Eymard", "Lydie", "Jean-Marie Vianney", "Abel", "Transfiguration", "Gaétan", "Dominique", "Amour", "Laurent", "Claire", "Clarisse", "Hippolyte", "Évrard", "Assomption • Marie", "Armel", "Hyacinthe", "Hélène", "Jean Eudes", "Bernard", "Christophe", "Fabrice", "Rose de Lima", "Barthélemy", "Louis", "Natacha", "Monique", "Augustin", "Sabine", "Fiacre", "Aristide"],
            // 9. Septembre
            ["Gilles", "Ingrid", "Grégoire", "Rosalie", "Raïssa", "Bertrand", "Reine", "Nativité", "Alain", "Inès", "Adelphe", "Apollinaire", "Aimé", "La Sainte-Croix", "Roland", "Édith", "Renaud", "Nadège", "Émilie", "Davy", "Matthieu", "Maurice", "Automne • Constant", "Thècle", "Hermann", "Côme et Damien", "Vincent de Paul", "Venceslas", "Michel", "Jérôme"],
            // 10. Octobre
            ["Thérèse de l'Enfant-Jésus", "Léger", "Gérard", "François d'Assise", "Fleur", "Bruno", "Serge", "Pélagie", "Denis", "Ghislain", "Firmin", "Wilfried", "Géraud", "Juste", "Thérèse d'Avila", "Edwige", "Baudouin", "Luc", "René", "Adeline", "Céline", "Élodie", "Jean de Capistran", "Florentin", "Crépin", "Dimitri", "Émeline", "Simon et Jude", "Narcisse", "Bienvenue", "Quentin"],
            // 11. Novembre
            ["Toussaint", "Défunts", "Hubert", "Charles", "Sylvie", "Bertille", "Carine", "Geoffroy", "Théodore", "Léon", "Armistice • Martin", "Christian", "Brice", "Sidoine", "Albert", "Marguerite", "Élisabeth", "Aude", "Tanguy", "Edmond", "Prés. de Marie", "Cécile", "Clément", "Flora", "Catherine", "Delphine", "Sévrin", "Jacques de la Marche", "Saturnin", "André"],
            // 12. Décembre
            ["Florence", "Viviane", "François-Xavier", "Barbara", "Gérald", "Nicolas", "Ambroise", "Immaculée Conception", "Pierre Fourier", "Romaric", "Daniel", "Jeanne-Françoise", "Lucie", "Odile", "Ninon", "Alice", "Gaël", "Gatien", "Urbain", "Théophile", "Hiver • Pierre Canisius", "Françoise-Xavière", "Armand", "Adèle", "Noël", "Étienne", "Jean", "Innocents", "David", "Roger", "Sylvestre"]
        ]
        let monthArr = table[m - 1]
        let idx = min(d - 1, monthArr.count - 1)
        return monthArr[idx].trimmingCharacters(in: .whitespaces)
    }
    
    private func resolveCityName(location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            if let city = placemarks?.first?.locality, !city.isEmpty {
                DispatchQueue.main.async {
                    self?.cityName = city
                    UserDefaults.standard.set(city, forKey: "voxstream_weather_city")
                }
            }
        }
    }
    
    private func parseWeatherCode(_ code: Int) {
        switch code {
        case 0:
            weatherDescription = "Ciel dégagé"
            weatherIcon = "sun.max.fill"
        case 1, 2, 3:
            weatherDescription = "Partiellement nuageux"
            weatherIcon = "cloud.sun.fill"
        case 45, 48:
            weatherDescription = "Brouillard"
            weatherIcon = "cloud.fog.fill"
        case 51, 53, 55:
            weatherDescription = "Bruine"
            weatherIcon = "cloud.drizzle.fill"
        case 61, 63, 65:
            weatherDescription = "Pluie"
            weatherIcon = "cloud.rain.fill"
        case 71, 73, 75:
            weatherDescription = "Neige"
            weatherIcon = "snowflake"
        case 80, 81, 82:
            weatherDescription = "Averses"
            weatherIcon = "cloud.heavyrain.fill"
        case 95, 96, 99:
            weatherDescription = "Orage"
            weatherIcon = "cloud.bolt.rain.fill"
        default:
            weatherDescription = "Nuageux"
            weatherIcon = "cloud.fill"
        }
    }
}
