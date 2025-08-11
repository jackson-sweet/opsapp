//
//  SubClientDTO.swift
//  OPS
//
//  Data Transfer Object for Sub-Client API responses
//

import Foundation

struct SubClientDTO: Codable {
    let id: String
    let name: String?
    let title: String?
    let emailAddress: String?
    let phoneNumber: PhoneNumberType?  // Can be String or Number from API
    let address: BubbleAddress?
    
    // Custom type to handle phone numbers that can be either String or Number
    enum PhoneNumberType: Codable {
        case string(String)
        case number(Double)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else if let numberValue = try? container.decode(Double.self) {
                self = .number(numberValue)
            } else {
                throw DecodingError.typeMismatch(PhoneNumberType.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Number"))
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .number(let value):
                try container.encode(value)
            }
        }
        
        var stringValue: String? {
            switch self {
            case .string(let value):
                return value
            case .number(let value):
                return String(format: "%.0f", value)
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name = "Name"
        case title = "Title"
        case emailAddress = "Email Address"
        case phoneNumber = "Phone Number"
        case address = "Address"
    }
    
    /// Convert DTO to SubClient model
    func toSubClient() -> SubClient {
        let subClient = SubClient(
            id: id,
            name: name ?? "Unknown",
            title: title,
            email: emailAddress,
            phoneNumber: phoneNumber?.stringValue,  // Convert to string
            address: address?.formattedAddress
        )
        
        // Location is stored in the address string for now
        // Could add lat/lng properties to SubClient if needed later
        
        return subClient
    }
}

// Response wrapper for sub-client operations
struct SubClientResponse: Codable {
    let status: String
    let response: SubClientResponseData
}

struct SubClientResponseData: Codable {
    let subClient: SubClientDTO
    
    enum CodingKeys: String, CodingKey {
        case subClient = "subClient"
    }
}