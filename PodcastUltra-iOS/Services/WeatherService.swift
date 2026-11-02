import Foundation
import CoreLocation

struct WeatherData: Decodable {
    let current_weather: CurrentWeather
    
    struct CurrentWeather: Decodable {
        let temperature: Double
        let weathercode: Int
    }
}

final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = WeatherService()
    
    @Published var temperature: Double?
    @Published var weatherDescription: String
    @Published var weatherIcon: String
    @Published var cityName: String
    
    private let locationManager = CLLocationManager()
    private var hasFetchedThisSession = false
    
    override init() {
        let savedTemp = UserDefaults.standard.object(forKey: "voxstream_weather_temp") as? Double
        self.temperature = savedTemp ?? 19.0
        self.weatherDescription = UserDefaults.standard.string(forKey: "voxstream_weather_desc") ?? "Partiellement nuageux"
        self.weatherIcon = UserDefaults.standard.string(forKey: "voxstream_weather_icon") ?? "cloud.sun.fill"
        self.cityName = UserDefaults.standard.string(forKey: "voxstream_weather_city") ?? "Paris"
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        // Trigger initial weather fetch (using cached/fallback coordinates immediately while GPS resolves)
        let lat = UserDefaults.standard.object(forKey: "voxstream_weather_lat") as? Double ?? 48.8566
        let lon = UserDefaults.standard.object(forKey: "voxstream_weather_lon") as? Double ?? 2.3522
        fetchWeather(latitude: lat, longitude: lon)
    }
    
    func requestLocation() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.requestLocation()
        } else if !hasFetchedThisSession {
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
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current_weather=true") else { return }
        hasFetchedThisSession = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(WeatherData.self, from: data)
                
                await MainActor.run {
                    self.temperature = response.current_weather.temperature
                    self.parseWeatherCode(response.current_weather.weathercode)
                    UserDefaults.standard.set(response.current_weather.temperature, forKey: "voxstream_weather_temp")
                    UserDefaults.standard.set(self.weatherDescription, forKey: "voxstream_weather_desc")
                    UserDefaults.standard.set(self.weatherIcon, forKey: "voxstream_weather_icon")
                }
            } catch {
                // Keep cached/default weather values so UI is always visible
            }
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
