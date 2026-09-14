#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class ExpenseCorrectionSnapshotTests: XCTestCase {
    func testCrewHistoryRendersLongNamesAndBeforeAfterValuesAtPhoneWidths() throws {
        typealias F = ExpenseCorrectionFixtures
        let before = F.snapshot([
            "merchant_name": "North Shore Building Supply and Hardware",
            "amount": 438.72, "tax_amount": 52.65,
            "category_id": F.actor, "category_name": "Materials",
            "description": "Deck materials and tools",
            "allocations": [["project_id": F.company, "project_title": "Morrison residence — front deck replacement", "percentage": 100]]
        ])
        let after = F.snapshot([
            "status": "rejected", "merchant_name": "North Shore Building Supply",
            "amount": 392.34, "tax_amount": 47.08,
            "category_id": F.crew, "category_name": "Equipment / Tools",
            "description": "Replacement saw and blades",
            "allocations": [["project_id": F.request, "project_title": "Community centre — west entrance and accessible ramp", "percentage": 100]]
        ])
        let record: ExpenseCorrectionDTO = try F.decode(F.record(
            note: "The saw is equipment for the ramp job. The receipt includes a returned item, so use the final subtotal.",
            before: before, after: after
        ))
        XCTAssertEqual(ExpenseCorrectionChange.changes(in: record).count, 6)
        for width: CGFloat in [375, 390] {
            let image = try FixedSizeSnapshot.render(
                ExpenseCorrectionRecordView(correction: record, actorName: "Alexandra Thompson")
                    .padding(OPSStyle.Layout.spacing3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(OPSStyle.Colors.background)
                    .environment(\.colorScheme, .dark),
                size: CGSize(width: width, height: 1_400)
            )
            let data = try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(data.count, 20_000, "The actual hosted history must render text rather than a blank surface.")
            let attachment = XCTAttachment(image: image)
            attachment.name = "expense-correction-crew-history-\(Int(width))"
            attachment.lifetime = .keepAlways
            add(attachment)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("expense-correction-snapshots", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("crew-history-\(Int(width)).png"))
        }
    }

    func testCorrectionWithoutOptionalNoteStillRendersRequiredFieldFeedback() throws {
        typealias F = ExpenseCorrectionFixtures
        let record: ExpenseCorrectionDTO = try F.decode(F.record(note: ""))
        XCTAssertFalse(ExpenseCorrectionChange.changes(in: record).isEmpty)
        let image = try FixedSizeSnapshot.render(
            ExpenseCorrectionRecordView(correction: record, actorName: "Office")
                .padding(OPSStyle.Layout.spacing3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(OPSStyle.Colors.background),
            size: CGSize(width: 375, height: 500)
        )
        let attachment = XCTAttachment(image: image)
        attachment.name = "expense-correction-without-note"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 5_000)
    }
}
#endif
