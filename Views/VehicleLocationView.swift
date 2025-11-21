import SwiftUI
import MapKit

struct VehicleLocationView: View {
    @EnvironmentObject var statusViewModel: VehicleStatusViewModel
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    var body: some View {
        NavigationStack {
            VStack {
                if let status = statusViewModel.status {
                    Map(coordinateRegion: $region, annotationItems: [VehicleLocation(coordinate: status.location)]) { item in
                        MapMarker(coordinate: item.coordinate)
                    }
                    .onAppear { region = region(for: status) }
                    .onChange(of: status) { newStatus in
                        region = region(for: newStatus)
                    }
                } else {
                    Text("Location unavailable").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Location")
            .task {
                // ensure status available
                if statusViewModel.status == nil {
                    await statusViewModel.refreshStatus(for: nil)
                }
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
