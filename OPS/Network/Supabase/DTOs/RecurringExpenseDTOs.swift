//
//  RecurringExpenseDTOs.swift
//  OPS
//
//  Data Transfer Objects for the recurring_expenses Supabase table.
//

import Foundation

struct RecurringExpenseDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let name: String
    let amount: Double
    let currency: String
    let cadence: String
    let nextDueDate: String
    let endDate: String?
    let categoryId: String?
    let notes: String?
    let createdBy: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId    = "company_id"
        case name, amount, currency, cadence
        case nextDueDate  = "next_due_date"
        case endDate      = "end_date"
        case categoryId   = "category_id"
        case notes
        case createdBy    = "created_by"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
        case deletedAt    = "deleted_at"
    }
}

struct CreateRecurringExpenseDTO: Codable {
    let companyId: String
    let name: String
    let amount: Double
    let currency: String
    let cadence: String
    let nextDueDate: String     // ISO yyyy-MM-dd
    let endDate: String?
    let categoryId: String?
    let notes: String?
    let createdBy: String?

    enum CodingKeys: String, CodingKey {
        case companyId    = "company_id"
        case name, amount, currency, cadence
        case nextDueDate  = "next_due_date"
        case endDate      = "end_date"
        case categoryId   = "category_id"
        case notes
        case createdBy    = "created_by"
    }
}

struct UpdateRecurringExpenseDTO: Codable {
    let name: String?
    let amount: Double?
    let cadence: String?
    let nextDueDate: String?
    let endDate: String?
    let categoryId: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case name, amount, cadence
        case nextDueDate = "next_due_date"
        case endDate     = "end_date"
        case categoryId  = "category_id"
        case notes
    }
}
