import Foundation
import CoreLocation

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case gas = "Gas"
    case diesel = "Diesel"
    var id: String { rawValue }
}

struct EngineOption: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let fuelType: FuelType
    let glowPlugSeconds: Int

    var needsGlowPlugs: Bool { fuelType == .diesel }

    static let all: [EngineOption] = [
        EngineOption(id: "gas_v8", name: "Gasoline V8", fuelType: .gas, glowPlugSeconds: 0),
        EngineOption(id: "gas_v6", name: "Gasoline V6", fuelType: .gas, glowPlugSeconds: 0),
        EngineOption(id: "powerstroke_67", name: "Ford Power Stroke 6.7L", fuelType: .diesel, glowPlugSeconds: 6),
        EngineOption(id: "duramax_66", name: "GM Duramax 6.6L", fuelType: .diesel, glowPlugSeconds: 5),
        EngineOption(id: "cummins_67", name: "Ram Cummins 6.7L", fuelType: .diesel, glowPlugSeconds: 7),
        EngineOption(id: "maxxforce_75", name: "Navistar MaxxForce 7.5L", fuelType: .diesel, glowPlugSeconds: 8)
    ]

    static var fallback: EngineOption { all.first ?? EngineOption(id: "default", name: "Gasoline", fuelType: .gas, glowPlugSeconds: 0) }

    static func fallback(for fuelType: FuelType?) -> EngineOption {
        if let fuelType, let match = all.first(where: { $0.fuelType == fuelType }) {
            return match
        }
        return fallback
    }
}

struct Vehicle: Identifiable, Hashable, Codable {
    let id: UUID
    var make: String
    var model: String
    var year: Int
    var nickname: String
    var imageName: String
    var fuelType: FuelType?
    var engineId: String?

    var engineOption: EngineOption? {
        guard let engineId else { return nil }
        return EngineOption.all.first(where: { $0.id == engineId })
    }
}

struct VehicleStatus: Equatable, Codable {
    var isLocked: Bool
    var engineOn: Bool
    var fuelPercent: Double
    var batteryVoltage: Double
    var outsideTempF: Double
    var cabinTempF: Double?
    var location: CLLocationCoordinate2D

    private enum CodingKeys: String, CodingKey {
        case isLocked, engineOn, fuelPercent, batteryVoltage, outsideTempF, cabinTempF
        case location, latitude, longitude
    }
    private enum LatLonKeys: String, CodingKey { case latitude, longitude }

    init(isLocked: Bool, engineOn: Bool, fuelPercent: Double, batteryVoltage: Double,
         outsideTempF: Double, cabinTempF: Double?, location: CLLocationCoordinate2D) {
        self.isLocked = isLocked
        self.engineOn = engineOn
        self.fuelPercent = fuelPercent
        self.batteryVoltage = batteryVoltage
        self.outsideTempF = outsideTempF
        self.cabinTempF = cabinTempF
        self.location = location
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isLocked = try c.decode(Bool.self, forKey: .isLocked)
        engineOn = try c.decode(Bool.self, forKey: .engineOn)
        fuelPercent = try c.decode(Double.self, forKey: .fuelPercent)
        batteryVoltage = try c.decode(Double.self, forKey: .batteryVoltage)
        outsideTempF = try c.decode(Double.self, forKey: .outsideTempF)
        cabinTempF = try c.decodeIfPresent(Double.self, forKey: .cabinTempF)
        if let arr = try? c.decode([Double].self, forKey: .location), arr.count == 2 {
            location = .init(latitude: arr[0], longitude: arr[1])
        } else if let nested = try? c.nestedContainer(keyedBy: LatLonKeys.self, forKey: .location) {
            location = .init(latitude: try nested.decode(Double.self, forKey: .latitude),
                             longitude: try nested.decode(Double.self, forKey: .longitude))
        } else if let lat = try? c.decode(Double.self, forKey: .latitude),
                  let lon = try? c.decode(Double.self, forKey: .longitude) {
            location = .init(latitude: lat, longitude: lon)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Missing location"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isLocked, forKey: .isLocked)
        try c.encode(engineOn, forKey: .engineOn)
        try c.encode(fuelPercent, forKey: .fuelPercent)
        try c.encode(batteryVoltage, forKey: .batteryVoltage)
        try c.encode(outsideTempF, forKey: .outsideTempF)
        try c.encodeIfPresent(cabinTempF, forKey: .cabinTempF)
        try c.encode(location.latitude, forKey: .latitude)
        try c.encode(location.longitude, forKey: .longitude)
    }

    static func == (lhs: VehicleStatus, rhs: VehicleStatus) -> Bool {
        lhs.isLocked == rhs.isLocked &&
        lhs.engineOn == rhs.engineOn &&
        lhs.fuelPercent == rhs.fuelPercent &&
        lhs.batteryVoltage == rhs.batteryVoltage &&
        lhs.outsideTempF == rhs.outsideTempF &&
        lhs.cabinTempF == rhs.cabinTempF &&
        lhs.location.latitude == rhs.location.latitude &&
        lhs.location.longitude == rhs.location.longitude
    }
}

struct GlowPlugDiagnostics {
    let timestamp: Date
    let outsideTempF: Double
    let location: CLLocationCoordinate2D
    let threshold: Double
    let engineName: String
    let shouldRunGlowPlugs: Bool
}

enum VehicleCommand: String { case lock, unlock, start, stop, honkflash }
