//
//  CompanyEndpoints.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import Foundation

/// Extension for company-related API endpoints
extension APIService {
    
    /// Fetch a company by ID
    /// - Parameter id: The company ID
    /// - Returns: Company DTO
    func fetchCompany(id: String) async throws -> CompanyDTO {
        return try await fetchBubbleObject(
            objectType: BubbleFields.Types.company,
            id: id
        )
    }
    
    /// Fetch all companies
    /// - Returns: Array of company DTOs
    func fetchCompanies() async throws -> [CompanyDTO] {
        return try await fetchBubbleObjects(
            objectType: BubbleFields.Types.company,
            limit: 100
        )
    }
    
    /// Fetch projects for a specific company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of project DTOs
    func fetchCompanyProjects(companyId: String) async throws -> [ProjectDTO] {
        
        // Create constraint for company using array format
        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.Project.company,
                "constraint_type": "equals",
                "value": companyId
            ]
        ]
        
        return try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.project,
            constraints: constraints,
            sortField: BubbleFields.Project.startDate
        )
    }
    
    /// Update company information
    /// - Parameters:
    ///   - id: The company ID
    ///   - data: Dictionary of company properties to update
    func updateCompany(id: String, data: [String: Any]) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: data)

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.company)/\(id)",
            method: "PATCH",
            body: bodyData
        )
    }

    /// Link a task type to a company
    /// - Parameters:
    ///   - companyId: The company ID
    ///   - taskTypeId: The task type ID to link
    func linkTaskTypeToCompany(companyId: String, taskTypeId: String) async throws {
        let company = try await fetchCompany(id: companyId)
        var taskTypeIds = company.taskTypes?.compactMap { $0.stringValue } ?? []

        if !taskTypeIds.contains(taskTypeId) {
            taskTypeIds.append(taskTypeId)
        }

        let updateData: [String: Any] = ["Task Types": taskTypeIds]
        try await updateCompany(id: companyId, data: updateData)
    }
}
