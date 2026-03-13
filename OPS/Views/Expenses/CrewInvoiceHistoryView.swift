//
//  CrewInvoiceHistoryView.swift
//  OPS
//
//  Read-only invoice history for crew members to view their past submitted invoices.
//

import SwiftUI

struct CrewInvoiceHistoryView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var dataController: DataController
    @State private var selectedBatch: ExpenseBatchDTO? = nil
    @State private var batchExpenses: [ExpenseDTO] = []
    @State private var expandedExpenseId: String? = nil

    // MARK: - Computed

    private var crewBatches: [ExpenseBatchDTO] {
        guard let userId = dataController.currentUser?.id else { return [] }
        return viewModel.reviewBatches.filter { $0.submittedBy == userId }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            if selectedBatch != nil {
                batchDetailView
            } else {
                invoiceListView
            }
        }
        .navigationTitle("MY INVOICES")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadBatchesForReview()
        }
    }

    // MARK: - Invoice List

    private var invoiceListView: some View {
        ScrollView {
            if crewBatches.isEmpty {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    Spacer().frame(height: 80)
                    Image(systemName: "doc.text")
                        .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("NO INVOICES YET")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(crewBatches) { batch in
                        batchRowCard(batch)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing3)
            }
        }
    }

    private func batchRowCard(_ batch: ExpenseBatchDTO) -> some View {
        Button {
            Task {
                let repo = ExpenseRepository(companyId: batch.companyId)
                do {
                    batchExpenses = try await repo.fetchBatchExpenses(batch.id)
                } catch {
                    batchExpenses = []
                }
                selectedBatch = batch
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(batch.batchNumber)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    Text(formatCurrency(batch.totalAmount ?? 0))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                statusPill(batch.status)

                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Batch Detail

    private var batchDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                // Back button
                Button {
                    withAnimation(OPSStyle.Animation.fast) {
                        selectedBatch = nil
                        batchExpenses = []
                        expandedExpenseId = nil
                    }
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        Text("BACK TO INVOICES")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing2)

                // Expense rows
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(batchExpenses) { expense in
                        expenseRow(expense)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
    }

    // MARK: - Expense Row

    private func expenseRow(_ expense: ExpenseDTO) -> some View {
        let isExpanded = expandedExpenseId == expense.id
        let isFlagged = expense.flaggedBy != nil

        return VStack(spacing: 0) {
            // Collapsed row
            Button {
                withAnimation(OPSStyle.Animation.fast) {
                    expandedExpenseId = isExpanded ? nil : expense.id
                }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    // Flag icon
                    if isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                    }

                    // Merchant name
                    Text(expense.merchantName ?? "UNKNOWN")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    Spacer()

                    // Amount
                    Text(formatCurrency(expense.amount))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // Rotating chevron
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
                Divider()
                    .background(OPSStyle.Colors.cardBorder)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    // Flag comment
                    if isFlagged, let comment = expense.flagComment, !comment.isEmpty {
                        Text(comment)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                    }

                    // Notes
                    if let notes = expense.description, !notes.isEmpty {
                        Text(notes)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    // Edit button on flagged items
                    if isFlagged {
                        Button {
                            // Handled by parent navigation
                        } label: {
                            Text("EDIT")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(
                    isFlagged ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.cardBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
    }

    // MARK: - Status Pill

    private func statusPill(_ status: String) -> some View {
        let displayName = ExpenseBatchStatus(rawValue: status)?.displayName ?? status.uppercased()
        let color = statusColor(status)

        return Text(displayName)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(color)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case ExpenseBatchStatus.approved.rawValue,
             ExpenseBatchStatus.autoApproved.rawValue:
            return OPSStyle.Colors.successStatus
        case ExpenseBatchStatus.rejected.rawValue:
            return OPSStyle.Colors.errorStatus
        case ExpenseBatchStatus.partiallyApproved.rawValue:
            return OPSStyle.Colors.warningStatus
        default:
            return OPSStyle.Colors.primaryAccent
        }
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}
