import Foundation
import CoreLocation

@MainActor
final class VehicleStatusViewModel: ObservableObject {
    @Published var status: VehicleStatus?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastUpdatedAt: Date?

    private let remoteServiceProvider: () -> RemoteVehicleService

    init(remoteServiceProvider: @escaping () -> RemoteVehicleService) {
        self.remoteServiceProvider = remoteServiceProvider
    }

    func refreshStatus(for vehicle: Vehicle?) async {
        guard let vehicle else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let service = remoteServiceProvider()
            let fetched = try await service.fetchStatus(for: vehicle)
            status = fetched
            lastUpdatedAt = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load status"
        }
    }
}
