//
//  ExpenseConsoleSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the expense batch console — renders every console and
//  detail state to PNGs (UIHostingController + UIWindow + drawHierarchy,
//  dark, 390×844) and stashes them as attachments + files for
//  docs/artifacts export. Fixture DTOs only; no network.
//

import XCTest
import SwiftUI
import SwiftData
@testable import OPS

@MainActor
final class ExpenseConsoleSnapshotTests: XCTestCase {

    private let frameSize = CGSize(width: 390, height: 844)

    private var outDir: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("expense-console-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Fixtures

    private let marcus = "11111111-1111-1111-1111-111111111111"
    private let diego  = "22222222-2222-2222-2222-222222222222"

    private func names(_ id: String?) -> String {
        switch id {
        case .some(let value) where value == marcus: return "MARCUS WEBB"
        case .some(let value) where value == diego:  return "DIEGO RUIZ"
        default: return "UNASSIGNED"
        }
    }

    private func batch(
        id: String,
        number: Int,
        status: String,
        total: Double,
        approved: Double? = nil,
        paidAt: String? = nil,
        submittedBy: String,
        periodStart: String,
        periodEnd: String,
        scopeProjectId: String? = nil
    ) -> ExpenseBatchDTO {
        ExpenseBatchDTO(
            id: id,
            companyId: "co",
            batchNumber: String(format: "EXP-BATCH-%04d", number),
            periodStart: periodStart,
            periodEnd: periodEnd,
            status: status,
            submittedBy: submittedBy,
            reviewedBy: nil,
            reviewedAt: nil,
            totalAmount: total,
            approvedAmount: approved,
            parentBatchId: nil,
            amendmentNumber: 0,
            reviewNotes: nil,
            createdAt: "2026-07-01T10:00:00+00:00",
            scopeProjectId: scopeProjectId,
            paidAt: paidAt,
            paidBy: paidAt == nil ? nil : marcus
        )
    }

    private func line(
        id: String,
        batchId: String,
        merchant: String,
        amount: Double,
        status: String = "submitted",
        flaggedBy: String? = nil,
        category: String = "Materials",
        expenseDate: String = "2026-07-05"
    ) -> ExpenseDTO {
        ExpenseDTO(
            id: id,
            companyId: "co",
            submittedBy: marcus,
            status: status,
            categoryId: "cat",
            merchantName: merchant,
            description: flaggedBy == nil ? nil : "Receipt is blurry — need a retake.",
            amount: amount,
            taxAmount: 4.5,
            currency: "USD",
            expenseDate: expenseDate,
            paymentMethod: "personal_card",
            receiptImageUrl: nil,
            receiptThumbnailUrl: nil,
            receiptMissingReason: nil,
            receiptMissingNote: nil,
            projectMissingReason: nil,
            projectMissingNote: nil,
            ocrRawData: nil,
            ocrConfidence: nil,
            batchId: batchId,
            approvedBy: nil,
            approvedAt: nil,
            rejectedBy: nil,
            rejectedAt: nil,
            rejectionReason: nil,
            flagComment: flaggedBy == nil ? nil : "Wrong job — this was the Hilltop deck.",
            flaggedBy: flaggedBy,
            flaggedAt: nil,
            accountingSyncStatus: nil,
            accountingSyncId: nil,
            accountingSyncedAt: nil,
            createdAt: "2026-07-05T10:00:00+00:00",
            updatedAt: "2026-07-05T10:00:00+00:00",
            deletedAt: nil,
            allocations: [ExpenseAllocationDTO(id: "a-\(id)", expenseId: id, projectId: "proj", percentage: 100, amount: nil)],
            category: ExpenseCategoryDTO(
                id: "cat", companyId: "co", name: category, icon: "shippingbox.fill",
                isActive: true, isDefault: true, sortOrder: 0, createdAt: nil
            )
        )
    }

    /// A believable console dataset: two review batches (one flagged), a
    /// partial + an auto in TO PAY, two payouts across two months, one
    /// filling envelope + one sent-back batch with the crew.
    private func fixtureBatches() -> [ExpenseBatchDTO] {
        [
            batch(id: "r1", number: 41, status: "pending_review", total: 412,
                  submittedBy: marcus, periodStart: "2026-06-01", periodEnd: "2026-06-30"),
            batch(id: "r2", number: 44, status: "pending_review", total: 340,
                  submittedBy: marcus, periodStart: "2026-07-01", periodEnd: "2026-07-14"),
            batch(id: "r3", number: 43, status: "pending_review", total: 488,
                  submittedBy: diego, periodStart: "2026-07-01", periodEnd: "2026-07-14"),
            batch(id: "p1", number: 38, status: "auto_approved", total: 240, approved: 0,
                  submittedBy: diego, periodStart: "2026-06-01", periodEnd: "2026-06-30"),
            batch(id: "p2", number: 39, status: "partially_approved", total: 500, approved: 320,
                  submittedBy: marcus, periodStart: "2026-06-01", periodEnd: "2026-06-30"),
            batch(id: "paid1", number: 35, status: "approved", total: 618, approved: 0,
                  paidAt: "2026-07-08T18:00:00+00:00",
                  submittedBy: marcus, periodStart: "2026-05-01", periodEnd: "2026-05-31"),
            batch(id: "paid2", number: 31, status: "approved", total: 275, approved: 275,
                  paidAt: "2026-06-20T18:00:00+00:00",
                  submittedBy: diego, periodStart: "2026-05-01", periodEnd: "2026-05-31"),
            batch(id: "crew1", number: 45, status: "open", total: 186,
                  submittedBy: diego, periodStart: "2026-07-01", periodEnd: "2026-07-14"),
            batch(id: "crew2", number: 42, status: "rejected", total: 92,
                  submittedBy: marcus, periodStart: "2026-06-01", periodEnd: "2026-06-30")
        ]
    }

    private func fixtureLines() -> [ExpenseDTO] {
        [
            line(id: "e1", batchId: "r1", merchant: "HOME DEPOT", amount: 214),
            line(id: "e2", batchId: "r1", merchant: "SHELL", amount: 86, category: "Fuel / Mileage"),
            line(id: "e3", batchId: "r1", merchant: "GRAYBAR", amount: 112),
            line(id: "e4", batchId: "r2", merchant: "LOWES", amount: 340),
            line(id: "e5", batchId: "r3", merchant: "FASTENAL", amount: 250),
            line(id: "e6", batchId: "r3", merchant: "SUBWAY", amount: 38, flaggedBy: marcus, category: "Other"),
            line(id: "e7", batchId: "r3", merchant: "ACE HARDWARE", amount: 200, flaggedBy: marcus),
            line(id: "e8", batchId: "p1", merchant: "SHERWIN-WILLIAMS", amount: 240, status: "approved"),
            line(id: "e9", batchId: "p2", merchant: "UNITED RENTALS", amount: 320, status: "approved"),
            line(id: "e10", batchId: "paid1", merchant: "HOME DEPOT", amount: 618, status: "reimbursed", expenseDate: "2026-05-12"),
            line(id: "e11", batchId: "paid2", merchant: "SHELL", amount: 275, status: "reimbursed", expenseDate: "2026-05-20"),
            line(id: "e12", batchId: "crew1", merchant: "HOME DEPOT", amount: 186, expenseDate: "2026-07-09"),
            line(id: "e13", batchId: "crew2", merchant: "SUBWAY", amount: 92, status: "rejected", expenseDate: "2026-06-14")
        ]
    }

    private var fixedNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 11; comps.hour = 12
        return Calendar.current.date(from: comps)!
    }

    // MARK: - Console composites

    /// Strip + queue + CTA on the black canvas — the console minus the nav
    /// header (pure views, no network).
    private func console(
        bucket: ExpenseBucket,
        batches: [ExpenseBatchDTO],
        lines: [ExpenseDTO],
        crewExpanded: Bool = false,
        showCTA: Bool = true
    ) -> some View {
        let stats = ExpenseBuckets.lineStats(lines)
        let split = ExpenseBuckets.split(batches, lineStats: stats)
        let metrics = ExpenseBuckets.computeMetrics(batches: batches, expenses: lines, now: fixedNow)
        let cleanReview = split.review.filter { (stats[$0.id]?.flagged ?? 0) == 0 }

        return ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    ExpenseInstrumentStrip(metrics: metrics, selectedBucket: .constant(bucket))
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    ExpenseBucketQueue(
                        bucket: bucket,
                        split: split,
                        lineStats: stats,
                        autoSubmitGraceDays: 7,
                        canApprove: true,
                        nameFor: names,
                        onOpen: { _ in },
                        onApprove: { _ in },
                        onPay: { _ in },
                        onApproveGroup: { _ in },
                        onPayGroup: { _ in },
                        initialCrewExpanded: crewExpanded
                    )
                }
                .padding(.top, OPSStyle.Layout.spacing2)
            }

            if showCTA {
                switch bucket {
                case .review where cleanReview.count > 1:
                    ExpenseBulkCTABar(
                        label: "APPROVE ALL · \(BooksFormat.currency(cleanReview.reduce(0) { $0 + ($1.totalAmount ?? 0) }))"
                    ) {}
                case .pay where split.pay.count > 1:
                    ExpenseBulkCTABar(
                        label: "PAY ALL · \(BooksFormat.currency(split.pay.reduce(0) { $0 + ExpenseBuckets.owedAmount($1) }))"
                    ) {}
                default:
                    EmptyView()
                }
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
    }

    func testRenderConsoleStates() {
        let batches = fixtureBatches()
        let lines = fixtureLines()

        renderToPNG("console-review") {
            console(bucket: .review, batches: batches, lines: lines)
        }
        renderToPNG("console-pay") {
            console(bucket: .pay, batches: batches, lines: lines)
        }
        renderToPNG("console-paid") {
            console(bucket: .paid, batches: batches, lines: lines)
        }
        renderToPNG("console-crew-expanded") {
            console(bucket: .review, batches: batches, lines: lines, crewExpanded: true, showCTA: false)
        }
        renderToPNG("console-empty") {
            console(bucket: .review, batches: [], lines: [])
        }
        renderToPNG("console-pay-empty") {
            console(bucket: .pay, batches: [], lines: [])
        }
        renderToPNG("console-paid-empty") {
            console(bucket: .paid, batches: [], lines: [])
        }
    }

    // MARK: - Batch detail states

    private func makeTeamContainer() throws -> ModelContainer {
        let schema = Schema([TeamMember.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(TeamMember(id: marcus, firstName: "Marcus", lastName: "Webb", role: "Crew"))
        context.insert(TeamMember(id: diego, firstName: "Diego", lastName: "Ruiz", role: "Crew"))
        try context.save()
        return container
    }

    private func detailView(
        batch: ExpenseBatchDTO,
        lines: [ExpenseDTO],
        container: ModelContainer
    ) -> some View {
        let viewModel = ExpenseViewModel()
        viewModel.selectedBatchExpenses = lines
        viewModel.flaggedExpenseIds = Set(lines.compactMap { $0.flaggedBy != nil ? $0.id : nil })

        let permissions = PermissionStore()
        permissions.permissions = ["expenses.approve": "all", "expenses.view": "all"]

        return NavigationStack {
            ExpenseBatchDetailView(batch: batch, viewModel: viewModel)
        }
        .environmentObject(DataController())
        .environmentObject(permissions)
        .modelContainer(container)
        .frame(width: frameSize.width, height: frameSize.height)
    }

    func testRenderDetailStates() throws {
        let container = try makeTeamContainer()
        let batches = fixtureBatches()
        let lines = fixtureLines()

        renderToPNG("detail-review-flagged") {
            detailView(
                batch: batches.first { $0.id == "r3" }!,
                lines: lines.filter { $0.batchId == "r3" },
                container: container
            )
        }
        renderToPNG("detail-pay-partial") {
            detailView(
                batch: batches.first { $0.id == "p2" }!,
                lines: lines.filter { $0.batchId == "p2" },
                container: container
            )
        }
        renderToPNG("detail-paid") {
            detailView(
                batch: batches.first { $0.id == "paid1" }!,
                lines: lines.filter { $0.batchId == "paid1" },
                container: container
            )
        }
        renderToPNG("detail-crew-filling") {
            detailView(
                batch: batches.first { $0.id == "crew1" }!,
                lines: lines.filter { $0.batchId == "crew1" },
                container: container
            )
        }
    }

    // MARK: - Render harness (UIHostingController + UIWindow + drawHierarchy)

    private func renderToPNG(_ name: String, @ViewBuilder _ make: () -> some View) {
        let host = UIHostingController(rootView: make().frame(width: frameSize.width, height: frameSize.height))
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: frameSize)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: frameSize))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

        let renderer = UIGraphicsImageRenderer(size: frameSize)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name) -> \(outDir.appendingPathComponent("\(name).png").path)")
    }
}
