import SwiftUI
import SwiftData
import XCTest
@testable import OPS

/// Visual proof for the booking surfaces: the sheet in both modes and the
/// day-sheet panel's BOOKED row. Rendered via FixedSizeSnapshot (app-hosted
/// window, fixed 390×844 logical frame) so captures are device-agnostic.
@MainActor
final class BookSiteVisitSheetSnapshotTests: XCTestCase {
    private let frameSize = CGSize(width: 390, height: 844)

    private var outDir: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("site-visit-booking-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Panel states

    func testBookedPanelRowRendersBookedToken() throws {
        let view = ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                LeadSiteVisitPanel(state: .absent, onCapture: {})
                LeadSiteVisitPanel(state: .booked(token: "THU 10:30AM"), onCapture: {})
                LeadSiteVisitPanel(state: .open(token: "3H AGO"), onCapture: {})
            }
            .padding(OPSStyle.Layout.spacing3_5)
        }

        let image = try FixedSizeSnapshot.render(view, size: CGSize(width: 390, height: 320))
        XCTAssertGreaterThan(image.size.width, 0)
        attach(image, name: "panel-booked-row")
    }

    // MARK: - Sheet modes

    func testCreateModeSheetRenders() throws {
        let image = try FixedSizeSnapshot.render(
            sheetHost(existing: nil),
            size: frameSize
        )
        XCTAssertGreaterThan(image.size.width, 0)
        attach(image, name: "book-visit-sheet-create")
    }

    func testRescheduleModeSheetRendersWithCancelRow() throws {
        let snapshot = BookSiteVisitForm.BookingSnapshot(
            siteVisitId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            scheduledAt: Date(timeIntervalSince1970: 1_790_000_000),
            durationMinutes: 90,
            assigneeIds: ["dddddddd-dddd-4ddd-8ddd-dddddddddddd"],
            reminderLeadMinutes: 15
        )
        let image = try FixedSizeSnapshot.render(
            sheetHost(existing: snapshot),
            size: frameSize
        )
        XCTAssertGreaterThan(image.size.width, 0)
        attach(image, name: "book-visit-sheet-reschedule")
    }

    func testCreateModeShowsBookedThatDayContext() throws {
        let image = try FixedSizeSnapshot.render(sheetHost(existing: nil), size: frameSize)
        XCTAssertGreaterThan(image.size.width, 0)
        attach(image, name: "book-visit-sheet-context-strip")
    }

    // MARK: - Host builder

    private func sheetHost(existing: BookSiteVisitForm.BookingSnapshot?) -> some View {
        let controller = DataController()
        let lead = Opportunity(
            id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            companyId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            contactName: "Dana Whitfield"
        )
        lead.address = "418 Larchmont Ave"
        // Preseed the form — the harness has no signed-in DataController, and
        // the proof must show the field stack, not the loading spinner.
        let bookerId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        let form: BookSiteVisitForm
        if let existing {
            form = .reschedule(existing: existing, bookerId: bookerId, defaultHeadsUpMinutes: 30)
        } else {
            form = .create(
                bookerId: bookerId,
                defaultHeadsUpMinutes: 30,
                startingAt: Date(timeIntervalSince1970: 1_790_000_000)
            )
        }
        // Deterministic WHEN-surface context so the rail markers and the
        // BOOKED — <DAY> strip appear in the proof PNGs without a store: one
        // visit before the chosen window, one after (the second nameless, to
        // prove the "Site visit" fallback).
        let seededVisits = [
            BookingDayVisit(
                id: "11111111-1111-4111-8111-111111111111",
                opportunityId: "22222222-2222-4222-8222-222222222222",
                start: Date(timeIntervalSince1970: 1_790_000_000 - 7_200),
                durationMinutes: 60
            ),
            BookingDayVisit(
                id: "33333333-3333-4333-8333-333333333333",
                opportunityId: nil,
                start: Date(timeIntervalSince1970: 1_790_000_000 + 5_400),
                durationMinutes: 90
            ),
        ]
        return BookSiteVisitSheet(
            request: BookSiteVisitRequest(lead: lead, existing: existing),
            initialForm: form,
            initialContextVisits: seededVisits
        )
        .environmentObject(controller)
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
