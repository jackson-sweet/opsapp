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
        return try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.company)/\(id)"
        )
    }
    
    /// Fetch all companies
    /// - Returns: Array of company DTOs
    func fetchCompanies() async throws -> [CompanyDTO] {
        return try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.company)",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0")
            ]
        )
    }
    
    /// Fetch projects for a specific company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of project DTOs
    func fetchCompanyProjects(companyId: String) async throws -> [ProjectDTO] {
        // Create constraint for projects belonging to this company
        let companyConstraint: [String: Any] = [
            "key": BubbleFields.Project.company,
            "constraint_type": "equals",
            "value": companyId
        ]
        
        // Convert to JSON string
        guard let jsonData = try? JSONSerialization.data(withJSONObject: companyConstraint),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw APIError.invalidURL
        }
        
        return try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0"),
                URLQueryItem(name: "constraints", value: jsonString)
            ]
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
}
