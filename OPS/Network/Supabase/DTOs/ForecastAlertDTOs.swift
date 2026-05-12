//
//  ForecastAlertDTOs.swift
//  OPS
//
//  DTOs for the forecast_alerts anti-spam ledger. One row per company.
//  Re-fire rules: 24h gap + 10% worse min balance, OR cleared-then-redipped.
//

import Foundation

struct ForecastAlertDTO: Codable {
    let companyId: String
    let lastDipNotifiedAt: String?
    let lastDipMinBalance: Double?
    let lastDipMinWeekStart: String?
    let lastClearedAt: String?
    let dismissedUntilBalance: Double?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case companyId              = "company_id"
        case lastDipNotifiedAt      = "last_dip_notified_at"
        case lastDipMinBalance      = "last_dip_min_balance"
        case lastDipMinWeekStart    = "last_dip_min_week_start"
        case lastClearedAt          = "last_cleared_at"
        case dismissedUntilBalance  = "dismissed_until_balance"
        case updatedAt              = "updated_at"
    }
}

struct UpsertForecastAlertDTO: Codable {
    let companyId: String
    let lastDipNotifiedAt: String?
    let lastDipMinBalance: Double?
    let lastDipMinWeekStart: String?
    let lastClearedAt: String?
    let dismissedUntilBalance: Double?

    enum CodingKeys: String, CodingKey {
        case companyId              = "company_id"
        case lastDipNotifiedAt      = "last_dip_notified_at"
        case lastDipMinBalance      = "last_dip_min_balance"
        case lastDipMinWeekStart    = "last_dip_min_week_start"
        case lastClearedAt          = "last_cleared_at"
        case dismissedUntilBalance  = "dismissed_until_balance"
    }
}
