//
//  WhatsNewRepository.swift
//  OPS
//
//  Repository for What's New operations via Supabase.
//

import Foundation
import Supabase

@MainActor
class WhatsNewRepository {
    private let cacheKey = "whatsNewCategoriesCache"

    func fetchCategories() async throws -> [WhatsNewCategoryDTO] {
        let response: [WhatsNewCategoryDTO] = try await SupabaseService.shared.client
            .from("whats_new_categories")
            .select("*, whats_new_items(*)")
            .eq("is_active", value: true)
            .order("sort_order", ascending: true)
            .execute()
            .value

        // Sort items within each category and filter active only
        let sorted = response.map { cat -> WhatsNewCategoryDTO in
            var mutable = cat
            mutable.items = cat.items
                .filter { $0.isActive }
                .sorted { $0.sortOrder < $1.sortOrder }
            return mutable
        }

        // Cache for offline
        if let data = try? JSONEncoder().encode(sorted) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }

        return sorted
    }

    func getCachedCategories() -> [WhatsNewCategoryDTO]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let categories = try? JSONDecoder().decode([WhatsNewCategoryDTO].self, from: data) else {
            return nil
        }
        return categories
    }

    func submitBetaAccessRequest(_ dto: BetaAccessRequestDTO) async throws {
        let baseURL = AppConfiguration.API.webBaseURL
        let url = URL(string: "\(baseURL)/api/whats-new/request-access")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(dto)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "WhatsNew", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode == 409 {
            // Already requested — not an error
            return
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "WhatsNew", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Request failed: \(body)"])
        }
    }

    func fetchUserRequests(userId: String) async throws -> [String] {
        struct RequestRow: Decodable {
            let whats_new_item_id: String
        }

        let rows: [RequestRow] = try await SupabaseService.shared.client
            .from("beta_access_requests")
            .select("whats_new_item_id")
            .eq("user_id", value: userId)
            .execute()
            .value

        return rows.map { $0.whats_new_item_id }
    }
}
