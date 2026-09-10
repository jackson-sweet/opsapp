import SwiftUI
import SwiftData
import XCTest
@testable import OPS

@MainActor
final class SiteVisitConflictReviewSnapshotTests: XCTestCase {
    func testCurrentAndPendingVersionsRender() throws {
        try render(width: 390, sizeCategory: .large, name: "phone-conflict-review-390")
    }

    func testReviewSurvivesNarrowAccessibilityLayout() throws {
        try render(width: 320, sizeCategory: .accessibilityExtraLarge, name: "phone-conflict-review-320-accessibility")
    }

    func testSummaryIncludesChangedFieldDefinitionAndOrder() {
        let row: SiteVisitWriteJSON = .object(["answer_value": .object(["text": .string("Pending answer")]),
            "label": .string("Stair clearance"), "kind": .string("measurement"), "required": .bool(true),
            "help_text": .string("Measure the landing"), "sort_order": .number(3)])
        let summary = SiteVisitConflictReview.summary(row)
        for expected in ["Pending answer", "Stair clearance", "MEASURE", "Required: Yes", "Measure the landing", "Order: 3"] {
            XCTAssertTrue(summary.contains(expected), expected)
        }
    }

    private func render(width: CGFloat, sizeCategory: ContentSizeCategory, name: String) throws {
        let priorActor = UserDefaults.standard.string(forKey: "currentUserId")
        defer {
            if let priorActor { UserDefaults.standard.set(priorActor, forKey: "currentUserId") }
            else { UserDefaults.standard.removeObject(forKey: "currentUserId") }
        }
        UserDefaults.standard.set("review-actor", forKey: "currentUserId")
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let type = SiteVisitType(companyId: "review-company", slug: "deck-survey", name: "Deck survey")
        type.writeState = .init(revision: 4)
        context.insert(type)
        type.beginVersionedEdit()
        type.name = "Deck and railing survey"
        let command = try SiteVisitWriteModels.command([type])
        let operation = SyncOperation(entityType: SyncEntityType.siteVisitType.rawValue, entityId: type.id,
            operationType: "siteVisitWrite", payload: try JSONEncoder().encode(command), changedFields: ["name"])
        operation.siteVisitWriteActorId = "review-actor"
        operation.status = "parked"
        context.insert(operation); try context.save()
        guard case .object(var remote) = command.rows[0].values else { return XCTFail("Expected object") }
        remote["name"] = .string("Deck, stairs and landing survey")
        remote["write_revision"] = .number(5)
        let current: [SiteVisitWriteJSON] = [.object(remote)]
        let controller = DataController()
        controller.currentUser = User(id: "review-actor", firstName: "Field", lastName: "Operator", role: .owner, companyId: "review-company")
        let view = SiteVisitConflictReview(operation: operation, loadCurrent: { _, _ in current })
            .environmentObject(controller)
            .modelContainer(container)
            .environment(\.colorScheme, .dark)
            .environment(\.sizeCategory, sizeCategory)
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.background)
        let image = try FixedSizeSnapshot.render(view, size: CGSize(width: width, height: sizeCategory == .large ? 1200 : 2100), minimumSettle: 1, settleDeadline: 3)
        let data = try XCTUnwrap(image.pngData())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-conflict-review-snapshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name + ".png")
        try data.write(to: url)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(data.count, 1000)
        print("PHONE REVIEW SNAPSHOT: \(url.path)")
    }
}
