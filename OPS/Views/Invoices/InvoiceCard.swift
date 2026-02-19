//
//  InvoiceCard.swift
//  OPS
//
//  Card for invoice list — shows number, total, status, due/overdue badge.
//

import SwiftUI

struct InvoiceCard: View {
    let invoice: Invoice
    let onTap: () -> Void
    let onSwipeRight: () -> Void
    let onSwipeLeft: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var swipeThreshold: CGFloat { 80 }

    private var canSwipeRight: Bool {
        invoice.status.needsPayment
    }

    var body: some View {
        ZStack {
            // Swipe-right reveal — record payment
            if canSwipeRight {
                HStack {
                    Label("PAYMENT", systemImage: "dollarsign.circle.fill")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.black)
                        .padding(.leading, OPSStyle.Layout.spacing3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OPSStyle.Colors.successStatus)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .opacity(dragOffset > 0 ? Double(min(dragOffset / swipeThreshold, 1)) : 0)
            }

            // Swipe-left reveal — void
            if !invoice.status.isTerminal {
                HStack {
                    Spacer()
                    Label("VOID", systemImage: "xmark.circle.fill")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.white)
                        .padding(.trailing, OPSStyle.Layout.spacing3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OPSStyle.Colors.errorStatus)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .opacity(dragOffset < 0 ? Double(min(-dragOffset / swipeThreshold, 1)) : 0)
            }

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
                                withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                                onSwipeRight()
                            } else if value.translation.width < -swipeThreshold && !invoice.status.isTerminal {
                                withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                                onSwipeLeft()
                            } else {
                                withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                            }
                        }
                )
        }
    }

    private var cardContent: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                HStack {
                    Text(invoice.invoiceNumber.isEmpty ? "NEW INVOICE" : invoice.invoiceNumber)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(invoice.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                if let title = invoice.title, !title.isEmpty {
                    Text(title)
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }

                HStack {
                    statusBadge

                    Spacer()

                    if invoice.isOverdue, let due = invoice.dueDate {
                        Text("[overdue \(due.timeAgoShort)]")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    } else if let due = invoice.dueDate {
                        Text("[due \(due.dueInCaption)]")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    } else {
                        Text("[\(invoice.createdAt.timeAgoShort)]")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(
                        invoice.isOverdue ? OPSStyle.Colors.errorStatus.opacity(0.4) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var statusBadge: some View {
        let color = invoice.status.badgeColor(isOverdue: invoice.isOverdue)
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(invoice.isOverdue ? "OVERDUE" : invoice.status.displayName)
                .font(OPSStyle.Typography.smallCaption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Helpers

private extension InvoiceStatus {
    func badgeColor(isOverdue: Bool) -> Color {
        if isOverdue { return OPSStyle.Colors.errorStatus }
        switch self {
        case .draft:           return OPSStyle.Colors.tertiaryText
        case .sent:            return OPSStyle.Colors.primaryAccent
        case .awaitingPayment: return OPSStyle.Colors.warningStatus
        case .partiallyPaid:   return OPSStyle.Colors.warningStatus
        case .paid:            return OPSStyle.Colors.successStatus
        case .pastDue:         return OPSStyle.Colors.errorStatus
        case .void:            return OPSStyle.Colors.tertiaryText
        }
    }

    var isTerminal: Bool {
        self == .paid || self == .void
    }
}

private extension Date {
    var timeAgoShort: String {
        let interval = Date().timeIntervalSince(self)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 60 { return "\(max(1, minutes))m ago" }
        if hours < 24 { return "\(hours)hr ago" }
        if days == 1 { return "yesterday" }
        return "\(days)d ago"
    }

    var dueInCaption: String {
        let interval = self.timeIntervalSince(Date())
        let days = Int(interval / 86400)
        if days == 0 { return "today" }
        if days == 1 { return "tomorrow" }
        if days > 0 { return "in \(days) days" }
        return timeAgoShort
    }
}
