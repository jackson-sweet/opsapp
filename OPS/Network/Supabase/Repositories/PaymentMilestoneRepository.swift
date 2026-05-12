import Foundation
import Supabase

class PaymentMilestoneRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    /// Fetch all milestones for non-deleted estimates in the company.
    func fetchAll() async throws -> [PaymentMilestoneDTO] {
        // payment_milestones has no company_id — must filter through estimates.
        // Use an inner-join via select with embedded filter on estimates.company_id.
        try await client
            .from("payment_milestones")
            .select("*, estimates!inner(company_id, deleted_at)")
            .eq("estimates.company_id", value: companyId)
            .is("estimates.deleted_at", value: nil)
            .execute()
            .value
    }

    func fetchForEstimate(_ estimateId: String) async throws -> [PaymentMilestoneDTO] {
        try await client
            .from("payment_milestones")
            .select("*")
            .eq("estimate_id", value: estimateId)
            .order("sort_order", ascending: true)
            .execute()
            .value
    }
}
