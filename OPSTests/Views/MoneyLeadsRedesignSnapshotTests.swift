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
import SwiftData
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
        attach(name, data: data, size: image.size)
    }

    /// UIWindow + drawHierarchy render path — for views hosting UIKit-backed
    /// content (`Menu` renders a yellow unsupported-view placeholder under
    /// plain ImageRenderer). Same output contract as `snapshot`.
    private func snapshotHosted<V: View>(_ name: String, width: CGFloat? = nil, @ViewBuilder _ content: () -> V) {
        let w = width ?? deviceWidth
        let host = UIHostingController(
            rootView: content()
                .frame(width: w)
                .background(OPSStyle.Colors.background)
                .environment(\.colorScheme, .dark)
        )
        let fitted = host.sizeThatFits(in: CGSize(width: w, height: .greatestFiniteMagnitude))
        let size = CGSize(width: w, height: max(fitted.height, 10))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        // A detached test window never commits to the render server —
        // drawHierarchy returns blank. Attach to the host app's scene.
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        window.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        attach(name, data: data, size: size)
    }

    private func attach(_ name: String, data: Data, size: CGSize) {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        print("📸 SNAPSHOT \(name) (\(Int(size.width))×\(Int(size.height))pt)")
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
                BooksReviewBatchesLink(reviewCount: 0, payCount: 0, onTap: {})
                BooksReviewBatchesLink(reviewCount: 0, payCount: 2, onTap: {})
                BooksReviewBatchesLink(reviewCount: 3, payCount: 2, onTap: {})
            }
            .padding(OPSStyle.Layout.spacing3_5)
        }
    }

    // MARK: - Drill-down sheets (rebuilt 2026-07-01)

    /// Renders each lens's header + content directly (the production sheet
    /// wraps them in a ScrollView, which lays out empty under ImageRenderer).
    private func sheetShot<V: View>(_ name: String, title: String, tag: String, @ViewBuilder _ content: () -> V) {
        snapshot(name) {
            VStack(alignment: .leading, spacing: 0) {
                BooksSheetHeader(title: title, tag: tag)
                    .padding(.top, OPSStyle.Layout.spacing4)
                    .padding(.bottom, OPSStyle.Layout.spacing3_5)
                content()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
    }

    func testRenderLensSheets() {
        let vm = MoneyDashboardViewModel.previewStub()
        sheetShot("sheet_pl", title: "P&L", tag: "6M") {
            BooksPLSheet(viewModel: vm)
        }
        sheetShot("sheet_cashflow", title: "CASH FLOW", tag: "6M") {
            BooksCashFlowSheet(viewModel: vm)
        }
        sheetShot("sheet_receivables", title: "RECEIVABLES", tag: "ALL OPEN") {
            BooksARSheet(viewModel: vm)
                .environmentObject(DataController())
        }
        sheetShot("sheet_forecast", title: "FORECAST", tag: "ACTIVE") {
            BooksForecastSheet(viewModel: vm)
        }
        sheetShot("sheet_jobs", title: "JOBS", tag: "6M") {
            BooksJobsSheet(viewModel: vm)
        }
        sheetShot("sheet_empty_state", title: "JOBS", tag: "6M") {
            BooksJobsSheet(viewModel: .previewEmpty())
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

    // MARK: - Leads (redesign 2026-07-17 — chase console states)

    func testRenderLeadsSummary() {
        let vm = PipelineViewModel.previewLoaded()
        snapshot("leads_summary") {
            LeadsSummary(viewModel: vm).padding(.vertical, OPSStyle.Layout.spacing3)
        }
        snapshot("leads_summary_zero") {
            LeadsSummary(viewModel: .previewLoaded(opportunities: []))
                .padding(.vertical, OPSStyle.Layout.spacing3)
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

    /// Every chase-strip state on the rebuilt card: overdue / due today /
    /// your move / their move (waiting) / fresh — plus source rendering.
    func testRenderLeadTriageCards() {
        let vm = PipelineViewModel.previewLoaded()
        let overdue = Opportunity.preview(
            title: "Roof tear-off — 28 sq", contactName: "Marcus Webb",
            stage: .quoting, estimatedValue: 14_200, daysInStage: 5, nextFollowUpDaysFromNow: -3
        )
        let today = Opportunity.preview(
            title: "Window install — 8 units", contactName: "The Hensons",
            stage: .quoted, estimatedValue: 11_800, daysInStage: 3, nextFollowUpDaysFromNow: 0
        )
        let yourMove = Opportunity.preview(
            title: "Skylight quote question", contactName: "Aimee Watari",
            stage: .quoted, estimatedValue: 6_400, daysInStage: 2
        )
        yourMove.lastMessageDirection = "in"
        yourMove.lastInboundAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
        let waiting = Opportunity.preview(
            title: "Gutter replacement — 140 lf", contactName: "Dana Ruiz",
            stage: .quoted, estimatedValue: 8_600, daysInStage: 4, nextFollowUpDaysFromNow: 3
        )
        waiting.source = "referral"
        waiting.lastMessageDirection = "in"
        waiting.lastInboundAt = Calendar.current.date(byAdding: .day, value: -4, to: Date())
        waiting.handledAt = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        let fresh = Opportunity.preview(
            title: "Leak repair — kitchen ceiling", contactName: "Jamie Park",
            stage: .newLead, estimatedValue: 2_200, daysInStage: 0
        )
        snapshotHosted("leads_triage_cards") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                LeadTriageCard(lead: overdue, viewModel: vm, bucket: .overdue)
                LeadTriageCard(lead: today, viewModel: vm, bucket: .dueToday)
                LeadTriageCard(lead: yourMove, viewModel: vm, bucket: .waitingOnYou)
                LeadTriageCard(lead: waiting, viewModel: vm, bucket: .waitingOnThem)
                LeadTriageCard(lead: fresh, viewModel: vm, bucket: .fresh)
            }
            .padding(OPSStyle.Layout.spacing3_5)
        }
    }

    /// The summary footer band: collapsed, expanded (lavender agent rail),
    /// and absent (no ai_summary → no band).
    func testRenderLeadTriageCardBand() {
        let vm = PipelineViewModel.previewLoaded()
        func summarized() -> Opportunity {
            let o = Opportunity.preview(
                title: "Window install — 8 units", contactName: "The Hensons",
                stage: .quoted, estimatedValue: 11_800, daysInStage: 3
            )
            o.lastMessageDirection = "in"
            o.lastInboundAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
            o.aiSummary = "Quote sent Tuesday. They asked about triple-pane pricing; the decision lands after the 15th."
            o.aiSummaryUpdatedAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
            return o
        }
        let none = Opportunity.preview(
            title: "Gutter replacement — 140 lf", contactName: "Dana Ruiz",
            stage: .quoted, estimatedValue: 8_600, daysInStage: 4, nextFollowUpDaysFromNow: 3
        )
        snapshotHosted("leads_card_band_states") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                LeadTriageCard(lead: summarized(), viewModel: vm, bucket: .waitingOnYou)
                LeadTriageCard(lead: summarized(), viewModel: vm, bucket: .waitingOnYou,
                               summaryInitiallyExpanded: true)
                LeadTriageCard(lead: none, viewModel: vm, bucket: .all)
            }
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
        snapshotHosted("leads_triage_cards_terminal") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                LeadTriageCard(lead: wonConverted, viewModel: vm, bucket: .all)
                LeadTriageCard(lead: wonUnconverted, viewModel: vm, bucket: .all)
                LeadTriageCard(lead: lost, viewModel: vm, bucket: .all)
            }
            .padding(OPSStyle.Layout.spacing3_5)
        }
    }

    /// The dossier document's interactive rows (2026-07-22): tappable CLIENT
    /// with chevron, linked PROJECT open-only + guarded MATCH PROJECT state,
    /// and the LAST WORD correspondence row (inbound, outbound, and absent —
    /// no correspondence leaves no row, not a `—`).
    func testRenderLeadDocumentRows() {
        let linkedLead = Opportunity.preview(
            title: "Deck resurface — 320 sq ft", contactName: "Jill Adams",
            stage: .won, estimatedValue: 9_800, daysInStage: 3
        )
        linkedLead.projectId = "qa-linked-project"
        let unlinkedLead = Opportunity.preview(
            title: "Deck resurface — 320 sq ft", contactName: "Jill Adams",
            stage: .won, estimatedValue: 9_800, daysInStage: 3
        )
        let client = Client(id: "qa-client", name: "Adams Property Group")
        let inbound = LeadCorrespondence(
            subject: "Re: Deck quote — triple-pane pricing",
            direction: "inbound",
            occurredAt: Calendar.current.date(byAdding: .hour, value: -50, to: Date())!,
            source: "email"
        )
        let outbound = LeadCorrespondence(
            subject: "Updated quote attached",
            direction: "outbound",
            occurredAt: Calendar.current.date(byAdding: .hour, value: -3, to: Date())!,
            source: "email"
        )

        snapshot("lead_document_rows") {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                // Linked project (open only) · THEM last word · tappable client
                LeadDetailsDocument(
                    lead: linkedLead, client: client, rosterState: .mirrorsClient,
                    canEdit: true, canMatchProject: false, projectName: "Adams deck resurface",
                    attachments: [], estimates: [], correspondence: inbound
                )
                // Won + unconverted → guarded MATCH PROJECT · YOU last word
                LeadDetailsDocument(
                    lead: unlinkedLead, client: client, rosterState: .mirrorsClient,
                    canEdit: true, canMatchProject: true, projectName: nil,
                    attachments: [], estimates: [], correspondence: outbound
                )
                // Read-only, nothing linked, silent — the quiet document
                LeadDetailsDocument(
                    lead: unlinkedLead, client: nil, rosterState: .noClient,
                    canEdit: false, projectName: nil,
                    attachments: [], estimates: []
                )
            }
            .padding(.vertical, OPSStyle.Layout.spacing3_5)
            .environmentObject(PermissionStore.shared)
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

    /// The dossier hero: title-first with people + address + NEXT TOUCH, the
    /// blank fallback chain (no title/value/address → contact name + em
    /// dashes), and the nav status chips.
    func testRenderLeadDetailComponents() {
        let full = Opportunity.preview(
            title: "Roof tear-off, 28 sq", contactName: "Helen Calloway",
            stage: .quoted, estimatedValue: 14_200, daysInStage: 9,
            nextFollowUpDaysFromNow: 3
        )
        full.contactPhone = "(555) 123-4567"
        full.contactEmail = "helen@example.com"
        full.address = "1240 Maple Ave"
        full.source = "referral"
        let blanks = Opportunity.preview(
            contactName: "Jamie Park", stage: .newLead, daysInStage: 0
        )
        snapshot("leads_detail_hero") {
            VStack(spacing: OPSStyle.Layout.spacing4) {
                DetailHero(opportunity: full, clientName: "Calloway Homes")
                DetailHero(opportunity: blanks)
            }
            .padding(.vertical, OPSStyle.Layout.spacing3)
        }
        snapshot("leads_status_chips") {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                StageTag(stage: .quoted, detail: "9D", showsChevron: true)
                StageTag(stage: .negotiation, showsChevron: true)
                StageTag(stage: .newLead, detail: "0D", showsChevron: true)
                StageTag(stage: .won)
                StageTag(stage: .lost)
            }
            .padding(OPSStyle.Layout.spacing3)
        }
    }

    /// The dossier document: roster states (ON FILE / ADD TO CLIENT / no
    /// client) with project + files rows, blanks as em dashes. Deck feature
    /// rows need SwiftData for their @Query — an in-memory DeckDesign
    /// container backs the render.
    func testRenderLeadDetailsDocument() {
        let lead = Opportunity.preview(
            title: "Roof tear-off, 28 sq", contactName: "Helen Calloway",
            stage: .quoted, estimatedValue: 14_200, daysInStage: 9
        )
        lead.contactPhone = "(555) 123-4567"
        lead.contactEmail = "helen@example.com"
        let client = Client(id: "c1", name: "Calloway Homes")
        let estimate = Estimate(id: "e1", companyId: "preview", estimateNumber: "EST-0142")
        estimate.title = "Roof tear-off"
        estimate.total = 14_200
        let attachment = LeadAttachment(
            id: "a1", filename: "roof-photos.pdf", mimeType: "application/pdf",
            sourceUrl: nil, fromEmail: "helen@example.com",
            ingestStatus: "stored", occurredAt: "2026-07-14T10:00:00Z",
            createdAt: "2026-07-14T10:00:00Z"
        )
        guard let container = try? ModelContainer(
            for: DeckDesign.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ) else {
            XCTFail("in-memory DeckDesign container failed")
            return
        }
        snapshot("leads_details_document") {
            VStack(spacing: OPSStyle.Layout.spacing4) {
                // ON FILE + project + files
                LeadDetailsDocument(
                    lead: lead, client: client, rosterState: .onFile, canEdit: true,
                    projectName: "Calloway roof tear-off",
                    attachments: [attachment], estimates: [estimate]
                )
                // ADD TO CLIENT
                LeadDetailsDocument(
                    lead: lead, client: client, rosterState: .notOnFile, canEdit: true,
                    projectName: nil, attachments: [], estimates: []
                )
                // No client — em dashes
                LeadDetailsDocument(
                    lead: lead, client: nil, rosterState: .noClient, canEdit: false,
                    projectName: nil, attachments: [], estimates: []
                )
            }
            .padding(.vertical, OPSStyle.Layout.spacing3)
            .environmentObject(PermissionStore.previewWithFullAccess())
            .modelContainer(container)
        }
    }
}
#endif
