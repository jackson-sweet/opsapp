//
//  ForecastBreakdownSheet.swift
//  OPS
//
//  Bottom sheet that breaks down the weighted forecast by lead, sorted
//  by weighted value descending. Tapping a row pushes LeadDetailView.
//

import SwiftUI

struct ForecastBreakdownSheet: View {
    let opportunities: [Opportunity]
    var onSelect: (Opportunity) -> Void

    @Environment(\.dismiss) private var dismiss

    private var sortedActive: [Opportunity] {
        opportunities
            .filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }
            .sorted { $0.weightedValue > $1.weightedValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(sortedActive) { opp in
                        Button { onSelect(opp); dismiss() } label: {
                            HStack(spacing: 0) {
                                Rectangle().fill(opp.stage.color).frame(width: 3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: opp))
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    HStack(spacing: 4) {
                                        Text(opp.stage.displayName)
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                        Text("·")
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        Text("\(opp.stage.winProbability)%")
                                            .font(OPSStyle.Typography.metadata)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                }
                                .padding(OPSStyle.Layout.spacing3)
                                Spacer()
                                Text(formatCurrency(opp.weightedValue))
                                    .font(OPSStyle.Typography.dataValue)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .padding(.trailing, OPSStyle.Layout.spacing3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(OPSStyle.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("WEIGHTED FORECAST")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CLOSE") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                }
            }
        }
    }

    private func displayName(for opp: Opportunity) -> String {
        if let t = opp.title, !t.isEmpty { return t }
        if !opp.contactName.isEmpty { return opp.contactName }
        return "UNNAMED LEAD"
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}
