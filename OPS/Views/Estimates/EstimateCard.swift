//
//  EstimateCard.swift
//  OPS
//
//  Card for estimate list — shows number, client, total, status badge, and age.
//

import SwiftUI

struct EstimateCard: View {
    let estimate: Estimate
    let onTap: () -> Void
    let onSwipeRight: () -> Void
    let onSwipeLeft: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var swipeThreshold: CGFloat { 80 }

    private var swipeRightLabel: String {
        switch estimate.status {
        case .draft:    return "SEND"
        case .approved: return "CONVERT"
        default:        return ""
        }
    }

    private var swipeRightIcon: String {
        switch estimate.status {
        case .draft:    return "paperplane.fill"
        case .approved: return OPSStyle.Icons.invoiceReceipt
        default:        return ""
        }
    }

    private var canSwipeRight: Bool {
        estimate.status == .draft || estimate.status == .approved
    }

    var body: some View {
        ZStack {
            // Swipe-right reveal
            if canSwipeRight {
                HStack {
                    Label(swipeRightLabel, systemImage: swipeRightIcon)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.black)
                        .padding(.leading, OPSStyle.Layout.spacing3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(estimate.status == .draft ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.successStatus)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .opacity(dragOffset > 0 ? Double(min(dragOffset / swipeThreshold, 1)) : 0)
            }

            // Swipe-left reveal (void)
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
                            } else if value.translation.width < -swipeThreshold && !estimate.status.isTerminal {
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
                    Text(estimate.estimateNumber.isEmpty ? "NEW ESTIMATE" : estimate.estimateNumber)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(estimate.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                if let title = estimate.title, !title.isEmpty {
                    Text(title)
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }

                HStack {
                    statusBadge
                    Spacer()
                    Text("[\(estimate.createdAt.timeAgoShort)]")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var statusBadge: some View {
        let color = estimate.status.color
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(estimate.status.displayName)
                .font(OPSStyle.Typography.smallCaption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Helpers

private extension EstimateStatus {
    var color: Color {
        switch self {
        case .draft:     return OPSStyle.Colors.tertiaryText
        case .sent:      return OPSStyle.Colors.primaryAccent
        case .viewed:    return OPSStyle.Colors.primaryAccent
        case .approved:  return OPSStyle.Colors.successStatus
        case .converted: return OPSStyle.Colors.successStatus
        case .declined:  return OPSStyle.Colors.errorStatus
        case .expired:   return OPSStyle.Colors.warningStatus
        }
    }

    var isTerminal: Bool {
        self == .converted || self == .declined || self == .expired
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
}
