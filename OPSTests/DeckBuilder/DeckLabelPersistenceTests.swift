//
//  DeckLabelPersistenceTests.swift
//  OPSTests
//
//  Bug 71129ae2 — labelling SEVERAL edges in one Properties visit. Every
//  pre-existing label test drives a single target, so nothing covered the
//  reporter's actual flow: three edges selected, three fields on screen,
//  focus walking field to field, each hand-off committing through
//  `setLabel` (which saves, and saving reconciles surfaces) before the next
//  field is even touched. These tests drive the production commit sequence
//  end to end and assert all three labels survive the sheet AND a reload.
//

import CoreGraphics
import XCTest
@testable import OPS

@MainActor
final class DeckLabelPersistenceTests: XCTestCase {

    // MARK: - Fixtures

    /// Closed 12'×12' square — four edges, every vertex edge-bound so
    /// `toJSON()`'s edgeless-vertex pruning can't quietly empty the reload.
    private func squareData() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 144)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        return data
    }

    private func multiLevelSquareData() -> DeckDrawingData {
        var level = DeckLevel(id: "level-a", name: "Level 1", sortOrder: 0)
        let base = squareData()
        level.vertices = base.vertices
        level.edges = base.edges

        var upper = DeckLevel(id: "level-b", name: "Level 2", sortOrder: 1)
        upper.vertices = [
            DeckVertex(id: "b1", position: CGPoint(x: 240, y: 0)),
            DeckVertex(id: "b2", position: CGPoint(x: 312, y: 0)),
            DeckVertex(id: "b3", position: CGPoint(x: 312, y: 72)),
            DeckVertex(id: "b4", position: CGPoint(x: 240, y: 72)),
        ]
        upper.edges = [
            DeckEdge(id: "be1", startVertexId: "b1", endVertexId: "b2"),
            DeckEdge(id: "be2", startVertexId: "b2", endVertexId: "b3"),
            DeckEdge(id: "be3", startVertexId: "b3", endVertexId: "b4"),
            DeckEdge(id: "be4", startVertexId: "b4", endVertexId: "b1"),
        ]

        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.levels = [level, upper]
        return data
    }

    /// Drawing data is assigned post-init (never round-tripped in): `toJSON()`
    /// prunes edgeless vertices, so building the fixture through the design's
    /// JSON would silently reshape it.
    private func viewModel(_ data: DeckDrawingData) -> DeckBuilderViewModel {
        let viewModel = DeckBuilderViewModel(deckDesign: DeckDesign(
            companyId: "company-1",
            title: "Label persistence deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        ))
        viewModel.drawingData = data
        return viewModel
    }

    /// One `CommittingDeckLabelField`'s whole lifecycle, headless: the field
    /// owns a `DeckLabelEditSession` seeded from the edge's current label,
    /// stages keystrokes as drafts, and on focus loss / submit / disappear
    /// emits at most one commit into `viewModel.setLabel(_:for:)`.
    /// Mirrors `PropertySheetView.edgeLabelField` exactly.
    private func typeAndCommit(
        _ text: String,
        edgeId: String,
        on viewModel: DeckBuilderViewModel
    ) {
        let target = DeckLabelEditTarget.edge(id: edgeId, levelId: viewModel.activeLevel?.id)
        var session = DeckLabelEditSession(sourceValue: viewModel.findEdge(byId: edgeId)?.label)
        for prefixLength in 1...text.count {
            _ = session.handle(.changed(String(text.prefix(prefixLength))))
        }
        if let commit = session.handle(.commit) {
            viewModel.setLabel(commit.value, for: target)
        }
    }

    /// The drawing as it would come back off disk — the design's persisted
    /// JSON, decoded into a fresh view model.
    private func reloaded(_ viewModel: DeckBuilderViewModel) -> DeckBuilderViewModel {
        DeckBuilderViewModel(deckDesign: DeckDesign(
            companyId: viewModel.deckDesign.companyId,
            title: viewModel.deckDesign.title,
            drawingDataJSON: viewModel.deckDesign.drawingDataJSON
        ))
    }

    // MARK: - Bug 71129ae2

    func testThreeEdgesLabelledInOneVisit_allPersistAfterReload() {
        let viewModel = viewModel(squareData())
        viewModel.selection.selectedEdgeIds = ["e1", "e2", "e3"]

        typeAndCommit("Hot tub side", edgeId: "e1", on: viewModel)
        typeAndCommit("BBQ wall", edgeId: "e2", on: viewModel)
        typeAndCommit("Gate run", edgeId: "e3", on: viewModel)

        XCTAssertEqual(viewModel.findEdge(byId: "e1")?.label, "Hot tub side")
        XCTAssertEqual(viewModel.findEdge(byId: "e2")?.label, "BBQ wall")
        XCTAssertEqual(viewModel.findEdge(byId: "e3")?.label, "Gate run")
        XCTAssertNil(viewModel.findEdge(byId: "e4")?.label)

        let reopened = reloaded(viewModel)
        XCTAssertEqual(reopened.findEdge(byId: "e1")?.label, "Hot tub side")
        XCTAssertEqual(reopened.findEdge(byId: "e2")?.label, "BBQ wall")
        XCTAssertEqual(reopened.findEdge(byId: "e3")?.label, "Gate run")
        XCTAssertNil(reopened.findEdge(byId: "e4")?.label)
    }

    func testThreeEdgesLabelledOnAMultiLevelDrawing_allPersistAfterReload() {
        let viewModel = viewModel(multiLevelSquareData())
        viewModel.activeLevelIndex = 0
        viewModel.selection.selectedEdgeIds = ["e1", "e2", "e3"]

        typeAndCommit("Hot tub side", edgeId: "e1", on: viewModel)
        typeAndCommit("BBQ wall", edgeId: "e2", on: viewModel)
        typeAndCommit("Gate run", edgeId: "e3", on: viewModel)

        let reopened = reloaded(viewModel)
        XCTAssertEqual(reopened.drawingData.levels[0].edges.first(where: { $0.id == "e1" })?.label, "Hot tub side")
        XCTAssertEqual(reopened.drawingData.levels[0].edges.first(where: { $0.id == "e2" })?.label, "BBQ wall")
        XCTAssertEqual(reopened.drawingData.levels[0].edges.first(where: { $0.id == "e3" })?.label, "Gate run")
    }

    /// Each edge is its own undo step, and unwinding them restores the
    /// labels one at a time — proof the three commits are three independent
    /// mutations rather than one clobbering write.
    func testEachEdgeLabelIsItsOwnUndoStep() {
        let viewModel = viewModel(squareData())
        viewModel.selection.selectedEdgeIds = ["e1", "e2", "e3"]

        typeAndCommit("Hot tub side", edgeId: "e1", on: viewModel)
        typeAndCommit("BBQ wall", edgeId: "e2", on: viewModel)
        typeAndCommit("Gate run", edgeId: "e3", on: viewModel)

        viewModel.undo()
        XCTAssertEqual(viewModel.findEdge(byId: "e1")?.label, "Hot tub side")
        XCTAssertEqual(viewModel.findEdge(byId: "e2")?.label, "BBQ wall")
        XCTAssertNil(viewModel.findEdge(byId: "e3")?.label)

        viewModel.undo()
        XCTAssertEqual(viewModel.findEdge(byId: "e1")?.label, "Hot tub side")
        XCTAssertNil(viewModel.findEdge(byId: "e2")?.label)

        viewModel.undo()
        XCTAssertNil(viewModel.findEdge(byId: "e1")?.label)
        XCTAssertFalse(viewModel.canUndo)
    }

    /// Re-opening the sheet and retyping the value already on the edge must
    /// not churn undo or re-save — the no-op guards in `setLabel` own this.
    func testRelabellingWithTheSameValueIsANoOp() {
        let viewModel = viewModel(squareData())
        typeAndCommit("Hot tub side", edgeId: "e1", on: viewModel)
        XCTAssertTrue(viewModel.canUndo)

        let undoDepthAfterFirst = viewModel.canUndo
        typeAndCommit("Hot tub side", edgeId: "e1", on: viewModel)

        XCTAssertEqual(viewModel.findEdge(byId: "e1")?.label, "Hot tub side")
        XCTAssertEqual(viewModel.canUndo, undoDepthAfterFirst)
        viewModel.undo()
        XCTAssertNil(viewModel.findEdge(byId: "e1")?.label)
        XCTAssertFalse(viewModel.canUndo)
    }
}
