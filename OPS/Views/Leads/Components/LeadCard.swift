//
//  LeadCard.swift
//  OPS
//
//  Lead card for the LEADS tab. Quiet card body — actions revealed via
//  SwiftUI swipe gestures (leading edge → advance stage; trailing edge →
//  WON / LOST). Long-press opens the LeadActionSheet.
//
//  Layout: 3pt stage-color leading rail, Mohave bold title, JetBrains Mono
//  value, mono days-in-stage, one urgency chip (overdue > stale > untouched).
//
//  NOTE: temporarily named `LeadCard` (file: LeadCard.swift) to coexist with
//  the legacy `LeadCardView` in OPS/Views/Books/Pipeline/. Chunk P1-2 deletes
//  the legacy file (plan Task 14); rename back to `LeadCardView` (file:
//  LeadCardView.swift) after that.
//

import SwiftUI

struct LeadCard: View {
    let opportunity: Opportunity
    let canManage: Bool
    let isPendingOfflineError: Bool

    var onTap: () -> Void
    var onAdvance: () -> Void
    var onWon: () -> Void
    var onLost: () -> Void
    var onLongPress: () -> Void

    private var displayTitle: String {
        if let t = opportunity.title, !t.isEmpty { return t }
        if !opportunity.contactName.isEmpty { return opportunity.contactName }
        return "UNNAMED LEAD"
    }

    private var valueText: String? {
        guard let v = opportunity.estimatedValue else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: v))
    }

    private var daysInStageNumber: String { "\(opportunity.daysInStage)" }

    /// Highest-severity urgency marker; nil if none.
    private var urgencyChip: (label: String, color: Color)? {
        let isOverdue = (opportunity.nextFollowUpAt.map { $0 <= Date() }) ?? false
        if isOverdue {
            let days = max(1, daysOverdue)
            return ("\(days)D OVERDUE", OPSStyle.Colors.errorStatus)
        }
        if opportunity.isStale {
            return ("STALE", OPSStyle.Colors.warningStatus)
        }
        if opportunity.stage == .newLead && opportunity.lastActivityAt == nil {
            return ("UNTOUCHED", OPSStyle.Colors.tertiaryText)
        }
        return nil
    }

    private var daysOverdue: Int {
        guard let due = opportunity.nextFollowUpAt else { return 0 }
        let diff = Calendar.current.dateComponents([.day], from: due, to: Date()).day ?? 0
        return max(0, diff)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(opportunity.stage.color)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text(displayTitle)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if let valueText {
                            Text(valueText)
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        Text("·")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        HStack(spacing: 2) {
                            Text(daysInStageNumber)
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Text("D IN STAGE")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        if let chip = urgencyChip {
                            Text(chip.label)
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(chip.color)
                        }
                        if isPendingOfflineError {
                            Text("OFFLINE — TRY AGAIN")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                        Spacer()
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(OPSStyle.Colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.5, perform: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPress()
        })
        .accessibilityLabel(accessibilityLabel)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if canManage, !opportunity.stage.isTerminal, let next = opportunity.stage.next {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onAdvance()
                } label: {
                    Label("→ \(next.displayName)", systemImage: "arrow.right")
                }
                .tint(OPSStyle.Colors.primaryAccent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canManage, !opportunity.stage.isTerminal {
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onWon()
                } label: {
                    Label("WON", systemImage: "checkmark")
                }
                .tint(OPSStyle.Colors.successStatus)

                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLost()
                } label: {
                    Label("LOST", systemImage: "xmark")
                }
            }
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = [displayTitle, opportunity.stage.displayName]
        if let v = valueText { parts.append(v) }
        if let chip = urgencyChip { parts.append(chip.label) }
        return parts.joined(separator: ", ")
    }
}
