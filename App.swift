import SwiftUI
import MapKit
import UIKit
import UserNotifications

// MARK: - Models

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case gas = "Gas"
    case diesel = "Diesel"
    var id: String { rawValue }
}

struct DieselOption: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let glowPlugSeconds: Int

    static let all: [DieselOption] = [
        DieselOption(id: "powerstroke_67", name: "Ford Power Stroke 6.7L", glowPlugSeconds: 6),
        DieselOption(id: "duramax_66", name: "GM Duramax 6.6L", glowPlugSeconds: 5),
        DieselOption(id: "cummins_67", name: "Ram Cummins 6.7L", glowPlugSeconds: 7),
        DieselOption(id: "maxxforce_75", name: "Navistar MaxxForce 7.5L", glowPlugSeconds: 8)
    ]

    static var fallback: DieselOption { all.first ?? DieselOption(id: "default", name: "Diesel", glowPlugSeconds: 5) }
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

    static func == (lhs: VehicleStatus, rhs: VehicleStatus) -> Bool {
        lhs.isLocked == rhs.isLocked &&
        lhs.engineOn == rhs.engineOn &&
        lhs.fuelPercent == rhs.fuelPercent &&
        lhs.batteryVoltage == rhs.batteryVoltage &&
        lhs.outsideTempF == rhs.outsideTempF &&
        lhs.cabinTempF == rhs.cabinTempF &&
        lhs.location.latitude == rhs.location.latitude &&
        lhs.location.longitude == rhs.location.longitude
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

// MARK: - Auth

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var accessToken: String?

    init() {
        accessToken = "DEV_BYPASS_TOKEN"
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
    @Published var showFuelSetup = false
    @Published var isRefreshing = false
    @Published private(set) var dieselSelections: [String: String] = [:]

    var remoteServiceProvider: () -> RemoteVehicleService

    private let dieselDefaultsKey = "TruckRemoteStart.DieselSelections"

    init(remoteServiceProvider: @escaping () -> RemoteVehicleService) {
        self.remoteServiceProvider = remoteServiceProvider
        if let data = UserDefaults.standard.data(forKey: dieselDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            dieselSelections = decoded
        }
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
            if type == .gas { dieselSelections[vin] = nil; persistDieselSelections() }
        } catch {
            print("Fuel update failed: \(error)")
        }
    }

    func dieselOption(for vin: String) -> DieselOption? {
        guard let id = dieselSelections[vin] else { return nil }
        return DieselOption.all.first(where: { $0.id == id })
    }

    func setDieselOption(_ option: DieselOption, for vin: String) {
        dieselSelections[vin] = option.id
        persistDieselSelections()
    }

    func send(command: VehicleCommand, fuelType: FuelType?) async {
        guard let vin = selectedVehicle?.vin else { return }
        let service = remoteServiceProvider()
        do {
            if command == .start, fuelType == .diesel {
                let option = dieselOption(for: vin) ?? DieselOption.fallback
                bannerMessage = "Cycling glow plugs for \(option.glowPlugSeconds)s…"
                try? await Task.sleep(nanoseconds: UInt64(option.glowPlugSeconds) * 1_000_000_000)
            }
            try await service.sendCommand(command, for: vin)
            try await refreshStatus()
            bannerMessage = command == .start ? "Engine start sent" : nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.bannerMessage = nil
            }
        } catch {
            print("Command failed: \(error)")
        }
    }

    func checkFuelPrompt() {
        if let vehicle = selectedVehicle, vehicle.fuelType == nil {
            showFuelSetup = true
        }
    }

    private func persistDieselSelections() {
        if let data = try? JSONEncoder().encode(dieselSelections) {
            UserDefaults.standard.set(data, forKey: dieselDefaultsKey)
        }
    }
}

@MainActor
// MARK: - Views

struct RootView: View {
    @EnvironmentObject var garageVM: GarageViewModel
    @EnvironmentObject var pushManager: PushManager
    @EnvironmentObject var configStore: ConfigStore

    @State private var selectedTab = 0

    var body: some View {
        ZStack {
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
        }
        .onAppear {
            Task { await garageVM.loadVehicles() }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var garageVM: GarageViewModel
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Controls").font(.headline)
            HStack(spacing: 12) {
                PrimaryButton(title: "Lock") { Task { await garageVM.send(command: .lock, fuelType: garageVM.selectedVehicle?.fuelType) } }
                PrimaryButton(title: "Unlock") { Task { await garageVM.send(command: .unlock, fuelType: garageVM.selectedVehicle?.fuelType) } }
            }
            HStack(spacing: 12) {
                PrimaryButton(title: "Start") {
                    Task { await garageVM.send(command: .start, fuelType: garageVM.selectedVehicle?.fuelType) }
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
    @EnvironmentObject var garageVM: GarageViewModel
    @EnvironmentObject var pushManager: PushManager

    @State private var baseURLString: String = ""
    @State private var clientId: String = ""
    @State private var redirectScheme: String = ""

    var body: some View {
        Form {
            Section(header: Text("API")) {
                TextField("Base URL", text: $baseURLString)
                    .textInputAutocapitalization(.never)
                TextField("Client ID", text: $clientId)
                TextField("Redirect Scheme", text: $redirectScheme)
                    .textInputAutocapitalization(.never)
                PrimaryButton(title: "Apply Changes") {
                    applyChanges()
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
    @EnvironmentObject var garageVM: GarageViewModel

    @State private var valetMode = false
    @State private var requireFaceID = false
    @State private var selectedVin: String?
    @State private var selectedFuel: FuelType?
    @State private var selectedDieselId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Vehicle")) {
                    if garageVM.vehicles.isEmpty {
                        Text("No vehicles available. Check your API settings to load your garage.")
                    } else {
                        Picker("Selected Vehicle", selection: Binding(
                            get: { selectedVin ?? garageVM.selectedVehicle?.vin ?? garageVM.vehicles.first?.vin ?? "" },
                            set: { newValue in
                                selectedVin = newValue
                                guard let vehicle = garageVM.vehicles.first(where: { $0.vin == newValue }) else { return }
                                garageVM.selectedVehicle = vehicle
                                selectedFuel = vehicle.fuelType ?? .gas
                                selectedDieselId = garageVM.dieselOption(for: vehicle.vin)?.id
                                Task { try? await garageVM.refreshStatus() }
                            }
                        )) {
                            ForEach(garageVM.vehicles, id: \.vin) { vehicle in
                                Text(vehicle.nickname).tag(vehicle.vin)
                            }
                        }

                        if let vehicle = garageVM.selectedVehicle ?? garageVM.vehicles.first(where: { $0.vin == selectedVin }) {
                            Picker("Fuel Type", selection: Binding(
                                get: { selectedFuel ?? vehicle.fuelType ?? .gas },
                                set: { newValue in
                                    selectedFuel = newValue
                                    Task { await garageVM.setFuel(type: newValue) }
                                })) {
                                    ForEach(FuelType.allCases) { type in
                                        Text(type.rawValue).tag(type)
                                    }
                                }

                            if (selectedFuel ?? vehicle.fuelType) == .diesel {
                                Picker(
                                    "Diesel Engine",
                                    selection: Binding(
                                        get: {
                                            selectedDieselId
                                                ?? garageVM.dieselOption(for: vehicle.vin)?.id
                                                ?? DieselOption.fallback.id
                                        },
                                        set: { newValue in
                                            selectedDieselId = newValue
                                            if let option = DieselOption.all.first(where: { $0.id == newValue }) {
                                                garageVM.setDieselOption(option, for: vehicle.vin)
                                            }
                                        }
                                    )
                                ) {
                                    ForEach(DieselOption.all) { option in
                                        Text(option.name).tag(option.id)
                                    }
                                }

                                if let option = garageVM.dieselOption(for: vehicle.vin)
                                    ?? DieselOption.all.first(where: { $0.id == selectedDieselId }) {
                                    Text("Glow plugs will cycle for \(option.glowPlugSeconds) seconds before starting.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Glow plugs will cycle for \(DieselOption.fallback.glowPlugSeconds) seconds before starting.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Security")) {
                    Toggle("Valet Mode", isOn: $valetMode)
                    Toggle("Require Face ID", isOn: $requireFaceID)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                selectedVin = garageVM.selectedVehicle?.vin ?? garageVM.vehicles.first?.vin
                selectedFuel = garageVM.selectedVehicle?.fuelType
                if let vin = garageVM.selectedVehicle?.vin {
                    selectedDieselId = garageVM.dieselOption(for: vin)?.id
                }
            }
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
                .environmentObject(pushManager)
                .environmentObject(garageVM)
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
        }
        .onChange(of: pushManager.deviceTokenHex) { _ in
            Task { await uploadPushTokenIfAuthorized() }
        }
    }

    private func configurePushUploader() {
        let client = APIClient(config: configStore.config, tokenProvider: { authManager.accessToken })
        pushManager.uploader = { hex in
            try await LiveRemoteVehicleService(client: client).uploadPushToken(hex)
        }
    }

    private func uploadPushTokenIfAuthorized() async {
        guard authManager.accessToken != nil, let token = pushManager.deviceTokenHex else { return }
        configurePushUploader()
        try? await pushManager.uploader?(token)
    }
}

// MARK: - ATS Note

/*
 App Transport Security is enabled by default. To allow local or development hosts,
 add NSAppTransportSecurity with NSAllowsArbitraryLoads set to NO and insert
 NSExceptionDomains for specific hosts only during development.
*/