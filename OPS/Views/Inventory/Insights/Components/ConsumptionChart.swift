//
//  ConsumptionChart.swift
//  OPS
//
//  Interactive line chart for inventory consumption trends.
//  Uses Swift Charts with scrub gesture, time range pills, and legend toggling.
//

import SwiftUI
import Charts

struct ConsumptionChart: View {
    @ObservedObject var viewModel: InventoryInsightsViewModel

    // Scrub state
    @State private var scrubPosition: CGFloat? = nil
    @State private var scrubDate: Date? = nil
    @State private var scrubValues: [(name: String, quantity: Double, color: Color)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Section header
            sectionHeader

            if viewModel.hasEnoughData {
                // Time range pills
                timeRangePills

                // Chart
                chartView
                    .frame(height: 220)

                // Legend
                legendView
            } else {
                emptyState
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("CONSUMPTION TRENDS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Spacer()
        }
    }

    // MARK: - Time Range Pills

    private var timeRangePills: some View {
        HStack(spacing: 8) {
            ForEach(InsightsTimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(OPSStyle.Animation.fast) {
                        viewModel.selectedTimeRange = range
                        // Clear scrub on range change
                        scrubPosition = nil
                        scrubDate = nil
                        scrubValues = []
                    }
                } label: {
                    Text(range.rawValue)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(
                            viewModel.selectedTimeRange == range
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.secondaryText
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            viewModel.selectedTimeRange == range
                                ? OPSStyle.Colors.primaryAccent.opacity(0.15)
                                : Color.clear
                        )
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(
                                    viewModel.selectedTimeRange == range
                                        ? OPSStyle.Colors.primaryAccent.opacity(0.4)
                                        : OPSStyle.Colors.cardBorder,
                                    lineWidth: OPSStyle.Layout.Border.standard
                                )
                        )
                }
            }

            Spacer()
        }
    }

    // MARK: - Chart

    private var visibleTrends: [ItemTrend] {
        viewModel.trendData.filter { viewModel.visibleItemIds.contains($0.id) }
    }

    private var chartView: some View {
        Chart {
            ForEach(visibleTrends) { trend in
                let lineColor = Color(hex: trend.colorHex) ?? OPSStyle.Colors.primaryAccent

                ForEach(trend.dataPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Quantity", point.quantity)
                    )
                    .foregroundStyle(lineColor)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol {
                        Circle()
                            .fill(lineColor)
                            .frame(width: 4, height: 4)
                    }
                }
            }

            // Scrub rule mark
            if let date = scrubDate {
                RuleMark(x: .value("Scrub", date))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel()
                    .font(.custom("Kosugi-Regular", size: 10))
                    .foregroundStyle(OPSStyle.Colors.tertiaryText)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel()
                    .font(.custom("Kosugi-Regular", size: 10))
                    .foregroundStyle(OPSStyle.Colors.tertiaryText)
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let xPos = value.location.x
                                guard let plotFrame = proxy.plotFrame else { return }
                                let plotOrigin = geometry[plotFrame].origin
                                let relativeX = xPos - plotOrigin.x

                                guard relativeX >= 0,
                                      relativeX <= geometry[plotFrame].width else {
                                    return
                                }

                                guard let date: Date = proxy.value(atX: relativeX) else { return }
                                scrubPosition = relativeX
                                scrubDate = date

                                // Find nearest data point for each visible trend
                                var values: [(name: String, quantity: Double, color: Color)] = []
                                for trend in visibleTrends {
                                    let lineColor = Color(hex: trend.colorHex) ?? OPSStyle.Colors.primaryAccent
                                    if let nearest = trend.dataPoints.min(by: {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    }) {
                                        values.append((name: trend.name, quantity: nearest.quantity, color: lineColor))
                                    }
                                }
                                scrubValues = values
                            }
                            .onEnded { _ in
                                scrubPosition = nil
                                scrubDate = nil
                                scrubValues = []
                            }
                    )

                // Tooltip card
                if let xPos = scrubPosition, !scrubValues.isEmpty {
                    let plotFrame = proxy.plotFrame
                    let plotWidth = plotFrame.map { geometry[$0].width } ?? geometry.size.width
                    // Flip tooltip to left side if near right edge
                    let tooltipOnRight = xPos < plotWidth * 0.65

                    tooltipCard
                        .offset(
                            x: tooltipOnRight ? xPos + 12 : xPos - 162,
                            y: 8
                        )
                }
            }
        }
    }

    // MARK: - Tooltip

    private var tooltipCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let date = scrubDate {
                Text(date, format: .dateTime.month(.abbreviated).day())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            ForEach(Array(scrubValues.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 6, height: 6)

                    Text(item.name)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)

                    Spacer()

                    Text(formatQuantity(item.quantity))
                        .font(.custom("Mohave-Bold", size: 12))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .padding(10)
        .frame(width: 150)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Legend

    private var legendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.trendData) { trend in
                    let isVisible = viewModel.visibleItemIds.contains(trend.id)
                    let chipColor = Color(hex: trend.colorHex) ?? OPSStyle.Colors.primaryAccent

                    Button {
                        withAnimation(OPSStyle.Animation.fast) {
                            if isVisible {
                                viewModel.visibleItemIds.remove(trend.id)
                            } else {
                                viewModel.visibleItemIds.insert(trend.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isVisible ? chipColor : chipColor.opacity(0.3))
                                .frame(width: 6, height: 6)

                            Text(trend.name)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(
                                    isVisible
                                        ? OPSStyle.Colors.primaryText
                                        : OPSStyle.Colors.tertiaryText
                                )
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isVisible
                                ? chipColor.opacity(0.1)
                                : Color.clear
                        )
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(
                                    isVisible
                                        ? chipColor.opacity(0.3)
                                        : OPSStyle.Colors.cardBorder,
                                    lineWidth: OPSStyle.Layout.Border.standard
                                )
                        )
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                withAnimation(OPSStyle.Animation.fast) {
                                    // Solo: show only this item
                                    if viewModel.visibleItemIds == Set([trend.id]) {
                                        // Already solo'd — restore top 5
                                        let topIds = Set(viewModel.topMovers.prefix(5).map { $0.id })
                                        viewModel.visibleItemIds = topIds.isEmpty
                                            ? Set(viewModel.trendData.prefix(5).map { $0.id })
                                            : topIds
                                    } else {
                                        viewModel.visibleItemIds = Set([trend.id])
                                    }
                                }
                            }
                    )
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("Take at least 2 inventory snapshots to see trends.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func formatQuantity(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
