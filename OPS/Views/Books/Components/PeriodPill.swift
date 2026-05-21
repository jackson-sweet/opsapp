//
//  PeriodPill.swift
//  OPS
//
//  Books Phase 2 — single-tap pill replacing the multi-button PeriodToggle.
//  Surfaces 8 period options (trailing windows + calendar buckets) via Menu.
//  Compact, inline-friendly: just the menu button, no Spacer or sibling chrome.
//

import SwiftUI

struct PeriodPill: View {
    @Binding var selected: MoneyDashboardViewModel.Period

    var body: some View {
        Menu {
            ForEach(MoneyDashboardViewModel.Period.allCases, id: \.self) { period in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selected = period
                } label: {
                    HStack {
                        Text(period.pillLabel)
                        if selected == period {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selected.pillLabel)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(12)
            .frame(minHeight: 44)  // Mission Deck — 44pt mobile touch-target floor
        }
        .accessibilityLabel("Period selector, currently \(selected.label)")
        .accessibilityHint("Double-tap to change period")
    }
}

#if DEBUG
private struct PeriodPillPreviewHost: View {
    @State private var period: MoneyDashboardViewModel.Period = .sixMonths
    var body: some View {
        VStack(spacing: 24) {
            PeriodPill(selected: $period)
            Text("Selected: \(period.pillLabel)")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(24)
        .background(OPSStyle.Colors.background)
    }
}

#Preview("PeriodPill") {
    PeriodPillPreviewHost()
        .preferredColorScheme(.dark)
}
#endif

extension MoneyDashboardViewModel.Period {
    /// Human-friendly label used by `PeriodPill` and `CollapsedCarouselStrip`.
    var pillLabel: String {
        switch self {
        case .month:       return "30 DAYS"
        case .quarter:     return "90 DAYS"
        case .sixMonths:   return "6 MONTHS"
        case .year:        return "1 YEAR"
        case .thisMonth:   return "THIS MONTH"
        case .lastMonth:   return "LAST MONTH"
        case .thisQuarter: return "THIS QUARTER"
        case .ytd:         return "YEAR TO DATE"
        }
    }

    /// Short label used in tight UI like the collapsed strip.
    var shortLabel: String {
        switch self {
        case .month:       return "30D"
        case .quarter:     return "90D"
        case .sixMonths:   return "6M"
        case .year:        return "1Y"
        case .thisMonth:   return "MTD"
        case .lastMonth:   return "LAST"
        case .thisQuarter: return "QTD"
        case .ytd:         return "YTD"
        }
    }
}
