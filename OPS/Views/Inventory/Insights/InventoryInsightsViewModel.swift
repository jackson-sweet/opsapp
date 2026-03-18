//
//  InventoryInsightsViewModel.swift
//  OPS
//
//  ViewModel for inventory insights dashboard.
//  Fetches snapshot history, computes consumption rates, depletion forecasts, and alerts.
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - Data Models

struct HealthSummary {
    let totalItems: Int
    let lowStockCount: Int
    let criticalCount: Int
}

struct ItemTrend: Identifiable {
    let id: String // item ID
    let name: String
    let colorHex: String
    var dataPoints: [TrendPoint]

    struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let quantity: Double
    }
}

struct DepletionForecast: Identifiable {
    let id: String
    let name: String
    let daysRemaining: Double
    let currentQty: Double
    let monthlyRate: Double
    let unitDisplay: String
}

struct ConsumptionRank: Identifiable {
    let id: String
    let name: String
    let unitsPerMonth: Double
    let unitDisplay: String
    let sparklinePoints: [Double] // normalized 0-1 for sparkline shape
    let colorHex: String
}

struct StockAlert: Identifiable {
    let id: String
    let name: String
    let currentQty: Double
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let unitDisplay: String

    enum Severity { case warning, critical }
    var severity: Severity {
        if let crit = criticalThreshold, currentQty <= crit { return .critical }
        return .warning
    }
}

enum InsightsTimeRange: String, CaseIterable {
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "ALL"

    var monthsBack: Int? {
        switch self {
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .oneYear: return 12
        case .all: return nil
        }
    }
}

// MARK: - Chart Color Palette

/// Subset of curated colors optimized for chart line visibility on dark backgrounds.
enum InsightsChartColors {
    static let palette: [String] = [
        "89C3EB", // Clear Sky
        "C79A95", // Fired Clay
        "6F9587", // Verdigris
        "C4A868", // Amber (warning, but good for charts)
        "89729E", // Last Light
        "A79473", // Rawhide
        "48929B", // Oxidized Copper
        "B7788D", // Dusk
        "BBBE9F", // New Growth
        "5D8CAE", // Steel Blue
    ]

    static func color(at index: Int) -> String {
        palette[index % palette.count]
    }
}

// MARK: - ViewModel

@MainActor
class InventoryInsightsViewModel: ObservableObject {
    @Published var healthSummary = HealthSummary(totalItems: 0, lowStockCount: 0, criticalCount: 0)
    @Published var trendData: [ItemTrend] = []
    @Published var depletionForecasts: [DepletionForecast] = []
    @Published var topMovers: [ConsumptionRank] = []
    @Published var criticalAlerts: [StockAlert] = []
    @Published var warningAlerts: [StockAlert] = []
    @Published var isLoading = true
    @Published var selectedTimeRange: InsightsTimeRange = .sixMonths
    @Published var visibleItemIds: Set<String> = []
    @Published var hasEnoughData = false

    private var allItems: [InventoryItem] = []
    private var allSnapshots: [InventorySnapshotReadDTO] = []
    private var snapshotItemsBySnapshot: [String: [InventorySnapshotItemReadDTO]] = [:]
    private let repository: InventoryRepository

    init(companyId: String) {
        self.repository = InventoryRepository(companyId: companyId)
    }

    // MARK: - Load Data

    func loadData(items: [InventoryItem]) async {
        isLoading = true
        allItems = items.filter { $0.deletedAt == nil }

        // Fetch snapshots from Supabase
        do {
            allSnapshots = try await repository.fetchSnapshots()
                .sorted { $0.createdAt < $1.createdAt }

            // Fetch all snapshot items
            for snapshot in allSnapshots {
                let items = try await repository.fetchSnapshotItems(snapshotId: snapshot.id)
                snapshotItemsBySnapshot[snapshot.id] = items
            }
        } catch {
            print("[INSIGHTS] Failed to fetch snapshots: \(error)")
        }

        hasEnoughData = allSnapshots.count >= 2

        // Compute everything
        computeHealthSummary()
        computeTrends()
        computeDepletionForecasts()
        computeTopMovers()
        computeAlerts()

        // Default visible items = top 5 by consumption
        let topIds = Set(topMovers.prefix(5).map { $0.id })
        visibleItemIds = topIds.isEmpty ? Set(allItems.prefix(5).map { $0.id }) : topIds

        isLoading = false
    }

    // MARK: - Health Summary

    private func computeHealthSummary() {
        let total = allItems.count
        var lowCount = 0
        var critCount = 0

        for item in allItems {
            let (warning, critical) = item.effectiveThresholds()
            if let crit = critical, item.quantity <= crit {
                critCount += 1
            } else if let warn = warning, item.quantity <= warn {
                lowCount += 1
            }
        }

        healthSummary = HealthSummary(totalItems: total, lowStockCount: lowCount, criticalCount: critCount)
    }

    // MARK: - Trends

    private func computeTrends() {
        // Build time series per item from snapshots
        var itemTimeSeries: [String: [(date: Date, qty: Double)]] = [:]
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for snapshot in filteredSnapshots {
            guard let snapshotDate = dateFormatter.date(from: snapshot.createdAt) else { continue }
            let items = snapshotItemsBySnapshot[snapshot.id] ?? []

            for snapshotItem in items {
                guard let originalId = snapshotItem.originalItemId else { continue }
                itemTimeSeries[originalId, default: []].append((date: snapshotDate, qty: snapshotItem.quantity))
            }
        }

        // Also add current quantities as the latest data point
        let now = Date()
        for item in allItems {
            itemTimeSeries[item.id, default: []].append((date: now, qty: item.quantity))
        }

        // Convert to ItemTrend objects
        trendData = allItems.enumerated().compactMap { index, item in
            guard let series = itemTimeSeries[item.id], series.count >= 2 else { return nil }
            let sorted = series.sorted { $0.date < $1.date }

            return ItemTrend(
                id: item.id,
                name: item.name,
                colorHex: InsightsChartColors.color(at: index),
                dataPoints: sorted.map { ItemTrend.TrendPoint(date: $0.date, quantity: $0.qty) }
            )
        }
    }

    // MARK: - Depletion Forecasts

    private func computeDepletionForecasts() {
        var forecasts: [DepletionForecast] = []

        for item in allItems {
            guard item.quantity > 0 else { continue }

            // Find earliest and latest snapshot for this item
            let itemSnapPoints = allSnapshotPointsForItem(item.id)
            guard itemSnapPoints.count >= 2 else { continue }

            let earliest = itemSnapPoints.first!
            let latest = itemSnapPoints.last!
            let daysBetween = max(1, Calendar.current.dateComponents([.day], from: earliest.date, to: latest.date).day ?? 30)
            let monthsBetween = max(1, daysBetween / 30)

            let consumed = earliest.qty - item.quantity
            guard consumed > 0 else { continue } // Stock increasing, skip

            let monthlyRate = consumed / Double(max(1, monthsBetween))
            let daysRemaining = (item.quantity / monthlyRate) * 30

            forecasts.append(DepletionForecast(
                id: item.id,
                name: item.name,
                daysRemaining: min(daysRemaining, 90), // Cap at 90
                currentQty: item.quantity,
                monthlyRate: monthlyRate,
                unitDisplay: item.unit?.display ?? "ea"
            ))
        }

        depletionForecasts = forecasts.sorted { $0.daysRemaining < $1.daysRemaining }
    }

    // MARK: - Top Movers

    private func computeTopMovers() {
        var movers: [ConsumptionRank] = []

        for (index, item) in allItems.enumerated() {
            let points = allSnapshotPointsForItem(item.id)
            guard points.count >= 2 else { continue }

            let earliest = points.first!
            let consumed = earliest.qty - item.quantity
            guard consumed > 0 else { continue }

            let daysBetween = max(1, Calendar.current.dateComponents([.day], from: earliest.date, to: Date()).day ?? 30)
            let monthlyRate = (consumed / Double(daysBetween)) * 30

            // Build sparkline points (normalized 0-1)
            let allQtys = points.map { $0.qty } + [item.quantity]
            let minQ = allQtys.min() ?? 0
            let maxQ = allQtys.max() ?? 1
            let range = max(maxQ - minQ, 1)
            let sparkline = allQtys.map { ($0 - minQ) / range }

            movers.append(ConsumptionRank(
                id: item.id,
                name: item.name,
                unitsPerMonth: monthlyRate,
                unitDisplay: item.unit?.display ?? "ea",
                sparklinePoints: sparkline,
                colorHex: InsightsChartColors.color(at: index)
            ))
        }

        topMovers = Array(movers.sorted { $0.unitsPerMonth > $1.unitsPerMonth }.prefix(8))
    }

    // MARK: - Alerts

    private func computeAlerts() {
        var critical: [StockAlert] = []
        var warning: [StockAlert] = []

        for item in allItems {
            let (warn, crit) = item.effectiveThresholds()
            let unitDisplay = item.unit?.display ?? "ea"

            if let c = crit, item.quantity <= c {
                critical.append(StockAlert(
                    id: item.id, name: item.name,
                    currentQty: item.quantity,
                    warningThreshold: warn, criticalThreshold: c,
                    unitDisplay: unitDisplay
                ))
            } else if let w = warn, item.quantity <= w {
                warning.append(StockAlert(
                    id: item.id, name: item.name,
                    currentQty: item.quantity,
                    warningThreshold: w, criticalThreshold: crit,
                    unitDisplay: unitDisplay
                ))
            }
        }

        criticalAlerts = critical.sorted { $0.currentQty < $1.currentQty }
        warningAlerts = warning.sorted { $0.currentQty < $1.currentQty }
    }

    // MARK: - Threshold Update

    func updateThreshold(itemId: String, warning: Double?, critical: Double?) async {
        // Find and update local item
        guard let item = allItems.first(where: { $0.id == itemId }) else { return }
        item.warningThreshold = warning
        item.criticalThreshold = critical

        // Push to Supabase via UpdateInventoryItemDTO
        do {
            let dto = UpdateInventoryItemDTO(
                warningThreshold: warning,
                criticalThreshold: critical
            )
            _ = try await repository.updateItem(itemId, fields: dto)
        } catch {
            print("[INSIGHTS] Failed to update threshold: \(error)")
        }

        // Recompute alerts
        computeAlerts()
        computeHealthSummary()
    }

    // MARK: - Helpers

    private var filteredSnapshots: [InventorySnapshotReadDTO] {
        guard let monthsBack = selectedTimeRange.monthsBack else { return allSnapshots }
        let cutoff = Calendar.current.date(byAdding: .month, value: -monthsBack, to: Date()) ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return allSnapshots.filter {
            guard let d = formatter.date(from: $0.createdAt) else { return false }
            return d >= cutoff
        }
    }

    private func allSnapshotPointsForItem(_ itemId: String) -> [(date: Date, qty: Double)] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var points: [(date: Date, qty: Double)] = []

        for snapshot in allSnapshots {
            guard let date = formatter.date(from: snapshot.createdAt) else { continue }
            if let items = snapshotItemsBySnapshot[snapshot.id],
               let match = items.first(where: { $0.originalItemId == itemId }) {
                points.append((date: date, qty: match.quantity))
            }
        }
        return points.sorted { $0.date < $1.date }
    }
}
