//
//  BugReportPickableTests.swift
//  OPSTests
//
//  Bug 14e5a792 — POINT AT IT on the live app, proven in the app host's own
//  window rather than assumed:
//
//    · `.bugReportPickable` adds nothing — no view, no pixel, no layout —
//      while no pick is running, and mounts a probe on every house component
//      while one is.
//    · On a representative screen (ScrollView, glass card, FormField, house
//      button, the site-visit banner's hand-built verbs) the pick names what
//      the finger is on, by role and label, with Vision supplying the words.
//    · A covering sheet, a faded-out subtree, a scroll view's clipped
//      overflow and a parked keep-alive tab can never win.
//
//  The PICK PROBES log lines are the on-simulator record of the ordering and
//  visibility measurements (depth, cumulative alpha, clip, frontmost root).
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class BugReportPickableTests: XCTestCase {

    // MARK: - Helpers

    private func allViews(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { allViews(in: $0) }
    }

    private func probeViews(in view: UIView) -> [BugReportProbeView] {
        allViews(in: view).compactMap { $0 as? BugReportProbeView }
    }

    private func candidates(at point: CGPoint, in window: UIWindow) -> [BugReportProbeCandidate] {
        BugReportProbeCollector.candidates(
            at: point,
            in: window,
            probes: BugReportPickProbeReadout.probes(in: window)
        )
    }

    private func winner(at point: CGPoint, in window: UIWindow, _ label: String) -> BugReportProbeCandidate? {
        let measured = candidates(at: point, in: window)
        BugReportPickProbeReadout.log("\(label) \(point)", measured)
        return BugReportPickResolver.frontmostProbe(at: point, among: measured)
    }

    // MARK: - Nothing while not picking

    /// A plain sample, with and without the modifier, rendered twice.
    private struct Sample: View {
        let marked: Bool

        var body: some View {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                row("SCHEDULE", role: .row)
                row("START", role: .button)
                row("CLIENT NAME", role: .field)
            }
            .padding(OPSStyle.Layout.spacing4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(OPSStyle.Colors.background)
        }

        @ViewBuilder
        private func row(_ text: String, role: BugReportPickRole) -> some View {
            let base = Text(text)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.text)
                .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.surfaceInput)
            if marked {
                base.bugReportPickable(role, label: text)
            } else {
                base
            }
        }
    }

    func testPickableAddsNothingWhileNoPickIsRunning() async throws {
        BugReportPickMode.shared.deactivate()

        let marked = try BugReportPickStage(Sample(marked: true))
        await marked.settle()
        let markedViews = allViews(in: marked.container.view).count
        let markedProbes = probeViews(in: marked.container.view).count
        let markedSize = marked.container.children.first?.view.intrinsicContentSize
        let markedPixels = marked.render().pngData()
        marked.tearDown()

        let plain = try BugReportPickStage(Sample(marked: false))
        await plain.settle()
        let plainViews = allViews(in: plain.container.view).count
        let plainSize = plain.container.children.first?.view.intrinsicContentSize
        let plainPixels = plain.render().pngData()
        plain.tearDown()

        print("PICKABLE OFF: views marked=\(markedViews) plain=\(plainViews)")
        XCTAssertEqual(markedProbes, 0, "No probe may exist outside a pick session")
        XCTAssertEqual(markedViews, plainViews, "The modifier must add no UIView — no representable, no host")
        XCTAssertEqual(markedSize, plainSize, "The modifier must not change layout")
        XCTAssertNotNil(markedPixels)
        XCTAssertEqual(markedPixels, plainPixels, "The modifier must not change a single pixel")
        XCTAssertTrue(BugReportPickMode.shared.registeredProbes.isEmpty)
    }

    func testHouseComponentsMountProbesOnlyWhilePicking() async throws {
        BugReportPickMode.shared.deactivate()
        let stage = try BugReportPickStage(BugReportPickRepresentativeScreen())
        defer {
            stage.tearDown()
            BugReportPickMode.shared.deactivate()
        }
        await stage.settle()
        XCTAssertEqual(probeViews(in: stage.container.view).count, 0)

        BugReportPickMode.shared.activate()
        await stage.settle()
        let probes = BugReportPickProbeReadout.probes(in: stage.window)
        for probe in probes {
            print("PROBE \(probe.role.rawValue) '\(probe.label ?? "—")' \(probe.component ?? "—") \(BugReportPickProbeReadout.frame(of: probe, in: stage.window).integral)")
        }
        XCTAssertTrue(
            probes.contains { $0.role == .field && $0.label == "Client name" && $0.component == "FormInputs" },
            "FormField must name itself by its title"
        )
        XCTAssertTrue(probes.contains { $0.role == .button && $0.component == "ButtonStyles" })
        XCTAssertTrue(probes.contains { $0.role == .card && $0.component == "GlassSurface" })
        XCTAssertTrue(probes.contains { $0.role == .card && $0.component == "BooksCommandKit" })
        for verb in ["START", "REBOOK", "CANCEL"] {
            XCTAssertTrue(
                probes.contains { $0.role == .button && $0.label == verb && $0.component == "LeadSiteVisitBanner" },
                "The banner's \(verb) verb must be pickable by name"
            )
        }

        BugReportPickMode.shared.deactivate()
        await stage.settle()
        XCTAssertEqual(
            probeViews(in: stage.container.view).count, 0,
            "Ending the session must unmount every probe"
        )
    }

    // MARK: - The representative screen

    func testAPickOnTheLiveScreenNamesWhatTheFingerIsOn() async throws {
        // Per-step timeline, attached to the result: this case once took 491 s
        // in a full run while every step in it is bounded, so where the time
        // goes is recorded rather than guessed.
        let started = Date()
        var timeline: [String] = []
        func mark(_ step: String) {
            timeline.append(String(format: "%8.2fs  %@", Date().timeIntervalSince(started), step))
        }

        BugReportPickMode.shared.deactivate()
        let stage = try BugReportPickStage(BugReportPickRepresentativeScreen())
        defer {
            stage.tearDown()
            BugReportPickMode.shared.deactivate()
            mark("teardown")
            let attachment = XCTAttachment(string: timeline.joined(separator: "\n"))
            attachment.name = "pick-live-screen-timeline.txt"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("PICK TIMELINE\n\(timeline.joined(separator: "\n"))")
        }
        mark("stage hosted")
        BugReportPickMode.shared.activate()
        await stage.settle()
        mark("settled with probes")

        let session = BugReportPickSession(
            appWindow: stage.window,
            screenName: "Leads",
            capture: { _ in stage.render() }
        )
        session.arm()
        mark("armed (capture taken)")
        await BugReportPickProbeReadout.awaitText(session)
        mark("vision done: \(session.lines.count) lines")
        XCTAssertTrue(session.linesReady)
        print("VISION LINES: \(session.lines.map { "\($0.text) @ \($0.frame.integral)" })")
        XCTAssertFalse(session.lines.isEmpty, "Vision must read the capture")

        let window = stage.window
        let probes = BugReportPickProbeReadout.probes(in: window)

        func pick(_ point: CGPoint) -> BugReportPickResolution? {
            session.track(at: point)
            return session.target
        }

        // The form field: named by its title, ahead of the card around it.
        let field = try XCTUnwrap(probes.first { $0.role == .field })
        let fieldPoint = BugReportPickProbeReadout.centre(of: field, in: window)
        _ = winner(at: fieldPoint, in: window, "field")
        let onField = try XCTUnwrap(pick(fieldPoint))
        XCTAssertEqual(onField.source, .component)
        XCTAssertEqual(onField.role, .field)
        XCTAssertEqual(onField.label, "Client name")
        mark("field resolved")

        // The house button: its label is a view, so Vision names it.
        let houseButton = try XCTUnwrap(probes.first { $0.role == .button && $0.component == "ButtonStyles" })
        let buttonPoint = BugReportPickProbeReadout.centre(of: houseButton, in: window)
        _ = winner(at: buttonPoint, in: window, "house button")
        let onButton = try XCTUnwrap(pick(buttonPoint))
        XCTAssertEqual(onButton.role, .button)
        XCTAssertEqual(onButton.component, "ButtonStyles")
        XCTAssertTrue(
            onButton.label.uppercased().contains("START JOB"),
            "Expected the button's own words, got '\(onButton.label)'"
        )
        XCTAssertGreaterThanOrEqual(onButton.rect.height, OPSStyle.Layout.touchTargetStandard - 0.5)
        mark("house button resolved")

        // The banner's START verb beats the command card it sits on.
        let startVerb = try XCTUnwrap(probes.first { $0.label == "START" })
        let startPoint = BugReportPickProbeReadout.centre(of: startVerb, in: window)
        _ = winner(at: startPoint, in: window, "banner START")
        let onStart = try XCTUnwrap(pick(startPoint))
        XCTAssertEqual(onStart.role, .button)
        XCTAssertEqual(onStart.label, "START")
        XCTAssertEqual(onStart.component, "LeadSiteVisitBanner")
        XCTAssertEqual(onStart.cardText, "START · BUTTON")
        mark("banner verb resolved")

        // The glass card's own padding is the card, named by what it holds.
        let card = try XCTUnwrap(probes.first { $0.role == .card && $0.component == "GlassSurface" })
        let cardFrame = BugReportPickProbeReadout.frame(of: card, in: window)
        let onCard = try XCTUnwrap(pick(CGPoint(x: cardFrame.maxX - 6, y: cardFrame.maxY - 6)))
        XCTAssertEqual(onCard.role, .card)
        XCTAssertEqual(onCard.rect.integral, cardFrame.integral)
        XCTAssertFalse(onCard.labelIsRole, "A card with text on it is named by that text")
        mark("card resolved")

        // Plain text with no component under it.
        let header = try XCTUnwrap(
            session.lines.first { $0.text.uppercased().contains("THIS WEEK") },
            "Vision must read the section header"
        )
        let onHeader = try XCTUnwrap(pick(CGPoint(x: header.frame.midX, y: header.frame.midY)))
        XCTAssertEqual(onHeader.source, .text)
        XCTAssertEqual(onHeader.role, .text)
        XCTAssertTrue(onHeader.label.uppercased().contains("THIS WEEK"))
        mark("text line resolved")

        // Empty canvas: a region.
        let emptyPoint = CGPoint(x: window.bounds.midX, y: window.bounds.maxY - 80)
        let onNothing = try XCTUnwrap(pick(emptyPoint))
        XCTAssertEqual(onNothing.source, .region)
        XCTAssertEqual(onNothing.rect.size, CGSize(width: 44, height: 44))
        mark("region resolved")

        // Lift on START: the finished pick carries a pick-time capture sized
        // to the window, so its rect lands on the attached image.
        let spot = try await XCTUnwrapAsync(await session.commit(at: startPoint))
        mark("committed")
        XCTAssertEqual(spot.element.resolution.label, "START")
        XCTAssertEqual(spot.element.viewport, window.bounds.size)
        XCTAssertEqual(spot.element.screen, "Leads")
        let shot = try XCTUnwrap(spot.screenshot)
        XCTAssertEqual(shot.size, window.bounds.size)

        let metadata = try XCTUnwrap(BugReportSubmissionService.customMetadata(element: spot.element))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(metadata)
        print("PICK PAYLOAD\n\(String(decoding: json, as: UTF8.self))")
        let attachment = XCTAttachment(data: json, uniformTypeIdentifier: "public.json")
        attachment.name = "bugreport-pick-payload.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - What can never win

    private struct UnderSheetScreen: View {
        var body: some View {
            Text("UNDER")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OPSStyle.Colors.surfaceInput)
                .bugReportPickable(.button, label: "UNDER")
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.background)
        }
    }

    private struct SheetContent: View {
        var body: some View {
            VStack(spacing: 0) {
                Text("ON SHEET")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.text)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .bugReportPickable(.row, label: "ON SHEET")
                    .padding(.top, OPSStyle.Layout.spacing5)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPSStyle.Colors.background)
        }
    }

    func testContentUnderAPresentedSheetNeverWins() async throws {
        BugReportPickMode.shared.deactivate()
        let stage = try BugReportPickStage(UnderSheetScreen())
        defer {
            stage.tearDown()
            BugReportPickMode.shared.deactivate()
        }
        BugReportPickMode.shared.activate()
        await stage.settle()

        let sheet = UIHostingController(rootView: SheetContent())
        sheet.modalPresentationStyle = .pageSheet
        sheet.overrideUserInterfaceStyle = .dark
        stage.container.present(sheet, animated: false)
        await stage.settle(minimum: 0.6)

        let window = stage.window
        let probes = BugReportPickProbeReadout.probes(in: window)
        let row = try XCTUnwrap(probes.first { $0.label == "ON SHEET" })
        XCTAssertNotNil(probes.first { $0.label == "UNDER" }, "The covered content is still mounted — the rule, not luck, must exclude it")

        let rowPoint = BugReportPickProbeReadout.centre(of: row, in: window)
        XCTAssertEqual(winner(at: rowPoint, in: window, "sheet row")?.label, "ON SHEET")

        // On the sheet, over the covered button, where the sheet has nothing
        // pickable: the covered button is bigger-or-smaller irrelevant — it is
        // not in the frontmost presentation.
        let emptySheet = CGPoint(x: window.bounds.midX, y: window.bounds.maxY - 140)
        XCTAssertNotEqual(winner(at: emptySheet, in: window, "empty sheet")?.label, "UNDER")
        let underAtEmpty = candidates(at: emptySheet, in: window).first { $0.label == "UNDER" }
        XCTAssertEqual(underAtEmpty?.isInFrontmostPresentation, false)

        // The dimmed surround above the page sheet.
        let surround = CGPoint(x: window.bounds.midX, y: 12)
        XCTAssertNotEqual(winner(at: surround, in: window, "sheet surround")?.label, "UNDER")
    }

    private struct VisibilityScreen: View {
        var body: some View {
            VStack(spacing: 0) {
                ZStack {
                    Text("VISIBLE")
                        .frame(width: 300, height: 120)
                        .background(OPSStyle.Colors.surfaceInput)
                        .bugReportPickable(.card, label: "VISIBLE")
                    Text("FADED")
                        .frame(width: 200, height: 60)
                        .bugReportPickable(.button, label: "FADED")
                        .opacity(0)
                    Text("HIDDEN")
                        .frame(width: 120, height: 40)
                        .bugReportPickable(.button, label: "HIDDEN")
                        .hidden()
                }
                .frame(height: 160)

                ScrollView {
                    VStack(spacing: 0) {
                        Text("IN VIEW")
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .background(OPSStyle.Colors.surfaceInput)
                            .bugReportPickable(.row, label: "IN VIEW")
                        Text("CLIPPED")
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .background(OPSStyle.Colors.surfaceInput)
                            .bugReportPickable(.row, label: "CLIPPED")
                    }
                }
                .frame(height: 150)

                // Bigger than a CLIPPED row, so area alone would hand the
                // point to the clipped overflow.
                Text("FOOTER")
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .background(OPSStyle.Colors.surfaceRaised)
                    .bugReportPickable(.card, label: "FOOTER")

                Spacer(minLength: 0)
            }
            .foregroundColor(OPSStyle.Colors.text)
            .background(OPSStyle.Colors.background)
        }
    }

    func testFadedHiddenAndClippedContentIsNotOnScreen() async throws {
        BugReportPickMode.shared.deactivate()
        let stage = try BugReportPickStage(VisibilityScreen())
        defer {
            stage.tearDown()
            BugReportPickMode.shared.deactivate()
        }
        BugReportPickMode.shared.activate()
        await stage.settle()

        let window = stage.window
        let probes = BugReportPickProbeReadout.probes(in: window)
        let visible = try XCTUnwrap(probes.first { $0.label == "VISIBLE" })
        let centre = BugReportPickProbeReadout.centre(of: visible, in: window)
        XCTAssertEqual(
            winner(at: centre, in: window, "faded/hidden over visible")?.label,
            "VISIBLE",
            "A smaller element at opacity 0 or .hidden() must never win"
        )
        if let faded = candidates(at: centre, in: window).first(where: { $0.label == "FADED" }) {
            XCTAssertFalse(BugReportPickResolver.isEligible(faded, at: centre))
        }
        if let hidden = candidates(at: centre, in: window).first(where: { $0.label == "HIDDEN" }) {
            XCTAssertFalse(BugReportPickResolver.isEligible(hidden, at: centre))
        }

        let footer = try XCTUnwrap(probes.first { $0.label == "FOOTER" })
        let footerFrame = BugReportPickProbeReadout.frame(of: footer, in: window)
        let justIntoFooter = CGPoint(x: footerFrame.midX, y: footerFrame.minY + 40)
        XCTAssertEqual(
            winner(at: justIntoFooter, in: window, "clipped overflow over footer")?.label,
            "FOOTER",
            "A scroll view's clipped overflow is not on screen"
        )
        if let clipped = candidates(at: justIntoFooter, in: window).first(where: { $0.label == "CLIPPED" }) {
            XCTAssertTrue(clipped.frame.contains(justIntoFooter), "The clipped row's frame does reach the point")
            XCTAssertFalse(BugReportPickResolver.isEligible(clipped, at: justIntoFooter))
        }
    }

    private struct KeepAliveScreen: View {
        var body: some View {
            KeepAliveTabContainer(selected: 0, mounted: [0, 1]) { index in
                VStack {
                    if index == 0 {
                        Text("ON SCREEN")
                            .frame(width: 320, height: 200)
                            .background(OPSStyle.Colors.surfaceInput)
                            .bugReportPickable(.row, label: "ON SCREEN")
                    } else {
                        Text("PARKED")
                            .frame(width: 100, height: 50)
                            .bugReportPickable(.button, label: "PARKED")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 120)
                .frame(maxWidth: .infinity)
            }
            .foregroundColor(OPSStyle.Colors.text)
            .background(OPSStyle.Colors.background)
        }
    }

    func testAParkedKeepAliveTabNeverWins() async throws {
        BugReportPickMode.shared.deactivate()
        let stage = try BugReportPickStage(KeepAliveScreen())
        defer {
            stage.tearDown()
            BugReportPickMode.shared.deactivate()
        }
        BugReportPickMode.shared.activate()
        await stage.settle()

        let window = stage.window
        let probes = BugReportPickProbeReadout.probes(in: window)
        XCTAssertNil(
            probes.first { $0.label == "PARKED" },
            "A parked tab is on no one's screen and mounts no probe"
        )
        let onScreen = try XCTUnwrap(probes.first { $0.label == "ON SCREEN" })
        let centre = BugReportPickProbeReadout.centre(of: onScreen, in: window)
        XCTAssertEqual(winner(at: centre, in: window, "keep-alive")?.label, "ON SCREEN")
    }
}

// MARK: - Async unwrap

func XCTUnwrapAsync<T>(
    _ expression: @autoclosure () async throws -> T?,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> T {
    let value = try await expression()
    return try XCTUnwrap(value, file: file, line: line)
}
#endif
