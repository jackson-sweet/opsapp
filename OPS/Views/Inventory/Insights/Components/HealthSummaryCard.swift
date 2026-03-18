//
//  HealthSummaryCard.swift
//  OPS
//
//  Single metric card for inventory health summary row.
//

import SwiftUI

struct HealthSummaryCard: View {
    let icon: String
    let value: Int
    let label: String
    let valueColor: Color
    let iconColor: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(iconColor)
                Spacer()
            }

            Text("\(value)")
                .font(OPSStyle.Typography.displayQuantity)
                .foregroundColor(valueColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}
