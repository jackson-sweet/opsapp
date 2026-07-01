import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit

final class PermitMetaRoundTripTests: XCTestCase {
    func testPermitMetaEncodeDecodeStableWithCachedComplianceReport() throws {
        var data = DeckDrawingData()
        data.permitMeta = PermitMeta(
            jurisdictionId: "US-IRC",
            codeEdition: "IRC 2021 / DCA6-12",
            setbacks: SetbackInput(
                propertyLines: [
                    CGPoint(x: 0, y: 0),
                    CGPoint(x: 240, y: 0),
                    CGPoint(x: 240, y: 180),
                    CGPoint(x: 0, y: 180),
                ],
                requiredSetbackFeet: 5,
                ahjVerified: false
            ),
            disclaimerAcknowledgedAt: Date(timeIntervalSince1970: 1_788_220_800),
            lastComplianceRunAt: Date(timeIntervalSince1970: 1_788_221_100),
            lastComplianceResult: ComplianceReport(
                mode: .design,
                packageEdition: "IRC 2021 / DCA6-12",
                generatedAt: Date(timeIntervalSince1970: 1_788_221_100),
                findings: [],
                summaryStatement: ComplianceStrings.noFailures,
                disclaimer: ComplianceStrings.disclaimer
            ),
            peStampRequest: PEStampRequest(
                requested: true,
                reason: "Beam span exceeds packaged table envelope.",
                requestedAt: Date(timeIntervalSince1970: 1_788_221_200)
            )
        )

        let json1 = data.toJSON()
        let back = try XCTUnwrap(DeckDrawingData.fromJSON(json1))
        let json2 = back.toJSON()

        XCTAssertEqual(json1, json2)
        XCTAssertEqual(back.permitMeta?.jurisdictionId, "US-IRC")
        XCTAssertEqual(back.permitMeta?.setbacks?.propertyLines.count, 4)
        XCTAssertEqual(back.permitMeta?.lastComplianceResult?.summaryStatement, ComplianceStrings.noFailures)
        XCTAssertEqual(back.permitMeta?.peStampRequest?.requested, true)
    }

    func testMinimalP1PermitMetaDecodesIntoFullP7Shape() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "permitMeta": {
            "jurisdictionId": "CA-BC",
            "codeEdition": "BCBC 2024 Part 9"
          }
        }
        """

        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertEqual(decoded.permitMeta?.jurisdictionId, "CA-BC")
        XCTAssertEqual(decoded.permitMeta?.codeEdition, "BCBC 2024 Part 9")
        XCTAssertNil(decoded.permitMeta?.setbacks)
        XCTAssertNil(decoded.permitMeta?.lastComplianceResult)
        XCTAssertNil(decoded.permitMeta?.peStampRequest)
    }

    func testMalformedPermitMetaDecodesNilWithoutDroppingRestOfDesign() throws {
        let json = """
        {
          "vertices": [
            {"id":"v1","position":[0,0]},
            {"id":"v2","position":[120,0]},
            {"id":"v3","position":[120,96]},
            {"id":"v4","position":[0,96]}
          ],
          "edges": [
            {"id":"e1","startVertexId":"v1","endVertexId":"v2"},
            {"id":"e2","startVertexId":"v2","endVertexId":"v3"},
            {"id":"e3","startVertexId":"v3","endVertexId":"v4"},
            {"id":"e4","startVertexId":"v4","endVertexId":"v1"}
          ],
          "permitMeta": {
            "jurisdictionId": ["not", "a", "string"],
            "setbacks": "not-an-object"
          }
        }
        """

        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertNil(decoded.permitMeta)
        XCTAssertEqual(decoded.vertices.count, 4)
        XCTAssertEqual(decoded.edges.count, 4)
    }

    func testP7PermitMetaBlockIsPreservedAcrossDecodeReencode() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "permitMeta": {
            "jurisdictionId": "US-IRC",
            "codeEdition": "IRC 2021 / DCA6-12",
            "lastComplianceResult": {
              "mode": "design",
              "packageEdition": "IRC 2021 / DCA6-12",
              "generatedAt": 1788221100,
              "findings": [],
              "summaryStatement": "no code failures detected",
              "disclaimer": "This is not a guarantee of full code adherence. Have plans reviewed by a licensed engineer in your jurisdiction."
            }
          }
        }
        """

        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        let reencodedObject = try DeckJSONValue.parseObject(from: decoded.toJSON())

        guard case .object(let permitMeta)? = reencodedObject["permitMeta"] else {
            return XCTFail("permitMeta must remain present after a P7 round trip")
        }
        XCTAssertEqual(permitMeta["jurisdictionId"], .string("US-IRC"))
        XCTAssertEqual(permitMeta["codeEdition"], .string("IRC 2021 / DCA6-12"))
        XCTAssertNotNil(permitMeta["lastComplianceResult"])
    }

    func testPermitMetaStampsSchemaVersion7WhenPresent() {
        var data = DeckDrawingData()
        data.permitMeta = PermitMeta(jurisdictionId: "US-IRC", codeEdition: "IRC 2021 / DCA6-12")

        let stamped = DeckSchemaMigration.stampFramingVersion(data)

        XCTAssertEqual(DeckSchemaMigration.currentSchemaVersion, 7)
        XCTAssertEqual(stamped.schemaVersion, 7)
    }

    func testCapabilitiesKeepPermitGradeWorkFullOnly() {
        XCTAssertFalse(DeckCapabilities.light.contains(.compliance))
        XCTAssertFalse(DeckCapabilities.light.contains(.permitPlanSet))
        XCTAssertFalse(DeckCapabilities.light.contains(.peStamp))

        XCTAssertTrue(DeckCapabilities.full.contains(.compliance))
        XCTAssertTrue(DeckCapabilities.full.contains(.permitPlanSet))
        XCTAssertTrue(DeckCapabilities.full.contains(.peStamp))
    }
}
