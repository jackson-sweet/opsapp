import CoreGraphics
import XCTest
@testable import DeckKit

final class OverheadSizingCoordinatorTests: XCTestCase {
    func testPergolaSizesBeamsRaftersAndPostsViaStructuralEngine() throws {
        let structure = pergolaStructure()
        let result = OverheadSizingCoordinator.size(
            structure,
            load: sampleLoad(),
            package: samplePackage()
        )

        XCTAssertNil(result.blocked)
        XCTAssertEqual(result.assumptions.liveLoadPSF, 40, accuracy: 0.001)
        XCTAssertEqual(result.assumptions.deadLoadPSF, 10, accuracy: 0.001)
        XCTAssertEqual(result.assumptions.species, .douglasFirLarch)
        XCTAssertEqual(result.assumptions.grade, .no1)
        XCTAssertEqual(result.assumptions.packageEdition, "IRC 2021 / DCA6-12")

        let beam = try XCTUnwrap(result.structure.framing.first { $0.id == "beam-1" })
        let rafter = try XCTUnwrap(result.structure.framing.first { $0.id == "rafter-1" })
        let post = try XCTUnwrap(result.structure.framing.first { $0.id == "post-1" })

        assertSized(
            beam.sizing,
            size: .twoByTen,
            plyCount: 2,
            allowableSpanFeet: 14,
            actualSpanFeet: 12,
            codeSection: "AWC DCA6 beam table"
        )
        assertSized(
            rafter.sizing,
            size: .twoBySix,
            plyCount: 1,
            allowableSpanFeet: 12,
            actualSpanFeet: 10,
            codeSection: "AWC DCA6 rafter table"
        )
        assertSized(
            post.sizing,
            size: .sixBySix,
            plyCount: 1,
            allowableSpanFeet: 8,
            actualSpanFeet: 8,
            codeSection: "IRC R507.4 post height table"
        )
    }

    func testSolidRoofHardStopsAppendixHAndEmitsNoMemberSizes() throws {
        let structure = OverheadStructure(
            kind: .solidRoof,
            roofShape: .shed,
            framing: pergolaStructure().framing
        )

        let result = OverheadSizingCoordinator.size(
            structure,
            load: LoadPreset(liveLoadPSF: 40, deadLoadPSF: 15, snowLoadPSF: 30),
            package: samplePackage()
        )

        let blocked = try XCTUnwrap(result.blocked)
        XCTAssertTrue(blocked.codeSection.contains("Appendix H"))
        XCTAssertTrue(blocked.limitingCheck.localizedCaseInsensitiveContains("roof-cover"))
        XCTAssertTrue(result.structure.framing.allSatisfy { $0.sizing == nil })
    }

    func testLouveredRoofProductHardStopsToManufacturerStampedTables() throws {
        let structure = OverheadStructure(
            kind: .louveredRoof,
            roofShape: .shed,
            framing: pergolaStructure().framing,
            productModel: "StruXure pergola X"
        )

        let result = OverheadSizingCoordinator.size(
            structure,
            load: sampleLoad(),
            package: samplePackage()
        )

        let blocked = try XCTUnwrap(result.blocked)
        XCTAssertTrue(blocked.codeSection.localizedCaseInsensitiveContains("manufacturer"))
        XCTAssertTrue(blocked.limitingCheck.localizedCaseInsensitiveContains("stamped"))
        XCTAssertTrue(result.structure.framing.allSatisfy { $0.sizing == nil })
    }

    func testReusesStructuralSizingEngineForIndividualMembers() throws {
        let structure = pergolaStructure()
        let package = samplePackage()
        let load = sampleLoad()

        let result = OverheadSizingCoordinator.size(
            structure,
            load: load,
            package: package
        )

        let beam = try XCTUnwrap(structure.framing.first { $0.id == "beam-1" })
        let post = try XCTUnwrap(structure.framing.first { $0.id == "post-1" })
        let sizedBeam = try XCTUnwrap(result.structure.framing.first { $0.id == "beam-1" })
        let sizedPost = try XCTUnwrap(result.structure.framing.first { $0.id == "post-1" })

        XCTAssertEqual(
            sizedBeam.sizing,
            StructuralSizingEngine.beamSizing(member: beam, load: load, package: package)
        )
        XCTAssertEqual(
            sizedPost.sizing,
            StructuralSizingEngine.postSizing(member: post, load: load, package: package)
        )
    }

    func testMissingPackageRowsHardStopPerMemberWithoutFabricatingSizes() throws {
        let result = OverheadSizingCoordinator.size(
            pergolaStructure(),
            load: sampleLoad(),
            package: CodePackage(
                jurisdictionId: "US-IRC",
                edition: "IRC 2021"
            )
        )

        XCTAssertNil(result.blocked)
        let beam = try XCTUnwrap(result.structure.framing.first { $0.id == "beam-1" })
        let post = try XCTUnwrap(result.structure.framing.first { $0.id == "post-1" })

        guard case let .outOfEnvelope(beamReason, beamCitation) = beam.sizing?.outcome else {
            return XCTFail("Expected missing beam rows to hard-stop the member.")
        }
        guard case let .outOfEnvelope(postReason, postCitation) = post.sizing?.outcome else {
            return XCTFail("Expected missing post rows to hard-stop the member.")
        }

        XCTAssertTrue(beamReason.contains("No beam span table"))
        XCTAssertTrue(postReason.contains("No post height table"))
        XCTAssertEqual(beamCitation.packageEdition, "IRC 2021")
        XCTAssertEqual(postCitation.packageEdition, "IRC 2021")
    }

    func testZeroLengthPostHardStopsInsteadOfAssumingHeight() throws {
        let structure = OverheadStructure(
            kind: .pergola,
            framing: [
                FramingMember(
                    id: "post-without-height",
                    role: .post,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: 0),
                    nominalSize: .sixBySix,
                    species: .douglasFirLarch,
                    grade: .no1
                ),
            ]
        )

        let result = OverheadSizingCoordinator.size(
            structure,
            load: sampleLoad(),
            package: samplePackage()
        )
        let post = try XCTUnwrap(result.structure.framing.first)

        guard case let .outOfEnvelope(reason, citation) = post.sizing?.outcome else {
            return XCTFail("Expected zero-length post to hard-stop for missing height.")
        }

        XCTAssertTrue(reason.localizedCaseInsensitiveContains("height"))
        XCTAssertEqual(citation.codeSection, "IRC R507.4 / package post table")
    }

    func testOlderCodePackageJSONDecodesWithEmptyOverheadTables() throws {
        let data = Data("""
        {
          "jurisdictionId": "US-IRC",
          "edition": "IRC 2021"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(CodePackage.self, from: data)

        XCTAssertEqual(decoded.beamSpanTable, [])
        XCTAssertEqual(decoded.postHeightTable, [])
        XCTAssertEqual(decoded.envelopeLimits, EnvelopeLimits())
    }

    private func pergolaStructure() -> OverheadStructure {
        OverheadStructure(
            id: "pergola-1",
            kind: .pergola,
            framing: [
                FramingMember(
                    id: "beam-1",
                    role: .beam,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 144, y: 0),
                    nominalSize: .twoByTen,
                    plyCount: 2,
                    species: .douglasFirLarch,
                    grade: .no1
                ),
                FramingMember(
                    id: "rafter-1",
                    role: .joist,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: 120),
                    nominalSize: .twoBySix,
                    species: .douglasFirLarch,
                    grade: .no1
                ),
                FramingMember(
                    id: "post-1",
                    role: .post,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: 96),
                    nominalSize: .sixBySix,
                    species: .douglasFirLarch,
                    grade: .no1
                ),
            ]
        )
    }

    private func samplePackage() -> CodePackage {
        CodePackage(
            jurisdictionId: "US-IRC",
            edition: "IRC 2021 / DCA6-12",
            publishedDate: Date(timeIntervalSince1970: 0),
            unitSystem: .imperial,
            beamSpanTable: [
                BeamSpanSizingRow(
                    role: .beam,
                    size: .twoByTen,
                    plyCount: 2,
                    species: .douglasFirLarch,
                    grade: .no1,
                    maxSpanFeet: 14,
                    codeSection: "AWC DCA6 beam table",
                    limitingCheck: "beam span table"
                ),
                BeamSpanSizingRow(
                    role: .joist,
                    size: .twoBySix,
                    plyCount: 1,
                    species: .douglasFirLarch,
                    grade: .no1,
                    maxSpanFeet: 12,
                    codeSection: "AWC DCA6 rafter table",
                    limitingCheck: "rafter span table"
                ),
            ],
            postHeightTable: [
                PostHeightSizingRow(
                    size: .sixBySix,
                    species: .douglasFirLarch,
                    grade: .no1,
                    maxHeightFeet: 8,
                    codeSection: "IRC R507.4 post height table",
                    limitingCheck: "post height table"
                ),
            ]
        )
    }

    private func sampleLoad() -> LoadPreset {
        LoadPreset(
            liveLoadPSF: 40,
            deadLoadPSF: 10,
            snowLoadPSF: nil,
            species: .douglasFirLarch,
            grade: .no1
        )
    }

    private func assertSized(
        _ result: MemberSizingResult?,
        size: LumberSize,
        plyCount: Int,
        allowableSpanFeet: Double,
        actualSpanFeet: Double,
        codeSection: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .ok(value, citation, assumptions) = result?.outcome else {
            return XCTFail("Expected ok sizing.", file: file, line: line)
        }

        XCTAssertEqual(value.size, size, file: file, line: line)
        XCTAssertEqual(value.plyCount, plyCount, file: file, line: line)
        XCTAssertEqual(value.allowableSpanFeet, allowableSpanFeet, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(value.actualSpanFeet, actualSpanFeet, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(value.utilization, actualSpanFeet / allowableSpanFeet, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(citation.codeSection, codeSection, file: file, line: line)
        XCTAssertEqual(assumptions.packageEdition, "IRC 2021 / DCA6-12", file: file, line: line)
    }
}
