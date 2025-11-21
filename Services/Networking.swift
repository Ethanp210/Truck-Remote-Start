import Foundation
import CoreLocation

enum HTTPMethod: String { case get = "GET", post = "POST", patch = "PATCH" }

struct APIClient {
    let config: APIConfig
    let tokenProvider: () -> String?
    let session: URLSession = .shared

    func request<T: Decodable>(_ path: String, method: HTTPMethod = .get, body: Encodable? = nil) async throws -> T {
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func send(path: String, method: HTTPMethod, body: Encodable? = nil) async throws {
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = method.rawValue
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}

struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ base: Encodable) { self.encodeFunc = base.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}

protocol LocationProviding {
    func currentLocation() async -> CLLocationCoordinate2D?
}

final class LocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func currentLocation() async -> CLLocationCoordinate2D? {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            return nil
        default:
            break
        }

        manager.requestLocation()
        return await withCheckedContinuation { continuation in
            if let existing = self.continuation {
                existing.resume(returning: nil)
            }
            self.continuation = continuation
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.first?.coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }
}
