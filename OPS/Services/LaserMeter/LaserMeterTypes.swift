// OPS/OPS/Services/LaserMeter/LaserMeterTypes.swift

import Foundation
import CoreBluetooth

enum LaserMeterBrand: String, Codable {
    case bosch
    case leica
    case generic

    var displayName: String {
        switch self {
        case .bosch: return "Bosch"
        case .leica: return "Leica"
        case .generic: return "Laser Meter"
        }
    }

    var iconName: String {
        switch self {
        case .bosch: return "ruler"
        case .leica: return "ruler"
        case .generic: return "antenna.radiowaves.left.and.right"
        }
    }
}

enum LaserConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case reconnecting
}

struct DiscoveredLaserDevice: Identifiable {
    let id: UUID           // CBPeripheral.identifier
    let name: String
    let brand: LaserMeterBrand
    let rssi: Int          // signal strength
    let peripheral: CBPeripheral
}

struct LaserMeasurement {
    let meters: Double
    let inches: Double
    let timestamp: Date
    let brand: LaserMeterBrand

    init(meters: Double, brand: LaserMeterBrand) {
        self.meters = meters
        self.inches = meters * 39.3701
        self.timestamp = Date()
        self.brand = brand
    }
}

struct SavedLaserDevice: Codable {
    let peripheralId: String   // UUID string
    let name: String
    let brand: LaserMeterBrand
}
