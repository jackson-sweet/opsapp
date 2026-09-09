//
//  BugReportPointAtItSnapshotTests.swift
//  OPSTests
//
//  Visual proof for bug 5aabcc3a — the optional POINT AT IT step on the
//  screenshot-triggered bug report: the offer, the marked state with its ring,
//  and the armed full-screen shot the operator taps.
//
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult --output-path <dir>
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class BugReportPointAtItSnapshotTests: XCTestCase {

    private let sheetSize = CGSize(width: 390, height: 700)
    private let screenSize = CGSize(width: 390, height: 844)

    private func snapshot<V: View>(
        _ name: String,
        size: CGSize,
        @ViewBuilder content: () -> V
    ) throws {
        let image = try FixedSizeSnapshot.render(
            content()
                .environment(\.colorScheme, .dark),
            size: size,
            minimumSettle: 0.3
        )
        guard let data = image.pngData() else {
            return XCTFail("Failed to render \(name)")
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SNAPSHOT \(name) (\(Int(image.size.width))x\(Int(image.size.height))pt)")
    }

    /// A stand-in for the captured screen: dark canvas, a header band, and a
    /// button-shaped block at the spot the mark points to.
    private func syntheticScreen() -> UIImage {
        UIGraphicsImageRenderer(size: screenSize).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: screenSize))
            UIColor(white: 0.14, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: screenSize.width, height: 110))
            UIColor(white: 0.10, alpha: 1).setFill()
            for row in 0..<5 {
                ctx.fill(CGRect(x: 20, y: 140 + row * 90, width: 350, height: 72))
            }
            // A neutral control band, deliberately NOT the accent colour — the
            // mark's own legibility is proven by the halo test below.
            UIColor(white: 0.22, alpha: 1).setFill()
            ctx.fill(CGRect(x: 20, y: 300, width: 350, height: 52))
            UIColor(red: 0.435, green: 0.580, blue: 0.690, alpha: 1).setFill()
            ctx.fill(CGRect(x: 20, y: 620, width: 350, height: 52))
        }
    }

    private func capture() -> BugReportCaptureService.AppWindowCapture {
        BugReportCaptureService.AppWindowCapture(
            screenshot: syntheticScreen(),
            elements: [
                .init(frame: CGRect(origin: .zero, size: screenSize), depth: 0, viewType: "UIWindow"),
                .init(
                    frame: CGRect(x: 20, y: 300, width: 350, height: 52),
                    depth: 4,
                    label: "Start job",
                    identifier: "job.start",
                    viewType: "SwiftUIButton"
                ),
                .init(frame: CGRect(x: 24, y: 304, width: 342, height: 44), depth: 6, viewType: "_UIGraphicsView")
            ],
            size: screenSize
        )
    }

    private var markOnTheButton: BugReportElementMark {
        BugReportElementHitTest.mark(
            atNormalized: CGPoint(x: 195.0 / 390.0, y: 326.0 / 844.0),
            windowSize: screenSize,
            candidates: capture().elements
        )
    }

    private func sheet(
        mark: BugReportElementMark? = nil,
        pointing: Bool = false
    ) -> some View {
        BugReportSheet(
            capture: capture(),
            onClose: {},
            initialElementMark: mark,
            initialPointing: pointing
        )
        .environmentObject(AppState())
        .environmentObject(DataController())
    }

    /// Before pointing: the evidence card offers the step and nothing else has
    /// changed about the report.
    func testSheetOffersPointAtIt() throws {
        try snapshot("bugreport-point-offer", size: sheetSize) {
            sheet()
        }
    }

    /// After one tap: the ring rides the thumbnail and the card names what the
    /// frozen hierarchy found there.
    func testSheetShowsTheMarkedSpot() throws {
        try snapshot("bugreport-point-marked", size: sheetSize) {
            sheet(mark: markOnTheButton)
        }
    }

    /// Armed: the full-screen shot with the instruction and the SKIP out.
    /// Rendered directly — a `fullScreenCover` presents outside its host's
    /// view, so a snapshot of the sheet would capture the sheet, not the cover.
    func testArmedFullScreenAwaitsTheTap() throws {
        try snapshot("bugreport-point-armed", size: screenSize) {
            BugReportScreenshotViewer(
                image: syntheticScreen(),
                mark: nil,
                isPointing: true,
                onPlace: { _ in },
                onClose: {}
            )
        }
    }

    /// The mark landing on a FILLED ACCENT control — the case where a bare
    /// steel-blue ring would vanish. The halo is what keeps it readable.
    func testRingStaysLegibleOnAnAccentFilledControl() throws {
        try snapshot("bugreport-point-ring-on-accent", size: screenSize) {
            BugReportScreenshotViewer(
                image: syntheticScreen(),
                mark: BugReportElementHitTest.mark(
                    atNormalized: CGPoint(x: 195.0 / 390.0, y: 646.0 / 844.0),
                    windowSize: screenSize,
                    candidates: capture().elements
                ),
                isPointing: false,
                onPlace: { _ in },
                onClose: {}
            )
        }
    }

    /// The ring, at full size, on the spot that was tapped.
    func testFullScreenShowsTheRingOnTheSpot() throws {
        try snapshot("bugreport-point-ring", size: screenSize) {
            BugReportScreenshotViewer(
                image: syntheticScreen(),
                mark: markOnTheButton,
                isPointing: false,
                onPlace: { _ in },
                onClose: {}
            )
        }
    }
}
#endif
