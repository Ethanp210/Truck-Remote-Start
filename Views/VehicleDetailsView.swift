import SwiftUI

struct VehicleDetailsView: View {
    @EnvironmentObject var vehiclesViewModel: VehiclesViewModel
    @EnvironmentObject var statusViewModel: VehicleStatusViewModel

    var body: some View {
        NavigationStack {
            List {
                if let vehicle = vehiclesViewModel.selectedVehicle {
                    Section(header: Text("Vehicle")) {
                        detailRow(title: "Nickname", value: vehicle.nickname)
                        detailRow(title: "Make", value: vehicle.make)
                        detailRow(title: "Model", value: vehicle.model)
                        detailRow(title: "Year", value: String(vehicle.year))
                        if let fuel = vehicle.fuelType { detailRow(title: "Fuel", value: fuel.rawValue) }
                        if let engine = vehicle.engineOption { detailRow(title: "Engine", value: engine.name) }
                    }
                }

                if let status = statusViewModel.status {
                    Section(header: Text("Status")) {
                        detailRow(title: "Fuel", value: "\(Int(status.fuelPercent * 100))%")
                        detailRow(title: "Engine", value: status.engineOn ? "Running" : "Off")
                        detailRow(title: "Locked", value: status.isLocked ? "Yes" : "No")
                        detailRow(title: "Battery", value: String(format: "%.1f V", status.batteryVoltage))
                        detailRow(title: "Outside Temp", value: String(format: "%.0f°F", status.outsideTempF))
                    }
                }
            }
            .navigationTitle("Vehicle")
            .refreshable {
                await statusViewModel.refreshStatus(for: vehiclesViewModel.selectedVehicle)
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}
