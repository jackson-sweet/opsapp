//
//  BugReportPointAtItSnapshotTests.swift
//  OPSTests
//
//  Visual proof for bug 14e5a792 — POINT AT IT picks on the live app:
//
//    · the pick layer armed over a real screen (bar only, app untouched)
//    · the pick layer with a finger on a house button: outline, dim, tag
//    · the pick layer with a finger on a plain line of text
//    · the report sheet after a pick: SPOT MARKED, the element's name, and
//      the pick-time screenshot with the element outlined
//    · the enlarged screenshot, outlined
//
//  Everything is rendered in the app host's own window, with the real probe,
//  Vision and resolution pipeline — no staged answers.
//
//  Extract: xcrun xcresulttool export attachments --path <result>.xcresult --output-path <dir>
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class BugReportPointAtItSnapshotTests: XCTestCase {

    private func attach(_ image: UIImage, _ name: String) {
        guard let data = image.pngData() else {
            return XCTFail("Failed to encode \(name)")
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SNAPSHOT \(name) (\(Int(image.size.width))x\(Int(image.size.height))pt)")
    }

    /// The representative screen, pick mode on, Vision finished.
    private func armedStage() async throws -> (BugReportPickStage, BugReportPickSession) {
        BugReportPickMode.shared.deactivate()
        let stage = try BugReportPickStage(BugReportPickRepresentativeScreen())
        BugReportPickMode.shared.activate()
        await stage.settle()

        let session = BugReportPickSession(
            appWindow: stage.window,
            screenName: "Leads",
            capture: { _ in stage.render() }
        )
        session.arm()
        await BugReportPickProbeReadout.awaitText(session)
        XCTAssertTrue(session.linesReady)
        return (stage, session)
    }

    private func layer(for session: BugReportPickSession) -> BugReportPickLayer {
        BugReportPickLayer(session: session, onCancel: {}, onLift: { _ in })
    }

    func testPickLayerArmedOverTheLiveScreen() async throws {
        let (stage, session) = try await armedStage()
        defer {
            stage.tearDown()
            BugReportPickMode.shared.deactivate()
        }
        stage.overlay(layer(for: session))
        await stage.settle(minimum: 0.4)
        XCTAssertNil(session.target, "Nothing is outlined before a finger lands")
        attach(stage.render(), "pick-layer-armed")
    }

    func testPickLayerOutlinesAButtonAndTagsIt() async throws {
        let (stage, session) = try await armedStage()
        defer {
            stage.tearDown()
            BugReportPickMode.shared.deactivate()
        }
        stage.overlay(layer(for: session))
        await stage.settle(minimum: 0.3)

        let probes = BugReportPickProbeReadout.probes(in: stage.window)
        let button = try XCTUnwrap(probes.first { $0.role == .button && $0.component == "ButtonStyles" })
        session.track(at: BugReportPickProbeReadout.centre(of: button, in: stage.window))
        await stage.settle(minimum: 0.4)

        let target = try XCTUnwrap(session.target)
        XCTAssertEqual(target.role, .button)
        print("PICK TAG: \(target.tagText)")
        attach(stage.render(), "pick-layer-button")
    }

    func testPickLayerOnAPlainLineOfText() async throws {
        let (stage, session) = try await armedStage()
        defer {
            stage.tearDown()
            BugReportPickMode.shared.deactivate()
        }
        stage.overlay(layer(for: session))
        await stage.settle(minimum: 0.3)

        let header = try XCTUnwrap(session.lines.first { $0.text.uppercased().contains("THIS WEEK") })
        session.track(at: CGPoint(x: header.frame.midX, y: header.frame.midY))
        await stage.settle(minimum: 0.4)

        let target = try XCTUnwrap(session.target)
        XCTAssertEqual(target.source, .text)
        print("PICK TAG: \(target.tagText)")
        attach(stage.render(), "pick-layer-text")
    }

    func testTheReportSheetComesBackWithTheOutlinedPick() async throws {
        let (stage, session) = try await armedStage()
        // Idempotent — the explicit teardown below hands the window back
        // before the sheet renders; this one covers an early throw.
        defer {
            stage.tearDown()
            BugReportPickMode.shared.deactivate()
        }
        let probes = BugReportPickProbeReadout.probes(in: stage.window)
        let start = try XCTUnwrap(probes.first { $0.label == "START" })
        let spot = try await XCTUnwrapAsync(
            await session.commit(at: BugReportPickProbeReadout.centre(of: start, in: stage.window))
        )
        let trigger = stage.render()
        stage.tearDown()
        BugReportPickMode.shared.deactivate()

        let draft = BugReportDraft(
            triggerScreenshot: trigger,
            description: "START does nothing on this visit",
            category: .bug
        )
        draft.mark(spot.element, screenshot: spot.screenshot)
        XCTAssertEqual(draft.element?.resolution.cardText, "START · BUTTON")

        let sheet = try FixedSizeSnapshot.render(
            BugReportSheet(draft: draft, onClose: {}, onPointAtIt: {})
                .environmentObject(AppState())
                .environmentObject(DataController())
                .environment(\.colorScheme, .dark),
            size: CGSize(width: 390, height: 700),
            minimumSettle: 0.3
        )
        attach(sheet, "report-sheet-after-pick")

        let viewer = try FixedSizeSnapshot.render(
            BugReportScreenshotViewer(
                image: draft.screenshot,
                element: draft.element,
                onClose: {}
            )
            .environment(\.colorScheme, .dark),
            size: CGSize(width: 390, height: 844),
            minimumSettle: 0.2
        )
        attach(viewer, "viewer-with-outline")
    }
}
#endif
