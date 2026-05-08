//
//  LeadCardView.swift
//  OPS
//
//  Per-lead card with title, value, days-in-stage, stale indicator,
//  and inline action chips (advance/won/lost/⋯). Tap card body → detail.
//

import SwiftUI

struct LeadCardView: View {
    let opportunity: Opportunity
    let canManage: Bool
    var onTap: () -> Void
    var onAdvance: () -> Void       // → opportunity.stage.next
    var onWon: () -> Void
    var onLost: () -> Void
    var onMore: () -> Void          // opens LeadActionSheet

    private var displayTitle: String {
        if let t = opportunity.title, !t.isEmpty { return t }
        return opportunity.contactName.isEmpty ? "(no name)" : opportunity.contactName
    }

    private var valueText: String? {
        guard let v = opportunity.estimatedValue else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: v))
    }

    private var daysInStageText: String {
        let d = opportunity.daysInStage
        return d == 1 ? "1d in stage" : "\(d)d in stage"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                // Title row
                Text(displayTitle)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Metadata row
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    if let valueText {
                        Text(valueText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    Text("·")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(daysInStageText)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    if opportunity.isStale {
                        Text("⚠ STALE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    }
                    Spacer()
                }

                // Inline action chips (only if canManage AND not terminal)
                if canManage && !opportunity.stage.isTerminal {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if let next = opportunity.stage.next {
                            ChipButton(
                                label: "→ \(next.displayName)",
                                tint: OPSStyle.Colors.primaryAccent,
                                inverted: true,
                                action: onAdvance
                            )
                        }
                        ChipButton(
                            label: "WON",
                            tint: OPSStyle.Colors.successStatus,
                            inverted: true,
                            action: onWon
                        )
                        ChipButton(
                            label: "LOST",
                            tint: OPSStyle.Colors.tertiaryText,
                            inverted: false,
                            action: onLost
                        )
                        Spacer()
                        Button(action: onMore) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackground)
            .overlay(alignment: .leading) {
                if opportunity.isStale {
                    Rectangle()
                        .fill(OPSStyle.Colors.errorStatus.opacity(0.6))
                        .frame(width: 3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct ChipButton: View {
    let label: String
    let tint: Color
    let inverted: Bool         // when true, fill = tint, text = invertedText
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(inverted ? OPSStyle.Colors.invertedText : tint)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(inverted ? tint : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(inverted ? Color.clear : tint, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
