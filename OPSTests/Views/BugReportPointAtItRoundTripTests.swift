//
//  BugReportPointAtItRoundTripTests.swift
//  OPSTests
//
//  Bug 14e5a792 — the whole POINT AT IT round trip through the REAL
//  presenter: the report sheet steps aside, the pick layer comes up over the
//  live app, the finger lifts on an element, and the sheet comes back with the
//  mark — holding everything the operator had already typed. The pieces are
//  proven elsewhere (resolution, probes, snapshots); this proves the sequence
//  that joins them, which is the part an operator actually lives through.
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class BugReportPointAtItRoundTripTests: XCTestCase {

    func testTheSheetStepsAsideForThePickAndComesBackWithTheMark() async throws {
        let (stage, presenter) = try await presentReport()

        presenter.testingDraft?.description = "START JOB does nothing"
        let pointingStarted = Date()
        presenter.beginPointing()
        try await waitUntil("the pick layer is up and the sheet is down") {
            presenter.testingPickLayerIsUp && !presenter.testingSheetIsUp
        }
        await stage.settle()

        // A person takes longer to reach the problem than Vision takes to read
        // the screen. Lifting before the read finishes is the instant tap the
        // session deliberately bounds at `textWaitLimit` (named by role, not
        // by its words), and on a loaded simulator the read can outlast that
        // bound. So aim like a person: wait for the read, then prove it saw
        // the button's words, so a blank or misread capture fails here, by name.
        try await waitUntil("Vision has read the pick-time capture", limit: 30) {
            presenter.testingRecognizedText != nil
        }
        let read = presenter.testingRecognizedText ?? []
        let readSeconds = Date().timeIntervalSince(pointingStarted)
        XCTContext.runActivity(named: String(format: "Pick-time capture read %.2f s after POINT AT IT", readSeconds)) { _ in }
        XCTAssertTrue(
            read.contains { $0.text.uppercased().contains("START JOB") },
            "Vision must read the button's words off the pick-time capture; it read \(read.map(\.text))"
        )

        // The house button in the fixture card carries no explicit label, so
        // its name has to come from what is written on it.
        let probes: [BugReportProbeView] = BugReportPickProbeReadout.probes(in: stage.window)
        let unlabelledButtons: [BugReportProbeView] = probes.filter { probe in
            probe.role == .button && probe.label == nil
        }
        let button: BugReportProbeView = try XCTUnwrap(
            unlabelledButtons.first,
            "the house button mounted no probe while picking"
        )
        let centre: CGPoint = BugReportPickProbeReadout.centre(of: button, in: stage.window)
        presenter.testingLift(at: centre)

        try await waitUntil("the sheet is back with the mark", limit: 15) {
            presenter.testingSheetIsUp
                && !presenter.testingPickLayerIsUp
                && presenter.testingDraft?.element != nil
        }

        let draft = try XCTUnwrap(presenter.testingDraft)
        let pick = try XCTUnwrap(draft.element)
        XCTAssertEqual(pick.resolution.role, .button)
        XCTAssertEqual(pick.resolution.source, .component)
        XCTAssertTrue(
            pick.resolution.label.uppercased().contains("START JOB"),
            "recorded label: \(pick.resolution.label)"
        )
        XCTAssertEqual(draft.description, "START JOB does nothing", "the typed report must survive the pick")
        XCTAssertNotNil(draft.spot?.screenshot, "the report carries the pick-time capture")
        XCTAssertFalse(BugReportPickMode.shared.isActive, "pick mode ends when the sheet returns")

        await close(presenter, stage)
    }

    func testCancellingThePickBringsTheSheetBackUnmarked() async throws {
        let (stage, presenter) = try await presentReport()

        presenter.testingDraft?.description = "kept"
        presenter.beginPointing()
        try await waitUntil("the pick layer is up") { presenter.testingPickLayerIsUp }

        presenter.testingCancelPick()
        try await waitUntil("the sheet is back") {
            presenter.testingSheetIsUp && !presenter.testingPickLayerIsUp
        }

        XCTAssertNil(presenter.testingDraft?.element)
        XCTAssertEqual(presenter.testingDraft?.description, "kept")
        XCTAssertFalse(BugReportPickMode.shared.isActive)

        await close(presenter, stage)
    }

    // MARK: - Harness

    private func presentReport() async throws -> (BugReportPickStage, BugReportPresenter) {
        let stage = try BugReportPickStage(BugReportPickRepresentativeScreen())
        await stage.settle()
        let presenter = BugReportPresenter.shared
        if presenter.isPresenting {
            presenter.dismiss()
            try await waitUntil("a leftover report is gone") { !presenter.isPresenting }
        }
        presenter.present(
            screenshot: stage.render(),
            appState: AppState(),
            dataController: DataController()
        )
        try await waitUntil("the report sheet is up") { presenter.testingSheetIsUp }
        return (stage, presenter)
    }

    private func close(_ presenter: BugReportPresenter, _ stage: BugReportPickStage) async {
        presenter.dismiss()
        try? await waitUntil("the report is torn down") { !presenter.isPresenting }
        stage.tearDown()
    }

    /// Bounded poll that yields the main actor between checks — UIKit's
    /// presentation callbacks and the session's Vision hop both need it.
    private func waitUntil(
        _ what: String,
        limit: TimeInterval = 6,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let end = Date(timeIntervalSinceNow: limit)
        while !condition() {
            if Date() > end {
                XCTFail("timed out waiting until \(what)")
                throw XCTSkip("timed out: \(what)")
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
#endif
