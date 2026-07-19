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

    /// `opportunities` has a live unique constraint on
    /// `(company_id, source_thread_key)`. A deterministic key makes the
    /// automatic child write idempotent even when the first response times out
    /// after the database committed it.
    static func sourceThreadKey(forClientId clientId: String) -> String {
        "client-autocreate:\(clientId.lowercased())"
    }

    static func makeOpportunityDTO(for client: Client, companyId: String) -> CreateOpportunityDTO? {
        makeOpportunityDTO(
            companyId: companyId,
            clientId: client.id,
            name: client.name,
            email: client.email,
            phoneNumber: client.phoneNumber,
            address: client.address,
            notes: client.notes
        )
    }

    static func makeOpportunityDTO(
        for request: PendingClientLeadAutocreate
    ) -> CreateOpportunityDTO? {
        makeOpportunityDTO(
            companyId: request.companyId,
            clientId: request.clientId,
            name: request.name,
            email: request.email,
            phoneNumber: request.phoneNumber,
            address: request.address,
            notes: request.notes
        )
    }

    private static func makeOpportunityDTO(
        companyId: String,
        clientId: String,
        name: String,
        email: String?,
        phoneNumber: String?,
        address: String?,
        notes: String?
    ) -> CreateOpportunityDTO? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        return CreateOpportunityDTO(
            title: "\(trimmedName) — lead",
            contactName: trimmedName,
            contactEmail: sanitizedOptional(email),
            contactPhone: sanitizedOptional(phoneNumber),
            description: sanitizedOptional(notes),
            address: sanitizedOptional(address),
            estimatedValue: nil,
            source: schemaAllowedSource,
            sourceThreadKey: sourceThreadKey(forClientId: clientId),
            priority: schemaAllowedPriority,
            quoteDeliveryMethod: nil,
            clientId: clientId
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

    var errorDescription: String? {
        switch self {
        case .missingClientName:
            return "Client saved. Pipeline lead needs a client name."
        }
    }
}
