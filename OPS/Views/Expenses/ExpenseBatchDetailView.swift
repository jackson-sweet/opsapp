//
//  ExpenseBatchDetailView.swift
//  OPS
//
//  Batch review detail — receipt-forward expense cards, flag toggles,
//  review progress bar, dynamic sticky footer.
//
//  Recurring reimbursements (a fixed monthly amount the office pays with this
//  person's expenses) are handled here too: their line shows the repeat mark
//  instead of a receipt and opens to the arrangement with EDIT and SKIP (UNDO
//  rides the toast), and a quiet action under the lines adds one for this
//  person, starting at this batch's month.
//

import SwiftUI
import SwiftData

/// Shared receipt rendering policy for compact Books surfaces.
struct ExpenseReceiptThumbnailImage: View {
    let image: Image

    var body: some View {
        image
            .resizable()
            .scaledToFit()
    }
}

enum ExpenseReceiptDisplaySource {
    static func reviewURL(full: String?, thumbnail: String?) -> String? {
        full ?? thumbnail
    }
}

struct ExpenseBatchDetailView: View {
    let batch: ExpenseBatchDTO
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var teamMembers: [TeamMember]

    @State private var expandedExpenseId: String? = nil
    @State private var isLoading = false
    @State private var showReceiptViewer = false
    @State private var receiptImageUrl: String? = nil
    @State private var showRejectConfirmation = false
    @State private var hasLeftDetail = false
    @State private var correctingExpense: ExpenseDTO? = nil
    @StateObject private var recurring = RecurringReimbursementViewModel()
    @State private var recurringSheet: RecurringSheetMode? = nil

    // MARK: - Computed

    private var cleanCount: Int {
        viewModel.selectedBatchExpenses.count - viewModel.flaggedExpenseIds.count
    }

    private var flaggedCount: Int {
        viewModel.flaggedExpenseIds.count
    }

    private var canApprove: Bool { permissionStore.can("expenses.approve", requiredScope: "all") }

    /// Where this batch sits in its lifecycle — drives the header stats and
    /// which footer (if any) renders. Same derivation as the console so the
    /// two can never disagree.
    private var currentBatch: ExpenseBatchDTO {
        viewModel.reviewBatches.first(where: { $0.id == batch.id }) ?? batch
    }

    private var bucket: ExpenseBucket? {
        ExpenseBuckets.bucket(for: currentBatch, lineCount: viewModel.selectedBatchExpenses.count)
    }

    private var owedAmount: Double { ExpenseBuckets.owedAmount(currentBatch) }

    private var batchStatus: ExpenseBatchStatus? { ExpenseBatchStatus(rawValue: currentBatch.status) }

    private var isReviewable: Bool {
        // Filling (open) envelopes are not review-ready; only sent ones are.
        // Shared rule with the console's review bucket so they never diverge.
        canApprove && (batchStatus?.needsReview ?? false)
    }

    private var hasFooter: Bool {
        guard !viewModel.selectedBatchExpenses.isEmpty else { return false }
        if isReviewable { return true }
        return canApprove && bucket == .pay
    }

    private var paidByName: String? {
        guard let paidBy = batch.paidBy else { return nil }
        return teamMembers.first(where: { $0.id == paidBy })?.fullName.uppercased()
    }

    private var crewName: String {
        guard let userId = batch.submittedBy else { return "UNASSIGNED" }
        if let member = teamMembers.first(where: { $0.id == userId }) {
            return member.fullName.uppercased()
        }
        return userId.prefix(8).uppercased()
    }

    private var crewInitials: String {
        guard let userId = batch.submittedBy else { return "?" }
        if let member = teamMembers.first(where: { $0.id == userId }) {
            return member.initials
        }
        return String(userId.prefix(2)).uppercased()
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()

            if isLoading && viewModel.selectedBatchExpenses.isEmpty {
                VStack {
                    Spacer()
                    TacticalLoadingBarAnimated()
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        headerCard
                            .padding(.top, OPSStyle.Layout.spacing3)

                        lifecycleLine

                        if isReviewable {
                            reviewProgressBar
                        }

                        sectionHeader("EXPENSES")

                        expenseCards
                            .disabled(viewModel.isApprovingBatches || viewModel.approvalInFlightBatchIds.contains(batch.id))
                    }
                    .padding(.bottom, hasFooter ? 100 : OPSStyle.Layout.spacing5)
                }
            }

            if hasFooter {
                stickyFooter
            }
        }
        .navigationTitle(batch.batchNumber)
        .navigationBarTitleDisplayMode(.inline)
        .hidesGlobalTabBar()
        .onAppear { hasLeftDetail = false }
        .onDisappear { hasLeftDetail = true }
        .task {
            isLoading = true
            await viewModel.loadBatchExpenses(batch.id)
            isLoading = false
        }
        .task {
            guard canApprove,
                  let companyId = dataController.currentUser?.companyId, !companyId.isEmpty else { return }
            recurring.setup(companyId: companyId)
            await recurring.load()
        }
        // A setup changed on another device: keep the arrangement current.
        .onReceive(
            NotificationCenter.default.publisher(for: .expenseUpdated)
                .receive(on: DispatchQueue.main)
        ) { _ in
            guard canApprove, !hasLeftDetail else { return }
            recurring.scheduleRefresh()
        }
        .fullScreenCover(isPresented: $showReceiptViewer) {
            if let url = receiptImageUrl {
                FullScreenReceiptViewer(imageUrl: url)
            }
        }
        .sheet(isPresented: $showRejectConfirmation) {
            RejectConfirmationView(
                batch: batch,
                viewModel: viewModel,
                onDismiss: { dismiss() }
            )
        }
        .sheet(item: $correctingExpense, onDismiss: {
            Task {
                await viewModel.loadBatchExpenses(batch.id)
                await viewModel.loadConsole()
            }
        }) { expense in
            ExpenseFormSheet(viewModel: viewModel, editing: expense, correctionBatch: currentBatch, correctionMode: true)
                .environmentObject(dataController)
        }
        .sheet(item: $recurringSheet) { mode in
            RecurringReimbursementSheet(
                viewModel: recurring,
                mode: mode,
                batches: viewModel.reviewBatches,
                people: [],
                nameFor: personName,
                onChanged: reloadLinesAfterRecurringChange
            )
            .environmentObject(dataController)
        }
        .errorToast($viewModel.error, label: Feedback.Err.batchUpdateFailed)
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 0) {
            // Crew info
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Circle()
                    .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(crewInitials)
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(crewName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    Text(batch.batchNumber)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    if let start = batch.periodStart, let end = batch.periodEnd {
                        Text("\(formatPeriodDate(start)) \u{2013} \(formatPeriodDate(end))")
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }

                Spacer()
            }
            .padding(OPSStyle.Layout.spacing3)

            Divider().background(OPSStyle.Colors.cardBorder)

            // Stats row — leads with the number that matters for where this
            // batch sits: submitted total in review, owed once approved,
            // the recorded payout once paid, the running total while filling.
            HStack(spacing: 0) {
                ForEach(statCells, id: \.label) { cell in
                    statCell(label: cell.label, value: cell.value)
                }
            }
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private var statCells: [(label: String, value: String)] {
        let items = "\(viewModel.selectedBatchExpenses.count)"
        switch bucket {
        case .pay:
            if batchStatus == .partiallyApproved {
                return [("OWED", BooksFormat.exact(owedAmount)),
                        ("ITEMS", items),
                        ("TOTAL", BooksFormat.exact(batch.totalAmount ?? 0))]
            }
            return [("OWED", BooksFormat.exact(owedAmount)),
                    ("ITEMS", items),
                    ("SUBMITTED", formatShortDate(batch.createdAt))]
        case .paid where ExpenseBuckets.isPaid(currentBatch):
            let when = ExpenseBuckets.parseDate(currentBatch.paidAt).map(formatDateValue) ?? "—"
            return [("PAID", BooksFormat.exact(owedAmount)),
                    ("ITEMS", items),
                    ("ON", when)]
        case .crew where batchStatus == .open:
            return [("SO FAR", BooksFormat.exact(batch.totalAmount ?? 0)),
                    ("ITEMS", items),
                    ("STARTED", formatShortDate(batch.createdAt))]
        default:
            return [("TOTAL", BooksFormat.exact(batch.totalAmount ?? 0)),
                    ("ITEMS", items),
                    ("SUBMITTED", formatShortDate(batch.createdAt))]
        }
    }

    // MARK: - Lifecycle line

    /// One quiet line under the header naming the batch's current reality:
    /// who recorded the payout, when a filling envelope auto-sends, or that
    /// sent-back lines are with the crew. UNDO rides the paid line —
    /// mis-tap recovery, never prominent.
    @ViewBuilder
    private var lifecycleLine: some View {
        switch bucket {
        case .paid where ExpenseBuckets.isPaid(currentBatch):
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Circle()
                    .fill(OPSStyle.Colors.olive)
                    .frame(width: OPSStyle.Layout.Indicator.dotSM, height: OPSStyle.Layout.Indicator.dotSM)
                if let when = ExpenseBuckets.parseDate(currentBatch.paidAt) {
                    Text("PAID \(formatDateValue(when))")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.olive)
                }
                if let paidByName {
                    Text("·")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(paidByName)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                Spacer()
                if canApprove {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task {
                            await viewModel.unmarkPaid(batch)
                            dismiss()
                        }
                    } label: {
                        Text("UNDO")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Undo payout")
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        case .paid:
            Text("APPROVED")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
        case .crew where batchStatus == .open:
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Circle()
                    .fill(OPSStyle.Colors.tertiaryText)
                    .frame(width: OPSStyle.Layout.Indicator.dotSM, height: OPSStyle.Layout.Indicator.dotSM)
                Text(crewForesight)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        case .crew:
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Circle()
                    .fill(OPSStyle.Colors.rose)
                    .frame(width: OPSStyle.Layout.Indicator.dotSM, height: OPSStyle.Layout.Indicator.dotSM)
                Text("SENT BACK — the crew is fixing the flagged lines")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        default:
            EmptyView()
        }
    }

    private var crewForesight: String {
        let graceDays = viewModel.settings?.autoSubmitGraceDays ?? 7
        if let sendDate = ExpenseBuckets.autoSendDate(batch, graceDays: graceDays) {
            return sendDate <= Date()
                ? "STILL FILLING — SENDS TODAY"
                : "STILL FILLING — AUTO-SENDS \(formatDateValue(sendDate))"
        }
        return "STILL FILLING — SENDS AFTER THE JOB WRAPS"
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            Text(value)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Review Progress Bar

    private var reviewProgressBar: some View {
        let total = viewModel.selectedBatchExpenses.count
        let cleanFraction: Double = total > 0 ? Double(cleanCount) / Double(total) : 1.0
        let flaggedFraction: Double = total > 0 ? Double(flaggedCount) / Double(total) : 0

        return VStack(spacing: OPSStyle.Layout.spacing1) {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    if cleanCount > 0 {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                            .fill(OPSStyle.Colors.successStatus)
                            .frame(width: geometry.size.width * cleanFraction)
                    }
                    if flaggedCount > 0 {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                            .fill(OPSStyle.Colors.warningStatus)
                            .frame(width: geometry.size.width * flaggedFraction)
                    }
                    if cleanCount == 0 && flaggedCount == 0 {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                            .fill(OPSStyle.Colors.cardBorder)
                    }
                }
                .animation(OPSStyle.Animation.standard, value: flaggedCount)
            }
            .frame(height: 4)

            HStack {
                if flaggedCount > 0 {
                    Text("\(cleanCount) clean \u{00B7} \(flaggedCount) flagged")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                } else {
                    Text("\(total) expenses")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                Spacer()
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Expense Cards

    private var expenseCards: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(viewModel.selectedBatchExpenses) { expense in
                expenseReviewCard(expense)
            }

            addRecurringAction
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    /// Rare, person-level setup — a quiet action under the lines, never prime
    /// space. Starts at this batch's month; hidden once the batch is paid out,
    /// and on an approver's own batch unless they are an admin (the database
    /// refuses anyone else a reimbursement for themselves).
    @ViewBuilder
    private var addRecurringAction: some View {
        if canApprove, currentBatch.paidAt == nil, let userId = batch.submittedBy, !userId.isEmpty,
           permissionStore.isAdmin || userId.lowercased() != dataController.currentUser?.id.lowercased() {
            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    recurringSheet = .create(
                        person: RecurringPerson(id: userId, name: personName(userId)),
                        firstPeriod: batch.periodStart
                    )
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: OPSStyle.Icons.plus)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                        Text("RECURRING REIMBURSEMENT")
                            .font(OPSStyle.Typography.metadata)
                            .kerning(1.2)
                    }
                    .foregroundColor(OPSStyle.Colors.text3)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Add a recurring reimbursement")
                .accessibilityHint("A fixed amount paid with this person's expenses every month")
                Spacer()
            }
            .padding(.top, OPSStyle.Layout.spacing1)
        }
    }

    private func expenseReviewCard(_ expense: ExpenseDTO) -> some View {
        let isExpanded = expandedExpenseId == expense.id
        let isFlagged = viewModel.flaggedExpenseIds.contains(expense.id)
        let expStatus = ExpenseStatus(rawValue: expense.status) ?? .draft

        return VStack(spacing: 0) {
            // Main card content — always visible
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // Receipt thumbnail
                receiptThumbnail(expense)

                // Info column
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.merchantName ?? "UNKNOWN MERCHANT")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        if expense.isRecurringReimbursement {
                            Text("Recurring")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            if let period = expense.recurringPeriod {
                                Text("\u{00B7}")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                Text(ExpenseRecurring.formatMonth(period))
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        } else {
                            Text(expense.category?.name ?? "Uncategorized")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            if let dateStr = expense.expenseDate {
                                Text("\u{00B7}")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                Text(formatExpenseDate(dateStr))
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }
                    }

                    // Status line
                    if isFlagged {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            Text("FLAGGED")
                                .font(OPSStyle.Typography.smallCaption)
                        }
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                    } else {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Circle()
                                .fill(expStatus.reviewColor)
                                .frame(width: OPSStyle.Layout.Indicator.dotSM, height: OPSStyle.Layout.Indicator.dotSM)
                            Text(statusLabel(expStatus))
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(expStatus.reviewColor)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(OPSStyle.Animation.fast) {
                        expandedExpenseId = isExpanded ? nil : expense.id
                    }
                }

                Spacer()

                // Amount + flag toggle
                VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing2) {
                    Text(BooksFormat.exact(expense.amount, code: expense.currency ?? "USD"))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // A recurring line is office-owned: nothing to flag.
                    if isReviewable && !expense.isRecurringReimbursement {
                        Button {
                            if isFlagged {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                Task { await viewModel.unflagExpense(expense.id) }
                            } else {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                let userId = dataController.currentUser?.id ?? ""
                                Task { await viewModel.flagExpense(expense.id, comment: "", flaggedBy: userId) }
                                withAnimation(OPSStyle.Animation.fast) {
                                    expandedExpenseId = expense.id
                                }
                            }
                        } label: {
                            Image(systemName: isFlagged ? "flag.fill" : "flag")
                                .font(.system(size: OPSStyle.Layout.IconSize.md))
                                .foregroundColor(isFlagged ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.tertiaryText)
                                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)

            // Expanded details
            if isExpanded {
                expandedSection(expense, isFlagged: isFlagged)
            }
        }
        .glassSurface(
            borderColor: isFlagged ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.glassBorder
        )
        .animation(OPSStyle.Animation.fast, value: isFlagged)
    }

    // MARK: - Receipt Thumbnail

    private func receiptThumbnail(_ expense: ExpenseDTO) -> some View {
        Group {
            if expense.isRecurringReimbursement {
                RecurringReimbursementMark(width: 60, height: 80, iconSize: OPSStyle.Layout.IconSize.md)
            } else if let receiptUrl = ExpenseReceiptDisplaySource.reviewURL(
                full: expense.receiptImageUrl,
                thumbnail: expense.receiptThumbnailUrl
            ), let url = URL(string: receiptUrl) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    receiptImageUrl = receiptUrl
                    showReceiptViewer = true
                } label: {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            ExpenseReceiptThumbnailImage(image: image)
                        } else if case .failure = phase {
                            receiptPlaceholder
                        } else {
                            ProgressView()
                                .tint(OPSStyle.Colors.secondaryText)
                                .frame(width: 60, height: 80)
                        }
                    }
                    .frame(width: 60, height: 80)
                    .background(OPSStyle.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                receiptPlaceholder
            }
        }
    }

    private var receiptPlaceholder: some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
            .fill(OPSStyle.Colors.background)
            .frame(width: 60, height: 80)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    // MARK: - Expanded Section

    @ViewBuilder
    private func expandedSection(_ expense: ExpenseDTO, isFlagged: Bool) -> some View {
        if expense.isRecurringReimbursement {
            recurringExpandedSection(expense)
        } else {
            receiptExpandedSection(expense, isFlagged: isFlagged)
        }
    }

    /// The arrangement behind a recurring line, and the two verbs for its month.
    private func recurringExpandedSection(_ expense: ExpenseDTO) -> some View {
        let setup = recurring.setup(for: expense)
        let canSkip = canApprove
            && ExpenseStatus(rawValue: expense.status) == .approved
            && currentBatch.paidAt == nil
            && expense.recurringPeriod != nil
        let skipping = recurring.inFlight == .skip(expense.id)

        return VStack(spacing: 0) {
            Divider().background(OPSStyle.Colors.cardBorder)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("RECURRING")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Text(setup.map(recurringArrangement) ?? "—")
                    .font(OPSStyle.Typography.caption)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let period = expense.recurringPeriod {
                    Text("Pays for \(ExpenseRecurring.formatMonth(period))")
                        .font(OPSStyle.Typography.caption)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                if canApprove {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if let setup {
                            Button("EDIT") {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                recurringSheet = .edit(setupId: setup.id)
                            }
                            .opsSecondaryCompactButtonStyle()
                            .disabled(recurring.inFlight != nil)
                            .accessibilityHint("Change the amount, end it, or delete it")
                        }
                        if canSkip, let period = expense.recurringPeriod {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                Task { await recurring.skip(expense, onChanged: reloadLinesAfterRecurringChange) }
                            } label: {
                                if skipping {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(OPSStyle.Colors.text2)
                                } else {
                                    Text("SKIP \(ExpenseRecurring.formatMonth(period))")
                                }
                            }
                            .opsSecondaryCompactButtonStyle()
                            .disabled(recurring.inFlight != nil)
                            .accessibilityHint("Leave this month out. Undo from the confirmation.")
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, OPSStyle.Layout.spacing1)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .background(OPSStyle.Colors.background.opacity(0.3))
    }

    /// `CA$350.00 every month · since AUG 2026` / `… · AUG 2026 to DEC 2026`.
    private func recurringArrangement(_ setup: ExpenseRecurringReimbursementDTO) -> String {
        let amount = BooksFormat.exact(setup.amount, code: setup.currency)
        let since = ExpenseRecurring.formatMonth(setup.firstPeriod)
        guard let last = setup.lastPeriod else { return "\(amount) every month · since \(since)" }
        return "\(amount) every month · \(since) to \(ExpenseRecurring.formatMonth(last))"
    }

    /// A recurring command moved money in this batch — re-read its lines if it
    /// is still the batch on screen (a toast's UNDO can land later). Totals and
    /// the console refresh on the expense signal the command broadcasts.
    private func reloadLinesAfterRecurringChange() {
        let batchId = batch.id
        Task { await viewModel.reloadBatchLinesIfSelected(batchId) }
    }

    /// Proper-case display name for a crew member (the sheet's "Paid to …").
    private func personName(_ userId: String) -> String {
        if let member = teamMembers.first(where: { $0.id.lowercased() == userId.lowercased() }) {
            let name = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return "—"
    }

    private func receiptExpandedSection(_ expense: ExpenseDTO, isFlagged: Bool) -> some View {
        VStack(spacing: 0) {
            Divider().background(OPSStyle.Colors.cardBorder)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                if let desc = expense.description, !desc.isEmpty {
                    detailRow(label: "NOTES", value: desc)
                }
                if let method = expense.paymentMethod {
                    let display = ExpensePaymentMethod(rawValue: method)?.displayName ?? method.uppercased()
                    detailRow(label: "PAYMENT", value: display)
                }
                if let tax = expense.taxAmount, tax > 0 {
                    detailRow(label: "TAX", value: BooksFormat.exact(tax))
                }

                ExpenseCorrectionHistoryView(expense: expense, viewModel: viewModel)

                if ExpenseCorrectionPolicy.canCorrect(
                    expense: expense, batch: currentBatch,
                    actorId: dataController.currentUser?.id,
                    companyId: dataController.currentUser?.companyId,
                    canApproveAll: canApprove,
                    canViewAll: permissionStore.can("expenses.view", requiredScope: "all")
                ) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        correctingExpense = expense
                    } label: {
                        Text("CORRECT & RETURN")
                            .font(OPSStyle.Typography.button)
                    }
                    .opsSecondaryButtonStyle()
                    .accessibilityHint("Edit this expense and return it to the crew for review")
                }

                // Flag comment field (when flagged)
                if isFlagged {
                    flagCommentField(expense)
                }

                // Early clear — approve one line while the envelope keeps
                // filling (e.g. the crew member needs that money now). The
                // server approves, recalculates, and notifies them itself.
                if canApprove,
                   batchStatus == .open,
                   ExpenseStatus(rawValue: expense.status) == .submitted {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await viewModel.earlyClearLine(expense.id, batchId: batch.id) }
                    } label: {
                        Text("CLEAR NOW")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.olive)
                            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Approve this line now")
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .background(OPSStyle.Colors.background.opacity(0.3))
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(value)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    private func flagCommentField(_ expense: ExpenseDTO) -> some View {
        HStack {
            TextField(
                "Add a note for the crew member...",
                text: Binding(
                    get: { viewModel.flagComments[expense.id] ?? "" },
                    set: { viewModel.flagComments[expense.id] = $0 }
                )
            )
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.primaryText)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await viewModel.unflagExpense(expense.id) }
            } label: {
                Image(systemName: OPSStyle.Icons.xmark)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.surfaceInput)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.5), lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Sticky Footer

    private var stickyFooter: some View {
        OPSFloatingButtonBar(horizontalPadding: OPSStyle.Layout.spacing3, verticalPadding: OPSStyle.Layout.spacing2) {
            Group {
                if viewModel.isApprovingBatches {
                    footerButton(viewModel.approvalProgressLabel, background: OPSStyle.Colors.successStatus) {}
                        .disabled(true)
                        .accessibilityValue("Approval in progress")
                } else if viewModel.approvalInFlightBatchIds.contains(batch.id) {
                    footerButton("APPROVAL IN PROGRESS", background: OPSStyle.Colors.successStatus) {}
                        .disabled(true)
                } else if isReviewable && viewModel.confirmedApprovedBatchIds.contains(batch.id) {
                    footerButton("APPROVED · REFRESH PENDING", background: OPSStyle.Colors.successStatus) {}
                        .disabled(true)
                } else if isReviewable {
                    reviewFooter
                } else if bucket == .pay {
                    // Approved money not yet settled — the one next step.
                    footerButton(
                        "MARK PAID · \(BooksFormat.exact(owedAmount))",
                        background: OPSStyle.Colors.successStatus
                    ) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        Task {
                            await viewModel.markPaid(batch)
                            dismiss()
                        }
                    }
                }
            }
            .animation(OPSStyle.Animation.fast, value: flaggedCount)
        }
    }

    @ViewBuilder
    private var reviewFooter: some View {
        if flaggedCount == 0 {
            // No flags — one clean commit through the atomic RPC.
            footerButton(
                "APPROVE ALL (\(viewModel.selectedBatchExpenses.count))",
                background: OPSStyle.Colors.successStatus
            ) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    if await viewModel.approveBatch(batch), !hasLeftDetail { dismiss() }
                }
            }
        } else {
            // Has flags — approve everything anyway, or send the flags back.
            HStack(spacing: OPSStyle.Layout.spacing2) {
                footerButton("APPROVE ALL", background: OPSStyle.Colors.successStatus) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        if await viewModel.approveBatch(batch), !hasLeftDetail { dismiss() }
                    }
                }
                footerButton("SEND BACK \(flaggedCount)", background: OPSStyle.Colors.errorStatus) {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    showRejectConfirmation = true
                }
            }
        }
    }

    private func footerButton(
        _ label: String,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.buttonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(background)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Formatters

    /// Crew-facing vocabulary: a reimbursed line reads "paid".
    private func statusLabel(_ status: ExpenseStatus) -> String {
        status == .reimbursed ? "PAID" : status.displayName
    }

    private func formatDateValue(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date).uppercased()
    }

    // Date-only strings parse at LOCAL midnight (ExpenseBuckets.parseDate) —
    // the old UTC-midnight parse showed period bounds and expense dates one
    // day early for anyone west of Greenwich.

    private func formatPeriodDate(_ dateString: String) -> String {
        guard let resolved = ExpenseBuckets.parseDate(dateString) else { return dateString }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: resolved)
    }

    private func formatShortDate(_ dateString: String) -> String {
        formatPeriodDate(dateString).uppercased()
    }

    private func formatExpenseDate(_ dateString: String) -> String {
        formatPeriodDate(dateString)
    }
}

// MARK: - ExpenseStatus Review Color

private extension ExpenseStatus {
    var reviewColor: Color {
        switch self {
        case .draft:      return OPSStyle.Colors.tertiaryText
        case .submitted:  return OPSStyle.Colors.primaryAccent
        case .approved:   return OPSStyle.Colors.successStatus
        case .rejected:   return OPSStyle.Colors.errorStatus
        case .reimbursed: return OPSStyle.Colors.successStatus
        }
    }
}
