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

    /// The triage card in the by-stage drill (`bucket: .all`), including a lead
    /// that carries a SOURCE — confirms the source renders on real data (the
    /// preview mix carries none, so the queue snapshot never exercises it).
    func testRenderLeadTriageCardSource() {
        let vm = PipelineViewModel.previewLoaded()
        let sourced = Opportunity.preview(
            title: "Gutter replacement — 140 lf", contactName: "Dana Ruiz",
            stage: .quoted, estimatedValue: 8_600, daysInStage: 4,
            lastActivityDaysAgo: 6, nextFollowUpDaysFromNow: 3
        )
        sourced.source = "referral"
        snapshot("leads_triage_card_source") {
            LeadTriageCard(lead: sourced, viewModel: vm, bucket: .all)
                .padding(OPSStyle.Layout.spacing3_5)
        }
    }

    /// Terminal-stage cards — the new outcome strip (won → converted vs not,
    /// lost → reason). These render in the by-stage drill for a closed stage;
    /// the triage queue never routes terminal leads here.
    func testRenderLeadTriageCardsTerminal() {
        let vm = PipelineViewModel.previewLoaded()
        let wonConverted = Opportunity.preview(
            title: "Maple Lane porch", contactName: "Tom Liu",
            stage: .won, estimatedValue: 11_200, daysInStage: 12, actualCloseDaysAgo: 3
        )
        wonConverted.projectId = "proj-123"
        wonConverted.source = "referral"
        let wonUnconverted = Opportunity.preview(
            title: "Foster patio", contactName: "Jen Foster",
            stage: .won, estimatedValue: 9_400, daysInStage: 6, actualCloseDaysAgo: 1
        )
        let lost = Opportunity.preview(
            title: "Beacon Hill addition", contactName: "Beacon Hill LLC",
            stage: .lost, estimatedValue: 26_500, daysInStage: 20, actualCloseDaysAgo: 5
        )
        lost.lostReason = "price"
        snapshot("leads_triage_cards_terminal") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                LeadTriageCard(lead: wonConverted, viewModel: vm, bucket: .all)
                LeadTriageCard(lead: wonUnconverted, viewModel: vm, bucket: .all)
                LeadTriageCard(lead: lost, viewModel: vm, bucket: .all)
            }
            .padding(OPSStyle.Layout.spacing3_5)
        }
    }

    /// The won → convert chooser (2+ unconverted wins).
    func testRenderLeadsWonChooser() {
        let wins: [Opportunity] = [
            {
                let o = Opportunity.preview(title: "Roof tear-off, 28 sq", contactName: "Helen Calloway",
                                            stage: .won, estimatedValue: 14_200, daysInStage: 2, actualCloseDaysAgo: 3)
                o.source = "referral"
                return o
            }(),
            {
                let o = Opportunity.preview(title: "Maple Lane porch", contactName: "Tom Liu",
                                            stage: .won, estimatedValue: 11_200, daysInStage: 5, actualCloseDaysAgo: 0)
                o.source = "website"
                return o
            }(),
            Opportunity.preview(title: "Skylight install", contactName: "Aimee Watari",
                                stage: .won, estimatedValue: nil, daysInStage: 8, actualCloseDaysAgo: 8),
        ]
        // Render the row list directly (the sheet wraps it in a ScrollView, which
        // ImageRenderer leaves blank) so the snapshot shows the actual rows.
        snapshot("leads_won_chooser") {
            VStack(spacing: 0) {
                ForEach(Array(wins.enumerated()), id: \.element.id) { idx, lead in
                    WonChooserRow(lead: lead, action: {})
                    if idx < wins.count - 1 {
                        Rectangle().fill(OPSStyle.Colors.lineSoft).frame(height: 1).padding(.leading, 52)
                    }
                }
            }
            .commandCard()
            .padding(OPSStyle.Layout.spacing3_5)
        }
    }

    /// The restyled detail cards — DetailHero + ContactCard now sit on the solid
    /// command surface. Confirms the glass→command swap renders cleanly.
    func testRenderLeadDetailComponents() {
        let lead = Opportunity.preview(
            title: "Roof tear-off, 28 sq", contactName: "Helen Calloway",
            stage: .quoted, estimatedValue: 14_200, daysInStage: 9
        )
        lead.contactPhone = "(555) 123-4567"
        lead.contactEmail = "helen@example.com"
        lead.address = "1240 Maple Ave"
        lead.source = "referral"
        snapshot("leads_detail_components") {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                DetailHero(opportunity: lead)
                ContactCard(opportunity: lead)
            }
            .padding(.vertical, OPSStyle.Layout.spacing3)
        }
    }
}
#endif
