//
//  ForecastAlertRepository.swift
//  OPS
//
//  Reads/upserts the per-company forecast_alerts ledger that drives
//  anti-spam logic for the persistent forecast_dip notification.
//

import Foundation
import Supabase

class ForecastAlertRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    /// Returns nil if no row yet exists for this company.
    func fetch() async throws -> ForecastAlertDTO? {
        do {
            let dto: ForecastAlertDTO = try await client
                .from("forecast_alerts")
                .select("*")
                .eq("company_id", value: companyId)
                .single()
                .execute()
                .value
            return dto
        } catch {
            // .single() throws when no row matches — treat as nil for fetch semantics.
            return nil
        }
    }

    func upsert(_ dto: UpsertForecastAlertDTO) async throws -> ForecastAlertDTO {
        try await client
            .from("forecast_alerts")
            .upsert(dto, onConflict: "company_id")
            .select()
            .single()
            .execute()
            .value
    }
}
