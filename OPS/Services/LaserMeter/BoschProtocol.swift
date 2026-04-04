// OPS/OPS/Services/LaserMeter/BoschProtocol.swift

import Foundation
import CoreBluetooth

struct BoschProtocol {

    // MARK: - Known Service/Characteristic UUIDs
    // Bosch uses proprietary UUIDs discovered via scanning

    static let serviceUUID = CBUUID(string: "00005301-0000-0041-5253-534F46540000")
    static let measurementCharUUID = CBUUID(string: "00005302-0000-0041-5253-534F46540000")
    static let commandCharUUID = CBUUID(string: "00005303-0000-0041-5253-534F46540000")

    // MARK: - Header bytes

    private static let expectedHeader: [UInt8] = [0xC0, 0x55]

    // MARK: - Parse Measurement

    /// Parse a Bosch MT-Protocol measurement message
    /// - Parameter data: Raw BLE notification data
    /// - Returns: Measurement in meters, or nil if parsing fails
    static func parseMeasurement(_ data: Data) -> Double? {
        // Minimum message size: header(2) + length(1) + type(1) + payload
        guard data.count >= 8 else { return nil }

        let bytes = [UInt8](data)

        // Validate header
        guard bytes[0] == expectedHeader[0],
              bytes[1] == expectedHeader[1] else { return nil }

        // Check error byte (position varies by message type)
        // For measurement responses, error is typically at byte 6
        if bytes.count > 6 && bytes[6] != 0x00 {
            return nil // measurement error
        }

        // Extract current measurement (bytes 7-10, IEEE 754 float, little-endian)
        guard bytes.count >= 11 else { return nil }

        let measurementBytes = Data(bytes[7...10])
        let meters = measurementBytes.withUnsafeBytes {
            $0.load(as: Float32.self)
        }

        // Sanity check: measurement should be between 0.01m and 300m
        guard meters > 0.01 && meters < 300.0 else { return nil }

        return Double(meters)
    }

    /// Validate checksum of a Bosch message
    /// - Parameter data: Full message data including checksum
    /// - Returns: true if checksum is valid
    static func validateChecksum(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let bytes = [UInt8](data)

        // Checksum is XOR of all bytes except the last one
        var checksum: UInt8 = 0
        for i in 0..<(bytes.count - 1) {
            checksum ^= bytes[i]
        }
        return checksum == bytes[bytes.count - 1]
    }

    /// Check if a peripheral name looks like a Bosch laser meter
    static func isBoschDevice(name: String?) -> Bool {
        guard let name = name?.uppercased() else { return false }
        return name.contains("GLM") || name.contains("PLR") || name.contains("BOSCH")
    }
}
