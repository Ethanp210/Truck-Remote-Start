import Foundation

struct APIConfig: Codable, Equatable {
    var baseURL: URL
    var clientId: String
    var redirectScheme: String
    var scopes: [String]

    static let `default` = APIConfig(
        baseURL: URL(string: "https://api.truckremote.example")!,
        clientId: "truck-remote-client",
        redirectScheme: "truckremote",
        scopes: ["openid", "profile", "vehicle"]
    )

    var redirectURI: String { "\(redirectScheme)://callback" }
}

struct WeatherAPIConfig: Codable, Equatable {
    var baseURL: URL
    var apiKey: String?
    var fallbackTemperatureF: Double

    static let `default` = WeatherAPIConfig(
        baseURL: URL(string: "https://api.open-meteo.com")!,
        apiKey: nil,
        fallbackTemperatureF: 68
    )
}

final class ConfigStore: ObservableObject {
    @Published var config: APIConfig {
        didSet { persist() }
    }
    @Published var weatherConfig: WeatherAPIConfig {
        didSet { persistWeather() }
    }
    private let defaultsKey = "TruckRemoteStart.APIConfig"
    private let weatherDefaultsKey = "TruckRemoteStart.WeatherAPIConfig"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(APIConfig.self, from: data) {
            config = decoded
        } else {
            config = .default
        }

        if let data = UserDefaults.standard.data(forKey: weatherDefaultsKey),
           let decoded = try? JSONDecoder().decode(WeatherAPIConfig.self, from: data) {
            weatherConfig = decoded
        } else {
            weatherConfig = .default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func persistWeather() {
        if let data = try? JSONEncoder().encode(weatherConfig) {
            UserDefaults.standard.set(data, forKey: weatherDefaultsKey)
        }
    }
}
