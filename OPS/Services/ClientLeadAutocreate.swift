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

    /// Mirror of the live `opportunities_source_check` allowlist. If the
    /// database contract ever changes, this set changes in the same commit as
    /// the migration — that coupling is the point.
    ///
    /// Bug 44db2ea4: the BOOK VISIT / log-activity inline lead forms sent
    /// `source: "log_activity"`, which is not in this list. Every such create
    /// had failed since the code shipped — prod holds zero opportunities with
    /// that source — and the raw constraint error was rendered into the form.
    static let permittedSources: Set<String> = [
        "referral", "website", "email", "phone", "walk_in",
        "social_media", "repeat_client", "voice_log", "other",
    ]

    /// Clamps any candidate to the schema vocabulary. Unknown or nil → `other`,
    /// the standing contract for client-created leads. Never widens the
    /// constraint to fit the client; the database vocabulary is the contract.
    static func conformedSource(_ candidate: String?) -> String {
        guard let candidate, permittedSources.contains(candidate) else {
            return schemaAllowedSource
        }
        return candidate
    }

    /// One constructor for every inline "New Lead" mini-form — the target
    /// picker and the unified log sheet both build through here, so neither can
    /// invent a source the database will refuse.
    ///
    /// Returns nil when the trimmed name is empty: a lead with no name is not a
    /// lead. No client linkage, title, or priority — those belong to the
    /// full-form paths.
    static func makeInlineLeadDTO(
        name: String,
        email: String?,
        phone: String?,
        source: String? = nil
    ) -> CreateOpportunityDTO? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        return CreateOpportunityDTO(
            contactName: trimmedName,
            contactEmail: sanitizedOptional(email),
            contactPhone: sanitizedOptional(phone),
            description: nil,
            estimatedValue: nil,
            source: conformedSource(source),
            quoteDeliveryMethod: nil
        )
    }

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

    static func sanitizedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum ClientLeadAutocreateError: LocalizedError {
    case missingClientName
    /// The parent client's OWN outbound create was permanently rejected by the
    /// server, so this lead has no customer row to hang off. Not a failure of
    /// the lead write — the lead was never attempted. Raised by the queue's
    /// ordering gate, never by the network layer.
    case clientCreateRejected

    /// The stable phrase every `clientCreateRejected` record carries, and the
    /// only thing the copy layer and the release rule match on. Loose wording
    /// would let an unrelated park masquerade as this one and be auto-released.
    /// Mirrors `SyncError.serverRowMissingMarker`.
    static let clientCreateRejectedMarker = "client create rejected"

    /// The exact string the queue stores in `lastError` when it parks a delivery
    /// behind a rejected customer. A constant rather than
    /// `String(describing:)` — that renders an enum case as its bare case name
    /// and would drop the marker entirely.
    static let clientCreateRejectedDetail =
        "\(clientCreateRejectedMarker): the server refused the customer record this lead belongs to."

    var errorDescription: String? {
        switch self {
        case .missingClientName:
            return "Client saved. Pipeline lead needs a client name."
        case .clientCreateRejected:
            return Self.clientCreateRejectedDetail
        }
    }
}
