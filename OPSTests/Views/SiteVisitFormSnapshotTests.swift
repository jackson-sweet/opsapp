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
//  ONE CANVAS PER TEST CASE, each on its own store. Both renders used to live
//  in a single method against one container, and the second one died with
//  "Test crashed with signal segv" — on a loaded machine and on an idle one
//  alike. The cause was never the canvas: the console's open-visit lookup ran
//  `assigneeIds.contains(user)` inside a `#Predicate`, which CoreData
//  segfaults on. The first render survived only because the store was still
//  empty, so the predicate had no row to evaluate; the second render met the
//  visit the first had just created and the process died. Fixed in
//  `SiteVisitCaptureViewModel.openVisits()`, pinned by
//  `SiteVisitOpenVisitsTests` and `SwiftDataPredicateLintTests`. The split
//  stands on its own merits: neither render can now inherit the other's rows,
//  and only one 1_800 pt canvas is ever alive.
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

    /// Standard width and text size — the full numbered sequence is legible
    /// end to end: 1 · LEAD → LEAD SUMMARY → 2 · CHECKLIST → 3 · NOTES.
    func testLeadFormNumberedStepsAndRequiredMarkers() throws {
        try renderLeadForm("02_lead_form_summary_390", width: 390)
    }

    /// Narrowest supported width at the largest accessibility text size. The
    /// form runs past the canvas here by design — what this proves is that
    /// step 1's numbered header, the name group's DONE marker, and the
    /// EMAIL / PHONE / ADDRESS REQUIRED markers all survive extreme wrapping,
    /// and that the read-only summary band still reads.
    func testLeadFormRequiredMarkersSurviveAccessibilityWrapping() throws {
        try renderLeadForm(
            "01_lead_form_summary_320_accessibility",
            width: 320,
            sizeCategory: .accessibilityExtraLarge
        )
    }

    /// A bound lead with only a name — the name/company group satisfies
    /// (DONE), contact + address groups stay outstanding (REQUIRED).
    private func renderLeadForm(
        _ name: String,
        width: CGFloat,
        sizeCategory: ContentSizeCategory = .large
    ) throws {
        let container = try inMemoryContainer()
        let lead = Opportunity(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            contactName: "Dale Harmon",
            stage: .newLead
        )
        lead.aiSummary = "Dale wants the existing cedar deck measured before Friday. Confirm stair rise, railing transitions, drainage at the patio door, and whether the current framing can carry composite boards without replacement."

        let view = SiteVisitCaptureView(opportunity: lead, onCreateProject: { _ in })
            .environmentObject(DataController())
            .modelContainer(container)

        try snapshot(name, width: width, height: 1_800, settle: 3.0, sizeCategory: sizeCategory) { view }
    }

    /// Renders via FixedSizeSnapshot (app-hosted window) — never a test-created
    /// UIWindow, which full-suite runs can render blank once the host drops out
    /// of the foreground pipeline. `settle` is the async view-model floor: the
    /// view shows a spinner until its `.task` finishes loading, and only then
    /// does the quiescence capture start counting. The render is pooled so the
    /// full-size bitmap goes away before the PNG is retained for attachment.
    private func snapshot<V: View>(
        _ name: String,
        width: CGFloat,
        height: CGFloat,
        settle: TimeInterval,
        sizeCategory: ContentSizeCategory = .large,
        @ViewBuilder _ content: () -> V
    ) throws {
        let encoded: Data? = try autoreleasepool {
            let image = try FixedSizeSnapshot.render(
                content()
                    .environment(\.colorScheme, .dark)
                    .environment(\.sizeCategory, sizeCategory),
                size: CGSize(width: width, height: height),
                minimumSettle: settle,
                settleDeadline: 3
            )
            return image.pngData()
        }
        guard let data = encoded else {
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
