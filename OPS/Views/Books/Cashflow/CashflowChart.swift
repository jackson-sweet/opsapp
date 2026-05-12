//
//  CashflowChart.swift
//  OPS
//
//  Full-width running-balance line chart for the cashflow forecast. Built on
//  Swift Charts with area fill, threshold rule line, zero rule line, and
//  enlarged below-zero point markers. State color drives all tints.
//

import SwiftUI
import Charts

struct CashflowChart: View {
    let result: ForecastResult
    let onTapWeek: (WeeklyProjection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Chart {
            // Zero reference line — dashed when healthy, solid when in danger.
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(zeroLineColor)
                .lineStyle(StrokeStyle(
                    lineWidth: 1,
                    dash: result.state == .danger ? [] : [2, 4]
                ))

            // Low-water threshold — subtle dashed tan line.
            RuleMark(y: .value("Threshold", result.lowWaterThreshold))
                .foregroundStyle(OPSStyle.Colors.warningStatus.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))

            // Running balance line + point markers.
            ForEach(result.weeks) { week in
                LineMark(
                    x: .value("Week", week.id),
                    y: .value("Balance", week.balance)
                )
                .foregroundStyle(lineColor)
                .interpolationMethod(.linear)

                PointMark(
                    x: .value("Week", week.id),
                    y: .value("Balance", week.balance)
                )
                .symbolSize(week.balance < 0 ? 70 : 30)
                .foregroundStyle(week.balance < 0 ? OPSStyle.Colors.errorStatus : lineColor)
            }

            // Area fill below the line — low-opacity state-tinted gradient.
            ForEach(result.weeks) { week in
                AreaMark(
                    x: .value("Week", week.id),
                    yStart: .value("Balance", week.balance),
                    yEnd: .value("Zero", 0)
                )
                .foregroundStyle(LinearGradient(
                    colors: [lineColor.opacity(0.25), lineColor.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
        }
        .chartXAxis {
            AxisMarks(values: Array(stride(
                from: 0,
                through: max(result.weeks.count - 1, 0),
                by: max(1, result.weeks.count / 6)
            ))) { value in
                AxisValueLabel {
                    if let idx = value.as(Int.self) {
                        Text("W\(idx + 1)")
                            .font(OPSStyle.Typography.microLabel)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                AxisGridLine()
                    .foregroundStyle(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(shortCurrency(v))
                            .font(OPSStyle.Typography.microLabel)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                AxisGridLine()
                    .foregroundStyle(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onEnded { value in
                            guard let plot = proxy.plotFrame else { return }
                            let origin = geo[plot].origin
                            let xInPlot = value.location.x - origin.x
                            if let idx: Int = proxy.value(atX: xInPlot, as: Int.self),
                               idx >= 0, idx < result.weeks.count {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onTapWeek(result.weeks[idx])
                            }
                        }
                    )
            }
        }
        .animation(reduceMotion ? .none : OPSStyle.Animation.fast, value: result.state)
    }

    private var lineColor: Color {
        switch result.state {
        case .healthy:  return OPSStyle.Colors.primaryAccent
        case .lowWater: return OPSStyle.Colors.warningStatus
        case .danger:   return OPSStyle.Colors.errorStatus
        }
    }

    private var zeroLineColor: Color {
        result.state == .danger ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.secondaryText
    }

    private func shortCurrency(_ v: Double) -> String {
        let abs = Swift.abs(v)
        let sign = v < 0 ? "-" : ""
        if abs >= 1000 { return "\(sign)$\(Int(abs / 1000))K" }
        return "\(sign)$\(Int(abs))"
    }
}
