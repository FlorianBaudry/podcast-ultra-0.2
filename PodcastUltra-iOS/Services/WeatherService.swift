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
    }
}

final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = WeatherService()
    
    @Published var temperature: Double?
    @Published var weatherDescription: String
    @Published var weatherIcon: String
    @Published var cityName: String
    @Published var weeklyForecast: [DailyWeatherForecast] = []
    
    private let locationManager = CLLocationManager()
    private var hasFetchedThisSession = false
    
    override init() {
        let savedTemp = UserDefaults.standard.object(forKey: "voxstream_weather_temp") as? Double
        self.temperature = savedTemp ?? 19.0
        self.weatherDescription = UserDefaults.standard.string(forKey: "voxstream_weather_desc") ?? "Partiellement nuageux"
        self.weatherIcon = UserDefaults.standard.string(forKey: "voxstream_weather_icon") ?? "cloud.sun.fill"
        self.cityName = UserDefaults.standard.string(forKey: "voxstream_weather_city") ?? "Paris"
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
        // Trigger initial weather fetch (using cached/fallback coordinates immediately while GPS resolves)
        let lat = UserDefaults.standard.object(forKey: "voxstream_weather_lat") as? Double ?? 48.8566
        let lon = UserDefaults.standard.object(forKey: "voxstream_weather_lon") as? Double ?? 2.3522
        fetchWeather(latitude: lat, longitude: lon)
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
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current_weather=true&daily=weathercode,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=7") else { return }
        hasFetchedThisSession = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(WeatherData.self, from: data)
                
                var parsedForecast: [DailyWeatherForecast] = []
                if let daily = response.daily,
                   let times = daily.time,
                   let codes = daily.weathercode,
                   let maxs = daily.temperature_2m_max,
                   let mins = daily.temperature_2m_min {
                    let count = min(7, min(times.count, min(codes.count, min(maxs.count, mins.count))))
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
                
                let resolvedForecast = parsedForecast
                await MainActor.run {
                    self.temperature = response.current_weather.temperature
                    self.parseWeatherCode(response.current_weather.weathercode)
                    if !resolvedForecast.isEmpty {
                        self.weeklyForecast = resolvedForecast
                        if let encoded = try? JSONEncoder().encode(resolvedForecast) {
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
        let sampleCodes = [1, 0, 2, 61, 1, 0, 2]
        let sampleMax: [Double] = [20, 22, 19, 17, 19, 21, 22]
        let sampleMin: [Double] = [12, 13, 11, 10, 11, 12, 13]
        return (0..<7).map { offset in
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
