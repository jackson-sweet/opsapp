//
//  PeriodPill.swift
//  OPS
//
//  Books Phase 2 — single-tap pill replacing the multi-button PeriodToggle.
//  Surfaces 8 period options (trailing windows + calendar buckets) via Menu.
//

import SwiftUI

struct PeriodPill: View {
    @Binding var selected: MoneyDashboardViewModel.Period
    /// Optional month-over-month trend value displayed beside the pill (positive = green, negative = red).
    var momTrend: Double?

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
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
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .cornerRadius(14)
            }
            Spacer()
            if let mom = momTrend {
                Text(momLabel(mom))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(mom >= 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
    }

    private func momLabel(_ mom: Double) -> String {
        let arrow = mom >= 0 ? "↑" : "↓"
        return "\(arrow)\(String(format: "%.1f", abs(mom)))% MoM"
    }
}

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
