//
//  ClientLeadAutocreate.swift
//  OPS
//

import Foundation

enum ClientLeadAutocreate {
    /// Live `opportunities.source_check` permits:
    /// referral, website, email, phone, walk_in, social_media,
    /// repeat_client, voice_log, other. Client-created leads use `other`
    /// until the database contract adds a dedicated source.
    static let schemaAllowedSource = "other"
    /// Live `opportunities_priority_check` permits low, medium, high.
    /// Client-created leads default to medium.
    static let schemaAllowedPriority = "medium"

    static func makeOpportunityDTO(for client: Client, companyId: String) -> CreateOpportunityDTO? {
        let trimmedName = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        return CreateOpportunityDTO(
            companyId: companyId,
            title: "\(trimmedName) — lead",
            contactName: trimmedName,
            contactEmail: sanitizedOptional(client.email),
            contactPhone: sanitizedOptional(client.phoneNumber),
            description: sanitizedOptional(client.notes),
            address: sanitizedOptional(client.address),
            estimatedValue: nil,
            source: schemaAllowedSource,
            priority: schemaAllowedPriority,
            quoteDeliveryMethod: nil,
            clientId: client.id
        )
    }

    private static func sanitizedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum ClientLeadAutocreateError: LocalizedError {
    case missingClientName
    case creationFailed

    var errorDescription: String? {
        switch self {
        case .missingClientName:
            return "Client saved. Pipeline lead needs a client name."
        case .creationFailed:
            return "Client saved. Pipeline lead did not create."
        }
    }
}
