// OPS/OPS/Services/LaserMeter/LeicaProtocol.swift

import Foundation
import CoreBluetooth

struct LeicaProtocol {

    // MARK: - Known Service/Characteristic UUIDs (official Leica DISTO GATT)

    static let serviceUUID = CBUUID(string: "3AB10100-F831-4395-B29D-570977D5AE94")
    static let measurementCharUUID = CBUUID(string: "3AB10101-F831-4395-B29D-570977D5AE94")

    // MARK: - Parse Measurement

    /// Parse a Leica DISTO measurement notification
    /// - Parameter data: Raw BLE notification data (4 bytes, IEEE 754 float)
    /// - Returns: Measurement in meters, or nil if parsing fails
    static func parseMeasurement(_ data: Data) -> Double? {
        // Leica sends a simple 4-byte IEEE 754 float in meters
        guard data.count >= 4 else { return nil }

        let meters = data.withUnsafeBytes {
            $0.load(as: Float32.self)
        }

        // Sanity check
        guard meters > 0.01 && meters < 300.0 else { return nil }

        return Double(meters)
    }

    /// Check if a peripheral name looks like a Leica laser meter
    static func isLeicaDevice(name: String?) -> Bool {
        guard let name = name?.uppercased() else { return false }
        return name.contains("DISTO") || name.contains("LEICA")
    }
}
