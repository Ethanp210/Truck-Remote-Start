import SwiftUI
import MapKit
import UIKit

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
    func updateFuelType(for vehicle: Vehicle, fuelType: FuelType) async throws -> Vehicle
    func fetchStatus(for vehicle: Vehicle) async throws -> VehicleStatus
    func sendCommand(_ command: VehicleCommand, for vehicle: Vehicle) async throws
}

enum VehicleCommand: String { case lock, unlock, start, stop, honkflash }

final class LocalRemoteVehicleService: RemoteVehicleService {
    static let shared = LocalRemoteVehicleService()

    private var vehicles: [Vehicle]
    private var statuses: [UUID: VehicleStatus]

    init() {
        let defaultVehicles = [
            Vehicle(id: UUID(), make: "Ford", model: "F-150", year: 2023, nickname: "Work Truck", imageName: "car.fill", fuelType: .diesel),
            Vehicle(id: UUID(), make: "Ram", model: "1500", year: 2022, nickname: "Family Hauler", imageName: "car.2.fill", fuelType: .gas),
            Vehicle(id: UUID(), make: "GMC", model: "Sierra", year: 2021, nickname: "Trail Rig", imageName: "car.circle.fill", fuelType: .diesel)
        ]

        let defaultStatus = VehicleStatus(isLocked: true, engineOn: false, fuelPercent: 0.68, batteryVoltage: 12.4, outsideTempF: 70, cabinTempF: 68, location: .init(latitude: 37.3349, longitude: -122.0090))

        self.vehicles = defaultVehicles
        self.statuses = Dictionary(uniqueKeysWithValues: defaultVehicles.map { ($0.id, defaultStatus) })
    }

    func fetchVehicles() async throws -> [Vehicle] {
        vehicles
    }

    func updateFuelType(for vehicle: Vehicle, fuelType: FuelType) async throws -> Vehicle {
        var updated = vehicle
        updated.fuelType = fuelType
        if let idx = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[idx] = updated
        }
        return updated
    }

    func fetchStatus(for vehicle: Vehicle) async throws -> VehicleStatus {
        statuses[vehicle.id] ?? VehicleStatus(isLocked: true, engineOn: false, fuelPercent: 0.5, batteryVoltage: 12.0, outsideTempF: 70, cabinTempF: 68, location: .init(latitude: 37.3349, longitude: -122.0090))
    }

    func sendCommand(_ command: VehicleCommand, for vehicle: Vehicle) async throws {
        guard var current = statuses[vehicle.id] else { return }

        switch command {
        case .lock:
            current.isLocked = true
        case .unlock:
            current.isLocked = false
        case .start:
            current.engineOn = true
        case .stop:
            current.engineOn = false
        case .honkflash:
            break
        }

        statuses[vehicle.id] = current
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
    @Published private(set) var dieselSelections: [UUID: String] = [:]

    var remoteServiceProvider: () -> RemoteVehicleService

    private let dieselDefaultsKey = "TruckRemoteStart.DieselSelections"

    init(remoteServiceProvider: @escaping () -> RemoteVehicleService) {
        self.remoteServiceProvider = remoteServiceProvider
        if let data = UserDefaults.standard.data(forKey: dieselDefaultsKey),
           let decoded = try? JSONDecoder().decode([UUID: String].self, from: data) {
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
        guard let vehicle = selectedVehicle else { return }
        let service = remoteServiceProvider()
        status = try await service.fetchStatus(for: vehicle)
    }

    func setFuel(type: FuelType) async {
        guard let vehicle = selectedVehicle else { return }
        do {
            let service = remoteServiceProvider()
            let updated = try await service.updateFuelType(for: vehicle, fuelType: type)
            if let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
                vehicles[index] = updated
            }
            selectedVehicle = updated
            showFuelSetup = false
            if type == .gas { dieselSelections[vehicle.id] = nil; persistDieselSelections() }
        } catch {
            print("Fuel update failed: \(error)")
        }
    }

    func dieselOption(for vehicleId: UUID) -> DieselOption? {
        guard let id = dieselSelections[vehicleId] else { return nil }
        return DieselOption.all.first(where: { $0.id == id })
    }

    func setDieselOption(_ option: DieselOption, for vehicleId: UUID) {
        dieselSelections[vehicleId] = option.id
        persistDieselSelections()
    }

    func send(command: VehicleCommand, fuelType: FuelType?) async {
        guard let vehicle = selectedVehicle else { return }
        let service = remoteServiceProvider()
        do {
            if command == .start, fuelType == .diesel {
                let option = dieselOption(for: vehicle.id) ?? DieselOption.fallback
                bannerMessage = "Cycling glow plugs for \(option.glowPlugSeconds)s…"
                try? await Task.sleep(nanoseconds: UInt64(option.glowPlugSeconds) * 1_000_000_000)
            }
            try await service.sendCommand(command, for: vehicle)
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
    @State private var selectedVehicleId: UUID?
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
                            get: { selectedVehicleId ?? garageVM.selectedVehicle?.id ?? garageVM.vehicles.first?.id ?? UUID() },
                            set: { newValue in
                                selectedVehicleId = newValue
                                guard let vehicle = garageVM.vehicles.first(where: { $0.id == newValue }) else { return }
                                garageVM.selectedVehicle = vehicle
                                selectedFuel = vehicle.fuelType ?? .gas
                                selectedDieselId = garageVM.dieselOption(for: vehicle.id)?.id
                                Task { try? await garageVM.refreshStatus() }
                            }
                        )) {
                            ForEach(garageVM.vehicles, id: \.id) { vehicle in
                                Text(vehicle.nickname).tag(vehicle.id)
                            }
                        }

                        if let vehicle = garageVM.selectedVehicle ?? garageVM.vehicles.first(where: { $0.id == selectedVehicleId }) {
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
                                                ?? garageVM.dieselOption(for: vehicle.id)?.id
                                                ?? DieselOption.fallback.id
                                        },
                                        set: { newValue in
                                            selectedDieselId = newValue
                                            if let option = DieselOption.all.first(where: { $0.id == newValue }) {
                                                garageVM.setDieselOption(option, for: vehicle.id)
                                            }
                                        }
                                    )
                                ) {
                                    ForEach(DieselOption.all) { option in
                                        Text(option.name).tag(option.id)
                                    }
                                }

                                if let option = garageVM.dieselOption(for: vehicle.id)
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
                selectedVehicleId = garageVM.selectedVehicle?.id ?? garageVM.vehicles.first?.id
                selectedFuel = garageVM.selectedVehicle?.fuelType
                if let vehicleId = garageVM.selectedVehicle?.id {
                    selectedDieselId = garageVM.dieselOption(for: vehicleId)?.id
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
    @StateObject private var configStore: ConfigStore
    @StateObject private var authManager: AuthManager
    @StateObject private var garageVM: GarageViewModel

    init() {
        let configStore = ConfigStore()
        let authManager = AuthManager()
        let garageVM = GarageViewModel(remoteServiceProvider: {
            LocalRemoteVehicleService.shared
        })
        _configStore = StateObject(wrappedValue: configStore)
        _authManager = StateObject(wrappedValue: authManager)
        _garageVM = StateObject(wrappedValue: garageVM)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(configStore)
                .environmentObject(garageVM)
                .onChange(of: configStore.config) { _ in
                    Task { await garageVM.loadVehicles() }
                }
        }
    }
}

// MARK: - ATS Note

/*
 App Transport Security is enabled by default. To allow local or development hosts,
 add NSAppTransportSecurity with NSAllowsArbitraryLoads set to NO and insert
 NSExceptionDomains for specific hosts only during development.
*/