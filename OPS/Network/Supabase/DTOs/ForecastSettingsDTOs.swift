//
//  ForecastSettingsDTOs.swift
//  OPS
//
//  DTOs for the three forecast_* columns on expense_settings:
//  low-water threshold, current bank balance, balance-as-of timestamp.
//

import Foundation

struct ForecastSettingsDTO: Codable {
    let companyId: String
    let lowWaterThreshold: Double?
    let currentBalance: Double?
    let balanceUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case companyId          = "company_id"
        case lowWaterThreshold  = "forecast_low_water_threshold"
        case currentBalance     = "forecast_current_balance"
        case balanceUpdatedAt   = "forecast_balance_updated_at"
    }
}

struct UpdateForecastSettingsDTO: Codable {
    let lowWaterThreshold: Double?
    let currentBalance: Double?
    let balanceUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case lowWaterThreshold = "forecast_low_water_threshold"
        case currentBalance    = "forecast_current_balance"
        case balanceUpdatedAt  = "forecast_balance_updated_at"
    }
}
