import Foundation
import UIKit

@MainActor
final class RemoteCommandViewModel: ObservableObject {
    enum CommandType { case start, stop, lock, unlock }
    enum CommandState {
        case idle
        case sending(command: CommandType)
        case success(message: String)
        case error(message: String)
    }

    struct RecentCommand: Identifiable {
        let id = UUID()
        let type: CommandType
        let timestamp: Date
        let success: Bool
    }

    @Published var state: CommandState = .idle
    @Published var recentCommands: [RecentCommand] = []
    @Published var glowPlugDiagnostics: GlowPlugDiagnostics?

    var vehicleProvider: () -> Vehicle?
    var statusProvider: () -> VehicleStatus?
    var remoteServiceProvider: () -> RemoteVehicleService
    var onStatusRefresh: () -> Void

    init(vehicleProvider: @escaping () -> Vehicle?,
         statusProvider: @escaping () -> VehicleStatus?,
         remoteServiceProvider: @escaping () -> RemoteVehicleService,
         onStatusRefresh: @escaping () -> Void) {
        self.vehicleProvider = vehicleProvider
        self.statusProvider = statusProvider
        self.remoteServiceProvider = remoteServiceProvider
        self.onStatusRefresh = onStatusRefresh
    }

    func startEngine() async { await send(command: .start) }
    func stopEngine() async { await send(command: .stop) }
    func lock() async { await send(command: .lock) }
    func unlock() async { await send(command: .unlock) }

    private func send(command: CommandType) async {
        guard let vehicle = vehicleProvider() else { return }
        guard case .idle = state else { return }
        let service = remoteServiceProvider()
        state = .sending(command: command)

        do {
            if command == .start {
                try await handleGlowPlugsIfNeeded(for: vehicle)
            }
            switch command {
            case .lock:
                try await service.sendCommand(.lock, for: vehicle)
            case .unlock:
                try await service.sendCommand(.unlock, for: vehicle)
            case .start:
                try await service.sendCommand(.start, for: vehicle)
            case .stop:
                try await service.sendCommand(.stop, for: vehicle)
            }
            onStatusRefresh()
            state = .success(message: successMessage(for: command))
            addRecent(command: command, success: true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            scheduleBannerReset()
        } catch {
            state = .error(message: "Failed to send command")
            addRecent(command: command, success: false)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            scheduleBannerReset()
        }
    }

    private func handleGlowPlugsIfNeeded(for vehicle: Vehicle) async throws {
        let engine = vehicle.engineOption ?? EngineOption.fallback(for: vehicle.fuelType)
        guard engine.needsGlowPlugs else {
            glowPlugDiagnostics = nil
            return
        }
        let temp = statusProvider()?.outsideTempF ?? 0
        let threshold = 50.0
        let shouldGlow = temp <= threshold
        let location = statusProvider()?.location ?? .init(latitude: 0, longitude: 0)
        glowPlugDiagnostics = GlowPlugDiagnostics(timestamp: Date(), outsideTempF: temp, location: location, threshold: threshold, engineName: engine.name, shouldRunGlowPlugs: shouldGlow)
        guard shouldGlow else { return }
        for remaining in stride(from: engine.glowPlugSeconds, through: 1, by: -1) {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            state = .sending(command: .start)
            print("Glow plugs warming: \(remaining)s")
        }
    }

    private func successMessage(for command: CommandType) -> String {
        switch command {
        case .lock: return "Truck locked."
        case .unlock: return "Truck unlocked."
        case .start: return "Engine start sent."
        case .stop: return "Engine stopped."
        }
    }

    private func addRecent(command: CommandType, success: Bool) {
        recentCommands.insert(RecentCommand(type: command, timestamp: Date(), success: success), at: 0)
        recentCommands = Array(recentCommands.prefix(5))
    }

    private func scheduleBannerReset() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            state = .idle
        }
    }
}
