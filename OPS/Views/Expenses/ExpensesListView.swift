//
//  ExpensesListView.swift
//  OPS
//
//  The expense batch console — the owner-side review surface. Two jobs, one
//  structure: a spend hero answers "how much are we spending on job
//  expenses"; three money tiles (TO REVIEW / TO PAY / PAID) are the metrics
//  AND the bucket switcher for the person-grouped queue below. WITH CREW
//  (filling + sent-back envelopes) rides underneath as a quiet expandable
//  footer — findable, never in the way. Cross-period always: the old month
//  pills hid prior-month pending batches and are gone.
//
//  Approval runs through the atomic `approve_expense_batch` RPC; payouts
//  through `mark_expense_batch_paid` / `unmark_expense_batch_paid`. The
//  surface stays live via the realtime `.expenseUpdated` signal.
//

import SwiftUI
import SwiftData

struct ExpensesListView: View {
    /// Pushed screens (Books, Settings) own the bottom edge and hide the
    /// global tab bar; as a tab root (single-segment Books auto-skip) the
    /// tab bar stays and content clears it.
    var isPushed: Bool = true
    /// When set (from a batch-scoped expense deep link), the console
    /// auto-pushes this batch's detail once batches load. Bug 7cdbe7bb.
    var deepLinkBatchId: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel = ExpenseViewModel()
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Query private var teamMembers: [TeamMember]
    @Query private var users: [User]

    @State private var selectedBucket: ExpenseBucket = .review
    @State private var hasAutoSelectedBucket = false
    @State private var selectedBatch: ExpenseBatchDTO? = nil
    @State private var showExpenseSettings = false
    @State private var showAddExpense = false
    @State private var hasAppeared = false

    // Bulk-action confirmation state — one dialog pair serves both the
    // per-person buttons and the ALL floating CTA.
    @State private var pendingApproveBatches: [ExpenseBatchDTO] = []
    @State private var showApproveConfirm = false
    @State private var pendingPayBatches: [ExpenseBatchDTO] = []
    @State private var showPayConfirm = false

    // MARK: - Derived

    private var canApprove: Bool { permissionStore.can("expenses.approve") }
    private var split: ExpenseBucketSplit { viewModel.consoleSplit }
    private var metrics: ExpenseConsoleMetrics { viewModel.consoleMetrics }

    /// Bulk-approve working set: clean (unflagged) review batches only.
    private var cleanReviewBatches: [ExpenseBatchDTO] {
        split.review.filter { (viewModel.consoleLineStats[$0.id]?.flagged ?? 0) == 0 }
    }

    private var approveConfirmTitle: String {
        "Approve \(pendingApproveBatches.count) Batch\(pendingApproveBatches.count == 1 ? "" : "es")?"
    }

    private var payConfirmTitle: String {
        "Mark \(pendingPayBatches.count) Batch\(pendingPayBatches.count == 1 ? "" : "es") Paid?"
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isPushed {
                core.hidesGlobalTabBar()
            } else {
                core
            }
        }
    }

    private var core: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                consoleScroll
            }

            bulkCTA
        }
        .trackScreen("Expenses")
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showExpenseSettings) {
            ExpenseSettingsView(viewModel: viewModel)
                .environmentObject(dataController)
        }
        .navigationDestination(item: $selectedBatch) { batch in
            ExpenseBatchDetailView(batch: batch, viewModel: viewModel)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showAddExpense) {
            ExpenseFormSheet(viewModel: viewModel)
                .environmentObject(dataController)
        }
        .confirmationDialog(
            approveConfirmTitle,
            isPresented: $showApproveConfirm,
            titleVisibility: .visible
        ) {
            Button("Approve \(pendingApproveBatches.count) Batch\(pendingApproveBatches.count == 1 ? "" : "es")") {
                let batches = pendingApproveBatches
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Task { await viewModel.approveBatches(batches) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Total \(BooksFormat.currency(pendingApproveBatches.reduce(0) { $0 + ($1.totalAmount ?? 0) })). Flagged batches stay put.")
        }
        .confirmationDialog(
            payConfirmTitle,
            isPresented: $showPayConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark \(pendingPayBatches.count) Batch\(pendingPayBatches.count == 1 ? "" : "es") Paid") {
                let batches = pendingPayBatches
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Task { await viewModel.markPaidBatches(batches) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Records \(BooksFormat.currency(pendingPayBatches.reduce(0) { $0 + ExpenseBuckets.owedAmount($1) })) paid out. Lines flip to paid.")
        }
        .errorToast($viewModel.error, label: Feedback.Err.batchUpdateFailed)
        // Local mutations (create/edit/delete anywhere in the app) AND remote
        // realtime changes — RealtimeProcessor posts BOTH signals for
        // expenses / expense_batches, so both funnel through the debounce: an
        // approval's event storm (batch flip + every line) collapses to one
        // reload.
        .onReceive(
            NotificationCenter.default.publisher(for: .opsExpensesDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            viewModel.scheduleRealtimeRefresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .expenseUpdated)
                .receive(on: DispatchQueue.main)
        ) { _ in
            viewModel.scheduleRealtimeRefresh()
        }
        .onChange(of: deepLinkBatchId) { _, _ in
            Task { await openDeepLinkBatchIfNeeded() }
        }
        .task {
            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                let user = dataController.currentUser
                let userName = [user?.firstName, user?.lastName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                viewModel.setup(
                    companyId: companyId,
                    currentUserId: user?.id,
                    currentUserName: userName.isEmpty ? nil : userName
                )
                await viewModel.loadConsole()
                autoSelectBucketIfNeeded()
                withAnimation(reduceMotion ? nil : OPSStyle.Animation.fast) {
                    hasAppeared = true
                }
                await openDeepLinkBatchIfNeeded()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if isPushed {
                Button(action: { dismiss() }) {
                    Image(systemName: OPSStyle.Icons.chevronLeft)
                        .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            } else {
                Spacer().frame(width: OPSStyle.Layout.touchTargetMin)
            }

            Spacer()

            Text("BATCHES")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showAddExpense = true
            }) {
                Image(systemName: OPSStyle.Icons.plus)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            .accessibilityLabel("New Expense")

            Button(action: { showExpenseSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            .accessibilityLabel("Expense Settings")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.top, OPSStyle.Layout.spacing2_5)
    }

    // MARK: - Console scroll

    private var consoleScroll: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                if viewModel.isLoading && viewModel.reviewBatches.isEmpty && !hasAppeared {
                    TacticalLoadingBarAnimated()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing5)
                } else {
                    ExpenseInstrumentStrip(metrics: metrics, selectedBucket: $selectedBucket)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                    ExpenseBucketQueue(
                        bucket: selectedBucket,
                        split: split,
                        lineStats: viewModel.consoleLineStats,
                        autoSubmitGraceDays: viewModel.settings?.autoSubmitGraceDays ?? 7,
                        canApprove: canApprove,
                        nameFor: resolveCrewName,
                        onOpen: { selectedBatch = $0 },
                        onApprove: { batch in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            Task { await viewModel.approveBatch(batch) }
                        },
                        onPay: { batch in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            Task { await viewModel.markPaid(batch) }
                        },
                        onApproveGroup: { group in
                            pendingApproveBatches = group.batches.filter {
                                (viewModel.consoleLineStats[$0.id]?.flagged ?? 0) == 0
                            }
                            showApproveConfirm = !pendingApproveBatches.isEmpty
                        },
                        onPayGroup: { group in
                            pendingPayBatches = group.batches
                            showPayConfirm = !pendingPayBatches.isEmpty
                        }
                    )
                    .opacity(hasAppeared ? 1 : 0)
                    .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: selectedBucket)
                }
            }
            .padding(.top, OPSStyle.Layout.spacing2)
            .padding(.bottom, bottomClearance)
        }
        .refreshable { await viewModel.loadConsole() }
    }

    /// Clears the floating CTA (pushed) or CTA + global tab bar (tab root).
    private var bottomClearance: CGFloat {
        let ctaAllowance = OPSStyle.Layout.touchTargetLarge + OPSStyle.Layout.spacing4
        return isPushed ? ctaAllowance : ctaAllowance + 100
    }

    // MARK: - Bulk CTA

    @ViewBuilder
    private var bulkCTA: some View {
        if canApprove {
            switch selectedBucket {
            case .review where cleanReviewBatches.count > 1:
                ExpenseBulkCTABar(
                    label: "APPROVE ALL · \(BooksFormat.currency(cleanReviewBatches.reduce(0) { $0 + ($1.totalAmount ?? 0) }))",
                    bottomInset: isPushed ? 0 : 100
                ) {
                    pendingApproveBatches = cleanReviewBatches
                    showApproveConfirm = true
                }
            case .pay where split.pay.count > 1:
                ExpenseBulkCTABar(
                    label: "PAY ALL · \(BooksFormat.currency(split.pay.reduce(0) { $0 + ExpenseBuckets.owedAmount($1) }))",
                    bottomInset: isPushed ? 0 : 100
                ) {
                    pendingPayBatches = split.pay
                    showPayConfirm = true
                }
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Helpers

    /// One-time landing bucket: the first state of money with work in it.
    private func autoSelectBucketIfNeeded() {
        guard !hasAutoSelectedBucket else { return }
        hasAutoSelectedBucket = true
        if !split.review.isEmpty { selectedBucket = .review }
        else if !split.pay.isEmpty { selectedBucket = .pay }
        else { selectedBucket = .paid }
    }

    /// Resolves `deepLinkBatchId` against the loaded batches (any bucket) and
    /// pushes its detail. No-op when there's no deep link or the batch can't
    /// be found — the user still lands on the console, never a dead tap.
    private func openDeepLinkBatchIfNeeded() async {
        guard let id = deepLinkBatchId, !id.isEmpty, selectedBatch?.id != id else { return }
        if viewModel.reviewBatches.isEmpty {
            await viewModel.loadConsole()
        }
        guard let batch = viewModel.reviewBatches.first(where: { $0.id == id }) else { return }
        selectedBatch = batch
    }

    private func resolveCrewName(_ userId: String?) -> String {
        guard let userId = userId else { return "UNASSIGNED" }
        if let user = users.first(where: { $0.id == userId }),
           !user.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return user.fullName.uppercased()
        }
        if let member = teamMembers.first(where: { $0.id == userId }) {
            return member.fullName.uppercased()
        }
        return userId.prefix(8).uppercased()
    }
}

// MARK: - Hashable Conformance

/// `navigationDestination(item:)` needs Hashable; identity is the row id.
extension ExpenseBatchDTO: Hashable {
    static func == (lhs: ExpenseBatchDTO, rhs: ExpenseBatchDTO) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ExpenseDTO: Hashable {
    static func == (lhs: ExpenseDTO, rhs: ExpenseDTO) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
