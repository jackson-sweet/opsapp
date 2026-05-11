//
//  TaskTemplateDTOs.swift
//  OPS
//
//  DTOs for the Supabase `task_templates` table. The wire shape mirrors
//  the iOS TaskTemplate @Model. The `task_type_id` column is text (legacy
//  bubble-id mirror) and `task_type_ref` is the proper uuid FK. New writes
//  populate both with the same uuid string so reads from either path resolve
//  to the same parent TaskType.
//

import Foundation

struct TaskTemplateDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let taskTypeId: String
    let taskTypeRef: String?
    let title: String
    let description: String?
    let estimatedHours: Double?
    let displayOrder: Int
    let defaultTeamMemberIds: [String]?
    let createdAt: String
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId             = "company_id"
        case taskTypeId            = "task_type_id"
        case taskTypeRef           = "task_type_ref"
        case title
        case description
        case estimatedHours        = "estimated_hours"
        case displayOrder          = "display_order"
        case defaultTeamMemberIds  = "default_team_member_ids"
        case createdAt             = "created_at"
        case updatedAt             = "updated_at"
        case deletedAt             = "deleted_at"
    }

    func toModel() -> TaskTemplate {
        let template = TaskTemplate(
            id: id,
            companyId: companyId,
            taskTypeId: taskTypeId,
            taskTypeRef: taskTypeRef ?? taskTypeId,
            title: title,
            templateDescription: description,
            estimatedHours: estimatedHours,
            displayOrder: displayOrder,
            defaultTeamMemberIds: defaultTeamMemberIds ?? [],
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        template.updatedAt = updatedAt.flatMap { SupabaseDate.parse($0) }
        template.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return template
    }
}

struct CreateTaskTemplateDTO: Codable {
    let id: String
    let companyId: String
    let taskTypeId: String
    let taskTypeRef: String?
    let title: String
    let description: String?
    let estimatedHours: Double?
    let displayOrder: Int
    let defaultTeamMemberIds: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId             = "company_id"
        case taskTypeId            = "task_type_id"
        case taskTypeRef           = "task_type_ref"
        case title
        case description
        case estimatedHours        = "estimated_hours"
        case displayOrder          = "display_order"
        case defaultTeamMemberIds  = "default_team_member_ids"
    }
}

struct UpdateTaskTemplateDTO: Codable {
    var title: String?
    var description: String?
    var estimatedHours: Double?
    var displayOrder: Int?
    var defaultTeamMemberIds: [String]?
    var taskTypeId: String?
    var taskTypeRef: String?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case estimatedHours        = "estimated_hours"
        case displayOrder          = "display_order"
        case defaultTeamMemberIds  = "default_team_member_ids"
        case taskTypeId            = "task_type_id"
        case taskTypeRef           = "task_type_ref"
    }
}
