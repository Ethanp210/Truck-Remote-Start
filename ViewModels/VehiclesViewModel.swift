import Foundation
import CoreLocation

@MainActor
final class VehiclesViewModel: ObservableObject {
    @Published var vehicles: [Vehicle] = []
    @Published var selectedVehicle: Vehicle?
    @Published private(set) var engineSelections: [UUID: String] = [:]

    var remoteServiceProvider: () -> RemoteVehicleService
    private let engineDefaultsKey = "TruckRemoteStart.EngineSelections"

    init(remoteServiceProvider: @escaping () -> RemoteVehicleService) {
        self.remoteServiceProvider = remoteServiceProvider
        if let data = UserDefaults.standard.data(forKey: engineDefaultsKey),
           let decoded = try? JSONDecoder().decode([UUID: String].self, from: data) {
            engineSelections = decoded
        }
    }

    func loadVehicles() async {
        do {
            let service = remoteServiceProvider()
            let fetched = try await service.fetchVehicles()
            vehicles = fetched
            if selectedVehicle == nil { selectedVehicle = fetched.first }
            for vehicle in fetched {
                if let engineId = vehicle.engineId, engineSelections[vehicle.id] == nil {
                    engineSelections[vehicle.id] = engineId
                }
            }
            persistEngineSelections()
        } catch {
            print("Failed to load vehicles: \(error)")
        }
    }

    func selectVehicle(_ vehicle: Vehicle) {
        selectedVehicle = vehicle
    }

    func engineOption(for vehicleId: UUID) -> EngineOption? {
        guard let id = engineSelections[vehicleId] else { return nil }
        return EngineOption.all.first(where: { $0.id == id })
    }

    func setEngineOption(_ option: EngineOption, for vehicleId: UUID) async {
        engineSelections[vehicleId] = option.id
        persistEngineSelections()
        guard var vehicle = vehicles.first(where: { $0.id == vehicleId }) else { return }
        vehicle.engineId = option.id
        vehicle.fuelType = option.fuelType
        do {
            let service = remoteServiceProvider()
            let updated = try await service.updateVehicle(vehicle)
            if let index = vehicles.firstIndex(where: { $0.id == vehicleId }) {
                vehicles[index] = updated
            }
            if selectedVehicle?.id == vehicleId { selectedVehicle = updated }
        } catch {
            print("Failed to update engine: \(error)")
        }
    }

    func updateVehicleDetails(make: String, model: String, year: Int, nickname: String) async {
        guard var vehicle = selectedVehicle else { return }
        vehicle.make = make
        vehicle.model = model
        vehicle.year = year
        vehicle.nickname = nickname
        do {
            let service = remoteServiceProvider()
            let updated = try await service.updateVehicle(vehicle)
            if let idx = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
                vehicles[idx] = updated
            }
            selectedVehicle = updated
        } catch {
            print("Failed to update vehicle details: \(error)")
        }
    }

    private func persistEngineSelections() {
        if let data = try? JSONEncoder().encode(engineSelections) {
            UserDefaults.standard.set(data, forKey: engineDefaultsKey)
        }
    }
}
