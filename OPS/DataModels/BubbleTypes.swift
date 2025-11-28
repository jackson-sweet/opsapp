
//
//  BubbleTypes.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-28.
//

import Foundation

/// Bubble's geographic address structure
struct BubbleAddress: Codable {
    let formattedAddress: String
    let lat: Double?
    let lng: Double?
    
    enum CodingKeys: String, CodingKey {
        case formattedAddress = "address"
        case lat, lng
    }
}

/// Bubble's reference type - handles both string and object references
struct BubbleReference: Codable {
    let value: ReferenceValue

    /// Initialize with a string value directly
    init(stringValue: String) {
        self.value = .string(stringValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode as string first (direct ID reference)
        if let stringValue = try? container.decode(String.self) {
            value = .string(stringValue)
        }
        // Then try to decode as object reference
        else if let objectValue = try? container.decode(ObjectReference.self) {
            value = .object(objectValue)
        }
        // Fallback - treat as empty string
        else {
            value = .string("")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .string(let stringValue):
            try container.encode(stringValue)
        case .object(let objectValue):
            try container.encode(objectValue)
        }
    }
    
    struct ObjectReference: Codable {
        let uniqueID: String
        let text: String?
        
        enum CodingKeys: String, CodingKey {
            case uniqueID = "unique_id"
            case text
        }
    }
    
    enum ReferenceValue {
        case string(String)
        case object(ObjectReference)
    }
    
    var stringValue: String {
        switch value {
        case .string(let id):
            return id
        case .object(let obj):
            return obj.uniqueID
        }
    }
}

// Add string conversion for BubbleReference
extension BubbleReference: ExpressibleByStringLiteral {
    typealias StringLiteralType = String
    
    init(stringLiteral value: String) {
        self.value = .string(value)
    }
}
