//
//  ContactLeadFill.swift
//  OPS
//
//  One mapping from a picked CNContact to lead-form fields, shared by every
//  new-lead entry point (AddLeadSheet, the booking picker's inline form).
//  Semantics are the capture panel's (bug 5d5df5b0 lineage): FILL, never
//  create — no Client row, no Opportunity row, no autocreate queue. Fields
//  only overwrite when the contact actually carries a value, so a partly
//  typed form is never wiped.
//
//  Composition is delegated to PhoneContactImporter so the name fallback and
//  the comma-canonical address line stay identical to every other contact
//  import in the app.
//

import Contacts
import Foundation

struct ContactLeadFill: Equatable {
    var name: String?
    var phone: String?
    var email: String?
    /// Comma-canonical single line, matching AddressAutocompleteField output.
    var address: String?

    /// `@MainActor` only on the composing entry point: `PhoneContactImporter`
    /// is main-actor-isolated, and both call sites are views. The struct
    /// itself stays nonisolated so its synthesized `==` satisfies `Equatable`
    /// without actor hops.
    @MainActor
    static func from(_ contact: CNContact) -> ContactLeadFill {
        let name = PhoneContactImporter.composeName(from: contact)
        let phone = contact.phoneNumbers.first?.value.stringValue
            .trimmingCharacters(in: .whitespaces)
        let email = contact.emailAddresses.first
            .map { ($0.value as String).trimmingCharacters(in: .whitespaces) }
        return ContactLeadFill(
            name: name.isEmpty ? nil : name,
            phone: (phone?.isEmpty ?? true) ? nil : phone,
            email: (email?.isEmpty ?? true) ? nil : email,
            address: PhoneContactImporter.composeAddress(from: contact)
        )
    }

    /// Apply into three INDEPENDENT bound strings (e.g. three separate
    /// `@State` vars) — non-nil fields win, everything else is untouched.
    /// Never call this with three properties of ONE struct: simultaneous
    /// inout access to one variable is a Swift exclusivity violation —
    /// struct consumers use `applied(to:)` below.
    func apply(name: inout String, phone: inout String, email: inout String) {
        if let value = self.name { name = value }
        if let value = self.phone { phone = value }
        if let value = self.email { email = value }
    }

    /// Value-typed application for `LeadForm`: copies the form, assigns only
    /// the carried identity fields, routes the address through the form's own
    /// coordinate-divergence rule (imported text owns no coords, so any stale
    /// lat/lng from an earlier autocomplete pick must drop).
    func applied(to form: LeadForm) -> LeadForm {
        var updated = form
        if let name { updated.contactName = name }
        if let phone { updated.phone = phone }
        if let email { updated.email = email }
        if let address {
            updated.address = address
            updated.addressTextChanged(address)
        }
        return updated
    }
}
