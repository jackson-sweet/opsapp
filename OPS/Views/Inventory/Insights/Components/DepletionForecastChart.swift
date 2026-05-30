//
//  DepletionForecastChart.swift
//  OPS
//
//  Horizontal bar chart showing estimated days until inventory items deplete.
//  Custom drawn via GeometryReader — does NOT use Swift Charts.
//

import SwiftUI

struct DepletionForecastChart: View {
    let forecasts: [DepletionForecast]
    let onItemTap: (String) -> Void

    /// Maximum items shown before "Show all" appears.
    private let maxVisible = 10

    @State private var showingAll = false

    // MARK: - Computed

    /// Sorted shortest-to-longest (most urgent at top).
    private var sortedForecasts: [DepletionForecast] {
        forecasts.sorted { $0.daysRemaining < $1.daysRemaining }
    }

    private var visibleForecasts: [DepletionForecast] {
        if showingAll { return sortedForecasts }
        return Array(sortedForecasts.prefix(maxVisible))
    }

    /// Longest days value among visible items, used to scale bar widths.
    private var maxDays: Double {
        visibleForecasts.map(\.daysRemaining).max() ?? 1
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Section header
            sectionHeader

            if forecasts.isEmpty {
                emptyState
            } else {
                barsContent
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("DEPLETION FORECAST")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text("Not enough snapshot history to project depletion.")
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, OPSStyle.Layout.spacing4)
    }

    // MARK: - Bars Content

    private var barsContent: some View {
        VStack(spacing: 0) {
            ForEach(visibleForecasts) { forecast in
                Button {
                    onItemTap(forecast.id)
                } label: {
                    forecastRow(forecast)
                }
                .buttonStyle(.plain)
            }

            // "Show all" button when truncated
            if !showingAll && sortedForecasts.count > maxVisible {
                showAllButton
            }
        }
    }

    // MARK: - Forecast Row

    private func forecastRow(_ forecast: DepletionForecast) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            // Item name — left aligned, fixed width proportion
            Text(forecast.name)
                .font(OPSStyle.Typography.caption) // Kosugi 14pt
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            // Horizontal bar + day label
            GeometryReader { geo in
                let availableWidth = geo.size.width
                let proportion = maxDays > 0 ? forecast.daysRemaining / maxDays : 0
                let barWidth = max(4, CGFloat(proportion) * (availableWidth - 36))
                // Reserve ~36pt for the day label to the right of the bar

                HStack(spacing: 6) {
                    // Bar
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .fill(barColor(for: forecast.daysRemaining))
                        .frame(width: barWidth, height: 6)

                    // Day count label
                    Text(dayLabel(for: forecast.daysRemaining))
                        .font(Font.custom("Mohave-Bold", size: 14))
                        .foregroundColor(barColor(for: forecast.daysRemaining))
                        .lineLimit(1)
                        .fixedSize()

                    Spacer(minLength: 0)
                }
                .frame(height: geo.size.height)
            }
        }
        .frame(height: 32)
        .contentShape(Rectangle())
    }

    // MARK: - Show All Button

    private var showAllButton: some View {
        Button {
            withAnimation(OPSStyle.Animation.standard) {
                showingAll = true
            }
        } label: {
            Text("Show all")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, OPSStyle.Layout.spacing2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// Bar color based on urgency thresholds.
    private func barColor(for days: Double) -> Color {
        if days < 14 {
            return OPSStyle.Colors.errorStatus
        } else if days <= 30 {
            return OPSStyle.Colors.warningStatus
        } else {
            return OPSStyle.Colors.secondaryText
        }
    }

    /// Format day label: "12d", "45d", "90d+".
    private func dayLabel(for days: Double) -> String {
        let rounded = Int(days)
        if rounded >= 90 {
            return "90d+"
        }
        return "\(rounded)d"
    }
}
