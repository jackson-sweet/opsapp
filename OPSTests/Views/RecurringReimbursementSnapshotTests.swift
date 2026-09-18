//
//  RecurringReimbursementSnapshotTests.swift
//  OPSTests
//
//  Visual proof for recurring reimbursements — a fixed monthly amount the
//  office pays a crew member with their expenses. Renders every surface the
//  feature touches to PNGs (FixedSizeSnapshot: hosted in the app's own window
//  at a fixed 390×844, dark, device-agnostic): the line as My Expenses and the
//  Books ledger draw it, the batch review card collapsed and open, the
//  settings list, the editor in each of its stages, and the read-only line
//  sheet.
//
//  Invented people and amounts only, and a stub repository — nothing here
//  reads or writes a real record. `ops-ios` is a public repository.
//

import XCTest
import SwiftUI
import SwiftData
@testable import OPS

@MainActor
final class RecurringReimbursementSnapshotTests: XCTestCase {

    private let frameSize = CGSize(width: 390, height: 844)

    private let priya = "11111111-1111-1111-1111-111111111111"
    private let sam   = "22222222-2222-2222-2222-222222222222"
    private let setupId = "33333333-3333-3333-3333-333333333333"

    private var outDir: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recurring-reimbursement-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Stub repository

    /// Answers reads from a seeded snapshot and refuses every command — no
    /// surface rendered here sends one.
    private final class StubRepository: RecurringReimbursementRepository {
        enum Unused: Error { case notSent }
        let snapshot: RecurringReimbursementsSnapshot

        init(snapshot: RecurringReimbursementsSnapshot) { self.snapshot = snapshot }

        func fetchSnapshot() async throws -> RecurringReimbursementsSnapshot { snapshot }
        func create(_ params: CreateRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO { throw Unused.notSent }
        func update(_ params: UpdateRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO { throw Unused.notSent }
        func end(_ params: EndRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO { throw Unused.notSent }
        func delete(_ params: DeleteRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO { throw Unused.notSent }
        func skipLine(expenseId: String) async throws -> ExpenseRecurringReimbursementDTO { throw Unused.notSent }
        func restoreLine(expenseId: String) async throws -> ExpenseRecurringReimbursementDTO { throw Unused.notSent }
    }

    // MARK: - Fixtures

    private func setup(
        id: String? = nil,
        userId: String? = nil,
        name: String = "Phone plan",
        amount: Double = 275,
        lastPeriod: String? = nil
    ) -> ExpenseRecurringReimbursementDTO {
        ExpenseRecurringReimbursementDTO(
            id: id ?? setupId,
            companyId: "co-1",
            userId: userId ?? priya,
            name: name,
            amount: amount,
            currency: "CAD",
            firstPeriod: "2026-08-01",
            lastPeriod: lastPeriod,
            nextPeriod: "2026-10-01",
            createdBy: sam,
            updatedBy: sam,
            createdAt: "2026-08-01T16:20:11.402118+00:00",
            updatedAt: "2026-09-02T16:20:11.402118+00:00",
            lines: [
                RecurringLineSummary(expenseId: "line-aug", period: "2026-08-01", batchId: "batch-1", status: "approved", amount: amount, deleted: false),
                RecurringLineSummary(expenseId: "line-sep", period: "2026-09-01", batchId: "batch-1", status: "approved", amount: amount, deleted: false),
            ]
        )
    }

    private func snapshot(_ setups: [ExpenseRecurringReimbursementDTO]) -> RecurringReimbursementsSnapshot {
        RecurringReimbursementsSnapshot(setups: setups, currency: "CAD", timeZone: "America/Vancouver")
    }

    /// A view model already settled on `snapshot`, with no network behind it.
    private func model(_ snapshot: RecurringReimbursementsSnapshot) async -> RecurringReimbursementViewModel {
        let repository = StubRepository(snapshot: snapshot)
        let viewModel = RecurringReimbursementViewModel(
            makeRepository: { _ in repository },
            toasts: { _ in }
        )
        viewModel.setup(companyId: "co-1")
        await viewModel.load()
        return viewModel
    }

    private func recurringLine(
        id: String = "line-sep",
        period: String = "2026-09-01",
        status: String = "approved",
        amount: Double = 275
    ) -> ExpenseDTO {
        ExpenseDTO(
            id: id, companyId: "co-1", submittedBy: priya, status: status, categoryId: nil,
            merchantName: "Phone plan", description: "Monthly · September 2026", amount: amount,
            taxAmount: nil, currency: "CAD", expenseDate: period, paymentMethod: nil,
            receiptImageUrl: nil, receiptThumbnailUrl: nil, receiptMissingReason: "other",
            receiptMissingNote: "Recurring reimbursement. No receipt needed.",
            projectMissingReason: "overhead", projectMissingNote: nil, ocrRawData: nil, ocrConfidence: nil,
            batchId: "batch-1", approvedBy: sam, approvedAt: "2026-09-02T16:20:11+00:00",
            rejectedBy: nil, rejectedAt: nil, rejectionReason: nil, flagComment: nil, flaggedBy: nil,
            flaggedAt: nil, accountingSyncStatus: nil, accountingSyncId: nil, accountingSyncedAt: nil,
            createdAt: "2026-09-02T16:20:11+00:00", updatedAt: "2026-09-02T16:20:11+00:00", deletedAt: nil,
            allocations: nil, category: nil,
            recurringReimbursementId: setupId, recurringPeriod: period
        )
    }

    private func receiptLine(
        id: String = "line-receipt",
        merchant: String = "Harbour Building Supply",
        amount: Double = 118.42,
        status: String = "submitted"
    ) -> ExpenseDTO {
        ExpenseDTO(
            id: id, companyId: "co-1", submittedBy: priya, status: status, categoryId: "cat-1",
            merchantName: merchant, description: nil, amount: amount,
            taxAmount: 14.21, currency: "CAD", expenseDate: "2026-09-08", paymentMethod: "personal_card",
            receiptImageUrl: nil, receiptThumbnailUrl: nil, receiptMissingReason: nil,
            receiptMissingNote: nil, projectMissingReason: nil, projectMissingNote: nil,
            ocrRawData: nil, ocrConfidence: nil, batchId: "batch-1", approvedBy: nil, approvedAt: nil,
            rejectedBy: nil, rejectedAt: nil, rejectionReason: nil, flagComment: nil, flaggedBy: nil,
            flaggedAt: nil, accountingSyncStatus: nil, accountingSyncId: nil, accountingSyncedAt: nil,
            createdAt: "2026-09-08T18:02:00+00:00", updatedAt: "2026-09-08T18:02:00+00:00", deletedAt: nil,
            allocations: nil,
            category: ExpenseCategoryDTO(
                id: "cat-1", companyId: "co-1", name: "Materials", icon: "shippingbox.fill",
                isActive: true, isDefault: true, sortOrder: 0, createdAt: nil
            )
        )
    }

    private func batch(paidAt: String? = nil) -> ExpenseBatchDTO {
        ExpenseBatchDTO(
            id: "batch-1", companyId: "co-1", batchNumber: "EXP-BATCH-0014",
            periodStart: "2026-09-01", periodEnd: "2026-09-30", status: "pending_review",
            submittedBy: priya, reviewedBy: nil, reviewedAt: nil,
            totalAmount: 393.42, approvedAmount: nil, parentBatchId: nil, amendmentNumber: 0,
            reviewNotes: nil, createdAt: "2026-09-01T07:00:00+00:00", scopeProjectId: nil,
            paidAt: paidAt, paidBy: nil, reimbursementAmount: nil
        )
    }

    private func approver() -> PermissionStore {
        let store = PermissionStore()
        store.permissions = ["expenses.approve": "all", "expenses.view": "all"]
        return store
    }

    private func peopleContainer() throws -> ModelContainer {
        let schema = Schema([User.self, TeamMember.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let crew = User(id: priya, firstName: "Priya", lastName: "Rivera", role: .crew, companyId: "co-1")
        crew.isActive = true
        context.insert(crew)
        let office = User(id: sam, firstName: "Sam", lastName: "Okafor", role: .crew, companyId: "co-1")
        office.isActive = true
        context.insert(office)
        context.insert(TeamMember(id: priya, firstName: "Priya", lastName: "Rivera", role: "Crew"))
        context.insert(TeamMember(id: sam, firstName: "Sam", lastName: "Okafor", role: "Office"))
        try context.save()
        return container
    }

    private func name(_ userId: String) -> String {
        switch userId {
        case priya: return "Priya Rivera"
        case sam:   return "Sam Okafor"
        default:    return "—"
        }
    }

    // MARK: - Render

    private func renderToPNG(
        _ name: String,
        size: CGSize? = nil,
        minimumSettle: TimeInterval = 0.4,
        @ViewBuilder _ make: () -> some View
    ) {
        let image: UIImage
        do {
            image = try FixedSizeSnapshot.render(make(), size: size ?? frameSize, minimumSettle: minimumSettle)
        } catch {
            XCTFail("Could not acquire the app host window for \(name): \(error)")
            return
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        XCTAssertGreaterThan(data.count, 10_000, "\(name) must render content, not a blank surface.")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name) -> \(outDir.appendingPathComponent("\(name).png").path)")
    }

    // MARK: - The line as every list draws it

    func testRenderRecurringLineRows() throws {
        renderToPNG("my-expenses-recurring-row", size: CGSize(width: 390, height: 240), minimumSettle: 0) {
            VStack(spacing: 0) {
                ExpenseCard(
                    expense: recurringLine(),
                    categoryName: nil,
                    categoryIcon: nil,
                    batchStatus: .pendingReview,
                    onTap: {},
                    onSwipeLeft: {}
                )
                Rectangle().fill(OPSStyle.Colors.cardBorderSubtle).frame(height: 0.5)
                ExpenseCard(
                    expense: receiptLine(),
                    categoryName: "Materials",
                    categoryIcon: "shippingbox.fill",
                    batchStatus: .pendingReview,
                    onTap: {},
                    onSwipeLeft: {}
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(OPSStyle.Colors.background)
        }

        renderToPNG("books-ledger-recurring-row", size: CGSize(width: 390, height: 200), minimumSettle: 0) {
            VStack(spacing: 0) {
                BooksExpenseRow(expense: recurringLine(), who: "PRIYA RIVERA", batchStatus: .pendingReview) {}
                Rectangle().fill(OPSStyle.Colors.cardBorderSubtle).frame(height: 0.5)
                BooksExpenseRow(expense: receiptLine(), who: "PRIYA RIVERA", batchStatus: .pendingReview) {}
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(OPSStyle.Colors.background)
        }
    }

    // MARK: - Batch review

    private func review(expanded: String?, model: RecurringReimbursementViewModel, container: ModelContainer) -> some View {
        let expenses = ExpenseViewModel()
        expenses.selectedBatchExpenses = [recurringLine(), receiptLine()]
        expenses.reviewBatches = [batch()]

        return NavigationStack {
            ExpenseBatchDetailView(
                batch: batch(),
                viewModel: expenses,
                recurring: model,
                initialExpandedExpenseId: expanded
            )
        }
        .environmentObject(DataController())
        .environmentObject(approver())
        .modelContainer(container)
        .frame(width: frameSize.width, height: frameSize.height)
    }

    func testRenderBatchReview() async throws {
        let container = try peopleContainer()
        let viewModel = await model(snapshot([setup()]))

        renderToPNG("batch-review-recurring-collapsed") {
            review(expanded: nil, model: viewModel, container: container)
        }
        renderToPNG("batch-review-recurring-open") {
            review(expanded: "line-sep", model: viewModel, container: container)
        }
    }

    // MARK: - Settings list

    func testRenderSettingsList() async throws {
        let container = try peopleContainer()
        let listed = await model(snapshot([
            setup(),
            setup(id: "44444444-4444-4444-4444-444444444444", name: "Tool allowance", amount: 90),
            setup(id: "55555555-5555-5555-5555-555555555555", userId: sam, name: "Van wrap", amount: 140, lastPeriod: "2026-11-01"),
        ]))
        let empty = await model(snapshot([]))

        renderToPNG("settings-recurring-list") {
            ScrollView {
                RecurringReimbursementsSection(batches: [batch()], viewModel: listed)
                    .padding(.vertical, OPSStyle.Layout.spacing4)
            }
            .environmentObject(DataController())
            .environmentObject(approver())
            .modelContainer(container)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(OPSStyle.Colors.background)
        }

        renderToPNG("settings-recurring-empty") {
            ScrollView {
                RecurringReimbursementsSection(batches: [batch()], viewModel: empty)
                    .padding(.vertical, OPSStyle.Layout.spacing4)
            }
            .environmentObject(DataController())
            .environmentObject(approver())
            .modelContainer(container)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(OPSStyle.Colors.background)
        }
    }

    // MARK: - Editor sheet

    func testRenderEditorSheet() async throws {
        let viewModel = await model(snapshot([setup()]))
        let people = [RecurringPerson(id: priya, name: "Priya Rivera"), RecurringPerson(id: sam, name: "Sam Okafor")]

        renderToPNG("editor-add") {
            RecurringReimbursementSheet(
                viewModel: viewModel,
                mode: .create(person: people[0], firstPeriod: "2026-09-01"),
                batches: [batch()],
                people: people,
                nameFor: name
            )
            .frame(width: frameSize.width, height: frameSize.height)
        }

        renderToPNG("editor-edit") {
            RecurringReimbursementSheet(
                viewModel: viewModel,
                mode: .edit(setupId: setupId),
                batches: [batch()],
                people: people,
                nameFor: name
            )
            .frame(width: frameSize.width, height: frameSize.height)
        }
    }

    // MARK: - Read-only line sheet

    func testRenderLineSheet() async throws {
        let viewModel = await model(snapshot([setup()]))

        renderToPNG("line-sheet-approver") {
            RecurringLineSheet(
                line: recurringLine(),
                batchIsPaid: false,
                canManage: true,
                batches: [batch()],
                nameFor: name,
                viewModel: viewModel
            )
            .environmentObject(DataController())
            .frame(width: frameSize.width, height: frameSize.height)
        }

        renderToPNG("line-sheet-crew") {
            RecurringLineSheet(
                line: recurringLine(status: "reimbursed"),
                batchIsPaid: true,
                canManage: false,
                batches: [batch(paidAt: "2026-09-12T19:00:00+00:00")],
                nameFor: name,
                viewModel: viewModel
            )
            .environmentObject(DataController())
            .frame(width: frameSize.width, height: frameSize.height)
        }
    }
}
