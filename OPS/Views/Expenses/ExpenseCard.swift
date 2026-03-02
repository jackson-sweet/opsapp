//
//  ExpenseCard.swift
//  OPS
//
//  Card for expense list — shows merchant, amount, category, status badge, and date.
//

import SwiftUI

struct ExpenseCard: View {
    let expense: ExpenseDTO
    let categoryName: String?
    let categoryIcon: String?
    let onTap: () -> Void
    let onSwipeRight: () -> Void
    let onSwipeLeft: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var swipeThreshold: CGFloat { 80 }

    private var expenseStatus: ExpenseStatus {
        ExpenseStatus(rawValue: expense.status) ?? .draft
    }

    private var canSwipeRight: Bool {
        expenseStatus == .draft
    }

    private var canSwipeLeft: Bool {
        expenseStatus != .approved && expenseStatus != .reimbursed
    }

    private var formattedDate: String {
        guard let dateString = expense.expenseDate ?? Optional(expense.createdAt) else {
            return ""
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: dateString) {
            let display = DateFormatter()
            display.dateFormat = "MMM d"
            return display.string(from: date)
        }
        // Fallback: try the full createdAt string
        let fallback = ISO8601DateFormatter()
        if let date = fallback.date(from: expense.createdAt) {
            let display = DateFormatter()
            display.dateFormat = "MMM d"
            return display.string(from: date)
        }
        return ""
    }

    var body: some View {
        ZStack {
            // Swipe-right reveal (SUBMIT)
            if canSwipeRight {
                HStack {
                    Label("SUBMIT", systemImage: "paperplane.fill")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .padding(.leading, OPSStyle.Layout.spacing3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .opacity(dragOffset > 0 ? Double(min(dragOffset / swipeThreshold, 1)) : 0)
            }

            // Swipe-left reveal (DELETE)
            HStack {
                Spacer()
                Label("DELETE", systemImage: "trash.fill")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.trailing, OPSStyle.Layout.spacing3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPSStyle.Colors.errorStatus)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .opacity(dragOffset < 0 ? Double(min(-dragOffset / swipeThreshold, 1)) : 0)

            // Card content
            cardContent
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            if value.translation.width > swipeThreshold && canSwipeRight {
                                withAnimation(OPSStyle.Animation.faster) { dragOffset = 0 }
                                onSwipeRight()
                            } else if value.translation.width < -swipeThreshold && canSwipeLeft {
                                withAnimation(OPSStyle.Animation.faster) { dragOffset = 0 }
                                onSwipeLeft()
                            } else {
                                withAnimation(OPSStyle.Animation.faster) { dragOffset = 0 }
                            }
                        }
                )
        }
    }

    private var cardContent: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                // Row 1: merchant name + amount
                HStack {
                    Text(expense.merchantName ?? "UNKNOWN MERCHANT")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(expense.amount, format: .currency(code: expense.currency ?? "USD").precision(.fractionLength(2)))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                // Row 2: category icon + name
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    if let icon = categoryIcon, !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Text(categoryName ?? "UNCATEGORIZED")
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }

                // Row 3: status badge + date
                HStack {
                    statusBadge
                    Spacer()
                    Text(formattedDate)
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
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var statusBadge: some View {
        let color = expenseStatus.badgeColor
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(expenseStatus.displayName)
                .font(OPSStyle.Typography.smallCaption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Helpers

private extension ExpenseStatus {
    var badgeColor: Color {
        switch self {
        case .draft:      return OPSStyle.Colors.tertiaryText
        case .submitted:  return OPSStyle.Colors.primaryAccent
        case .approved:   return OPSStyle.Colors.successStatus
        case .rejected:   return OPSStyle.Colors.errorStatus
        case .reimbursed: return OPSStyle.Colors.successStatus
        }
    }
}
