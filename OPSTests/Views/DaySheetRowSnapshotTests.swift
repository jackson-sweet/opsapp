//
//  DaySheetRowSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for DaySheetLeadRow — the delegate day sheet's
//  collapsed row. Renders the urgency variants (rose LATE chip, tan TODAY chip),
//  the coordinates-only map thumb, and the bare lead whose CALL and ROUTE verbs
//  are both spent, through a real UIHostingController in a UIWindow
//  (ImageRenderer mis-resolves OPS asset colors). A rendering harness, not an
//  assertion.
//
//  The map-thumb case may render as the Mapbox land-color base rather than a
//  finished tile — the Snapshotter needs a network round trip the harness does
//  not wait on. The row geometry is what this proves.
//
//  One addition to the ClientLeadRow harness: the hosted view ignores safe
//  area. A UIWindow inherits the device's insets whatever its frame, which
//  pushed the 80pt row down ~46pt and clipped it out of the 110pt canvas.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DaySheetRowSnapshotTests
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class DaySheetRowSnapshotTests: XCTestCase {

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-day-sheet-row-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, size: CGSize, @ViewBuilder _ content: () -> V) {
        let host = UIHostingController(rootView: content().ignoresSafeArea())
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { XCTFail("render \(name)"); return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name)")
    }

    // MARK: - Fixtures

    private static let rowSize = CGSize(width: 390, height: 110)

    private func lead(
        id: String,
        name: String,
        stage: PipelineStage,
        daysInStage: Int,
        address: String? = nil,
        phone: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> Opportunity {
        let entered = Calendar.current.date(byAdding: .day, value: -daysInStage, to: Date()) ?? Date()
        let opportunity = Opportunity(
            id: id,
            companyId: "c1",
            contactName: name,
            stage: stage,
            stageEnteredAt: entered
        )
        opportunity.address = address
        opportunity.contactPhone = phone
        opportunity.latitude = latitude
        opportunity.longitude = longitude
        return opportunity
    }

    private func row(
        _ lead: Opportunity,
        _ urgency: DaySheetViewModel.Urgency,
        _ milestone: LeadMilestone?
    ) -> DaySheetViewModel.Row {
        DaySheetViewModel.Row(lead: lead, urgency: urgency, milestone: milestone)
    }

    @ViewBuilder
    private func hosted(_ row: DaySheetViewModel.Row,
                        canEdit: Bool = true,
                        canConvert: Bool = true) -> some View {
        // Canvas inset stays tight: the row is 80pt minimum, so a 20pt sheet
        // inset would not fit the 110pt frame and the card would render clipped.
        DaySheetLeadRow(row: row, canEdit: canEdit, canConvert: canConvert)
            .padding(OPSStyle.Layout.spacing2)
            .frame(width: Self.rowSize.width)
            .background(Color.black)
    }

    // MARK: - Renders

    /// Rose LATE chip — the loudest row on the sheet. Initial tile (no photos).
    func testRenderLateRow() {
        let lead = lead(
            id: "D1", name: "Marcus Webb", stage: .quoting, daysInStage: 5,
            address: "1841 Beckwith Ave, Burnaby", phone: "604-555-0142"
        )
        snapshot("day_sheet_row_late_rose", size: Self.rowSize) {
            hosted(row(lead, .late(days: 3), .quoteSent))
        }
    }

    /// Tan TODAY chip — follow-up lands today.
    func testRenderTodayRow() {
        let lead = lead(
            id: "D2", name: "The Hensons", stage: .quoted, daysInStage: 3,
            address: "22 Wharf Road, North Vancouver", phone: "604-555-0199"
        )
        snapshot("day_sheet_row_today_tan", size: Self.rowSize) {
            hosted(row(lead, .today, .won))
        }
    }

    /// Coordinates, no photos → the thumb falls to the map snapshot tile.
    func testRenderMapFallbackRow() {
        let lead = lead(
            id: "D3", name: "Dana Ruiz", stage: .followUp, daysInStage: 4,
            phone: "604-555-0177", latitude: 49.2827, longitude: -123.1207
        )
        snapshot("day_sheet_row_map_fallback", size: Self.rowSize) {
            hosted(row(lead, .yourMove, .won))
        }
    }

    /// No phone, no address, no coordinates → both verbs disabled, and the
    /// comeback token is absent (waiting with no date).
    func testRenderRouteDisabledRow() {
        let lead = lead(
            id: "D4", name: "Cedar Ridge HOA", stage: .negotiation, daysInStage: 6
        )
        snapshot("day_sheet_row_route_disabled", size: Self.rowSize) {
            hosted(row(lead, .waiting(back: nil), nil))
        }
    }
}
#endif
