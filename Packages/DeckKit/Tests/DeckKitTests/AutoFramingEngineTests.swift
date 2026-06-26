import CoreGraphics
import XCTest
@testable import DeckKit

final class AutoFramingEngineTests: XCTestCase {
    func test_generate_rectangleMemberCounts() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        let preset = LoadPreset(species: .douglasFirLarch, grade: .no1)

        let plan = AutoFramingEngine.generate(from: data, preset: preset)
        let members = plan.members.flatMap(\.members)

        XCTAssertEqual(plan.generationSource, .auto)
        XCTAssertEqual(members.filter { $0.role == .ledger }.count, 1)
        XCTAssertEqual(members.filter { $0.role == .rimBand }.count, 3)
        XCTAssertEqual(members.filter { $0.role == .beam }.count, 1)
        XCTAssertGreaterThanOrEqual(members.filter { $0.role == .post }.count, 2)
        XCTAssertEqual(members.filter { $0.role == .joist }.count, 10)
        XCTAssertTrue(members.allSatisfy { $0.sizing == nil })
        XCTAssertTrue(members.allSatisfy { $0.species == .douglasFirLarch })
        XCTAssertTrue(members.allSatisfy { $0.grade == .no1 })
    }

    func test_generate_freestandingTwoBeams() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .freestanding, dimensions: [144, 120]))

        let plan = AutoFramingEngine.generate(from: data, preset: LoadPreset())
        let members = plan.members.flatMap(\.members)

        XCTAssertEqual(members.filter { $0.role == .ledger }.count, 0)
        XCTAssertEqual(members.filter { $0.role == .beam }.count, 2)
    }

    func test_generate_multiLevelPerLevelSets() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .multiLevel, dimensions: [144, 96, 120, 84]))

        let plan = AutoFramingEngine.generate(from: data, preset: LoadPreset())

        XCTAssertEqual(plan.members.count, 2)
        XCTAssertEqual(Set(plan.members.map(\.levelId)), Set(data.levels.map(\.id)))
        XCTAssertTrue(plan.members.allSatisfy { !$0.members.isEmpty })
    }

    func test_regenerate_preservesLockedMember() throws {
        var data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        let preset = LoadPreset()
        var existing = AutoFramingEngine.generate(from: data, preset: preset)
        let setIndex = try XCTUnwrap(existing.members.firstIndex(where: { $0.levelId == "" }))
        let beamIndex = try XCTUnwrap(existing.members[setIndex].members.firstIndex(where: { $0.role == .beam }))
        let originalBeamId = existing.members[setIndex].members[beamIndex].id
        existing.members[setIndex].members[beamIndex].locked = true
        existing.members[setIndex].members[beamIndex].nominalSize = .fourBySix
        data.vertices[2].position.x += 12

        let regenerated = AutoFramingEngine.regenerate(from: data, existing: existing, preset: preset)
        let members = regenerated.members.flatMap(\.members)
        let lockedBeam = try XCTUnwrap(members.first(where: { $0.id == originalBeamId }))

        XCTAssertEqual(regenerated.generationSource, .autoThenEdited)
        XCTAssertTrue(lockedBeam.locked)
        XCTAssertEqual(lockedBeam.nominalSize, .fourBySix)
    }

    func test_regenerate_allUnlockedIsPureAuto() throws {
        var data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        let preset = LoadPreset()
        let existing = AutoFramingEngine.generate(from: data, preset: preset)
        data.vertices[2].position.x += 12

        let regenerated = AutoFramingEngine.regenerate(from: data, existing: existing, preset: preset)

        XCTAssertEqual(regenerated.generationSource, .auto)
        XCTAssertFalse(regenerated.members.flatMap(\.members).contains(where: \.locked))
    }

    func test_generate_lShapeClipsJoistsToPolygon() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .lShape, dimensions: [144, 120, 48, 48]))
        let polygon = data.vertices.map(\.position)

        let plan = AutoFramingEngine.generate(from: data, preset: LoadPreset())
        let joists = plan.members.flatMap(\.members).filter { $0.role == .joist }

        XCTAssertGreaterThan(joists.count, 0)
        XCTAssertTrue(joists.allSatisfy { pointIsInsideOrOn($0.start, polygon: polygon) })
        XCTAssertTrue(joists.allSatisfy { pointIsInsideOrOn($0.end, polygon: polygon) })
    }

    func test_generate_neverSetsSizing() throws {
        let fixtures = [
            DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]),
            DeckTemplateEngine.generate(template: .freestanding, dimensions: [144, 120]),
            DeckTemplateEngine.generate(template: .lShape, dimensions: [144, 120, 48, 48]),
        ]

        for data in try fixtures.map({ try XCTUnwrap($0) }) {
            let plan = AutoFramingEngine.generate(from: data, preset: LoadPreset())
            XCTAssertTrue(plan.members.flatMap(\.members).allSatisfy { $0.sizing == nil })
        }
    }

    private func pointIsInsideOrOn(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        if PolygonMath.pointInPolygon(point, vertices: polygon) { return true }
        return polygon.indices.contains { index in
            let next = (index + 1) % polygon.count
            return PolygonMath.closestPointOnSegment(
                point: point,
                segStart: polygon[index],
                segEnd: polygon[next]
            ).distance < 0.0001
        }
    }
}
