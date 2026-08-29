//
//  SiteVisitFormSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the site-visit form overhaul (site-visit report):
//  the numbered, sequential layout (1 · LEAD → LEAD SUMMARY → 2 · CHECKLIST
//  → 3 · NOTES) and the per-field REQUIRED → DONE markers. Renders the real
//  SiteVisitCaptureView against the current in-memory schema (the console
//  inserts live @Models, so the container must register `OPSSchemaCurrent`)
//  with a bound name-only lead and a deliberately long summary, so
//  narrow-width wrapping, the read-only band, and both requirement states
//  are visible.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/SiteVisitFormSnapshotTests
//  Shots land in NSTemporaryDirectory()/ops-site-visit-form-shots.
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitFormSnapshotTests: XCTestCase {
    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-site-visit-form-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testLeadFormNumberedStepsAndRequiredMarkers() throws {
        let container = try inMemoryContainer()
        // A bound lead with only a name — name/company group satisfies (DONE),
        // contact + address groups stay outstanding (REQUIRED).
        let lead = Opportunity(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            contactName: "Dale Harmon",
            stage: .newLead
        )
        lead.aiSummary = "Dale wants the existing cedar deck measured before Friday. Confirm stair rise, railing transitions, drainage at the patio door, and whether the current framing can carry composite boards without replacement."

        let view = SiteVisitCaptureView(opportunity: lead, onCreateProject: { _ in })
            .environmentObject(DataController())
            .modelContainer(container)

        try snapshot(
            "01_lead_form_summary_320_accessibility",
            width: 320,
            height: 1_800,
            settle: 3.0,
            sizeCategory: .accessibilityExtraLarge
        ) { view }
        try snapshot(
            "02_lead_form_summary_390",
            width: 390,
            height: 1_800,
            settle: 3.0
        ) { view }
    }

    /// Renders via FixedSizeSnapshot (app-hosted window) — never a test-created
    /// UIWindow, which full-suite runs can render blank once the host drops out
    /// of the foreground pipeline. `settle` is the async view-model floor: the
    /// view shows a spinner until its `.task` finishes loading, and only then
    /// does the quiescence capture start counting.
    private func snapshot<V: View>(
        _ name: String,
        width: CGFloat,
        height: CGFloat,
        settle: TimeInterval,
        sizeCategory: ContentSizeCategory = .large,
        @ViewBuilder _ content: () -> V
    ) throws {
        let image = try FixedSizeSnapshot.render(
            content()
                .environment(\.colorScheme, .dark)
                .environment(\.sizeCategory, sizeCategory),
            size: CGSize(width: width, height: height),
            minimumSettle: settle,
            settleDeadline: 3
        )
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name)")
    }
}
#endif
