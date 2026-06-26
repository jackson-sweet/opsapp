import XCTest
@testable import DeckKit

final class EngineEnvelopeCodableTests: XCTestCase {
    func test_engineOutcome_ok_roundTripsWithStableDiscriminator() throws {
        let citation = EngineCitation(
            limitingCheck: "deflection L/360",
            codeSection: "IRC R507.6",
            packageEdition: "IRC 2021 / DCA6-12"
        )
        let assumptions = EngineAssumptions(
            liveLoadPSF: 40,
            deadLoadPSF: 10,
            snowLoadPSF: nil,
            species: .sprucePineFir,
            grade: .no2,
            soilBearingPSF: nil,
            packageEdition: "IRC 2021 / DCA6-12"
        )
        let sized = SizedMember(
            size: .twoByEight,
            plyCount: 1,
            allowableSpanFeet: 12,
            actualSpanFeet: 10,
            utilization: 0.83
        )
        let outcome = EngineOutcome<SizedMember>.ok(
            value: sized,
            citation: citation,
            assumptions: assumptions
        )

        let encoded = try JSONEncoder.sorted.encode(outcome)
        let object = try DeckJSONValue.parseObject(from: String(decoding: encoded, as: UTF8.self))

        XCTAssertEqual(object["case"], DeckJSONValue.string("ok"))
        XCTAssertEqual(try JSONDecoder().decode(EngineOutcome<SizedMember>.self, from: encoded), outcome)
    }

    func test_engineOutcome_outOfEnvelope_roundTripsWithReasonAndCitation() throws {
        let citation = EngineCitation(
            limitingCheck: "span table envelope",
            codeSection: "AWC DCA6 Table 4",
            packageEdition: "DCA6-12"
        )
        let outcome = EngineOutcome<SizedMember>.outOfEnvelope(
            reason: "Span exceeds table envelope.",
            citation: citation
        )

        let encoded = try JSONEncoder.sorted.encode(outcome)
        let decoded = try JSONDecoder().decode(EngineOutcome<SizedMember>.self, from: encoded)

        XCTAssertEqual(decoded, outcome)
    }

    func test_memberSizingResult_optionalOnFramingMember_roundTrips() throws {
        let nilSizingMember = FramingMember(
            id: "joist-nil-sizing",
            role: .joist,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: 120),
            nominalSize: .twoByEight,
            spacingInchesOC: 16,
            species: .sprucePineFir,
            grade: .no2
        )
        XCTAssertNil(try roundTrip(nilSizingMember).sizing)

        let citation = EngineCitation(
            limitingCheck: "deflection L/360",
            codeSection: "IRC R507.6",
            packageEdition: "IRC 2021 / DCA6-12"
        )
        let assumptions = EngineAssumptions(
            liveLoadPSF: 40,
            deadLoadPSF: 10,
            snowLoadPSF: nil,
            species: .sprucePineFir,
            grade: .no2,
            soilBearingPSF: nil,
            packageEdition: "IRC 2021 / DCA6-12"
        )
        let sizing = MemberSizingResult(
            outcome: .ok(
                value: SizedMember(
                    size: .twoByEight,
                    plyCount: 1,
                    allowableSpanFeet: 12,
                    actualSpanFeet: 10,
                    utilization: 0.83
                ),
                citation: citation,
                assumptions: assumptions
            )
        )
        var sizedMember = nilSizingMember
        sizedMember.sizing = sizing

        XCTAssertEqual(try roundTrip(sizedMember), sizedMember)
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: try JSONEncoder.sorted.encode(value))
    }
}
