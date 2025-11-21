import SwiftUI
import MapKit

struct HomeDashboardView: View {
    @EnvironmentObject var vehiclesViewModel: VehiclesViewModel
    @EnvironmentObject var statusViewModel: VehicleStatusViewModel
    @EnvironmentObject var commandViewModel: RemoteCommandViewModel

    @State private var showVehiclePicker = false
    @State private var showSettings = false

    private var selectedVehicle: Vehicle? { vehiclesViewModel.selectedVehicle }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    topBar
                    heroCard
                    statusCards
                    recentActivity
                }
                .padding(20)
            }
            .refreshable {
                await statusViewModel.refreshStatus(for: vehiclesViewModel.selectedVehicle)
            }
            .sheet(isPresented: $showVehiclePicker) {
                vehiclePicker
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting()).font(.footnote).foregroundColor(.secondary)
                Text("Remote Start").font(.title2).bold()
            }
            Spacer()
            Button(action: { showVehiclePicker = true }) {
                HStack(spacing: 6) {
                    Text(selectedVehicle?.nickname ?? "Select Vehicle")
                        .font(.subheadline).bold()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color.blue.opacity(0.9), Color.blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(radius: 8, y: 4)
            VStack(spacing: 20) {
                Image(systemName: "car.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 80)
                    .foregroundColor(.white)
                    .padding(.top, 24)

                HStack(spacing: 20) {
                    circleButton(title: "Lock", system: "lock.fill", action: { Task { await commandViewModel.lock() } })
                    startStopButton
                    circleButton(title: "Unlock", system: "lock.open.fill", action: { Task { await commandViewModel.unlock() } })
                }
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if case let .sending(command) = commandViewModel.state {
                progressOverlay(text: overlayText(for: command))
            }

            if case let .success(message) = commandViewModel.state {
                banner(text: message, color: .green)
            } else if case let .error(message) = commandViewModel.state {
                banner(text: message, color: .red)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
    }

    private var statusCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status").font(.title3).bold()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statusCard(title: "Fuel", icon: "fuelpump.fill", value: fuelText)
                statusCard(title: "Engine", icon: "engine.combustion", value: engineText)
                statusCard(title: "Doors", icon: "lock.fill", value: doorText)
                statusCard(title: "Battery", icon: "bolt.fill", value: batteryText)
                if let updated = statusViewModel.lastUpdatedAt {
                    statusCard(title: "Updated", icon: "clock.arrow.circlepath", value: updated.formatted(.relative(presentation: .named)))
                }
            }
            if commandViewModel.glowPlugDiagnostics?.shouldRunGlowPlugs == true {
                Text("Warming glow plugs…")
                    .font(.footnote).foregroundColor(.yellow)
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity").font(.title3).bold()
            ForEach(commandViewModel.recentCommands.prefix(5)) { command in
                HStack {
                    Image(systemName: icon(for: command.type))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text(title(for: command.type)).bold()
                        Text(command.timestamp, style: .time).font(.footnote).foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: command.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(command.success ? .green : .red)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func circleButton(title: String, system: String, action: @escaping () -> Void) -> some View {
        let disabled = isBusy
        return Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: system)
                    .font(.title)
                Text(title).font(.footnote).bold()
            }
            .frame(width: 80, height: 80)
            .background(Color.white.opacity(0.15))
            .foregroundColor(.white)
            .clipShape(Circle())
        }
        .disabled(disabled)
    }

    private var startStopButton: some View {
        let isRunning = statusViewModel.status?.engineOn == true
        return Button(action: {
            Task {
                if isRunning {
                    await commandViewModel.stopEngine()
                } else {
                    await commandViewModel.startEngine()
                }
            }
        }) {
            VStack(spacing: 6) {
                Image(systemName: "power")
                    .font(.title2)
                Text(isRunning ? "STOP" : "START")
                    .font(.headline)
            }
            .frame(width: 100, height: 100)
            .background(Color.white)
            .foregroundColor(isRunning ? .red : .blue)
            .clipShape(Circle())
            .shadow(radius: 6, y: 2)
        }
        .disabled(isBusy)
    }

    private var vehiclePicker: some View {
        NavigationStack {
            List(vehiclesViewModel.vehicles) { vehicle in
                Button {
                    vehiclesViewModel.selectVehicle(vehicle)
                    showVehiclePicker = false
                } label: {
                    HStack {
                        Text(vehicle.nickname).bold()
                        Spacer()
                        if vehiclesViewModel.selectedVehicle?.id == vehicle.id {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Select Vehicle")
        }
    }

    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var fuelText: String {
        guard let status = statusViewModel.status else { return "--" }
        let percent = Int(status.fuelPercent * 100)
        return "\(percent)%"
    }

    private var engineText: String {
        guard let status = statusViewModel.status else { return "--" }
        return status.engineOn ? "Running" : "Off"
    }

    private var doorText: String {
        guard let status = statusViewModel.status else { return "--" }
        return status.isLocked ? "Locked" : "Unlocked"
    }

    private var batteryText: String {
        guard let status = statusViewModel.status else { return "--" }
        return String(format: "%.1f V", status.batteryVoltage)
    }

    private func overlayText(for command: RemoteCommandViewModel.CommandType) -> String {
        switch command {
        case .start: return "Sending start command…"
        case .stop: return "Sending stop command…"
        case .lock: return "Locking…"
        case .unlock: return "Unlocking…"
        }
    }

    private var isBusy: Bool {
        if case .sending = commandViewModel.state { return true }
        return false
    }

    private func statusCard(title: String, icon: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title).font(.subheadline).bold()
                Spacer()
            }
            Text(value)
                .font(.title3).bold()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func banner(text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote).bold()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.85))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .padding(.bottom, 16)
    }

    private func progressOverlay(text: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text(text).font(.footnote).foregroundColor(.white)
        }
        .padding(12)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 16)
    }

    private func title(for type: RemoteCommandViewModel.CommandType) -> String {
        switch type {
        case .lock: return "Locked"
        case .unlock: return "Unlocked"
        case .start: return "Started"
        case .stop: return "Stopped"
        }
    }

    private func icon(for type: RemoteCommandViewModel.CommandType) -> String {
        switch type {
        case .lock: return "lock.fill"
        case .unlock: return "lock.open.fill"
        case .start: return "power"
        case .stop: return "stop.fill"
        }
    }
}
