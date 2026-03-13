//
//  InvoiceCard.swift
//  OPS
//
//  Card component for the two-column Expense Review Dashboard grid.
//  Shows crew avatar, batch number, total amount, status pill, and amendment indicator.
//

import SwiftUI

struct ExpenseInvoiceCard: View {
    let batch: ExpenseBatchDTO

    // MARK: - Derived State

    private var batchStatus: ExpenseBatchStatus {
        ExpenseBatchStatus(rawValue: batch.status) ?? .pendingReview
    }

    private var crewDisplayName: String {
        batch.submittedBy ?? "UNASSIGNED"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Row 1: Avatar + crew info
            crewHeader

            // Row 2: Total amount
            Text(formatCurrency(batch.totalAmount ?? 0))
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)

            // Row 3: Status pill + amendment indicator
            statusRow
        }
        .padding(14)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Crew Header

    private var crewHeader: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            // Circle avatar placeholder
            Circle()
                .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(crewDisplayName)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Text(batch.batchNumber)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Status Row

    private var statusRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            statusPill

            if let amendment = batch.amendmentNumber, amendment > 0 {
                Text("+\(amendment) AMENDMENT\(amendment > 1 ? "S" : "")")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }

            Spacer(minLength: 0)
        }
    }

    private var statusPill: some View {
        Text(batchStatus.displayName)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(statusColor)
            )
    }

    // MARK: - Status Color

    private var statusColor: Color {
        switch batchStatus {
        case .pendingReview, .submitted:
            return OPSStyle.Colors.primaryAccent
        case .approved, .autoApproved:
            return OPSStyle.Colors.successStatus
        case .rejected:
            return OPSStyle.Colors.errorStatus
        case .partiallyApproved:
            return OPSStyle.Colors.warningStatus
        }
    }

    // MARK: - Currency Formatter

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}
