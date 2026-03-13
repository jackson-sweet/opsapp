//
//  WhatsNewDTOs.swift
//  OPS
//
//  Data Transfer Objects for What's New Supabase tables.
//

import Foundation

struct WhatsNewCategoryDTO: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let sortOrder: Int
    let isActive: Bool
    var items: [WhatsNewItemDTO]

    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case sortOrder = "sort_order"
        case isActive = "is_active"
        case items = "whats_new_items"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        items = try container.decodeIfPresent([WhatsNewItemDTO].self, forKey: .items) ?? []
    }
}

struct WhatsNewItemDTO: Codable, Identifiable {
    let id: String
    let categoryId: String
    let title: String
    let description: String
    let icon: String
    let status: String
    let featureFlagSlug: String?
    let sortOrder: Int
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, description, icon, status
        case categoryId = "category_id"
        case featureFlagSlug = "feature_flag_slug"
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }
}

enum WhatsNewStatus: String, CaseIterable {
    case planned = "planned"
    case inDevelopment = "in_development"
    case inTesting = "in_testing"
    case comingSoon = "coming_soon"
    case shipped = "shipped"
    case completed = "completed"

    var displayName: String {
        switch self {
        case .planned: return "Planned"
        case .inDevelopment: return "In Development"
        case .inTesting: return "In Testing"
        case .comingSoon: return "Coming Soon"
        case .shipped: return "Shipped"
        case .completed: return "Completed"
        }
    }

    var isActionable: Bool {
        switch self {
        case .inTesting: return true
        case .planned, .inDevelopment, .comingSoon: return true
        case .shipped, .completed: return false
        }
    }
}

struct BetaAccessRequestDTO: Codable {
    let userId: String
    let userEmail: String
    let userName: String
    let companyId: String
    let companyName: String
    let whatsNewItemId: String
    let companyPhone: String?
    let companyAddress: String?
    let companySize: String?
    let companyIndustries: [String]?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case userEmail = "user_email"
        case userName = "user_name"
        case companyId = "company_id"
        case companyName = "company_name"
        case whatsNewItemId = "whats_new_item_id"
        case companyPhone = "company_phone"
        case companyAddress = "company_address"
        case companySize = "company_size"
        case companyIndustries = "company_industries"
    }
}
