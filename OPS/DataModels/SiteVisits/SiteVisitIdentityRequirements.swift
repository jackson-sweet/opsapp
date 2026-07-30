//
//  SiteVisitIdentityRequirements.swift
//  OPS
//
//  What a site-visit lead actually requires, resolved as pure data so the form
//  and its tests read the same rule.
//
//  A lead needs three things: an identity, a way to reach them, and a site
//  address. COMPANY is NOT one of them — most visits are residential, and the
//  form used to tag COMPANY with the same REQUIRED marker as NAME (both read
//  the shared name-or-company predicate), showing homeowners a requirement
//  they could never honestly satisfy.
//
//  The either-or groups still light up together: NAME reports satisfied once
//  an identity exists (a person's name, or a business when the business IS the
//  client), and EMAIL/PHONE both report satisfied once either arrives.
//

import Foundation

/// Per-field requirement state for the identity form. `.required` carries its
/// own satisfied flag so either-or groups can light up every member at once.
enum SiteVisitIdentityFieldRequirement: Equatable {
    case optional
    case required(satisfied: Bool)
}

/// The resolved requirement state of every identity field, from the raw text
/// currently in the form.
struct SiteVisitIdentityRequirements: Equatable {
    let name: SiteVisitIdentityFieldRequirement
    /// Always `.optional`. Kept as a field (rather than omitted) so the form
    /// asks this type for every marker and no field can drift onto a
    /// hand-written rule.
    let company: SiteVisitIdentityFieldRequirement
    let email: SiteVisitIdentityFieldRequirement
    let phone: SiteVisitIdentityFieldRequirement
    let address: SiteVisitIdentityFieldRequirement

    /// `true` once the lead can stand on its own — the same three-part rule
    /// `SiteVisitIdentityDraft.isCompleteEnoughForProject` enforces.
    var isComplete: Bool {
        [name, email, address].allSatisfy { $0 == .required(satisfied: true) }
    }

    static func resolve(
        name: String,
        company: String,
        email: String,
        additionalEmails: String,
        phone: String,
        address: String
    ) -> SiteVisitIdentityRequirements {
        // An identity can be a person OR a business — a commercial visit may
        // legitimately carry only the company name.
        let hasIdentity = name.trimmedNilIfEmpty != nil || company.trimmedNilIfEmpty != nil
        let hasContactMethod = email.trimmedNilIfEmpty != nil
            || additionalEmails.trimmedNilIfEmpty != nil
            || phone.trimmedNilIfEmpty != nil
        let hasAddress = address.trimmedNilIfEmpty != nil

        return SiteVisitIdentityRequirements(
            name: .required(satisfied: hasIdentity),
            company: .optional,
            email: .required(satisfied: hasContactMethod),
            phone: .required(satisfied: hasContactMethod),
            address: .required(satisfied: hasAddress)
        )
    }
}

private extension String {
    /// Whitespace-trimmed, or nil when nothing but whitespace remains — a
    /// space bar press is not an answer.
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
