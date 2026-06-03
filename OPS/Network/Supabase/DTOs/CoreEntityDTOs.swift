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
    let seatGraceStartDate: String?
    let hasPrioritySupport: Bool?
    let stripeCustomerId: String?
    let companyCode: String?
    let accountHolderId: String?
    let preciseSchedulingEnabled: Bool?
    let skipWeekendsInAutoSchedule: Bool?
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
        case seatGraceStartDate   = "seat_grace_start_date"
        case hasPrioritySupport   = "has_priority_support"
        case stripeCustomerId     = "stripe_customer_id"
        case companyCode          = "company_code"
        case accountHolderId      = "account_holder_id"
        case preciseSchedulingEnabled    = "precise_scheduling_enabled"
        case skipWeekendsInAutoSchedule  = "skip_weekends_in_auto_schedule"
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
    let onboardingCompleted: [String: Bool]?
    let hasCompletedTutorial: Bool?
    let devPermission: Bool?
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    let isActive: Bool?
    let specialPermissions: [String]?
    let emergencyContactName: String?
    let emergencyContactPhone: String?
    let emergencyContactRelationship: String?
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
        case onboardingCompleted    = "onboarding_completed"
        case hasCompletedTutorial  = "has_completed_tutorial"
        case devPermission         = "dev_permission"
        case locationName          = "location_name"
        case isActive              = "is_active"
        case specialPermissions    = "special_permissions"
        case emergencyContactName         = "emergency_contact_name"
        case emergencyContactPhone        = "emergency_contact_phone"
        case emergencyContactRelationship = "emergency_contact_relationship"
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
// Note: Supabase table is `task_types`. Column is `display` (not `name`).

struct SupabaseTaskTypeDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let companyId: String
    let display: String
    let color: String
    let icon: String?
    let isDefault: Bool?
    let displayOrder: Int?
    let dependencies: [TaskTypeDependency]?
    let defaultTeamMemberIds: [String]?
    let defaultDuration: Int?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, display, color, icon, dependencies
        case bubbleId               = "bubble_id"
        case companyId              = "company_id"
        case isDefault              = "is_default"
        case displayOrder           = "display_order"
        case defaultTeamMemberIds   = "default_team_member_ids"
        case defaultDuration        = "default_duration"
        case deletedAt              = "deleted_at"
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
    let completedAt: String?
    let deletedAt: String?
    let createdAt: String?
    let createdBy: String?
    /// Project-level marker used by Deck Builder vinyl ordering. The server
    /// defaults to `not_ordered`; nullable here so older schemas still decode
    /// during phased rollout.
    var vinylOrderStatus: String? = nil
    var vinylOrderedAt: String? = nil
    var vinylOrderedBy: String? = nil
    /// Server-maintained `projects.updated_at` (bug 70a4d9fd). Read-only
    /// from iOS — Supabase auto-bumps it on every write, so outbound
    /// callers don't pass it. Declared as `var` with a default so the
    /// synthesized memberwise init keeps its existing arity.
    var updatedAt: String? = nil
    /// Company-wide manual project priority. Lower = higher priority.
    /// nil = unranked. Fractional indexing (FractionalRank). Synced to
    /// Supabase `projects.priority_rank`. Added 2026-06-03.
    var priorityRank: Double? = nil

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
        case completedAt    = "completed_at"
        case deletedAt      = "deleted_at"
        case createdAt      = "created_at"
        case createdBy      = "created_by"
        case vinylOrderStatus = "vinyl_order_status"
        case vinylOrderedAt = "vinyl_ordered_at"
        case vinylOrderedBy = "vinyl_ordered_by"
        case updatedAt      = "updated_at"
        case priorityRank   = "priority_rank"
    }
}

// MARK: - ProjectTask DTO

struct SupabaseProjectTaskDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let companyId: String
    let projectId: String
    let taskTypeId: String?
    let customTitle: String?
    let taskNotes: String?
    let status: String
    let taskColor: String?
    let displayOrder: Int?
    let priorityRank: Double?
    let teamMemberIds: [String]?
    let sourceLineItemId: String?
    let sourceEstimateId: String?
    let startDate: String?
    let endDate: String?
    let duration: Int?
    let dependencyOverrides: [TaskTypeDependency]?
    let startTime: String?   // "HH:mm" format
    let endTime: String?     // "HH:mm" format
    let pairedFromTaskId: String?
    let scheduleLocked: Bool?
    let deletedAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, duration
        case bubbleId             = "bubble_id"
        case companyId            = "company_id"
        case projectId            = "project_id"
        case taskTypeId           = "task_type_id"
        case customTitle          = "custom_title"
        case taskNotes            = "task_notes"
        case taskColor            = "task_color"
        case displayOrder         = "display_order"
        case priorityRank         = "priority_rank"
        case teamMemberIds        = "team_member_ids"
        case sourceLineItemId     = "source_line_item_id"
        case sourceEstimateId     = "source_estimate_id"
        case startDate            = "start_date"
        case endDate              = "end_date"
        case dependencyOverrides  = "dependency_overrides"
        case startTime            = "start_time"
        case endTime              = "end_time"
        case pairedFromTaskId     = "paired_from_task_id"
        case scheduleLocked       = "schedule_locked"
        case deletedAt            = "deleted_at"
        case createdAt            = "created_at"
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
