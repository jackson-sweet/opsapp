//
//  CashflowForecastCard.swift
//  OPS
//
//  Compact preview card. Lives on the Books surface (below MoneyDashboardHeader
//  while the parent carousel work is still pending). Tap → CashflowForecastScreen.
//

import SwiftUI

struct CashflowForecastCard: View {
    @ObservedObject var viewModel: CashflowForecastViewModel
    @State private var presentFull = false

    var body: some View {
        Button(action: { presentFull = true }) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                header
                heroNumber
                sparkline
                footer
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                    .stroke(borderColor, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius))
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $presentFull) {
            CashflowForecastScreen(viewModel: viewModel)
        }
        .task { if viewModel.result == nil { await viewModel.load() } }
    }

    private var state: ForecastState { viewModel.result?.state ?? .healthy }

    private var lineColor: Color {
        switch state {
        case .healthy:  return OPSStyle.Colors.primaryAccent
        case .lowWater: return OPSStyle.Colors.warningStatus
        case .danger:   return OPSStyle.Colors.errorStatus
        }
    }

    private var borderColor: Color {
        state == .danger ? OPSStyle.Colors.errorStatus : Color.clear
    }

    private var header: some View {
        HStack {
            Text("// CASH FORECAST · \(viewModel.result?.weeks.count ?? 13)W")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            stateBadge
        }
    }

    @ViewBuilder
    private var heroNumber: some View {
        if let r = viewModel.result {
            Text(formatCurrency(r.endingBalance))
                .font(OPSStyle.Typography.dataValueLg)
                .monospacedDigit()
                .foregroundColor(state == .danger ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)
        } else if viewModel.isLoading {
            Text("—")
                .font(OPSStyle.Typography.dataValueLg)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        } else {
            Text("TAP TO SET CURRENT BALANCE")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.warningStatus)
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        if let r = viewModel.result {
            CashflowSparkline(weeks: r.weeks, lineColor: lineColor, threshold: r.lowWaterThreshold)
                .frame(height: 32)
        } else {
            Rectangle().fill(Color.clear).frame(height: 32)
        }
    }

    private var footer: some View {
        HStack {
            if let r = viewModel.result {
                Text("LOWEST \(formatCurrency(r.lowestBalance)) · WK \(r.lowestWeekIndex + 1)")
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            Spacer()
            Text("TAP TO DRILL →")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    private var stateBadge: some View {
        Text(badgeLabel)
            .font(OPSStyle.Typography.microLabel)
            .padding(.horizontal, OPSStyle.Layout.spacing1 + 2)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .stroke(lineColor, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .foregroundColor(lineColor)
    }

    private var badgeLabel: String {
        switch state {
        case .healthy:  return "ON TRACK"
        case .lowWater: return "WATCH"
        case .danger:   return "DIP DETECTED"
        }
    }

    private func formatCurrency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "$0"
    }
}

/// Compact sparkline (no markers, no axis labels). Visual cue only.
struct CashflowSparkline: View {
    let weeks: [WeeklyProjection]
    let lineColor: Color
    let threshold: Double

    var body: some View {
        GeometryReader { geo in
            let points = computePoints(in: geo.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }
            }
            .stroke(lineColor, lineWidth: 1.5)
        }
    }

    private func computePoints(in size: CGSize) -> [CGPoint] {
        guard !weeks.isEmpty else { return [] }
        let yValues = weeks.map { $0.balance }
        let minY = min(0, yValues.min() ?? 0)
        let maxY = max(yValues.max() ?? 1, threshold)
        let range = (maxY - minY) == 0 ? 1 : (maxY - minY)
        let stepX = size.width / CGFloat(max(weeks.count - 1, 1))
        return weeks.enumerated().map { i, w in
            let xRaw = CGFloat(i) * stepX
            let yRatio = CGFloat((w.balance - minY) / range)
            return CGPoint(x: xRaw, y: size.height - (yRatio * size.height))
        }
    }
}
