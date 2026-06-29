//
//  SiteVisitIdentityDraft.swift
//  OPS
//
//  Local-first client/lead identity packet for a site visit. This lets field
//  capture start before the operator has contact details or a selected lead.
//

import Foundation
import SwiftData

@Model
final class SiteVisitIdentityDraft: Identifiable {
    @Attribute(.unique) var id: String
    var siteVisitId: String
    var companyId: String
    var opportunityId: String?
    var clientId: String?
    var subClientId: String?

    var searchText: String
    var clientName: String
    var contactName: String
    var preferredEmail: String
    var additionalEmailsJSON: String
    var phoneNumber: String
    var address: String
    var notes: String

    var createdAt: Date
    var updatedAt: Date
    var lastCommittedAt: Date?

    init(
        id: String = UUID().uuidString,
        siteVisitId: String,
        companyId: String,
        opportunityId: String? = nil,
        clientId: String? = nil,
        subClientId: String? = nil,
        searchText: String = "",
        clientName: String = "",
        contactName: String = "",
        preferredEmail: String = "",
        additionalEmails: [String] = [],
        phoneNumber: String = "",
        address: String = "",
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.siteVisitId = siteVisitId
        self.companyId = companyId
        self.opportunityId = opportunityId
        self.clientId = clientId
        self.subClientId = subClientId
        self.searchText = searchText
        self.clientName = clientName
        self.contactName = contactName
        self.preferredEmail = preferredEmail
        self.additionalEmailsJSON = Self.encodeAdditionalEmails(additionalEmails)
        self.phoneNumber = phoneNumber
        self.address = address
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var additionalEmails: [String] {
        get {
            guard let data = additionalEmailsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            additionalEmailsJSON = Self.encodeAdditionalEmails(newValue)
        }
    }

    var allEmails: [String] {
        ([preferredEmail] + additionalEmails)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var filledFieldCount: Int {
        [
            clientName.trimmedNilIfEmpty,
            contactName.trimmedNilIfEmpty,
            allEmails.isEmpty ? nil : allEmails.joined(separator: ","),
            phoneNumber.trimmedNilIfEmpty,
            address.trimmedNilIfEmpty
        ].compactMap { $0 }.count
    }

    var isCompleteEnoughForProject: Bool {
        let hasName = clientName.trimmedNilIfEmpty != nil || contactName.trimmedNilIfEmpty != nil
        let hasContact = !allEmails.isEmpty || phoneNumber.trimmedNilIfEmpty != nil
        return hasName && hasContact && address.trimmedNilIfEmpty != nil
    }

    var displayName: String {
        contactName.trimmedNilIfEmpty
        ?? clientName.trimmedNilIfEmpty
        ?? "Unlinked visit"
    }

    func touch() {
        updatedAt = Date()
    }

    private static func encodeAdditionalEmails(_ emails: [String]) -> String {
        let cleaned = emails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let data = try? JSONEncoder().encode(cleaned),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
