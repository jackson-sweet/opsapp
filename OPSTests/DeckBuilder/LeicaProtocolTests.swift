// OPS/OPSTests/DeckBuilder/LeicaProtocolTests.swift

import XCTest
@testable import OPS

final class LeicaProtocolTests: XCTestCase {

    func testParseMeasurement_valid() {
        // 5.0m as IEEE 754 little-endian float
        let bytes: [UInt8] = [0x00, 0x00, 0xA0, 0x40]
        let result = LeicaProtocol.parseMeasurement(Data(bytes))
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 5.0, accuracy: 0.001)
    }

    func testParseMeasurement_smallValue() {
        // 0.5m
        let value: Float32 = 0.5
        var bytes = [UInt8](repeating: 0, count: 4)
        withUnsafeBytes(of: value) { ptr in
            for i in 0..<4 { bytes[i] = ptr[i] }
        }
        let result = LeicaProtocol.parseMeasurement(Data(bytes))
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 0.5, accuracy: 0.001)
    }

    func testParseMeasurement_tooShort() {
        let bytes: [UInt8] = [0x00, 0x00]
        let result = LeicaProtocol.parseMeasurement(Data(bytes))
        XCTAssertNil(result)
    }

    func testParseMeasurement_outOfRange() {
        // 500.0m
        let value: Float32 = 500.0
        var bytes = [UInt8](repeating: 0, count: 4)
        withUnsafeBytes(of: value) { ptr in
            for i in 0..<4 { bytes[i] = ptr[i] }
        }
        let result = LeicaProtocol.parseMeasurement(Data(bytes))
        XCTAssertNil(result)
    }

    func testIsLeicaDevice() {
        XCTAssertTrue(LeicaProtocol.isLeicaDevice(name: "DISTO D2"))
        XCTAssertTrue(LeicaProtocol.isLeicaDevice(name: "Leica DISTO X3"))
        XCTAssertFalse(LeicaProtocol.isLeicaDevice(name: "Bosch GLM 50 C"))
        XCTAssertFalse(LeicaProtocol.isLeicaDevice(name: nil))
    }
}
