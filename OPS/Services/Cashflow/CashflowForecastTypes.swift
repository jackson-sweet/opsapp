//
//  CashflowForecastTypes.swift
//  OPS
//
//  Value types consumed and produced by CashflowForecastEngine. Pure-Swift —
//  no SwiftData, no Supabase, no SwiftUI dependencies. Decouples the engine
//  from the data layer so the engine is independently testable.
//

import Foundation

/// Toggleable layers of the projection. Each maps to a class of inflow or outflow.
enum ForecastLayer: String, CaseIterable, Codable {
    case committed   // sent invoices
    case contracted  // approved estimates + milestones
    case pipeline    // weighted opportunities
    case recurring   // recurring expenses (outflows)

    var displayName: String {
        switch self {
        case .committed:  return "COMMITTED"
        case .contracted: return "CONTRACTED"
        case .pipeline:   return "PIPELINE"
        case .recurring:  return "RECURRING"
        }
    }
}

/// Headline state of the forecast. Drives card/chart color treatment + notifications.
enum ForecastState: String, Codable {
    case healthy   // all weeks at or above the low-water threshold
    case lowWater  // at least one week below threshold but all >= 0
    case danger    // at least one week < 0
}

/// One source-entity contribution to a single weekly bucket. Drilling into a
/// week surfaces these rows in the breakdown sheet.
struct ProjectionContributor: Identifiable, Equatable {
    let id: String             // entity id (invoice / milestone / opp / recurring)
    let layer: ForecastLayer
    let label: String          // display label, e.g. "Smith Roof · INV-0042"
    let amount: Double         // positive for inflows, negative for outflows
    let sourceKind: SourceKind
    let probabilityHint: Int?  // 0-100, only set for pipeline contributions

    enum SourceKind: String, Equatable, Codable {
        case invoice
        case milestone
        case estimate
        case opportunity
        case recurring
    }
}

/// One week of the projection. `id` is the zero-based week index from `today`.
struct WeeklyProjection: Identifiable, Equatable {
    let id: Int
    let weekStart: Date
    let weekEnd: Date
    let inflows: Double
    let outflows: Double
    let net: Double
    let balance: Double        // running cumulative from startingBalance
    let contributors: [ProjectionContributor]

    var hasContributors: Bool { !contributors.isEmpty }
}

/// Top-level engine output. Captures every number the UI needs plus metadata
/// for the notification dispatcher (lowestBalance / lowestWeekIndex / state).
struct ForecastResult: Equatable {
    let weeks: [WeeklyProjection]
    let state: ForecastState
    let startingBalance: Double
    let startingBalanceAsOf: Date?
    let lowestWeekIndex: Int
    let lowestBalance: Double
    let endingBalance: Double
    let lowWaterThreshold: Double
    let layersIncluded: Set<ForecastLayer>
    let computedAt: Date
}
