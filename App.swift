import SwiftUI
import MapKit

@main
struct TruckRemoteStartApp: App {
    @StateObject private var configStore: ConfigStore
    @StateObject private var authManager: AuthManager
    @StateObject private var vehiclesViewModel: VehiclesViewModel
    @StateObject private var statusViewModel: VehicleStatusViewModel
    @StateObject private var commandViewModel: RemoteCommandViewModel

    init() {
        let configStore = ConfigStore()
        let authManager = AuthManager()
        let remoteService = LocalRemoteVehicleService(weatherConfigProvider: { configStore.weatherConfig })
        let vehiclesVM = VehiclesViewModel(remoteServiceProvider: { remoteService })
        let statusVM = VehicleStatusViewModel(remoteServiceProvider: { remoteService })
        let commandVM = RemoteCommandViewModel(
            vehicleProvider: { vehiclesVM.selectedVehicle },
            statusProvider: { statusVM.status },
            remoteServiceProvider: { remoteService },
            onStatusRefresh: { Task { await statusVM.refreshStatus(for: vehiclesVM.selectedVehicle) } }
        )

        _configStore = StateObject(wrappedValue: configStore)
        _authManager = StateObject(wrappedValue: authManager)
        _vehiclesViewModel = StateObject(wrappedValue: vehiclesVM)
        _statusViewModel = StateObject(wrappedValue: statusVM)
        _commandViewModel = StateObject(wrappedValue: commandVM)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(configStore)
                .environmentObject(authManager)
                .environmentObject(vehiclesViewModel)
                .environmentObject(statusViewModel)
                .environmentObject(commandViewModel)
        }
    }
}
