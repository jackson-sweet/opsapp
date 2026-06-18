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

    private var isReviewable: Bool {
        // Filling (open) envelopes are not review-ready; only sent ones are.
        // Shared rule with the hub's needsReview filter so they never diverge.
        (ExpenseBatchStatus(rawValue: batch.status) ?? .pendingReview).needsReview
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

                        reviewProgressBar

                        sectionHeader("EXPENSES")

                        expenseCards
                    }
                    .padding(.bottom, isReviewable ? 100 : OPSStyle.Layout.spacing5)
                }
            }

            if isReviewable && !viewModel.selectedBatchExpenses.isEmpty {
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

            // Stats row
            HStack(spacing: 0) {
                statCell(label: "TOTAL", value: formatCurrency(batch.totalAmount ?? 0))
                statCell(label: "ITEMS", value: "\(viewModel.selectedBatchExpenses.count)")
                statCell(label: "SUBMITTED", value: formatShortDate(batch.createdAt))
            }
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3)
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
                            Text(expStatus.displayName)
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
                if flaggedCount == 0 {
                    // No flags — approve all
                    Button {
                        let userId = dataController.currentUser?.id ?? ""
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        Task {
                            await viewModel.approveInvoice(batch.id, reviewedBy: userId)
                            dismiss()
                        }
                    } label: {
                        Text("APPROVE ALL (\(viewModel.selectedBatchExpenses.count))")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.buttonText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OPSStyle.Colors.successStatus)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Has flags — approve all or return for revision
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Button {
                            let userId = dataController.currentUser?.id ?? ""
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            Task {
                                await viewModel.approveInvoice(batch.id, reviewedBy: userId)
                                dismiss()
                            }
                        } label: {
                            Text("APPROVE ALL")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.buttonText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(OPSStyle.Colors.successStatus)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            showRejectConfirmation = true
                        } label: {
                            Text("RETURN \(flaggedCount) FOR REVISION")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.buttonText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(OPSStyle.Colors.errorStatus)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .animation(OPSStyle.Animation.fast, value: flaggedCount)
        }
    }

    // MARK: - Formatters

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    private func formatPeriodDate(_ dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let isoFull = ISO8601DateFormatter()
        var date: Date?
        date = iso.date(from: dateString)
        if date == nil { date = isoFull.date(from: dateString) }
        guard let resolved = date else { return dateString }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: resolved)
    }

    private func formatShortDate(_ dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let isoFull = ISO8601DateFormatter()
        var date: Date?
        date = iso.date(from: dateString)
        if date == nil { date = isoFull.date(from: dateString) }
        guard let resolved = date else { return dateString }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: resolved).uppercased()
    }

    private func formatExpenseDate(_ dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let isoFull = ISO8601DateFormatter()
        var date: Date?
        date = iso.date(from: dateString)
        if date == nil { date = isoFull.date(from: dateString) }
        guard let resolved = date else { return dateString }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: resolved)
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
