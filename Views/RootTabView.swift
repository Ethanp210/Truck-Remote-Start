import SwiftUI
import MapKit

struct RootTabView: View {
    @EnvironmentObject var vehiclesViewModel: VehiclesViewModel
    @EnvironmentObject var statusViewModel: VehicleStatusViewModel
    @EnvironmentObject var commandViewModel: RemoteCommandViewModel

    var body: some View {
        TabView {
            HomeDashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            VehicleDetailsView()
                .tabItem { Label("Vehicle", systemImage: "car.fill") }
            VehicleLocationView()
                .tabItem { Label("Location", systemImage: "location.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .onAppear {
            Task { await vehiclesViewModel.loadVehicles() }
            Task { await statusViewModel.refreshStatus(for: vehiclesViewModel.selectedVehicle) }
        }
        .onChange(of: vehiclesViewModel.selectedVehicle) { vehicle in
            Task { await statusViewModel.refreshStatus(for: vehicle) }
        }
    }
}
