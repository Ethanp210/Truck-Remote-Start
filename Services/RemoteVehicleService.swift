import Foundation
import CoreLocation
import MapKit

protocol RemoteVehicleService {
    func fetchVehicles() async throws -> [Vehicle]
    func updateFuelType(for vehicle: Vehicle, fuelType: FuelType) async throws -> Vehicle
    func updateVehicle(_ vehicle: Vehicle) async throws -> Vehicle
    func fetchStatus(for vehicle: Vehicle) async throws -> VehicleStatus
    func sendCommand(_ command: VehicleCommand, for vehicle: Vehicle) async throws
}

final class LocalRemoteVehicleService: RemoteVehicleService {
    private var vehicles: [Vehicle]
    private var statuses: [UUID: VehicleStatus]
    private let locationProvider: LocationProviding
    private let weatherConfigProvider: () -> WeatherAPIConfig

    private var weatherClient: WeatherClient { WeatherClient(config: weatherConfigProvider()) }

    init(locationProvider: LocationProviding = LocationProvider(),
         weatherConfigProvider: @escaping () -> WeatherAPIConfig = { .default }) {
        self.locationProvider = locationProvider
        self.weatherConfigProvider = weatherConfigProvider
        let defaultVehicles = [
            Vehicle(id: UUID(), make: "Ford", model: "F-150", year: 2023, nickname: "Work Truck", imageName: "car.fill", fuelType: .diesel, engineId: EngineOption.all.first?.id),
            Vehicle(id: UUID(), make: "Ram", model: "1500", year: 2022, nickname: "Family Hauler", imageName: "car.2.fill", fuelType: .gas, engineId: EngineOption.all.first(where: { $0.fuelType == .gas })?.id),
            Vehicle(id: UUID(), make: "GMC", model: "Sierra", year: 2021, nickname: "Trail Rig", imageName: "car.circle.fill", fuelType: .diesel, engineId: EngineOption.all.first(where: { $0.needsGlowPlugs })?.id)
        ]

        let defaultStatus = VehicleStatus(isLocked: true, engineOn: false, fuelPercent: 0.68, batteryVoltage: 12.4, outsideTempF: 70, cabinTempF: nil, location: .init(latitude: 37.3349, longitude: -122.0090))

        self.vehicles = defaultVehicles
        self.statuses = Dictionary(uniqueKeysWithValues: defaultVehicles.map { ($0.id, defaultStatus) })
    }

    func fetchVehicles() async throws -> [Vehicle] { vehicles }

    func updateVehicle(_ vehicle: Vehicle) async throws -> Vehicle {
        if let idx = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[idx] = vehicle
        }
        return vehicle
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
        var baseStatus = statuses[vehicle.id] ?? VehicleStatus(isLocked: true, engineOn: false, fuelPercent: 0.5, batteryVoltage: 12.0, outsideTempF: 70, cabinTempF: nil, location: .init(latitude: 37.3349, longitude: -122.0090))

        if let liveLocation = await locationProvider.currentLocation() {
            baseStatus.location = liveLocation
            statuses[vehicle.id] = baseStatus
        }

        let updatedTemp = await weatherClient.temperature(for: baseStatus.location)
        baseStatus.outsideTempF = updatedTemp
        baseStatus.cabinTempF = nil
        return baseStatus
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
