//
//  SiteVisitRecordSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the SITE VISIT RECORD, including the requirement that
//  carries real consequences: a viewer without financial visibility must get a
//  record with NO money in it — not a masked row, not a blurred figure, not a
//  gap where a number used to be.
//
//  The two full-record shots are rendered from the SAME metadata; the only
//  difference is the `canViewFinancials` flag handed to the assembler. Put the
//  two PNGs side by side: the permitted record ends with a `// VALUE` panel,
//  the restricted one simply ends. Nothing else moves.
//
//  A rendering harness, not an assertion — but the assembly rules underneath
//  are asserted in SiteVisitRecordTests.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/SiteVisitRecordSnapshotTests
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class SiteVisitRecordSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-site-visit-record-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A visit that captured everything, including a value — so the two
    /// permission states have something to actually differ about.
    private func fullMetadata() -> SiteVisitPacketMetadata {
        SiteVisitPacketMetadata(
            siteVisitId: "visit-1",
            photoCount: 6,
            measurements: [
                .init(label: "Deck footprint", value: "12' x 16'"),
                .init(label: "Height above grade", value: "30\""),
                .init(label: "Stair run", value: "4 risers")
            ],
            notes: ["Gate code 4417. Dog in the yard — call ahead.", "Owner wants composite, not cedar."],
            checklist: ["What the client wants", "Deck design"],
            address: "1100 Maple Ave, Springfield",
            contactName: "Helen Calloway",
            companyName: "Calloway Ltd",
            deckDesignId: "design-1",
            estimatedValue: 18_400
        )
    }

    private func record(canViewFinancials: Bool) -> SiteVisitRecord {
        SiteVisitRecord.assemble(
            metadata: fullMetadata(),
            photoURLs: [],
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000),
            operatorName: "Dale Harmon",
            canViewFinancials: canViewFinancials
        )
    }

    // MARK: - The permission pair

    func testFullRecord_financialsPermitted() {
        snapshot("01_record_financials_permitted", height: 1180) {
            SiteVisitRecordView(record: record(canViewFinancials: true))
        }
    }

    func testFullRecord_financialsWithheld() {
        snapshot("02_record_financials_withheld", height: 1180) {
            SiteVisitRecordView(record: record(canViewFinancials: false))
        }
    }

    // MARK: - Compact row

    func testCompactCard() {
        snapshot("03_record_card", height: 150) {
            SiteVisitRecordCard(
                record: record(canViewFinancials: true),
                teamMember: nil,
                onOpen: {}
            )
            .padding(OPSStyle.Layout.spacing3)
        }
    }

    /// Ruthless omission: a walkthrough that only took photos is a header and
    /// a photo count — not a page of empty headings.
    func testPhotosOnlyRecord() {
        let sparse = SiteVisitRecord.assemble(
            metadata: SiteVisitPacketMetadata(
                siteVisitId: "visit-2",
                photoCount: 3,
                measurements: nil, notes: nil, checklist: nil,
                address: nil, contactName: nil, companyName: nil,
                deckDesignId: nil, estimatedValue: nil
            ),
            photoURLs: [],
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000),
            operatorName: "Dale Harmon",
            canViewFinancials: true
        )
        snapshot("04_record_photos_only", height: 420) {
            SiteVisitRecordView(record: sparse)
        }
    }

    // MARK: - Harness

    private func snapshot<V: View>(
        _ name: String,
        height: CGFloat,
        @ViewBuilder _ content: () -> V
    ) {
        let size = CGSize(width: deviceWidth, height: height)
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
}
#endif
