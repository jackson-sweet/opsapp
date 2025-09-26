//
//  OpsContactDTO.swift
//  OPS
//
//  DTO for OPS support contacts from Bubble
//

import Foundation

struct OpsContactDTO: Codable {
    let id: String
    let email: String?
    let name: String?
    let phone: String?
    let display: String?
    let displayValue: String? // Alternative field name Bubble might use
    
    // Bubble sends option sets with these field names
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email = "Email"
        case name = "Name"
        case phone = "Phone"
        case display = "Display"
        case displayValue = "display"
    }
}

// MARK: - Response wrapper
struct OpsContactsResponse: Codable {
    let status: String
    let response: OpsContactsData
}

struct OpsContactsData: Codable {
    let results: [OpsContactDTO]
    let count: Int
    let remaining: Int
}

// MARK: - Conversion to Model
extension OpsContactDTO {
    func toOpsContact() -> OpsContact {
        return OpsContact(
            id: id,
            email: email ?? "",
            name: name ?? "",
            phone: phone ?? "",
            display: display ?? displayValue ?? "",
            role: display ?? displayValue ?? ""
        )
    }
}