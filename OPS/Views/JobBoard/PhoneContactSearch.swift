//
//  PhoneContactSearch.swift
//  OPS
//
//  Bug 388663d4 — pure search + dedupe rules for blending device contacts
//  into the client picker. Kept free of Contacts/UIKit I/O so it unit-tests
//  headlessly, mirroring `ProjectFormClientSearch`.
//

import Foundation

/// Normalized identity of the clients already in OPS. Used to decide which
/// device contacts are genuinely "not in OPS" and therefore earn the badge.
/// Sub-clients are folded in so a contact already captured as a sub-client is
/// not re-offered as new.
struct ClientIdentityIndex {
    private let names: Set<String>
    private let phones: Set<String>
    private let emails: Set<String>

    init(clients: [Client]) {
        var names = Set<String>()
        var phones = Set<String>()
        var emails = Set<String>()

        func add(name: String?, phone: String?, email: String?) {
            if let n = name?.trimmingCharacters(in: .whitespaces).lowercased(), !n.isEmpty {
                names.insert(n)
            }
            if let digits = phone.map({ $0.filter { $0.isNumber } }), !digits.isEmpty {
                phones.insert(digits)
            }
            if let e = email?.trimmingCharacters(in: .whitespaces).lowercased(), !e.isEmpty {
                emails.insert(e)
            }
        }

        for client in clients where client.deletedAt == nil {
            add(name: client.name, phone: client.phoneNumber, email: client.email)
            for sub in client.subClients where sub.deletedAt == nil {
                add(name: sub.name, phone: sub.phoneNumber, email: sub.email)
            }
        }

        self.names = names
        self.phones = phones
        self.emails = emails
    }

    /// True when this device contact already corresponds to an OPS client or
    /// sub-client by name, phone, or email.
    func contains(_ suggestion: PhoneContactSuggestion) -> Bool {
        if names.contains(suggestion.nameKey) { return true }
        if suggestion.phoneKeys.contains(where: { phones.contains($0) }) { return true }
        if suggestion.emailKeys.contains(where: { emails.contains($0) }) { return true }
        return false
    }
}

enum PhoneContactSearch {
    /// Substring match over name / phone / email. A digits-only pass lets a
    /// typed "5551234" hit a formatted "(555) 123-4…" number.
    static func matching(_ suggestions: [PhoneContactSuggestion], query: String) -> [PhoneContactSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        let digits = trimmed.filter { $0.isNumber }

        return suggestions.filter { suggestion in
            if suggestion.searchHaystack.contains(trimmed) { return true }
            if !digits.isEmpty, suggestion.phoneKeys.contains(where: { $0.contains(digits) }) { return true }
            return false
        }
    }

    /// Keeps only the device contacts NOT already in OPS — the rows that get
    /// the badge and, on tap, create a client. Also collapses duplicates
    /// within the device set itself (the same person can appear twice in an
    /// address book) by name / phone / email so the list stays clean. Input
    /// order is preserved.
    static func notInOps(_ matches: [PhoneContactSuggestion], existing identity: ClientIdentityIndex) -> [PhoneContactSuggestion] {
        var seenNames = Set<String>()
        var seenPhones = Set<String>()
        var seenEmails = Set<String>()
        var result: [PhoneContactSuggestion] = []

        for suggestion in matches {
            if identity.contains(suggestion) { continue }
            if seenNames.contains(suggestion.nameKey) { continue }
            if suggestion.phoneKeys.contains(where: { seenPhones.contains($0) }) { continue }
            if suggestion.emailKeys.contains(where: { seenEmails.contains($0) }) { continue }

            seenNames.insert(suggestion.nameKey)
            suggestion.phoneKeys.forEach { seenPhones.insert($0) }
            suggestion.emailKeys.forEach { seenEmails.insert($0) }
            result.append(suggestion)
        }
        return result
    }
}
