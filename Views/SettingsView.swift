import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var vehiclesViewModel: VehiclesViewModel
    @EnvironmentObject var statusViewModel: VehicleStatusViewModel

    @State private var baseURLString: String = ""
    @State private var clientId: String = ""
    @State private var redirectScheme: String = ""
    @State private var weatherURLString: String = ""
    @State private var weatherApiKey: String = ""
    @State private var fallbackTemp: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Account")) {
                    Text("Logged in via PKCE").foregroundColor(.secondary)
                }

                Section(header: Text("Developer Settings")) {
                    HStack {
                        Text("Mode")
                        Spacer()
                        Text(configStore.config.baseURL == APIConfig.default.baseURL ? "Prod" : "Dev")
                            .padding(6)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    TextField("Base URL", text: $baseURLString)
                        .textInputAutocapitalization(.never)
                    TextField("Client ID", text: $clientId)
                    TextField("Redirect Scheme", text: $redirectScheme)
                        .textInputAutocapitalization(.never)
                    Button("Apply & Restart Auth") {
                        applyChanges()
                    }
                }

                Section(header: Text("Weather")) {
                    TextField("Weather Base URL", text: $weatherURLString)
                        .textInputAutocapitalization(.never)
                    TextField("API Key (optional)", text: $weatherApiKey)
                        .textInputAutocapitalization(.never)
                    TextField("Fallback Temp (F)", text: $fallbackTemp)
                        .keyboardType(.decimalPad)
                    Button("Save Weather Settings") {
                        applyWeatherChanges()
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: loadValues)
        }
    }

    private func loadValues() {
        baseURLString = configStore.config.baseURL.absoluteString
        clientId = configStore.config.clientId
        redirectScheme = configStore.config.redirectScheme
        weatherURLString = configStore.weatherConfig.baseURL.absoluteString
        weatherApiKey = configStore.weatherConfig.apiKey ?? ""
        fallbackTemp = String(format: "%.1f", configStore.weatherConfig.fallbackTemperatureF)
    }

    private func applyChanges() {
        guard let url = URL(string: baseURLString) else { return }
        configStore.config = APIConfig(baseURL: url, clientId: clientId, redirectScheme: redirectScheme, scopes: configStore.config.scopes)
        Task {
            await vehiclesViewModel.loadVehicles()
            await statusViewModel.refreshStatus(for: vehiclesViewModel.selectedVehicle)
        }
    }

    private func applyWeatherChanges() {
        guard let url = URL(string: weatherURLString) else { return }
        let fallbackValue = Double(fallbackTemp) ?? WeatherAPIConfig.default.fallbackTemperatureF
        configStore.weatherConfig = WeatherAPIConfig(baseURL: url, apiKey: weatherApiKey.isEmpty ? nil : weatherApiKey, fallbackTemperatureF: fallbackValue)
    }
}
