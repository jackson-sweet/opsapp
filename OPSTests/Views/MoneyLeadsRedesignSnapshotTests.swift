//
//  MoneyLeadsRedesignSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the Money & Leads redesign (2026-06-30).
//  Renders the new Money command grid + ledger primitives and the Leads triage
//  surfaces to PNGs via SwiftUI's `ImageRenderer`, driven by the DEBUG preview
//  seeders so the output matches the live canvas. A rendering harness, not an
//  assertion test — it writes images for a human/agent to inspect.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/MoneyLeadsRedesignSnapshotTests \
//          -derivedDataPath <dd>
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class MoneyLeadsRedesignSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-money-leads-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, width: CGFloat? = nil, @ViewBuilder _ content: () -> V) {
        let w = width ?? deviceWidth
        let host = content()
            .frame(width: w)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: host)
        renderer.scale = 3
        renderer.isOpaque = true

        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    // MARK: - Money

    func testRenderMoneyCommandGrid() {
        let vm = MoneyDashboardViewModel.previewStub()
        snapshot("money_command_grid") {
            BooksCommandGrid(
                viewModel: vm,
                cashflowVM: CashflowForecastViewModel(),
                canFinances: true,
                canPipeline: true
            )
            .padding(.vertical, OPSStyle.Layout.spacing3)
        }
    }

    func testRenderMoneyLedgerPrimitives() {
        snapshot("money_ledger_segments") {
            BooksLedgerSegments(segments: BooksSection.allCases, selected: .constant(.invoices))
                .padding(OPSStyle.Layout.spacing3_5)
        }
        snapshot("money_status_pills") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                BooksPillView(pill: BooksPill(text: "OVERDUE", color: OPSStyle.Colors.rose))
                BooksPillView(pill: BooksPill(text: "PART-PAID", color: OPSStyle.Colors.tan))
                BooksPillView(pill: BooksPill(text: "PAID", color: OPSStyle.Colors.olive))
                BooksPillView(pill: BooksPill(text: "WON", color: OPSStyle.Colors.olive, solid: true))
                BooksPillView(pill: BooksPill(text: "NO RECEIPT", color: OPSStyle.Colors.rose))
                BooksPillView(pill: BooksPill(text: "NEEDS OK", color: OPSStyle.Colors.tan))
            }
            .padding(OPSStyle.Layout.spacing3_5)
        }
        snapshot("money_ledger_empty") {
            BooksLedgerEmpty(value: "$0", label: "NO ESTIMATES", hint: "QUOTE A JOB TO GET STARTED",
                             ctaTitle: "NEW ESTIMATE", onCreate: {})
        }
    }

    // MARK: - Leads

    func testRenderLeadsSummary() {
        let vm = PipelineViewModel.previewLoaded()
        snapshot("leads_summary") {
            LeadsSummary(viewModel: vm).padding(.vertical, OPSStyle.Layout.spacing3)
        }
        snapshot("leads_by_stage") {
            LeadsByStageRow(viewModel: vm, onStageTap: { _ in }).padding(.vertical, OPSStyle.Layout.spacing3)
        }
        snapshot("leads_won_nudge") {
            LeadsWonNudge(count: 2, totalValue: 27_400, onTap: {}).padding(.vertical, OPSStyle.Layout.spacing3)
        }
        snapshot("leads_caught_up") {
            LeadsCaughtUp(title: "ALL CAUGHT UP", label: "NO FOLLOW-UPS DUE",
                          hint: "23 OPEN · PIPELINE $52.4K")
        }
    }

    func testRenderLeadTriageCards() {
        let vm = PipelineViewModel.previewLoaded()
        let overdue = Opportunity.preview(
            title: "Roof tear-off — 28 sq", contactName: "Marcus Webb",
            stage: .quoting, estimatedValue: 14_200, daysInStage: 5, nextFollowUpDaysFromNow: -2
        )
        let today = Opportunity.preview(
            title: "Window install — 8 units", contactName: "The Hensons",
            stage: .quoted, estimatedValue: 11_800, daysInStage: 3, nextFollowUpDaysFromNow: 0
        )
        let fresh = Opportunity.preview(
            title: "Leak repair — kitchen ceiling", contactName: "Jamie Park",
            stage: .newLead, estimatedValue: 2_200, daysInStage: 0
        )
        snapshot("leads_triage_cards") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                LeadTriageCard(lead: overdue, viewModel: vm, bucket: .overdue)
                LeadTriageCard(lead: today, viewModel: vm, bucket: .dueToday)
                LeadTriageCard(lead: fresh, viewModel: vm, bucket: .fresh)
            }
            .padding(OPSStyle.Layout.spacing3_5)
        }
    }
}
#endif
