//
//  ExpenseBatchDetailView.swift
//  OPS
//
//  Batch review detail — receipt-forward expense cards, flag toggles,
//  review progress bar, dynamic sticky footer.
//

import SwiftUI
import SwiftData

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

    // MARK: - Computed

    private var cleanCount: Int {
        viewModel.selectedBatchExpenses.count - viewModel.flaggedExpenseIds.count
    }

    private var flaggedCount: Int {
        viewModel.flaggedExpenseIds.count
    }

    private var canApprove: Bool { permissionStore.can("expenses.approve") }

    /// Where this batch sits in its lifecycle — drives the header stats and
    /// which footer (if any) renders. Same derivation as the console so the
    /// two can never disagree.
    private var bucket: ExpenseBucket? {
        ExpenseBuckets.bucket(for: batch, lineCount: viewModel.selectedBatchExpenses.count)
    }

    private var owedAmount: Double { ExpenseBuckets.owedAmount(batch) }

    private var batchStatus: ExpenseBatchStatus? { ExpenseBatchStatus(rawValue: batch.status) }

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
        .task {
            isLoading = true
            await viewModel.loadBatchExpenses(batch.id)
            isLoading = false
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
                return [("OWED", formatCurrency(owedAmount)),
                        ("ITEMS", items),
                        ("TOTAL", formatCurrency(batch.totalAmount ?? 0))]
            }
            return [("OWED", formatCurrency(owedAmount)),
                    ("ITEMS", items),
                    ("SUBMITTED", formatShortDate(batch.createdAt))]
        case .paid:
            let when = ExpenseBuckets.parseDate(batch.paidAt).map(formatDateValue) ?? "—"
            return [("PAID", formatCurrency(owedAmount)),
                    ("ITEMS", items),
                    ("ON", when)]
        case .crew where batchStatus == .open:
            return [("SO FAR", formatCurrency(batch.totalAmount ?? 0)),
                    ("ITEMS", items),
                    ("STARTED", formatShortDate(batch.createdAt))]
        default:
            return [("TOTAL", formatCurrency(batch.totalAmount ?? 0)),
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
        case .paid:
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Circle()
                    .fill(OPSStyle.Colors.olive)
                    .frame(width: OPSStyle.Layout.Indicator.dotSM, height: OPSStyle.Layout.Indicator.dotSM)
                if let when = ExpenseBuckets.parseDate(batch.paidAt) {
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
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
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
                    Text(expense.amount, format: .currency(code: expense.currency ?? "USD").precision(.fractionLength(2)))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    if isReviewable {
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
            if let thumbUrl = expense.receiptThumbnailUrl ?? expense.receiptImageUrl,
               let url = URL(string: thumbUrl) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    receiptImageUrl = thumbUrl
                    showReceiptViewer = true
                } label: {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else if case .failure = phase {
                            receiptPlaceholder
                        } else {
                            ProgressView()
                                .tint(OPSStyle.Colors.secondaryText)
                                .frame(width: 60, height: 80)
                        }
                    }
                    .frame(width: 60, height: 80)
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

    private func expandedSection(_ expense: ExpenseDTO, isFlagged: Bool) -> some View {
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
                    detailRow(label: "TAX", value: formatCurrency(tax))
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
                if isReviewable {
                    reviewFooter
                } else if bucket == .pay {
                    // Approved money not yet settled — the one next step.
                    footerButton(
                        "MARK PAID · \(formatCurrency(owedAmount))",
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
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Task {
                    await viewModel.approveBatch(batch)
                    dismiss()
                }
            }
        } else {
            // Has flags — approve everything anyway, or send the flags back.
            HStack(spacing: OPSStyle.Layout.spacing2) {
                footerButton("APPROVE ALL", background: OPSStyle.Colors.successStatus) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Task {
                        await viewModel.approveBatch(batch)
                        dismiss()
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

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
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
