//
//  CoreEntityDTOs.swift
//  OPS
//
//  Codable DTOs matching the Supabase core entity tables.
//  Column names are snake_case to match Supabase JSON keys exactly.
//
//  Table reference: supabase/migrations/EXECUTED/004_core_entities.sql
//

import Foundation

// MARK: - Company DTO

struct SupabaseCompanyDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let name: String
    let description: String?
    let website: String?
    let phone: String?
    let email: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let logoUrl: String?
    let defaultProjectColor: String?
    let adminIds: [String]?
    let seatedEmployeeIds: [String]?
    let maxSeats: Int?
    let subscriptionStatus: String?
    let subscriptionPlan: String?
    let subscriptionEnd: String?
    let subscriptionPeriod: String?
    let trialStartDate: String?
    let trialEndDate: String?
    let hasPrioritySupport: Bool?
    let stripeCustomerId: String?
    let createdAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, website, phone, email, address, latitude, longitude
        case bubbleId             = "bubble_id"
        case logoUrl              = "logo_url"
        case defaultProjectColor  = "default_project_color"
        case adminIds             = "admin_ids"
        case seatedEmployeeIds    = "seated_employee_ids"
        case maxSeats             = "max_seats"
        case subscriptionStatus   = "subscription_status"
        case subscriptionPlan     = "subscription_plan"
        case subscriptionEnd      = "subscription_end"
        case subscriptionPeriod   = "subscription_period"
        case trialStartDate       = "trial_start_date"
        case trialEndDate         = "trial_end_date"
        case hasPrioritySupport   = "has_priority_support"
        case stripeCustomerId     = "stripe_customer_id"
        case createdAt            = "created_at"
        case deletedAt            = "deleted_at"
    }
}

// MARK: - User DTO

struct SupabaseUserDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let companyId: String?
    let firstName: String
    let lastName: String
    let email: String?
    let phone: String?
    let homeAddress: String?
    let profileImageUrl: String?
    let userColor: String?
    let role: String?
    let userType: String?
    let isCompanyAdmin: Bool?
    let hasCompletedOnboarding: Bool?
    let hasCompletedTutorial: Bool?
    let devPermission: Bool?
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    let isActive: Bool?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, phone, role, latitude, longitude
        case bubbleId              = "bubble_id"
        case companyId             = "company_id"
        case firstName             = "first_name"
        case lastName              = "last_name"
        case homeAddress           = "home_address"
        case profileImageUrl       = "profile_image_url"
        case userColor             = "user_color"
        case userType              = "user_type"
        case isCompanyAdmin        = "is_company_admin"
        case hasCompletedOnboarding = "has_completed_onboarding"
        case hasCompletedTutorial  = "has_completed_tutorial"
        case devPermission         = "dev_permission"
        case locationName          = "location_name"
        case isActive              = "is_active"
        case deletedAt             = "deleted_at"
    }
}

// MARK: - Client DTO
// Note: Supabase column is `phone_number` (not `phone`) — matches iOS Client.phoneNumber.

struct SupabaseClientDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let companyId: String
    let name: String
    let email: String?
    let phoneNumber: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let notes: String?
    let profileImageUrl: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, address, latitude, longitude, notes
        case bubbleId        = "bubble_id"
        case companyId       = "company_id"
        case phoneNumber     = "phone_number"
        case profileImageUrl = "profile_image_url"
        case deletedAt       = "deleted_at"
    }
}

// MARK: - SubClient DTO
// Note: Supabase column is `phone_number` (not `phone`) — matches iOS SubClient.phoneNumber.

struct SupabaseSubClientDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let clientId: String
    let companyId: String
    let name: String
    let title: String?
    let email: String?
    let phoneNumber: String?
    let address: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, title, email, address
        case bubbleId    = "bubble_id"
        case clientId    = "client_id"
        case companyId   = "company_id"
        case phoneNumber = "phone_number"
        case deletedAt   = "deleted_at"
    }
}

// MARK: - TaskType DTO
// Note: Supabase table is `task_types_v2`. Column is `display` (not `name`).

struct SupabaseTaskTypeDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let companyId: String
    let display: String
    let color: String
    let icon: String?
    let isDefault: Bool?
    let displayOrder: Int?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, display, color, icon
        case bubbleId      = "bubble_id"
        case companyId     = "company_id"
        case isDefault     = "is_default"
        case displayOrder  = "display_order"
        case deletedAt     = "deleted_at"
    }
}

// MARK: - Project DTO

struct SupabaseProjectDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let companyId: String
    let clientId: String?
    let opportunityId: String?
    let title: String
    let status: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let startDate: String?
    let endDate: String?
    let duration: Int?
    let notes: String?
    let description: String?
    let allDay: Bool?
    let teamMemberIds: [String]?
    let projectImages: [String]?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status, address, latitude, longitude, notes, description, duration
        case bubbleId       = "bubble_id"
        case companyId      = "company_id"
        case clientId       = "client_id"
        case opportunityId  = "opportunity_id"
        case startDate      = "start_date"
        case endDate        = "end_date"
        case allDay         = "all_day"
        case teamMemberIds  = "team_member_ids"
        case projectImages  = "project_images"
        case deletedAt      = "deleted_at"
    }
}

// MARK: - ProjectTask DTO
// Note: Supabase uses `task_notes` (not `notes`), `custom_title` (not `title`),
// `task_color`, `display_order`, `calendar_event_id`. There are no
// `scheduled_date` / `scheduled_end_date` / `all_day` columns in the DB —
// scheduling is managed via the linked CalendarEvent.

struct SupabaseProjectTaskDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let companyId: String
    let projectId: String
    let taskTypeId: String?
    let calendarEventId: String?
    let customTitle: String?
    let taskNotes: String?
    let status: String
    let taskColor: String?
    let displayOrder: Int?
    let teamMemberIds: [String]?
    let sourceLineItemId: String?
    let sourceEstimateId: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case bubbleId         = "bubble_id"
        case companyId        = "company_id"
        case projectId        = "project_id"
        case taskTypeId       = "task_type_id"
        case calendarEventId  = "calendar_event_id"
        case customTitle      = "custom_title"
        case taskNotes        = "task_notes"
        case taskColor        = "task_color"
        case displayOrder     = "display_order"
        case teamMemberIds    = "team_member_ids"
        case sourceLineItemId = "source_line_item_id"
        case sourceEstimateId = "source_estimate_id"
        case deletedAt        = "deleted_at"
    }
}

// MARK: - CalendarEvent DTO
// Note: Supabase `calendar_events` table has `title` (NOT NULL), `color`, `duration`,
// `team_member_ids`. There is no `task_id`, `all_day`, or `event_type` column in the DB —
// those are iOS-only model fields. `task_id` linkage is resolved via project_tasks.calendar_event_id.

struct SupabaseCalendarEventDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let companyId: String
    let projectId: String?
    let title: String
    let color: String?
    let startDate: String?
    let endDate: String?
    let duration: Int?
    let teamMemberIds: [String]?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, color, duration
        case bubbleId      = "bubble_id"
        case companyId     = "company_id"
        case projectId     = "project_id"
        case startDate     = "start_date"
        case endDate       = "end_date"
        case teamMemberIds = "team_member_ids"
        case deletedAt     = "deleted_at"
    }
}

// MARK: - OpsContact DTO

struct SupabaseOpsContactDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let name: String
    let email: String
    let phone: String?
    let display: String?
    let role: String

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, display, role
        case bubbleId = "bubble_id"
    }
}
