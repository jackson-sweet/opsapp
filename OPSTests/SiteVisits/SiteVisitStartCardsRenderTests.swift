import SwiftUI
import XCTest
@testable import OPS

/// Reference renders of the visit-day surface pinned above the Leads tab,
/// for the founder's taste review (f77d38fc — "UI/UX for that spot is ugly").
/// `leads-visits-before.png` was captured from the stacked START cards before
/// the rewrite; this test writes `leads-visits-after.png` for the rail.
/// PNGs land under `docs/artifacts/field-reports-0908/` in the checkout.
@MainActor
final class SiteVisitStartCardsRenderTests: XCTestCase {

    func testRenderTodayVisitsRail() throws {
        let rail = SiteVisitTodayRail(
            entries: [
                .init(id: "v-1", leadName: "Angela Wall", address: "4369 Happy Valley Rd, Victoria",
                      scheduledAt: Self.today(hour: 14, minute: 0)),
                .init(id: "v-2", leadName: "Kyle Kingsley", address: "10440 Resthaven Dr, Sidney",
                      scheduledAt: Self.today(hour: 16, minute: 30))
            ],
            onOpen: { _ in }, onStart: { _ in }, onDismiss: { _ in }
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OPSStyle.Colors.background)

        let image = try FixedSizeSnapshot.render(rail, size: CGSize(width: 393, height: 360), minimumSettle: 0.3)
        try Self.write(image, name: "leads-visits-after")
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testRenderTodayVisitsRailSingleVisit() throws {
        let rail = SiteVisitTodayRail(
            entries: [
                .init(id: "v-1", leadName: "Angela Wall", address: "4369 Happy Valley Rd, Victoria",
                      scheduledAt: Self.today(hour: 14, minute: 0))
            ],
            onOpen: { _ in }, onStart: { _ in }, onDismiss: { _ in }
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OPSStyle.Colors.background)

        let image = try FixedSizeSnapshot.render(rail, size: CGSize(width: 393, height: 200), minimumSettle: 0.3)
        try Self.write(image, name: "leads-visits-after-single")
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - Helpers

    static func today(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    static func write(_ image: UIImage, name: String, file: StaticString = #filePath) throws {
        var root = URL(fileURLWithPath: "\(file)")
        while root.pathComponents.count > 1 {
            root.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("OPS.xcodeproj").path) { break }
        }
        let dir = root.appendingPathComponent("docs/artifacts/field-reports-0908", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
