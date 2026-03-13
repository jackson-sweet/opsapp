//
//  InvoiceDetailView.swift
//  OPS
//
//  Invoice detail view where admins review individual expense line items,
//  flag them, and approve or reject the invoice.
//

import SwiftUI

struct ExpenseInvoiceDetailView: View {
    let batch: ExpenseBatchDTO
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var expandedExpenseId: String? = nil
    @State private var flagInputExpenseId: String? = nil
    @State private var flagInputText: String = ""
    @State private var showRejectConfirmation = false
    @State private var showReceiptViewer = false
    @State private var receiptImageUrl: String? = nil

    // MARK: - Computed

    private var isReviewable: Bool {
        let status = ExpenseBatchStatus(rawValue: batch.status) ?? .pendingReview
        return status == .pendingReview || status == .submitted
    }

    private var flagCount: Int {
        viewModel.flaggedExpenseIds.count
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    headerCard
                        .padding(.top, OPSStyle.Layout.spacing3)

                    sectionHeader("EXPENSES")

                    expenseRows
                }
                .padding(.bottom, isReviewable ? 120 : OPSStyle.Layout.spacing3)
            }

            if isReviewable {
                stickyFooter
            }
        }
        .navigationTitle(batch.batchNumber)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadBatchExpenses(batch.id)
        }
        .sheet(isPresented: $showRejectConfirmation) {
            RejectConfirmationView(
                batch: batch,
                viewModel: viewModel,
                onDismiss: { dismiss() }
            )
        }
        .fullScreenCover(isPresented: $showReceiptViewer) {
            if let url = receiptImageUrl {
                FullScreenReceiptViewer(imageUrl: url)
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 0) {
            // Crew info row
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // Crew avatar
                Circle()
                    .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(batch.submittedBy ?? "UNASSIGNED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    Text(batch.batchNumber)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }

                Spacer()

                // Flag count badge
                if flagCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        Text("\(flagCount)")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                }
            }
            .padding(OPSStyle.Layout.spacing3)

            Divider()
                .background(OPSStyle.Colors.cardBorder)

            // Stats row
            HStack(spacing: 0) {
                statCell(label: "TOTAL", value: formatCurrency(batch.totalAmount ?? 0))
                statCell(label: "EXPENSES", value: "\(viewModel.selectedBatchExpenses.count)")
                statCell(label: "SUBMITTED", value: formatDate(batch.createdAt))
            }
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Expense Rows

    private var expenseRows: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(viewModel.selectedBatchExpenses) { expense in
                expenseRow(expense)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func expenseRow(_ expense: ExpenseDTO) -> some View {
        let isExpanded = expandedExpenseId == expense.id
        let isFlagged = viewModel.flaggedExpenseIds.contains(expense.id)

        return VStack(spacing: 0) {
            // Collapsed row
            Button {
                withAnimation(OPSStyle.Animation.fast) {
                    expandedExpenseId = isExpanded ? nil : expense.id
                }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    // Flag icon if flagged
                    if isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                    }

                    // Date
                    Text(formatExpenseDate(expense.expenseDate ?? expense.createdAt))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(width: 50, alignment: .leading)

                    // Merchant name
                    Text(expense.merchantName ?? "UNKNOWN")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    Spacer()

                    // Amount
                    Text(formatCurrency(expense.amount))
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
            .buttonStyle(PlainButtonStyle())
            .background(isFlagged ? OPSStyle.Colors.warningStatus.opacity(0.08) : Color.clear)

            // Expanded content
            if isExpanded {
                expandedContent(expense, isFlagged: isFlagged)
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func expandedContent(_ expense: ExpenseDTO, isFlagged: Bool) -> some View {
        VStack(spacing: 0) {
            Divider()
                .background(OPSStyle.Colors.cardBorder)

            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
                // Left column: detail rows
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    detailRow(
                        label: "CATEGORY",
                        value: expense.category?.name ?? "Uncategorized"
                    )

                    if let method = expense.paymentMethod {
                        let display = ExpensePaymentMethod(rawValue: method)?.displayName ?? method.uppercased()
                        detailRow(label: "PAYMENT", value: display)
                    }

                    if let tax = expense.taxAmount, tax > 0 {
                        detailRow(label: "TAX", value: formatCurrency(tax))
                    }

                    if let notes = expense.description, !notes.isEmpty {
                        detailRow(label: "NOTES", value: notes)
                    }
                }

                Spacer()

                // Right column: receipt thumbnail
                receiptThumbnail(expense)
            }
            .padding(OPSStyle.Layout.spacing3)

            // Flag action area (only when reviewable)
            if isReviewable {
                flagActionArea(expense, isFlagged: isFlagged)
            }
        }
        .background(OPSStyle.Colors.background.opacity(0.5))
    }

    // MARK: - Receipt Thumbnail

    private func receiptThumbnail(_ expense: ExpenseDTO) -> some View {
        Group {
            if let thumbUrl = expense.receiptThumbnailUrl ?? expense.receiptImageUrl,
               let url = URL(string: thumbUrl) {
                Button {
                    receiptImageUrl = thumbUrl
                    showReceiptViewer = true
                } label: {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else if case .failure = phase {
                            receiptPlaceholder
                        } else {
                            ProgressView()
                                .tint(OPSStyle.Colors.secondaryText)
                        }
                    }
                    .frame(width: 80, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
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
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .fill(OPSStyle.Colors.cardBackgroundDark)
            .frame(width: 80, height: 100)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: OPSStyle.Layout.IconSize.lg))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    // MARK: - Flag Action Area

    private func flagActionArea(_ expense: ExpenseDTO, isFlagged: Bool) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Divider()
                .background(OPSStyle.Colors.cardBorder)

            if isFlagged {
                // Already flagged: show comment + unflag button
                flaggedState(expense)
            } else if flagInputExpenseId == expense.id {
                // Inputting flag comment
                flagInputState(expense)
            } else {
                // Not flagged: show flag button
                flagButton(expense)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    private func flagButton(_ expense: ExpenseDTO) -> some View {
        Button {
            withAnimation(OPSStyle.Animation.fast) {
                flagInputExpenseId = expense.id
                flagInputText = ""
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: "flag")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                Text("FLAG THIS EXPENSE")
                    .font(OPSStyle.Typography.smallCaption)
            }
            .foregroundColor(OPSStyle.Colors.warningStatus)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func flagInputState(_ expense: ExpenseDTO) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            TextField("Reason for flagging...", text: $flagInputText)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button {
                    withAnimation(OPSStyle.Animation.fast) {
                        flagInputExpenseId = nil
                        flagInputText = ""
                    }
                } label: {
                    Text("CANCEL")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    let userId = dataController.currentUser?.id ?? ""
                    let comment = flagInputText.isEmpty ? "Flagged for revision" : flagInputText
                    let expenseId = expense.id
                    flagInputExpenseId = nil
                    flagInputText = ""
                    Task {
                        await viewModel.flagExpense(expenseId, comment: comment, flaggedBy: userId)
                    }
                } label: {
                    Text("FLAG")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
            }
        }
    }

    private func flaggedState(_ expense: ExpenseDTO) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            if let comment = viewModel.flagComments[expense.id], !comment.isEmpty {
                Text(comment)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }

            Button {
                let expenseId = expense.id
                Task {
                    await viewModel.unflagExpense(expenseId)
                }
            } label: {
                Text("UNFLAG")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sticky Footer

    private var stickyFooter: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            if flagCount > 0 {
                // Flags present: remove all + reject
                Button {
                    Task {
                        await viewModel.unflagAllExpenses()
                    }
                } label: {
                    Text("REMOVE ALL FLAGS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    showRejectConfirmation = true
                } label: {
                    Text("REJECT WITH \(flagCount) REVISION\(flagCount == 1 ? "" : "S")")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(OPSStyle.Colors.errorStatus)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // No flags: reject + approve
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    // Reject (disabled when no flags)
                    Button { } label: {
                        Text("REJECT")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.clear)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(true)

                    // Approve all
                    Button {
                        let userId = dataController.currentUser?.id ?? ""
                        Task {
                            await viewModel.approveInvoice(batch.id, reviewedBy: userId)
                            dismiss()
                        }
                    } label: {
                        Text("APPROVE ALL")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OPSStyle.Colors.successStatus)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
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

    // MARK: - Formatters

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    /// Parses an ISO 8601 date string and returns an uppercased "MMM d" representation.
    private func formatDate(_ dateString: String) -> String {
        let isoDate = ISO8601DateFormatter()
        isoDate.formatOptions = [.withFullDate]
        let isoFull = ISO8601DateFormatter()

        var date: Date?
        date = isoDate.date(from: dateString)
        if date == nil { date = isoFull.date(from: dateString) }
        guard let resolved = date else { return dateString }

        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: resolved).uppercased()
    }

    /// Parses an ISO 8601 date string and returns "MM/dd" format.
    private func formatExpenseDate(_ dateString: String) -> String {
        let isoDate = ISO8601DateFormatter()
        isoDate.formatOptions = [.withFullDate]
        let isoFull = ISO8601DateFormatter()

        var date: Date?
        date = isoDate.date(from: dateString)
        if date == nil { date = isoFull.date(from: dateString) }
        guard let resolved = date else { return dateString }

        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd"
        return fmt.string(from: resolved)
    }
}
