// OPS/OPSTests/DeckBuilder/BoschProtocolTests.swift

import XCTest
@testable import OPS

final class BoschProtocolTests: XCTestCase {

    func testParseMeasurement_validMessage() {
        // Construct a valid Bosch message with a 5.0m measurement
        // IEEE 754 float for 5.0 = 0x40A00000 (big-endian) = 0x0000A040 (little-endian)
        var bytes: [UInt8] = [
            0xC0, 0x55, 0x10, 0x0A, 0x08, // header
            0x01,                           // sequence
            0x00,                           // error = no error
            0x00, 0x00, 0xA0, 0x40,        // 5.0m (little-endian IEEE 754)
            0x00, 0x00, 0xA0, 0x40,        // min (same)
            0x00, 0x00, 0xA0, 0x40,        // max (same)
        ]
        // Add checksum (XOR of all bytes)
        var checksum: UInt8 = 0
        for b in bytes { checksum ^= b }
        bytes.append(checksum)

        let data = Data(bytes)
        let result = BoschProtocol.parseMeasurement(data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 5.0, accuracy: 0.001)
    }

    func testParseMeasurement_badHeader() {
        let bytes: [UInt8] = [0xAA, 0xBB, 0x10, 0x0A, 0x08, 0x01, 0x00, 0x00, 0x00, 0xA0, 0x40]
        let result = BoschProtocol.parseMeasurement(Data(bytes))
        XCTAssertNil(result)
    }

    func testParseMeasurement_errorByte() {
        let bytes: [UInt8] = [0xC0, 0x55, 0x10, 0x0A, 0x08, 0x01, 0x01, 0x00, 0x00, 0xA0, 0x40]
        let result = BoschProtocol.parseMeasurement(Data(bytes))
        XCTAssertNil(result) // error byte = 0x01
    }

    func testParseMeasurement_tooShort() {
        let bytes: [UInt8] = [0xC0, 0x55, 0x10]
        let result = BoschProtocol.parseMeasurement(Data(bytes))
        XCTAssertNil(result)
    }

    func testParseMeasurement_outOfRange() {
        // 999.0m -- way too far
        // IEEE 754 for 999.0 = 0x4479C000 (big) = 0x00C07944 (little)
        let bytes: [UInt8] = [0xC0, 0x55, 0x10, 0x0A, 0x08, 0x01, 0x00, 0x00, 0xC0, 0x79, 0x44]
        let result = BoschProtocol.parseMeasurement(Data(bytes))
        XCTAssertNil(result) // > 300m sanity check
    }

    func testIsBoschDevice() {
        XCTAssertTrue(BoschProtocol.isBoschDevice(name: "Bosch GLM 50 C"))
        XCTAssertTrue(BoschProtocol.isBoschDevice(name: "GLM 100 C"))
        XCTAssertTrue(BoschProtocol.isBoschDevice(name: "PLR 40 C"))
        XCTAssertFalse(BoschProtocol.isBoschDevice(name: "DISTO D2"))
        XCTAssertFalse(BoschProtocol.isBoschDevice(name: nil))
    }

    func testValidateChecksum_valid() {
        var bytes: [UInt8] = [0xC0, 0x55, 0x10]
        var checksum: UInt8 = 0
        for b in bytes { checksum ^= b }
        bytes.append(checksum)
        XCTAssertTrue(BoschProtocol.validateChecksum(Data(bytes)))
    }

    func testValidateChecksum_invalid() {
        let bytes: [UInt8] = [0xC0, 0x55, 0x10, 0xFF] // wrong checksum
        XCTAssertFalse(BoschProtocol.validateChecksum(Data(bytes)))
    }
}
