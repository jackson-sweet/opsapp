//
//  PeriodToggle.swift
//  OPS
//
//  Horizontal pill selector for financial time period — 30D | 90D | 6M | 1Y.
//

import SwiftUI

struct PeriodToggle: View {
    @Binding var selectedPeriod: MoneyDashboardViewModel.Period

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(MoneyDashboardViewModel.Period.allCases, id: \.self) { period in
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(OPSStyle.Animation.fast) {
                        selectedPeriod = period
                    }
                } label: {
                    Text(period.rawValue)
                        .font(OPSStyle.Typography.smallButton)
                        .foregroundColor(selectedPeriod == period ? .white : OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(selectedPeriod == period ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackgroundDark)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(selectedPeriod == period ? Color.clear : OPSStyle.Colors.cardBorderSubtle, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
