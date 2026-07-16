//
//  SiteVisitDeckDesignResolverTests.swift
//  OPSTests
//
//  The visit's DECK action must CONTINUE an existing design — the visit's
//  own sketch first, then the lead's display candidate — and only report
//  nil (create-new) when the lead genuinely has no deck. Guards the fix for
//  the forking bug where the checklist's EDIT button created a second
//  design and silently re-linked.
//

import XCTest
@testable import OPS

final class SiteVisitDeckDesignResolverTests: XCTestCase {

    private let oppId = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"
    private let companyId = "a612edc0-5c18-4c4d-af97-55b9410dd077"

    private func squareJSON() -> String {
        var drawing = DeckDrawingData()
        drawing.vertices = [
            DeckVertex(id: "a", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "b", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "c", position: CGPoint(x: 100, y: 80)),
            DeckVertex(id: "d", position: CGPoint(x: 0, y: 80))
        ]
        drawing.edges = [
            DeckEdge(id: "ab", startVertexId: "a", endVertexId: "b"),
            DeckEdge(id: "bc", startVertexId: "b", endVertexId: "c"),
            DeckEdge(id: "cd", startVertexId: "c", endVertexId: "d"),
            DeckEdge(id: "da", startVertexId: "d", endVertexId: "a")
        ]
        drawing.scaleFactor = 1
        return drawing.toJSON()
    }

    private func design(
        id: String = UUID().uuidString.lowercased(),
        opportunityId: String? = nil,
        projectId: String? = nil,
        renderable: Bool = true,
        deleted: Bool = false,
        updatedAt: Date? = Date()
    ) -> DeckDesign {
        let d = DeckDesign(
            id: id,
            companyId: companyId,
            projectId: projectId,
            opportunityId: opportunityId,
            title: "Deck \(id.suffix(4))",
            drawingDataJSON: renderable ? squareJSON() : "{}"
        )
        if deleted { d.deletedAt = Date() }
        d.updatedAt = updatedAt
        return d
    }

    func test_PreferredDesignId_winsOverEverything() {
        // Bug (site-visit report) — the checklist EDIT knows exactly which
        // design it linked; that id must win over the visit sketch and the
        // lead candidate so EDIT never opens a re-derived (blank) design.
        let linked = design(opportunityId: oppId, updatedAt: Date(timeIntervalSince1970: 1_000))
        let visitSketch = design(opportunityId: oppId, updatedAt: Date(timeIntervalSince1970: 5_000))
        let leadDeck = design(opportunityId: oppId, updatedAt: Date(timeIntervalSince1970: 9_000))

        let resolved = SiteVisitDeckDesignResolver.existingDesign(
            preferredDesignId: linked.id,
            artifactDesignIds: [visitSketch.id],
            opportunityId: oppId,
            in: [linked, visitSketch, leadDeck]
        )
        XCTAssertEqual(resolved?.id, linked.id)
    }

    func test_PreferredDesignId_matchesAcrossUUIDCasing() {
        let linked = design(opportunityId: oppId)
        let resolved = SiteVisitDeckDesignResolver.existingDesign(
            preferredDesignId: linked.id.uppercased(),
            artifactDesignIds: [],
            opportunityId: oppId,
            in: [linked]
        )
        XCTAssertEqual(resolved?.id, linked.id)
    }

    func test_PreferredDesignId_deletedOrMissing_fallsThrough() {
        // A stale linked id (design since deleted) must not dead-end on nil —
        // fall through to the visit sketch / lead candidate.
        let deletedLinked = design(opportunityId: oppId, deleted: true)
        let sketch = design(opportunityId: oppId)
        let resolved = SiteVisitDeckDesignResolver.existingDesign(
            preferredDesignId: deletedLinked.id,
            artifactDesignIds: [sketch.id],
            opportunityId: oppId,
            in: [deletedLinked, sketch]
        )
        XCTAssertEqual(resolved?.id, sketch.id)
    }

    func test_VisitOwnSketch_winsOverLeadCandidate() {
        let visitSketch = design(opportunityId: oppId, updatedAt: Date(timeIntervalSince1970: 1_000))
        let newerLeadDeck = design(opportunityId: oppId, updatedAt: Date(timeIntervalSince1970: 9_000))

        let resolved = SiteVisitDeckDesignResolver.existingDesign(
            artifactDesignIds: [visitSketch.id],
            opportunityId: oppId,
            in: [visitSketch, newerLeadDeck]
        )
        XCTAssertEqual(resolved?.id, visitSketch.id,
                       "the design this visit already sketched wins, even over a newer lead deck")
    }

    func test_ArtifactId_matchesAcrossUUIDCasing() {
        let sketch = design(opportunityId: oppId)
        let resolved = SiteVisitDeckDesignResolver.existingDesign(
            artifactDesignIds: [sketch.id.uppercased()],
            opportunityId: oppId,
            in: [sketch]
        )
        XCTAssertEqual(resolved?.id, sketch.id)
    }

    func test_DeletedOrMissingArtifactDesign_fallsThroughToLeadCandidate() {
        let deletedSketch = design(opportunityId: oppId, deleted: true)
        let leadDeck = design(opportunityId: oppId)

        let resolved = SiteVisitDeckDesignResolver.existingDesign(
            artifactDesignIds: [deletedSketch.id, "ffffffff-0000-0000-0000-00000000dead"],
            opportunityId: oppId,
            in: [deletedSketch, leadDeck]
        )
        XCTAssertEqual(resolved?.id, leadDeck.id)
    }

    func test_NoVisitSketch_opensLeadDisplayCandidate_renderablePreferred() {
        let emptyButNewer = design(opportunityId: oppId, renderable: false,
                                   updatedAt: Date(timeIntervalSince1970: 9_000))
        let drawnButOlder = design(opportunityId: oppId, renderable: true,
                                   updatedAt: Date(timeIntervalSince1970: 1_000))

        let resolved = SiteVisitDeckDesignResolver.existingDesign(
            artifactDesignIds: [],
            opportunityId: oppId,
            in: [emptyButNewer, drawnButOlder]
        )
        XCTAssertEqual(resolved?.id, drawnButOlder.id,
                       "same display-candidate rule as the lead page: drawable geometry first")
    }

    func test_ConvertedLeadDeck_stillOpens() {
        let converted = design(opportunityId: oppId,
                               projectId: "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1")
        let resolved = SiteVisitDeckDesignResolver.existingDesign(
            artifactDesignIds: [],
            opportunityId: oppId,
            in: [converted]
        )
        XCTAssertEqual(resolved?.id, converted.id)
    }

    func test_OtherLeadsDecks_neverResolve() {
        let someoneElses = design(opportunityId: "ffffffff-0000-0000-0000-000000000001")
        let resolved = SiteVisitDeckDesignResolver.existingDesign(
            artifactDesignIds: [],
            opportunityId: oppId,
            in: [someoneElses]
        )
        XCTAssertNil(resolved)
    }

    func test_NoLeadBound_andNoSketch_createsNew() {
        let standalone = design(opportunityId: nil)
        let resolved = SiteVisitDeckDesignResolver.existingDesign(
            artifactDesignIds: [],
            opportunityId: nil,
            in: [standalone]
        )
        XCTAssertNil(resolved, "an unbound visit with no sketch of its own gets a fresh canvas")
    }
}
