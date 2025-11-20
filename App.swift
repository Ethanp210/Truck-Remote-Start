import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import MapKit
import UIKit
import UserNotifications

// MARK: - Models

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case gas = "Gas"
    case diesel = "Diesel"
    var id: String { rawValue }
}

struct Vehicle: Identifiable, Hashable, Codable {
    let id: UUID
    var vin: String
    var make: String
    var model: String
    var year: Int
    var nickname: String
    var imageName: String
    var fuelType: FuelType?
}

// IMPORTANT: No global Codable for CLLocationCoordinate2D!
struct VehicleStatus: Equatable, Codable {
    var isLocked: Bool
    var engineOn: Bool
    var fuelPercent: Double
    var batteryVoltage: Double
    var outsideTempF: Double
    var cabinTempF: Double?
    var location: CLLocationCoordinate2D

    private enum CodingKeys: String, CodingKey {
        case isLocked, engineOn, fuelPercent, batteryVoltage, outsideTempF, cabinTempF
        case location, latitude, longitude
    }
    private enum LatLonKeys: String, CodingKey { case latitude, longitude }

    init(isLocked: Bool, engineOn: Bool, fuelPercent: Double, batteryVoltage: Double,
         outsideTempF: Double, cabinTempF: Double?, location: CLLocationCoordinate2D) {
        self.isLocked = isLocked
        self.engineOn = engineOn
        self.fuelPercent = fuelPercent
        self.batteryVoltage = batteryVoltage
        self.outsideTempF = outsideTempF
        self.cabinTempF = cabinTempF
        self.location = location
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isLocked = try c.decode(Bool.self, forKey: .isLocked)
        engineOn = try c.decode(Bool.self, forKey: .engineOn)
        fuelPercent = try c.decode(Double.self, forKey: .fuelPercent)
        batteryVoltage = try c.decode(Double.self, forKey: .batteryVoltage)
        outsideTempF = try c.decode(Double.self, forKey: .outsideTempF)
        cabinTempF = try c.decodeIfPresent(Double.self, forKey: .cabinTempF)
        if let arr = try? c.decode([Double].self, forKey: .location), arr.count == 2 {
            location = .init(latitude: arr[0], longitude: arr[1])
        } else if let nested = try? c.nestedContainer(keyedBy: LatLonKeys.self, forKey: .location) {
            location = .init(latitude: try nested.decode(Double.self, forKey: .latitude),
                             longitude: try nested.decode(Double.self, forKey: .longitude))
        } else if let lat = try? c.decode(Double.self, forKey: .latitude),
                  let lon = try? c.decode(Double.self, forKey: .longitude) {
            location = .init(latitude: lat, longitude: lon)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Missing location"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isLocked, forKey: .isLocked)
        try c.encode(engineOn, forKey: .engineOn)
        try c.encode(fuelPercent, forKey: .fuelPercent)
        try c.encode(batteryVoltage, forKey: .batteryVoltage)
        try c.encode(outsideTempF, forKey: .outsideTempF)
        try c.encodeIfPresent(cabinTempF, forKey: .cabinTempF)
        try c.encode(location.latitude, forKey: .latitude)
        try c.encode(location.longitude, forKey: .longitude)
    }
}

// MARK: - Configuration

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

final class ConfigStore: ObservableObject {
    @Published var config: APIConfig {
        didSet { persist() }
    }
    private let defaultsKey = "TruckRemoteStart.APIConfig"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(APIConfig.self, from: data) {
            config = decoded
        } else {
            config = .default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

// MARK: - Keychain

final class KeychainStore {
    private let service = "com.example.TruckRemoteStart"
    private let account = "access_token"

    func setToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func token() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Presentation Anchor Provider

final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first!
        if let key = scene.windows.first(where: { $0.isKeyWindow }) { return key }
        if let any = scene.windows.first { return any }
        return UIWindow(windowScene: scene)
    }
}

// MARK: - Auth

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var accessToken: String?
    @Published var isAuthenticating = false
    private let keychain: KeychainStore
    private var session: ASWebAuthenticationSession?

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        self.accessToken = keychain.token()
    }

    func signIn(config: APIConfig) async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let verifier = Self.randomVerifier()
            let challenge = Self.challenge(for: verifier)
            let callbackURLScheme = config.redirectScheme
            var components = URLComponents(url: config.baseURL.appendingPathComponent("/oauth/authorize"), resolvingAgainstBaseURL: false)
            let scope = config.scopes.joined(separator: " ")
            components?.queryItems = [
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "client_id", value: config.clientId),
                URLQueryItem(name: "redirect_uri", value: config.redirectURI),
                URLQueryItem(name: "scope", value: scope),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256")
            ]
            guard let url = components?.url else { return }
            let anchorProvider = PresentationAnchorProvider()
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme) { [weak self] callbackURL, error in
                guard error == nil, let callbackURL else { return }
                let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value
                if let code {
                    Task { await self?.exchangeCode(code, verifier: verifier, config: config) }
                }
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = anchorProvider
            self.session = session
            session.start()
        }
    }

    func signOut() {
        accessToken = nil
        keychain.clear()
    }

    private func exchangeCode(_ code: String, verifier: String, config: APIConfig) async {
        struct TokenResponse: Decodable { let access_token: String }
        var request = URLRequest(url: config.baseURL.appendingPathComponent("/oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": config.clientId,
            "redirect_uri": config.redirectURI,
            "code_verifier": verifier
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return }
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            accessToken = tokenResponse.access_token
            keychain.setToken(tokenResponse.access_token)
        } catch {
            print("Token exchange failed: \(error)")
        }
    }

    private static func randomVerifier() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var result = ""
        for _ in 0..<64 { result.append(chars.randomElement() ?? "a") }
        return result
    }

    private static func challenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Networking

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

// MARK: - Remote Service

protocol RemoteVehicleService {
    func fetchVehicles() async throws -> [Vehicle]
    func updateFuelType(for vin: String, fuelType: FuelType) async throws -> Vehicle
    func fetchStatus(for vin: String) async throws -> VehicleStatus
    func sendCommand(_ command: VehicleCommand, for vin: String) async throws
    func uploadPushToken(_ tokenHex: String) async throws
}

enum VehicleCommand: String { case lock, unlock, start, stop, honkflash }

struct LiveRemoteVehicleService: RemoteVehicleService {
    let client: APIClient

    func fetchVehicles() async throws -> [Vehicle] {
        try await client.request("/v1/vehicles")
    }

    func updateFuelType(for vin: String, fuelType: FuelType) async throws -> Vehicle {
        struct Body: Encodable { let fuelType: FuelType }
        return try await client.request("/v1/vehicles/\(vin)", method: .patch, body: Body(fuelType: fuelType))
    }

    func fetchStatus(for vin: String) async throws -> VehicleStatus {
        try await client.request("/v1/vehicles/\(vin)/status")
    }

    func sendCommand(_ command: VehicleCommand, for vin: String) async throws {
        try await client.send(path: "/v1/vehicles/\(vin)/commands/\(command.rawValue)", method: .post)
    }

    func uploadPushToken(_ tokenHex: String) async throws {
        struct Body: Encodable { let token: String }
        try await client.send(path: "/v1/push/register", method: .post, body: Body(token: tokenHex))
    }
}

#if DEBUG
struct MockRemoteVehicleService: RemoteVehicleService {
    func fetchVehicles() async throws -> [Vehicle] {
        [Vehicle(id: UUID(), vin: "MOCKVIN123456", make: "Ford", model: "F-150", year: 2023, nickname: "Work Truck", imageName: "car.fill", fuelType: .diesel)]
    }
    func updateFuelType(for vin: String, fuelType: FuelType) async throws -> Vehicle {
        Vehicle(id: UUID(), vin: vin, make: "Ford", model: "F-150", year: 2023, nickname: "Work Truck", imageName: "car.fill", fuelType: fuelType)
    }
    func fetchStatus(for vin: String) async throws -> VehicleStatus {
        VehicleStatus(isLocked: true, engineOn: false, fuelPercent: 0.62, batteryVoltage: 12.3, outsideTempF: 72, cabinTempF: 70, location: .init(latitude: 37.3349, longitude: -122.0090))
    }
    func sendCommand(_ command: VehicleCommand, for vin: String) async throws {}
    func uploadPushToken(_ tokenHex: String) async throws {}
}
#endif

// MARK: - Push

final class PushManager: NSObject, ObservableObject {
    @Published var deviceTokenHex: String?
    var uploader: ((String) async throws -> Void)?

    func registerForPushNotifications() {
        #if targetEnvironment(simulator)
        return
        #endif
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func update(deviceTokenHex: String) {
        deviceTokenHex.withCString { _ in }
        DispatchQueue.main.async {
            self.deviceTokenHex = deviceTokenHex
            Task { try? await self.uploader?(deviceTokenHex) }
        }
    }

    func uploadManually() {
        guard let token = deviceTokenHex else { return }
        Task { try? await uploader?(token) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var sharedPushManager: PushManager?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        AppDelegate.sharedPushManager?.update(deviceTokenHex: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error)")
    }
}

// MARK: - View Models

@MainActor
final class GarageViewModel: ObservableObject {
    @Published var vehicles: [Vehicle] = []
    @Published var selectedVehicle: Vehicle?
    @Published var status: VehicleStatus?
    @Published var bannerMessage: String?
    @Published var showClimateSheet = false
    @Published var showFuelSetup = false
    @Published var isRefreshing = false

    var remoteServiceProvider: () -> RemoteVehicleService

    init(remoteServiceProvider: @escaping () -> RemoteVehicleService) {
        self.remoteServiceProvider = remoteServiceProvider
    }

    func loadVehicles() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let service = remoteServiceProvider()
            let fetched = try await service.fetchVehicles()
            vehicles = fetched
            if selectedVehicle == nil { selectedVehicle = fetched.first }
            checkFuelPrompt()
            try await refreshStatus()
        } catch {
            print("Failed to load vehicles: \(error)")
        }
    }

    func refreshStatus() async throws {
        guard let vin = selectedVehicle?.vin else { return }
        let service = remoteServiceProvider()
        status = try await service.fetchStatus(for: vin)
    }

    func setFuel(type: FuelType) async {
        guard let vin = selectedVehicle?.vin else { return }
        do {
            let service = remoteServiceProvider()
            let updated = try await service.updateFuelType(for: vin, fuelType: type)
            if let index = vehicles.firstIndex(where: { $0.vin == vin }) {
                vehicles[index] = updated
            }
            selectedVehicle = updated
            showFuelSetup = false
        } catch {
            print("Fuel update failed: \(error)")
        }
    }

    func send(command: VehicleCommand, fuelType: FuelType?) async {
        guard let vin = selectedVehicle?.vin else { return }
        let service = remoteServiceProvider()
        do {
            if command == .start, fuelType == .diesel {
                bannerMessage = "Warming glow plugs…"
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self.bannerMessage = nil
                }
            }
            try await service.sendCommand(command, for: vin)
            try await refreshStatus()
        } catch {
            print("Command failed: \(error)")
        }
    }

    func checkFuelPrompt() {
        if let vehicle = selectedVehicle, vehicle.fuelType == nil {
            showFuelSetup = true
        }
    }
}

@MainActor
final class VehicleViewModel: ObservableObject {
    @Published var climateTemp: Double = 72
    @Published var defrostOn = false
    @Published var seatHeatOn = false
    @Published var wheelHeatOn = false
}

// MARK: - Views

struct RootView: View {
    @EnvironmentObject var garageVM: GarageViewModel
    @EnvironmentObject var vehicleVM: VehicleViewModel
    @EnvironmentObject var pushManager: PushManager
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var authManager: AuthManager

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            LocationView()
                .tabItem { Label("Map", systemImage: "map" ) }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(2)
            DevSettingsView()
                .tabItem { Label("Dev", systemImage: "hammer.fill") }
                .tag(3)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $garageVM.showFuelSetup) {
            FuelSetupView()
                .environmentObject(garageVM)
        }
        .sheet(isPresented: $garageVM.showClimateSheet) {
            ClimateSheet()
                .environmentObject(vehicleVM)
                .environmentObject(garageVM)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var garageVM: GarageViewModel
    @EnvironmentObject var vehicleVM: VehicleViewModel
    @Binding var selectedTab: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let vehicle = garageVM.selectedVehicle {
                        vehicleHeader(vehicle)
                    }

                    if let status = garageVM.status {
                        StatusChips(status: status)
                    }

                    QuickControls()

                    if let status = garageVM.status {
                        statusDetails(status)
                    }

                    PrimaryButton(title: "Refresh Status", action: {
                        Task { try? await garageVM.refreshStatus() }
                    })
                }
                .padding()
            }
            .navigationTitle("Garage")
            .task {
                await garageVM.loadVehicles()
            }
            .overlay(alignment: .top) {
                if let message = garageVM.bannerMessage {
                    Banner(text: message)
                }
            }
        }
    }

    @ViewBuilder
    private func vehicleHeader(_ vehicle: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VehicleImageView(name: vehicle.imageName)
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading) {
                    Text(vehicle.nickname).font(.title2).bold()
                    Text("\(vehicle.year) \(vehicle.make) \(vehicle.model)").font(.subheadline)
                    Text("VIN: \(vehicle.vin)").font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            PrimaryButton(title: "Locate on Map") {
                selectedTab = 1
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statusDetails(_ status: VehicleStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vitals").font(.headline)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Battery: \(String(format: "%.1f", status.batteryVoltage))V")
                    if let cabin = status.cabinTempF {
                        Text("Cabin: \(Int(cabin))°F")
                    }
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct QuickControls: View {
    @EnvironmentObject var garageVM: GarageViewModel
    @EnvironmentObject var vehicleVM: VehicleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Controls").font(.headline)
            HStack(spacing: 12) {
                PrimaryButton(title: "Lock") { Task { await garageVM.send(command: .lock, fuelType: garageVM.selectedVehicle?.fuelType) } }
                PrimaryButton(title: "Unlock") { Task { await garageVM.send(command: .unlock, fuelType: garageVM.selectedVehicle?.fuelType) } }
            }
            HStack(spacing: 12) {
                PrimaryButton(title: "Start") {
                    garageVM.showClimateSheet = true
                }
                PrimaryButton(title: "Stop") { Task { await garageVM.send(command: .stop, fuelType: garageVM.selectedVehicle?.fuelType) } }
            }
            PrimaryButton(title: "Honk & Flash") { Task { await garageVM.send(command: .honkflash, fuelType: garageVM.selectedVehicle?.fuelType) } }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct StatusChips: View {
    let status: VehicleStatus
    var body: some View {
        HStack(spacing: 8) {
            StatusChip(text: status.isLocked ? "Locked" : "Unlocked", systemImage: status.isLocked ? "lock.fill" : "lock.open.fill")
            StatusChip(text: status.engineOn ? "Engine On" : "Engine Off", systemImage: "engine.combustion")
            StatusChip(text: "Fuel \(Int(status.fuelPercent * 100))%", systemImage: "fuelpump.fill")
            StatusChip(text: "\(Int(status.outsideTempF))°F", systemImage: "thermometer")
        }
    }
}

struct ClimateSheet: View {
    @EnvironmentObject var vehicleVM: VehicleViewModel
    @EnvironmentObject var garageVM: GarageViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Temperature")) {
                    Slider(value: $vehicleVM.climateTemp, in: 60...80, step: 1) {
                        Text("Cabin")
                    }
                    Text("Set to \(Int(vehicleVM.climateTemp))°F")
                }
                Section(header: Text("Comfort")) {
                    Toggle("Defrost", isOn: $vehicleVM.defrostOn)
                    Toggle("Seat Heat", isOn: $vehicleVM.seatHeatOn)
                    Toggle("Wheel Heat", isOn: $vehicleVM.wheelHeatOn)
                }
                Section {
                    PrimaryButton(title: "Start") {
                        garageVM.showClimateSheet = false
                        Task { await garageVM.send(command: .start, fuelType: garageVM.selectedVehicle?.fuelType) }
                    }
                }
            }
            .navigationTitle("Climate Start")
        }
        .presentationDetents([.medium, .large])
    }
}

struct FuelSetupView: View {
    @EnvironmentObject var garageVM: GarageViewModel
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Select Fuel Type").font(.title2).bold()
                Text("Choose the fuel type for this vehicle to personalize warming and start behavior.")
                    .multilineTextAlignment(.center)
                    .padding()
                HStack(spacing: 16) {
                    PrimaryButton(title: "Gas") { Task { await garageVM.setFuel(type: .gas) } }
                    PrimaryButton(title: "Diesel") { Task { await garageVM.setFuel(type: .diesel) } }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Fuel Setup")
        }
    }
}

struct LocationView: View {
    @EnvironmentObject var garageVM: GarageViewModel
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    var body: some View {
        VStack {
            if let status = garageVM.status {
                Map(coordinateRegion: $region, annotationItems: [VehicleLocation(coordinate: status.location)]) { item in
                    MapMarker(coordinate: item.coordinate)
                }
                .ignoresSafeArea()
                .onAppear { region = region(for: status) }
                .onChange(of: status) { newStatus in
                    region = region(for: newStatus)
                }
            } else {
                Text("Location unavailable").foregroundStyle(.secondary)
            }
        }
    }

    private func region(for status: VehicleStatus) -> MKCoordinateRegion {
        MKCoordinateRegion(center: status.location, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    }
}

struct VehicleLocation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct DevSettingsView: View {
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var garageVM: GarageViewModel
    @EnvironmentObject var pushManager: PushManager

    @State private var baseURLString: String = ""
    @State private var clientId: String = ""
    @State private var redirectScheme: String = ""

    var body: some View {
        Form {
            Section(header: Text("OAuth")) {
                TextField("Base URL", text: $baseURLString)
                    .textInputAutocapitalization(.never)
                TextField("Client ID", text: $clientId)
                TextField("Redirect Scheme", text: $redirectScheme)
                    .textInputAutocapitalization(.never)
                PrimaryButton(title: "Apply & Restart Auth") {
                    applyChanges()
                    Task { await authManager.signIn(config: configStore.config) }
                }
                PrimaryButton(title: authManager.accessToken == nil ? "Sign In" : "Sign Out") {
                    if authManager.accessToken == nil {
                        Task { await authManager.signIn(config: configStore.config) }
                    } else {
                        authManager.signOut()
                    }
                }
            }
            Section(header: Text("Push")) {
                PrimaryButton(title: "Upload Push Token Manually") {
                    pushManager.uploadManually()
                }
                if let token = pushManager.deviceTokenHex {
                    Text(token).font(.footnote).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Dev Settings")
        .onAppear {
            baseURLString = configStore.config.baseURL.absoluteString
            clientId = configStore.config.clientId
            redirectScheme = configStore.config.redirectScheme
        }
    }

    private func applyChanges() {
        guard let url = URL(string: baseURLString) else { return }
        configStore.config = APIConfig(baseURL: url, clientId: clientId, redirectScheme: redirectScheme, scopes: configStore.config.scopes)
        Task { await garageVM.loadVehicles() }
    }
}

struct SettingsView: View {
    @State private var valetMode = false
    @State private var requireFaceID = false
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Valet Mode", isOn: $valetMode)
                Toggle("Require Face ID", isOn: $requireFaceID)
            }
            .navigationTitle("Settings")
        }
    }
}

struct VehicleImageView: View {
    let name: String

    var body: some View {
        if let uiImage = UIImage(named: name) {
            Image(uiImage: uiImage)
                .resizable()
        } else if let system = UIImage(systemName: name) {
            Image(uiImage: system)
                .resizable()
        } else {
            Image(systemName: "car.fill")
                .resizable()
        }
    }
}

struct StatusChip: View {
    let text: String
    let systemImage: String
    var body: some View {
        Label(text, systemImage: systemImage)
            .padding(8)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct Banner: View {
    let text: String
    var body: some View {
        Text(text)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding()
    }
}

// MARK: - App

@main
struct TruckRemoteStartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var configStore: ConfigStore
    @StateObject private var authManager: AuthManager
    @StateObject private var pushManager = PushManager()
    @StateObject private var garageVM: GarageViewModel
    @StateObject private var vehicleVM = VehicleViewModel()

    init() {
        let configStore = ConfigStore()
        let authManager = AuthManager()
        let garageVM = GarageViewModel(remoteServiceProvider: {
            let client = APIClient(config: configStore.config, tokenProvider: { authManager.accessToken })
            return LiveRemoteVehicleService(client: client)
        })
        _configStore = StateObject(wrappedValue: configStore)
        _authManager = StateObject(wrappedValue: authManager)
        _garageVM = StateObject(wrappedValue: garageVM)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(configStore)
                .environmentObject(authManager)
                .environmentObject(pushManager)
                .environmentObject(garageVM)
                .environmentObject(vehicleVM)
                .onAppear {
                    AppDelegate.sharedPushManager = pushManager
                    configurePushUploader()
                }
                .task {
                    pushManager.registerForPushNotifications()
                }
                .onChange(of: configStore.config) { _ in
                    configurePushUploader()
                    Task { await garageVM.loadVehicles() }
                }
                .onChange(of: authManager.accessToken) { _ in
                    configurePushUploader()
                    Task { await garageVM.loadVehicles() }
                }
        }
        .onChange(of: pushManager.deviceTokenHex) { token in
            guard let token else { return }
            configurePushUploader()
            Task { try? await pushManager.uploader?(token) }
        }
    }

    private func configurePushUploader() {
        let client = APIClient(config: configStore.config, tokenProvider: { authManager.accessToken })
        pushManager.uploader = { hex in
            try await LiveRemoteVehicleService(client: client).uploadPushToken(hex)
        }
    }
}

// MARK: - ATS Note

/*
 App Transport Security is enabled by default. To allow local or development hosts,
 add NSAppTransportSecurity with NSAllowsArbitraryLoads set to NO and insert
 NSExceptionDomains for specific hosts only during development.
*/
