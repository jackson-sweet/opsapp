import SwiftUI
import XCTest
@testable import OPS

/// Visual proof for the appointment sheet's two states (counting down /
/// window open). Value-driven content view — no store, no DataController.
@MainActor
final class SiteVisitAppointmentSheetSnapshotTests: XCTestCase {
    private let frameSize = CGSize(width: 390, height: 500)

    private var outDir: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("site-visit-booking-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testCountdownStateRenders() throws {
        let view = ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            SiteVisitAppointmentContent(
                leadName: "Dana Whitfield",
                address: "418 Larchmont Ave",
                scheduledAt: Date(timeIntervalSince1970: 1_790_187_000),
                durationMinutes: 90,
                crewSummary: "You",
                crewMembers: [],
                now: Date(timeIntervalSince1970: 1_790_000_000),
                showsStartNow: false,
                showsRebook: true,
                onStartNow: {},
                onRebook: {}
            )
        }
        let image = try FixedSizeSnapshot.render(view, size: frameSize)
        XCTAssertGreaterThan(image.size.width, 0)
        attach(image, name: "appointment-sheet-countdown")
    }

    func testWindowOpenStateRenders() throws {
        let view = ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            SiteVisitAppointmentContent(
                leadName: "Dana Whitfield",
                address: "418 Larchmont Ave",
                scheduledAt: Date(timeIntervalSince1970: 1_789_999_000),
                durationMinutes: 60,
                crewSummary: "2 going",
                crewMembers: [],
                now: Date(timeIntervalSince1970: 1_790_000_000),
                showsStartNow: true,
                showsRebook: true,
                onStartNow: {},
                onRebook: {}
            )
        }
        let image = try FixedSizeSnapshot.render(view, size: frameSize)
        XCTAssertGreaterThan(image.size.width, 0)
        attach(image, name: "appointment-sheet-window-open")
    }

    /// Bug 2b085519 — a booking from two weeks ago that nobody started reads
    /// MISSED with how long ago, in rose, and offers REBOOK only.
    func testMissedStateRenders() throws {
        let view = ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            SiteVisitAppointmentContent(
                leadName: "Dana Whitfield",
                address: "418 Larchmont Ave",
                scheduledAt: Date(timeIntervalSince1970: 1788876800),
                durationMinutes: 60,
                crewSummary: "2 going",
                crewMembers: [],
                now: Date(timeIntervalSince1970: 1_790_000_000),
                showsStartNow: false,
                showsRebook: true,
                onStartNow: {},
                onRebook: {}
            )
        }
        let image = try FixedSizeSnapshot.render(view, size: frameSize)
        XCTAssertGreaterThan(image.size.width, 0)
        attach(image, name: "2b085519-appointment-sheet-missed")
    }

    private func attach(_ image: UIImage, name: String) {
        guard let data = image.pngData() else {
            XCTFail("Failed to encode \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name) -> \(outDir.appendingPathComponent("\(name).png").path)")
    }
}
