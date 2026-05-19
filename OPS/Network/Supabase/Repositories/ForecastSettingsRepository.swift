//
//  ForecastSettingsRepository.swift
//  OPS
//
//  Reads/writes the three forecast_* columns on expense_settings.
//  One row per company (existing expense_settings row).
//

import Foundation
import Supabase

class ForecastSettingsRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetch() async throws -> ForecastSettingsDTO {
        try await client
            .from("expense_settings")
            .select("company_id, forecast_low_water_threshold, forecast_current_balance, forecast_balance_updated_at")
            .eq("company_id", value: companyId)
            .single()
            .execute()
            .value
    }

    func update(_ fields: UpdateForecastSettingsDTO) async throws -> ForecastSettingsDTO {
        try await client
            .from("expense_settings")
            .update(fields)
            .eq("company_id", value: companyId)
            .select("company_id, forecast_low_water_threshold, forecast_current_balance, forecast_balance_updated_at")
            .single()
            .execute()
            .value
    }
}
