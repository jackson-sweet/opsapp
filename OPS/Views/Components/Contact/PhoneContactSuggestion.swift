//
//  PhoneContactSuggestion.swift
//  OPS
//
//  Bug 388663d4 — device address-book entries surfaced inside the client
//  picker. A lightweight, Sendable projection of a `CNContact` holding only
//  what the picker list needs (display name, one subtitle line) plus the
//  normalized keys used to search and to dedupe against existing OPS clients.
//  The heavy full `CNContact` (image data, postal address) is re-fetched by
//  identifier only at import time — see `PhoneContactsProvider.fullContact`.
//

import Foundation
import Contacts

struct PhoneContactSuggestion: Identifiable, Equatable, Sendable {
    /// `CNContact.identifier` — the stable handle used to re-fetch the full
    /// contact when the operator taps this row to import it.
    let id: String
    let displayName: String
    let firstName: String
    let lastName: String
    /// One disambiguating line under the name — first phone, else first email.
    let subtitle: String?

    // Normalized identity + search keys (all lowercased; phones digits-only).
    let nameKey: String
    let phoneKeys: [String]
    let emailKeys: [String]
    /// Pre-joined lowercase haystack for substring search.
    let searchHaystack: String

    /// Builds a suggestion from an enumerated contact. Returns `nil` for a
    /// nameless contact (nothing to show or match on). Reads only the keys the
    /// index fetch requests — never `imageData`/`postalAddresses`, which would
    /// throw when unfetched.
    init?(contact: CNContact) {
        let given = contact.givenName.trimmingCharacters(in: .whitespaces)
        let family = contact.familyName.trimmingCharacters(in: .whitespaces)
        var name = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        if name.isEmpty {
            name = contact.organizationName.trimmingCharacters(in: .whitespaces)
        }
        guard !name.isEmpty else { return nil }

        let phones = contact.phoneNumbers
            .map { $0.value.stringValue.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let emails = contact.emailAddresses
            .map { ($0.value as String).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        self.init(
            id: contact.identifier,
            displayName: name,
            firstName: given.isEmpty ? name : given,
            lastName: family,
            subtitle: phones.first ?? emails.first,
            phones: phones,
            emails: emails
        )
    }

    /// Memberwise init — also used by tests / previews (no `CNContact` needed).
    init(
        id: String,
        displayName: String,
        firstName: String,
        lastName: String,
        subtitle: String?,
        phones: [String] = [],
        emails: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.subtitle = subtitle
        self.nameKey = displayName.trimmingCharacters(in: .whitespaces).lowercased()
        self.phoneKeys = phones.map { PhoneContactSuggestion.normalizedPhone($0) }.filter { !$0.isEmpty }
        self.emailKeys = emails.map { $0.lowercased() }.filter { !$0.isEmpty }

        var haystack = [displayName.lowercased()]
        haystack.append(contentsOf: phones.map { $0.lowercased() })
        haystack.append(contentsOf: emails.map { $0.lowercased() })
        self.searchHaystack = haystack.joined(separator: " ")
    }

    /// Digits-only form so "(555) 123-4567" and "5551234567" compare equal.
    static func normalizedPhone(_ raw: String) -> String {
        raw.filter { $0.isNumber }
    }
}
