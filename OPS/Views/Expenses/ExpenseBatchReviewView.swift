//
//  ExpenseBatchReviewView.swift
//  OPS
//
//  Batch review view for office/admin — approve or reject expenses in bulk.
//

import SwiftUI

struct ExpenseBatchReviewView: View {
    let batch: ExpenseBatchDTO
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var dataController: DataController
    @State private var batchExpenses: [ExpenseDTO] = []
    @State private var showRejectReason = false
    @State private var rejectingExpenseId: String? = nil
    @State private var rejectionReason = ""
    @State private var expandedExpenseId: String? = nil
    @State private var isLoading = false

    private var pendingCount: Int {
        batchExpenses.filter { $0.status == ExpenseStatus.submitted.rawValue }.count
    }

    private var approvedCount: Int {
        batchExpenses.filter { $0.status == ExpenseStatus.approved.rawValue || $0.status == ExpenseStatus.reimbursed.rawValue }.count
    }

    private var rejectedCount: Int {
        batchExpenses.filter { $0.status == ExpenseStatus.rejected.rawValue }.count
    }

    private var totalAmount: Double {
        batchExpenses.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()

            if isLoading && batchExpenses.isEmpty {
                VStack {
                    Spacer()
                    TacticalLoadingBarAnimated()
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        batchHeaderCard
                            .padding(.top, OPSStyle.Layout.spacing3)

                        summaryBar

                        sectionHeader("EXPENSES")
                        expenseList
                    }
                    .padding(.bottom, 100)
                }
            }

            approveAllFooter
        }
        .navigationTitle("BATCH \(batch.batchNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBatchExpenses()
        }
        .alert("REJECT EXPENSE", isPresented: $showRejectReason) {
            TextField("Reason for rejection", text: $rejectionReason)
            Button("REJECT") {
                if let expId = rejectingExpenseId {
                    let userId = dataController.currentUser?.id ?? ""
                    let reason = rejectionReason
                    rejectingExpenseId = nil
                    rejectionReason = ""
                    Task { await viewModel.rejectExpense(expId, rejectedBy: userId, reason: reason) }
                }
            }
            Button("CANCEL", role: .cancel) {
                rejectingExpenseId = nil
                rejectionReason = ""
            }
        } message: {
            Text("Provide a reason for the field crew member.")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Batch Header Card

    private var batchHeaderCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack {
                Text("BATCH \(batch.batchNumber)")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Text(batch.status.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            if let start = batch.periodStart, let end = batch.periodEnd {
                Text("\(formatPeriodDate(start)) – \(formatPeriodDate(end))")
                    .font(OPSStyle.Typography.smallBody)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            HStack {
                Text(totalAmount, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Text("\(batchExpenses.count) EXPENSES")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 0) {
            summaryCell(label: "PENDING", count: pendingCount, color: OPSStyle.Colors.primaryAccent)
            Divider().background(OPSStyle.Colors.cardBorder)
            summaryCell(label: "APPROVED", count: approvedCount, color: OPSStyle.Colors.successStatus)
            Divider().background(OPSStyle.Colors.cardBorder)
            summaryCell(label: "REJECTED", count: rejectedCount, color: OPSStyle.Colors.errorStatus)
        }
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func summaryCell(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            Text("\(count)")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(color)
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - Expense List

    private var expenseList: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(batchExpenses) { expense in
                expenseReviewCard(expense)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func expenseReviewCard(_ expense: ExpenseDTO) -> some View {
        let isExpanded = expandedExpenseId == expense.id
        let expStatus = ExpenseStatus(rawValue: expense.status) ?? .draft
        let statusColor = expStatus.reviewColor

        return VStack(spacing: 0) {
            // Collapsed header
            Button {
                withAnimation(OPSStyle.Animation.fast) {
                    expandedExpenseId = isExpanded ? nil : expense.id
                }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    // Receipt thumbnail
                    if let thumbUrl = expense.receiptThumbnailUrl ?? expense.receiptImageUrl,
                       let url = URL(string: thumbUrl) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                Color(OPSStyle.Colors.cardBackgroundDark)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius))
                    } else {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(expense.merchantName ?? "UNKNOWN MERCHANT")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                        Text(expense.category?.name ?? "Uncategorized")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(expense.amount, format: .currency(code: expense.currency ?? "USD").precision(.fractionLength(2)))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            Text(expStatus.displayName)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(statusColor)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded details + actions
            if isExpanded {
                Divider().background(OPSStyle.Colors.cardBorder)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    if let desc = expense.description, !desc.isEmpty {
                        Text(desc)
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    if let method = expense.paymentMethod {
                        Text("PAYMENT: \(method.uppercased())")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    // Actions — only for submitted
                    if expStatus == .submitted {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Button("APPROVE") {
                                let userId = dataController.currentUser?.id ?? ""
                                Task { await viewModel.approveExpense(expense.id, approvedBy: userId) }
                            }
                            .opsPrimaryButtonStyle()

                            Button("REJECT") {
                                rejectingExpenseId = expense.id
                                showRejectReason = true
                            }
                            .opsSecondaryButtonStyle()
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing2)
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Approve All Footer

    private var approveAllFooter: some View {
        Group {
            if pendingCount > 0 {
                HStack {
                    Button("APPROVE ALL (\(pendingCount))") {
                        let userId = dataController.currentUser?.id ?? ""
                        Task {
                            for expense in batchExpenses where expense.status == ExpenseStatus.submitted.rawValue {
                                await viewModel.approveExpense(expense.id, approvedBy: userId)
                            }
                        }
                    }
                    .opsPrimaryButtonStyle()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.background)
            }
        }
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

    // MARK: - Helpers

    private func loadBatchExpenses() async {
        isLoading = true
        defer { isLoading = false }
        batchExpenses = viewModel.expenses.filter { $0.batchId == batch.id }
    }

    private func formatPeriodDate(_ dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: dateString) {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            return fmt.string(from: date)
        }
        return dateString
    }
}

// MARK: - Helpers

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
