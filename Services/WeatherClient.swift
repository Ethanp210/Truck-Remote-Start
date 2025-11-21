import Foundation
import CoreLocation

struct WeatherClient {
    var config: WeatherAPIConfig = .default
    var session: URLSession = .shared

    struct WeatherResponse: Decodable {
        struct Current: Decodable { let temperature_2m: Double? }
        let current: Current?
    }

    func temperature(for coordinate: CLLocationCoordinate2D) async -> Double {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("v1/forecast"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit")
        ]

        if let apiKey = config.apiKey, !apiKey.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "apikey", value: apiKey))
        }

        guard let url = components?.url else {
            return config.fallbackTemperatureF
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                return config.fallbackTemperatureF
            }

            let decoded = try JSONDecoder().decode(WeatherResponse.self, from: data)
            if let temp = decoded.current?.temperature_2m {
                return temp
            }

            return config.fallbackTemperatureF
        } catch {
            return config.fallbackTemperatureF
        }
    }
}
