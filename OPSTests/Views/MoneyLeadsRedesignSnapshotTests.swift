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

    // MARK: - Ledger rows + swipe actions (Books deepen, 2026-07-01)

    func testRenderLedgerRows() {
        let overdue = Invoice.previewRow(number: "INV-00214", status: .pastDue, total: 4_800, dueInDays: -12, title: "Acme deck rebuild")
        let partial = Invoice.previewRow(number: "INV-00219", status: .partiallyPaid, total: 9_200, balanceDue: 3_400, dueInDays: 6)
        let paid    = Invoice.previewRow(number: "INV-00221", status: .paid, total: 2_150)
        let draft   = Invoice.previewRow(number: "INV-00224", status: .draft, total: 5_600)
        snapshot("money_invoice_rows") {
            VStack(spacing: 0) {
                BooksInvoiceRow(invoice: overdue, clientName: "MARCUS WEBB", onTap: {})
                BooksInvoiceRow(invoice: partial, clientName: "THE HENSONS", onTap: {})
                BooksInvoiceRow(invoice: paid, clientName: "JAMIE PARK", onTap: {})
                BooksInvoiceRow(invoice: draft, clientName: nil, onTap: {})
            }
        }

        let draftEst = Estimate.previewRow(number: "EST-0142", status: .draft, total: 14_200, title: "Roof tear-off — 28 sq")
        let sentEst  = Estimate.previewRow(number: "EST-0139", status: .sent, total: 11_800)
        let wonEst   = Estimate.previewRow(number: "EST-0134", status: .converted, total: 22_400)
        let lostEst  = Estimate.previewRow(number: "EST-0131", status: .declined, total: 6_300)
        snapshot("money_estimate_rows") {
            VStack(spacing: 0) {
                BooksEstimateRow(estimate: draftEst, clientName: "NORTHWAY HVAC", onTap: {})
                BooksEstimateRow(estimate: sentEst, clientName: "QUARRY ELECTRIC", onTap: {})
                BooksEstimateRow(estimate: wonEst, clientName: "OAKMONT CONTRACT", onTap: {})
                BooksEstimateRow(estimate: lostEst, clientName: nil, onTap: {})
            }
        }

        snapshot("money_expense_rows") {
            VStack(spacing: 0) {
                // Receipt URL present — AsyncImage can't resolve in the renderer,
                // so this exercises the abstract-receipt placeholder path.
                BooksExpenseRow(expense: .previewRow(merchant: "HOME DEPOT", amount: 184.22, status: .submitted, category: "Materials"), who: "DEVON", onTap: {})
                BooksExpenseRow(expense: .previewRow(merchant: "SHELL", amount: 92.10, status: .approved, category: "Fuel"), who: nil, onTap: {})
                BooksExpenseRow(expense: .previewRow(merchant: "SITEONE LANDSCAPE", amount: 412.80, status: .draft, category: "Materials", hasReceipt: false), who: "MARCO", onTap: {})
            }
        }
    }

    func testRenderLedgerSwipeStrips() {
        let unpaid = Invoice.previewRow(number: "INV-00214", status: .awaitingPayment, total: 4_800, dueInDays: 4, title: "Acme deck rebuild")
        let payment = BooksRowAction(id: "payment", label: "PAYMENT", menuTitle: "Record Payment", icon: "dollarsign.circle", tone: OPSStyle.Colors.olive) {}
        let void = BooksRowAction(id: "void", label: "VOID", menuTitle: "Void Invoice", icon: OPSStyle.Icons.xmarkCircle, tone: OPSStyle.Colors.rose, isDestructive: true) {}
        let send = BooksRowAction(id: "send", label: "SEND", menuTitle: "Send Estimate", icon: "paperplane", tone: OPSStyle.Colors.olive) {}
        let delete = BooksRowAction(id: "delete", label: "DELETE", menuTitle: "Delete Expense", icon: OPSStyle.Icons.trash, tone: OPSStyle.Colors.rose, isDestructive: true) {}

        snapshot("money_swipe_leading_payment") {
            BooksSwipeRow(rowID: "r1", leading: [payment], trailing: [void],
                          openRowID: .constant("r1"), initialReveal: .leading) {
                BooksInvoiceRow(invoice: unpaid, clientName: "MARCUS WEBB", onTap: {})
            }
        }
        snapshot("money_swipe_trailing_void") {
            BooksSwipeRow(rowID: "r2", leading: [payment], trailing: [void],
                          openRowID: .constant("r2"), initialReveal: .trailing) {
                BooksInvoiceRow(invoice: unpaid, clientName: "MARCUS WEBB", onTap: {})
            }
        }
        snapshot("money_swipe_leading_send") {
            let draftEst = Estimate.previewRow(number: "EST-0142", status: .draft, total: 14_200)
            BooksSwipeRow(rowID: "r3", leading: [send],
                          openRowID: .constant("r3"), initialReveal: .leading) {
                BooksEstimateRow(estimate: draftEst, clientName: "NORTHWAY HVAC", onTap: {})
            }
        }
        snapshot("money_swipe_trailing_delete") {
            BooksSwipeRow(rowID: "r4", trailing: [delete],
                          openRowID: .constant("r4"), initialReveal: .trailing) {
                BooksExpenseRow(expense: .previewRow(merchant: "HOME DEPOT", amount: 184.22, status: .draft, category: "Materials"), who: "DEVON", onTap: {})
            }
        }
    }

    func testRenderReviewBatchesLink() {
        snapshot("money_review_batches_link") {
            VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing3) {
                BooksReviewBatchesLink(count: 0, onTap: {})
                BooksReviewBatchesLink(count: 3, onTap: {})
            }
            .padding(OPSStyle.Layout.spacing3_5)
        }
    }

    func testRenderCommandGridPermissionReflow() {
        let vm = MoneyDashboardViewModel.previewStub()
        snapshot("money_grid_no_pipeline") {
            BooksCommandGrid(
                viewModel: vm,
                cashflowVM: CashflowForecastViewModel(),
                canFinances: true,
                canPipeline: false
            )
            .padding(.vertical, OPSStyle.Layout.spacing3)
        }
        snapshot("money_grid_pipeline_only") {
            BooksCommandGrid(
                viewModel: vm,
                cashflowVM: CashflowForecastViewModel(),
                canFinances: false,
                canPipeline: true
            )
            .padding(.vertical, OPSStyle.Layout.spacing3)
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
