//
//  BugReportElementHitTestTests.swift
//  OPSTests
//
//  Bug 5aabcc3a — "allow the user to select an element with the bug report".
//  The whole mapping from one tap to one named element is pure, so it is tested
//  here rather than by aiming at a simulator: where the shot actually sits
//  inside the viewer, which view a tap lands on, and what the report carries.
//

import XCTest
@testable import OPS

final class BugReportElementHitTestTests: XCTestCase {

    // A 390×844 phone screen shown in a 400×900 viewer: the image is letterboxed
    // left/right after fitting to height.
    private let imageSize = CGSize(width: 390, height: 844)
    private let container = CGSize(width: 400, height: 900)

    // MARK: - Where the shot sits

    func testFittedRectCentresTheImageInsideTheViewer() {
        let rect = BugReportElementHitTest.fittedRect(imageSize: imageSize, in: container)
        // Height-bound: 900/844 > 400/390, so width wins the min().
        XCTAssertEqual(rect.width, 400, accuracy: 0.01)
        XCTAssertEqual(rect.height, 844 * (400 / 390), accuracy: 0.01)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.01)
        XCTAssertEqual(rect.midY, 450, accuracy: 0.01)
    }

    func testDegenerateSizesProduceNoRectRatherThanNaN() {
        XCTAssertEqual(BugReportElementHitTest.fittedRect(imageSize: .zero, in: container), .zero)
        XCTAssertEqual(BugReportElementHitTest.fittedRect(imageSize: imageSize, in: .zero), .zero)
    }

    // MARK: - The tap

    func testTapMapsToItsProportionalPositionInTheShot() {
        let rect = BugReportElementHitTest.fittedRect(imageSize: imageSize, in: container)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let normalized = BugReportElementHitTest.normalizedPoint(
            ofTap: centre,
            in: container,
            imageSize: imageSize
        )
        XCTAssertEqual(normalized?.x ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(normalized?.y ?? -1, 0.5, accuracy: 0.001)
    }

    func testTapOnTheLetterboxMarksNothing() {
        // Fitting 390×844 into 400×900 leaves ~17pt bands top and bottom.
        XCTAssertNil(
            BugReportElementHitTest.normalizedPoint(
                ofTap: CGPoint(x: 200, y: 4),
                in: container,
                imageSize: imageSize
            )
        )
        XCTAssertNil(
            BugReportElementHitTest.normalizedPoint(
                ofTap: CGPoint(x: 200, y: 896),
                in: container,
                imageSize: imageSize
            )
        )
    }

    // MARK: - Which view was pointed at

    /// A plausible slice of a real hierarchy: the window, a screen-filling host
    /// view, a labelled button, and the unnamed backing layer inside it.
    private var hierarchy: [BugReportElementCandidate] {
        [
            .init(frame: CGRect(x: 0, y: 0, width: 390, height: 844), depth: 0, viewType: "UIWindow"),
            .init(frame: CGRect(x: 0, y: 0, width: 390, height: 844), depth: 1, viewType: "UIHostingView"),
            .init(
                frame: CGRect(x: 20, y: 300, width: 350, height: 52),
                depth: 4,
                label: "Start job",
                identifier: "job.start",
                viewType: "SwiftUIButton"
            ),
            .init(frame: CGRect(x: 24, y: 304, width: 342, height: 44), depth: 6, viewType: "_UIGraphicsView"),
            // A sibling elsewhere on screen — must never win.
            .init(frame: CGRect(x: 20, y: 500, width: 350, height: 52), depth: 4, label: "Cancel", viewType: "SwiftUIButton")
        ]
    }

    func testDeepestViewNamesTheTypeAndTheNearestNamedAncestorNamesIt() {
        // Dead centre of the button.
        let mark = BugReportElementHitTest.mark(
            atNormalized: CGPoint(x: 195.0 / 390.0, y: 326.0 / 844.0),
            windowSize: CGSize(width: 390, height: 844),
            candidates: hierarchy
        )
        XCTAssertEqual(mark.point.x, 195, accuracy: 0.001)
        XCTAssertEqual(mark.point.y, 326, accuracy: 0.001)
        // The literal deepest view under the finger…
        XCTAssertEqual(mark.viewType, "_UIGraphicsView")
        // …named by the deepest ancestor that actually carries a name.
        XCTAssertEqual(mark.label, "Start job")
        XCTAssertEqual(mark.identifier, "job.start")
    }

    func testATapOnBareCanvasStillMarksThePoint() {
        let mark = BugReportElementHitTest.mark(
            atNormalized: CGPoint(x: 0.5, y: 0.95),
            windowSize: CGSize(width: 390, height: 844),
            candidates: hierarchy
        )
        // Nothing but the window and its host down there.
        XCTAssertEqual(mark.viewType, "UIHostingView")
        XCTAssertNil(mark.label)
        XCTAssertNil(mark.identifier)
        XCTAssertEqual(mark.point.y, 844 * 0.95, accuracy: 0.001)
    }

    func testAnEmptyHierarchyStillMarksThePoint() {
        let mark = BugReportElementHitTest.mark(
            atNormalized: CGPoint(x: 0.25, y: 0.75),
            windowSize: CGSize(width: 390, height: 844),
            candidates: []
        )
        XCTAssertNil(mark.viewType)
        XCTAssertNil(mark.label)
        XCTAssertNil(mark.identifier)
        XCTAssertEqual(mark.point.x, 97.5, accuracy: 0.001)
        XCTAssertEqual(mark.normalized.x, 0.25, accuracy: 0.001)
    }

    func testBlankAccessibilityStringsAreNotTreatedAsNames() {
        let candidates: [BugReportElementCandidate] = [
            .init(
                frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                depth: 1,
                label: "   ",
                identifier: "",
                viewType: "UIHostingView"
            )
        ]
        let mark = BugReportElementHitTest.mark(
            atNormalized: CGPoint(x: 0.5, y: 0.5),
            windowSize: CGSize(width: 390, height: 844),
            candidates: candidates
        )
        XCTAssertNil(mark.label)
        XCTAssertNil(mark.identifier)
        XCTAssertEqual(mark.viewType, "UIHostingView")
    }

    func testTighterFrameWinsAtEqualDepth() {
        let candidates: [BugReportElementCandidate] = [
            .init(frame: CGRect(x: 0, y: 0, width: 390, height: 844), depth: 3, viewType: "Wide"),
            .init(frame: CGRect(x: 100, y: 100, width: 40, height: 40), depth: 3, viewType: "Tight")
        ]
        let mark = BugReportElementHitTest.mark(
            atNormalized: CGPoint(x: 120.0 / 390.0, y: 120.0 / 844.0),
            windowSize: CGSize(width: 390, height: 844),
            candidates: candidates
        )
        XCTAssertEqual(mark.viewType, "Tight")
    }

    // MARK: - What the report carries

    func testMetadataIsOmittedEntirelyWhenNobodyPointed() {
        XCTAssertNil(BugReportSubmissionService.customMetadata(element: nil))
    }

    func testMetadataCarriesTheSpotAndWhatWasNamedThere() {
        let mark = BugReportElementMark(
            normalized: CGPoint(x: 0.5, y: 0.25),
            point: CGPoint(x: 195, y: 211),
            label: "Start job",
            identifier: "job.start",
            viewType: "SwiftUIButton"
        )
        guard case .nested(let element)? = BugReportSubmissionService
            .customMetadata(element: mark)?["element"] else {
            return XCTFail("expected an element object")
        }
        XCTAssertEqual(element["x"], .double(195))
        XCTAssertEqual(element["y"], .double(211))
        XCTAssertEqual(element["normalizedX"], .double(0.5))
        XCTAssertEqual(element["normalizedY"], .double(0.25))
        XCTAssertEqual(element["label"], .string("Start job"))
        XCTAssertEqual(element["identifier"], .string("job.start"))
        XCTAssertEqual(element["viewType"], .string("SwiftUIButton"))
    }

    func testUnnamedSpotSendsNullsRatherThanDroppingTheKeys() {
        let mark = BugReportElementMark(
            normalized: CGPoint(x: 0.1, y: 0.2),
            point: CGPoint(x: 39, y: 168.8),
            label: nil,
            identifier: nil,
            viewType: nil
        )
        guard case .nested(let element)? = BugReportSubmissionService
            .customMetadata(element: mark)?["element"] else {
            return XCTFail("expected an element object")
        }
        XCTAssertEqual(element["label"], .null)
        XCTAssertEqual(element["identifier"], .null)
        XCTAssertEqual(element["viewType"], .null)
    }

    /// A report queued by a build that predates POINT AT IT must still decode.
    func testPayloadsWithoutMetadataStillDecode() throws {
        let legacy = """
        {
          "companyId": "c", "reporterId": "r", "description": "d", "category": "bug",
          "platform": "ios", "appVersion": "1", "buildNumber": "1", "osName": "iOS",
          "osVersion": "26.5", "deviceModel": "iPhone17,1", "screenName": "Home",
          "networkType": "wifi", "batteryLevel": 1, "freeDiskMb": 1, "freeRamMb": 1,
          "reporterName": "n", "reporterEmail": "e"
        }
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(BugReportPayload.self, from: legacy)
        XCTAssertNil(payload.customMetadata)
    }
}
