//
//  BugReportPickResolverTests.swift
//  OPSTests
//
//  Bug 14e5a792 — POINT AT IT picks on the live app. Every rule that decides
//  WHAT the finger landed on is pure, so it is pinned here with synthetic
//  probes and text lines: nesting, visibility, the covering sheet, ties, the
//  text and region fallbacks, the label rule, and the payload the web bug
//  console reads.
//

import XCTest
import UIKit
@testable import OPS

final class BugReportPickResolverTests: XCTestCase {

    private let viewport = CGSize(width: 390, height: 844)
    private let card = CGRect(x: 20, y: 200, width: 350, height: 160)
    private let button = CGRect(x: 36, y: 290, width: 318, height: 56)

    private func probe(
        _ frame: CGRect,
        _ role: BugReportPickRole,
        label: String? = nil,
        depth: Int = 4,
        clip: CGRect? = nil,
        hidden: Bool = false,
        alpha: CGFloat = 1,
        inAppWindow: Bool = true,
        frontmost: Bool = true
    ) -> BugReportProbeCandidate {
        BugReportProbeCandidate(
            frame: frame,
            clipRect: clip,
            depth: depth,
            isHiddenInHierarchy: hidden,
            cumulativeAlpha: alpha,
            isInAppWindow: inAppWindow,
            isInFrontmostPresentation: frontmost,
            role: role,
            label: label,
            component: "Test"
        )
    }

    private func line(_ text: String, _ frame: CGRect) -> BugReportTextLine {
        BugReportTextLine(text: text, frame: frame)
    }

    // MARK: - Nesting

    func testTheSmallestProbeUnderTheFingerWins() {
        let probes = [probe(card, .card), probe(button, .button)]

        XCTAssertEqual(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 318), among: probes)?.role,
            .button,
            "A button inside a card is the button, never the card around it"
        )
        XCTAssertEqual(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 220), among: probes)?.role,
            .card,
            "The card's own padding is the card"
        )
        XCTAssertNil(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 600), among: probes)
        )
    }

    func testAProbeUnderAHiddenAncestorNeverWins() {
        let probes = [probe(card, .card), probe(button, .button, hidden: true)]
        XCTAssertEqual(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 318), among: probes)?.role,
            .card
        )
    }

    func testATransparentProbeNeverWins() {
        let faint = [probe(card, .card), probe(button, .button, alpha: 0.005)]
        XCTAssertEqual(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 318), among: faint)?.role,
            .card,
            "A parked keep-alive tab sits at opacity 0 — on no one's screen"
        )

        let dimButVisible = [probe(card, .card), probe(button, .button, alpha: 0.3)]
        XCTAssertEqual(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 318), among: dimButVisible)?.role,
            .button,
            "A disabled-looking control is still on screen and still pickable"
        )
    }

    func testContentUnderACoveringSheetNeverWins() {
        // The underlying screen's button is SMALLER than the sheet's row, so
        // area alone would pick it. The frontmost-presentation rule is what
        // keeps the finger on the sheet it is actually touching.
        let sheetRow = CGRect(x: 0, y: 250, width: 390, height: 140)
        let probes = [
            probe(button, .button, label: "Behind the sheet", frontmost: false),
            probe(sheetRow, .row, label: "On the sheet")
        ]
        let winner = BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 318), among: probes)
        XCTAssertEqual(winner?.label, "On the sheet")
    }

    func testAProbeInAnotherWindowNeverWins() {
        let probes = [probe(card, .card), probe(button, .button, inAppWindow: false)]
        XCTAssertEqual(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 318), among: probes)?.role,
            .card,
            "The report's own overlay (and the toast window) are not the app"
        )
    }

    func testTheClippedPartOfAProbeIsNotOnScreen() {
        // A card scrolled half under a header: its frame still reaches the
        // point, but the scroll view's viewport stops at y = 300.
        let viewportBelowHeader = CGRect(x: 0, y: 300, width: 390, height: 544)
        let header = CGRect(x: 0, y: 200, width: 390, height: 100)
        let probes = [
            probe(header, .card, label: "Header"),
            probe(button, .button, label: "Scrolled away", clip: viewportBelowHeader)
        ]
        XCTAssertEqual(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 295), among: probes)?.label,
            "Header"
        )
        XCTAssertEqual(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 320), among: probes)?.label,
            "Scrolled away"
        )
    }

    func testAnAreaTieGoesToTheDeeperProbe() {
        let probes = [
            probe(button, .button, label: "Shallow", depth: 3),
            probe(button, .button, label: "Deep", depth: 9)
        ]
        XCTAssertEqual(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 318), among: probes)?.label,
            "Deep"
        )
    }

    func testAnExactTieGoesToTheMoreSpecificRole() {
        // A list row drawn on its own glass card: same rect, same depth.
        let probes = [probe(card, .card), probe(card, .row, label: "Settings")]
        XCTAssertEqual(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 220), among: probes)?.role,
            .row
        )
    }

    func testAZeroSizedProbeIsIgnored() {
        let probes = [probe(card, .card), probe(CGRect(x: 195, y: 318, width: 0, height: 20), .button)]
        XCTAssertEqual(
            BugReportPickResolver.frontmostProbe(at: CGPoint(x: 195, y: 320), among: probes)?.role,
            .card
        )
    }

    // MARK: - Text lines

    func testATextLineIsTouchedWithinItsSlop() {
        let lines = [line("Schedule", CGRect(x: 40, y: 100, width: 80, height: 16))]
        XCTAssertNotNil(BugReportPickResolver.textLine(at: CGPoint(x: 80, y: 94), in: lines))
        XCTAssertNotNil(BugReportPickResolver.textLine(at: CGPoint(x: 126, y: 108), in: lines))
        XCTAssertNil(BugReportPickResolver.textLine(at: CGPoint(x: 80, y: 90), in: lines))
        XCTAssertNil(BugReportPickResolver.textLine(at: CGPoint(x: 130, y: 108), in: lines))
    }

    func testTheClosestTextLineWins() {
        let lines = [
            line("Upper", CGRect(x: 40, y: 100, width: 80, height: 16)),
            line("Lower", CGRect(x: 40, y: 124, width: 80, height: 16))
        ]
        // 2pt below Upper, 6pt above Lower: both within slop.
        XCTAssertEqual(BugReportPickResolver.textLine(at: CGPoint(x: 80, y: 118), in: lines)?.text, "Upper")
        XCTAssertEqual(BugReportPickResolver.textLine(at: CGPoint(x: 80, y: 122), in: lines)?.text, "Lower")
    }

    func testBlankRecognitionsAreNeverALine() {
        let lines = [line("   ", CGRect(x: 40, y: 100, width: 80, height: 16))]
        XCTAssertNil(BugReportPickResolver.textLine(at: CGPoint(x: 80, y: 108), in: lines))
    }

    // MARK: - Label assembly

    func testTextInsideARectReadsInReadingOrder() {
        // Vision returns lines in no promised order; the second row's two
        // words sit a pixel apart vertically.
        let lines = [
            line("REBOOK", CGRect(x: 150, y: 301, width: 60, height: 14)),
            line("CANCEL", CGRect(x: 260, y: 300, width: 60, height: 14)),
            line("// SITE VISIT · TODAY", CGRect(x: 30, y: 240, width: 200, height: 12)),
            line("START", CGRect(x: 40, y: 300, width: 50, height: 14))
        ]
        XCTAssertEqual(
            BugReportPickResolver.text(inside: card, lines: lines, limit: 80),
            "// SITE VISIT · TODAY START REBOOK CANCEL"
        )
    }

    func testOnlyLinesCentredInsideTheRectCount() {
        let lines = [
            line("Inside", CGRect(x: 40, y: 300, width: 50, height: 14)),
            // Starts inside, centre outside.
            line("Spills out", CGRect(x: 340, y: 300, width: 100, height: 14)),
            line("Elsewhere", CGRect(x: 40, y: 600, width: 50, height: 14))
        ]
        XCTAssertEqual(BugReportPickResolver.text(inside: card, lines: lines, limit: 80), "Inside")
        XCTAssertNil(BugReportPickResolver.text(inside: CGRect(x: 0, y: 700, width: 10, height: 10), lines: lines, limit: 80))
    }

    func testALongLabelIsCappedWithAnEllipsis() {
        let long = String(repeating: "Payment schedule ", count: 12)
        let lines = [line(long, CGRect(x: 30, y: 250, width: 300, height: 14))]
        let label = BugReportPickResolver.text(inside: card, lines: lines, limit: 80)
        XCTAssertEqual(label?.count, 80)
        XCTAssertEqual(label?.last, "…")
    }

    func testWhitespaceIsCollapsed() {
        XCTAssertEqual(BugReportPickResolver.collapse("  START \n  JOB  "), "START JOB")
        XCTAssertEqual(BugReportPickResolver.clamp("ABC", to: 80), "ABC")
    }

    // MARK: - The answer

    func testAComponentsOwnLabelBeatsTheTextOnIt() {
        let resolution = BugReportPickResolver.resolve(
            point: CGPoint(x: 195, y: 318),
            probes: [probe(button, .field, label: "Client name")],
            lines: [line("Jane Doe", CGRect(x: 50, y: 310, width: 80, height: 16))],
            viewport: viewport
        )
        XCTAssertEqual(resolution.source, .component)
        XCTAssertEqual(resolution.label, "Client name")
        XCTAssertEqual(resolution.text, "Jane Doe", "What the field shows still ships as its text")
        XCTAssertEqual(resolution.rect, button)
        XCTAssertEqual(resolution.component, "Test")
    }

    func testAComponentWithoutALabelIsNamedByItsText() {
        let resolution = BugReportPickResolver.resolve(
            point: CGPoint(x: 195, y: 318),
            probes: [probe(card, .card), probe(button, .button)],
            lines: [
                line("START", CGRect(x: 170, y: 310, width: 50, height: 16)),
                line("Card title", CGRect(x: 40, y: 220, width: 80, height: 16))
            ],
            viewport: viewport
        )
        XCTAssertEqual(resolution.role, .button)
        XCTAssertEqual(resolution.label, "START")
        XCTAssertEqual(resolution.tagText, "BUTTON · START")
        XCTAssertEqual(resolution.cardText, "START · BUTTON")
    }

    func testAPureIconFallsBackToItsRole() {
        let resolution = BugReportPickResolver.resolve(
            point: CGPoint(x: 195, y: 318),
            probes: [probe(button, .button)],
            lines: [],
            viewport: viewport
        )
        XCTAssertEqual(resolution.label, "button")
        XCTAssertTrue(resolution.labelIsRole)
        XCTAssertEqual(resolution.tagText, "BUTTON")
        XCTAssertEqual(resolution.cardText, "BUTTON")
        XCTAssertEqual(resolution.text, "")
    }

    func testPlainTextIsPickedWhenNoComponentIsUnderTheFinger() {
        let header = CGRect(x: 20, y: 120, width: 120, height: 14)
        let resolution = BugReportPickResolver.resolve(
            point: CGPoint(x: 60, y: 126),
            probes: [probe(card, .card)],
            lines: [line("// THIS WEEK", header)],
            viewport: viewport
        )
        XCTAssertEqual(resolution.source, .text)
        XCTAssertEqual(resolution.role, .text)
        XCTAssertEqual(resolution.rect, header)
        XCTAssertEqual(resolution.label, "// THIS WEEK")
        XCTAssertEqual(resolution.tagText, "TEXT · // THIS WEEK")
    }

    func testNothingNameableRecordsA44PointRegion() {
        let resolution = BugReportPickResolver.resolve(
            point: CGPoint(x: 200, y: 700),
            probes: [probe(card, .card)],
            lines: [],
            viewport: viewport
        )
        XCTAssertEqual(resolution.source, .region)
        XCTAssertEqual(resolution.role, .region)
        XCTAssertEqual(resolution.rect, CGRect(x: 178, y: 678, width: 44, height: 44))
        XCTAssertEqual(resolution.label, "region")
        XCTAssertEqual(resolution.tagText, "REGION")
    }

    func testTheRegionStaysInsideTheScreen() {
        XCTAssertEqual(
            BugReportPickResolver.regionRect(around: CGPoint(x: 5, y: 5), viewport: viewport),
            CGRect(x: 0, y: 0, width: 44, height: 44)
        )
        XCTAssertEqual(
            BugReportPickResolver.regionRect(around: CGPoint(x: 388, y: 842), viewport: viewport),
            CGRect(x: 346, y: 800, width: 44, height: 44)
        )
    }

    // MARK: - Payload

    private func samplePick() -> BugReportElementPick {
        BugReportElementPick(
            id: "6f1c1d7e-2f40-4b53-9a3c-1b2f0d6e7a11",
            resolution: BugReportPickResolution(
                source: .component,
                role: .button,
                rect: CGRect(x: 36, y: 290.5, width: 318, height: 56),
                label: "START",
                text: "START",
                component: "LeadSiteVisitBanner"
            ),
            point: CGPoint(x: 195, y: 318),
            viewport: viewport,
            screen: "LeadDetail",
            capturedAt: Date(timeIntervalSince1970: 1_788_000_000.125)
        )
    }

    private func decodedReferences(_ metadata: [String: JSONPrimitive]?) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(try XCTUnwrap(metadata))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["elementReferences"] as? [[String: Any]])
    }

    func testThePayloadMatchesTheWebPickersElementReferenceShape() throws {
        let references = try decodedReferences(
            BugReportSubmissionService.customMetadata(element: samplePick())
        )
        XCTAssertEqual(references.count, 1)
        let reference = try XCTUnwrap(references.first)

        // Every field of ops-web's `ElementReference`
        // (src/lib/types/bug-report-element.ts), and nothing renamed.
        let webFields: Set<String> = [
            "id", "label", "role", "tag", "selector", "classes", "testId", "text",
            "rect", "page", "viewport", "componentChain", "capturedAt", "attachmentIndex"
        ]
        XCTAssertTrue(webFields.isSubset(of: Set(reference.keys)), "Missing: \(webFields.subtracting(reference.keys))")
        XCTAssertEqual(Set(reference.keys).subtracting(webFields), ["source", "screen", "point"])

        XCTAssertEqual(reference["id"] as? String, "6f1c1d7e-2f40-4b53-9a3c-1b2f0d6e7a11")
        XCTAssertEqual(reference["label"] as? String, "START")
        XCTAssertEqual(reference["role"] as? String, "button")
        XCTAssertEqual(reference["text"] as? String, "START")

        // The admin console drops a reference whose selector is not a string
        // (feedback-content.tsx readElementReferences) — DOM-only fields are
        // present and empty, never invented and never null.
        XCTAssertEqual(reference["selector"] as? String, "")
        XCTAssertEqual(reference["classes"] as? String, "")
        XCTAssertEqual(reference["tag"] as? String, "")
        XCTAssertTrue(reference["testId"] is NSNull)
        // No crop attachment exists; the rect is measured on the report's own
        // (pick-time) screenshot.
        XCTAssertTrue(reference["attachmentIndex"] is NSNull)

        let rect = try XCTUnwrap(reference["rect"] as? [String: Double])
        XCTAssertEqual(rect, ["x": 36, "y": 290.5, "width": 318, "height": 56])
        XCTAssertEqual(reference["page"] as? [String: Double], ["x": 36, "y": 290.5])
        XCTAssertEqual(reference["viewport"] as? [String: Double], ["width": 390, "height": 844])
        XCTAssertEqual(reference["componentChain"] as? [String], ["LeadSiteVisitBanner"])
        XCTAssertEqual(reference["capturedAt"] as? String, "2026-08-29T10:40:00.125Z")

        XCTAssertEqual(reference["source"] as? String, "component")
        XCTAssertEqual(reference["screen"] as? String, "LeadDetail")
        XCTAssertEqual(reference["point"] as? [String: Double], ["x": 195, "y": 318])
    }

    func testTextAndRegionPicksCarryAnEmptyComponentChain() throws {
        let pick = BugReportElementPick(
            resolution: BugReportPickResolver.resolve(
                point: CGPoint(x: 200, y: 700),
                probes: [],
                lines: [],
                viewport: viewport
            ),
            point: CGPoint(x: 200, y: 700),
            viewport: viewport,
            screen: "Home"
        )
        let reference = try XCTUnwrap(try decodedReferences(
            BugReportSubmissionService.customMetadata(element: pick)
        ).first)
        XCTAssertEqual(reference["componentChain"] as? [String], [])
        XCTAssertEqual(reference["label"] as? String, "region")
        XCTAssertEqual(reference["source"] as? String, "region")
        // Lowercase, like every id Postgres hands back.
        XCTAssertEqual(pick.id, pick.id.lowercased())
    }

    func testAReportWithNoPickCarriesNoMetadata() {
        XCTAssertNil(BugReportSubmissionService.customMetadata(element: nil))
    }

    func testTheRetiredElementKeyIsNeverWritten() {
        let metadata = BugReportSubmissionService.customMetadata(element: samplePick())
        XCTAssertNil(metadata?["element"])
        XCTAssertEqual(metadata.map { Set($0.keys) }, ["elementReferences"])
    }

    func testAReportQueuedByThePreviousBuildStillDecodes() throws {
        // 5aabcc3a wrote `custom_metadata.element`; an operator who filed one
        // offline and then updated must still get it delivered.
        let json = """
        {
          "companyId": "c1", "reporterId": "r1", "description": "old", "category": "bug",
          "platform": "ios", "appVersion": "1", "buildNumber": "1", "osName": "iOS",
          "osVersion": "26.5", "deviceModel": "iPhone", "screenName": "Home",
          "networkType": "wifi", "batteryLevel": 0.5, "freeDiskMb": 1, "freeRamMb": 1,
          "customMetadata": {
            "element": {
              "x": 195.0, "y": 318.0, "normalizedX": 0.5, "normalizedY": 0.37,
              "label": null, "identifier": null, "viewType": "PlatformGroupContainer"
            }
          },
          "reporterName": "J", "reporterEmail": "j@example.com"
        }
        """
        let payload = try JSONDecoder().decode(BugReportPayload.self, from: Data(json.utf8))
        guard case let .nested(element)? = payload.customMetadata?["element"] else {
            return XCTFail("The old element key must survive decoding")
        }
        XCTAssertEqual(element["viewType"], .string("PlatformGroupContainer"))
        XCTAssertEqual(element["label"], .null)
    }

    func testAPayloadWithAPickRoundTripsThroughTheOutbox() throws {
        let payload = BugReportPayload(
            companyId: "c1", reporterId: "r1", description: "d", category: "bug",
            platform: "ios", appVersion: "1", buildNumber: "1", osName: "iOS",
            osVersion: "26.5", deviceModel: "iPhone", screenName: "Home",
            networkType: "wifi", batteryLevel: 1, freeDiskMb: 1, freeRamMb: 1,
            customMetadata: BugReportSubmissionService.customMetadata(element: samplePick()),
            reporterName: "J", reporterEmail: "j@example.com"
        )
        // The contract is the JSON the delivery sends. JSONPrimitive reads a
        // whole-number double (`36.0` → `36`) back as an int, so the enum
        // values can differ while the bytes are identical — compare bytes.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let stored = try encoder.encode(payload)
        let decoded = try JSONDecoder().decode(BugReportPayload.self, from: stored)
        XCTAssertEqual(try encoder.encode(decoded), stored)
        let reference = try XCTUnwrap(try decodedReferences(decoded.customMetadata).first)
        XCTAssertEqual(reference["label"] as? String, "START")
        XCTAssertEqual(reference["rect"] as? [String: Double], ["x": 36, "y": 290.5, "width": 318, "height": 56])
    }

    // MARK: - Vision → points

    func testAVisionBoxBecomesATopLeftRectInPoints() {
        let frame = BugReportTextRecognizer.frame(
            of: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.05),
            in: viewport
        )
        XCTAssertEqual(frame.minX, 39, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 844 * 0.15, accuracy: 0.001)
        XCTAssertEqual(frame.width, 195, accuracy: 0.001)
        XCTAssertEqual(frame.height, 844 * 0.05, accuracy: 0.001)
    }

    // MARK: - Drawing the mark

    func testAPickedRectProjectsOntoAFittedThumbnail() {
        // 390×844 fit into 80×140: height-bound.
        let fitted = BugReportShotGeometry.fittedRect(imageSize: viewport, in: CGSize(width: 80, height: 140))
        XCTAssertEqual(fitted.height, 140, accuracy: 0.001)
        XCTAssertEqual(fitted.midX, 40, accuracy: 0.001)

        let projected = BugReportShotGeometry.project(button, from: viewport, into: fitted)
        let scale = 140 / 844.0
        XCTAssertEqual(projected.minX, fitted.minX + 36 * scale, accuracy: 0.001)
        XCTAssertEqual(projected.minY, 290 * scale, accuracy: 0.001)
        XCTAssertEqual(projected.width, 318 * scale, accuracy: 0.001)
    }

    func testDegenerateShotsProduceNoRectRatherThanNaN() {
        XCTAssertEqual(BugReportShotGeometry.fittedRect(imageSize: .zero, in: viewport), .zero)
        XCTAssertEqual(BugReportShotGeometry.project(button, from: .zero, into: card), .zero)
    }

    // MARK: - Tag placement

    func testTheTagSitsAboveTheElementWhenThereIsRoom() {
        let origin = BugReportPickTagPlacement.origin(
            for: CGSize(width: 120, height: 22),
            target: button,
            bounds: viewport,
            topInset: 59
        )
        XCTAssertEqual(origin, CGPoint(x: 36, y: 290 - 8 - 22))
    }

    func testTheTagDropsBelowAnElementAtTheTop() {
        let navButton = CGRect(x: 300, y: 62, width: 44, height: 44)
        let origin = BugReportPickTagPlacement.origin(
            for: CGSize(width: 120, height: 22),
            target: navButton,
            bounds: viewport,
            topInset: 59
        )
        // Pulled in from the right edge, and below the element.
        XCTAssertEqual(origin, CGPoint(x: 390 - 8 - 120, y: 106 + 8))
    }

    func testTheTagGoesInsideAnElementThatFillsTheScreen() {
        let origin = BugReportPickTagPlacement.origin(
            for: CGSize(width: 120, height: 22),
            target: CGRect(origin: .zero, size: viewport),
            bounds: viewport,
            topInset: 59
        )
        XCTAssertEqual(origin, CGPoint(x: 8, y: 59 + 8))
    }

    // MARK: - Component names

    func testTheComponentNameIsTheSourceFile() {
        XCTAssertEqual(
            BugReportProbeCollector.componentName(fromFileID: "OPS/ButtonStyles.swift"),
            "ButtonStyles"
        )
        XCTAssertEqual(BugReportProbeCollector.componentName(fromFileID: "Bare"), "Bare")
    }

    // MARK: - Draft

    @MainActor
    func testClearingTheMarkRestoresTheTriggerScreenshot() {
        let trigger = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        let atPick = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        let draft = BugReportDraft(triggerScreenshot: trigger)
        draft.description = "Start does nothing"
        draft.category = .uiIssue

        draft.mark(samplePick(), screenshot: atPick)
        XCTAssertTrue(draft.screenshot === atPick, "A pick's rect is measured on the pick-time capture")
        XCTAssertEqual(draft.element?.resolution.label, "START")

        draft.clearMark()
        XCTAssertTrue(draft.screenshot === trigger)
        XCTAssertNil(draft.element)
        XCTAssertEqual(draft.description, "Start does nothing", "Clearing a mark touches nothing else")
        XCTAssertEqual(draft.category, .uiIssue)
    }

    @MainActor
    func testAPickWhoseCaptureFailedKeepsTheTriggerScreenshot() {
        let trigger = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        let draft = BugReportDraft(triggerScreenshot: trigger)
        draft.mark(samplePick(), screenshot: nil)
        XCTAssertTrue(draft.screenshot === trigger)
        XCTAssertNotNil(draft.element)
    }
}
