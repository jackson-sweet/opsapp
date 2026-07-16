//
//  UniversalSearchMatching.swift
//  OPS
//
//  Pure, testable match predicates for the money + leads rows of universal
//  search (bug ac2ace7a). Extracted from UniversalSearchSheet so the "what
//  counts as a hit" rules — the actual indexing logic — can be unit-tested
//  without standing up the whole SwiftUI sheet + SwiftData store, mirroring
//  UniversalSearchScheduleTargeting.
//
//  Every type matches on its own identifiers/title PLUS the resolved client
//  name (and, for money records, the project title) so a search for a customer
//  or a job surfaces the paperwork attached to it — not just the invoice /
//  estimate number nobody memorizes. Leads were previously not indexed at all.
//

import Foundation

enum UniversalSearchMatching {

    /// An invoice is a hit when the query matches its number, its title, the
    /// name of its client, or the title of its project.
    static func matches(
        invoice: Invoice,
        query: String,
        clientNameById: [String: String],
        projectTitleById: [String: String]
    ) -> Bool {
        if invoice.invoiceNumber.localizedCaseInsensitiveContains(query) { return true }
        if invoice.title?.localizedCaseInsensitiveContains(query) == true { return true }
        if let cid = invoice.clientId, clientNameById[cid]?.localizedCaseInsensitiveContains(query) == true { return true }
        if let pid = invoice.projectId, projectTitleById[pid]?.localizedCaseInsensitiveContains(query) == true { return true }
        return false
    }

    /// An estimate is a hit when the query matches its number, its title, the
    /// name of its client, or the title of its project.
    static func matches(
        estimate: Estimate,
        query: String,
        clientNameById: [String: String],
        projectTitleById: [String: String]
    ) -> Bool {
        if estimate.estimateNumber.localizedCaseInsensitiveContains(query) { return true }
        if estimate.title?.localizedCaseInsensitiveContains(query) == true { return true }
        if let cid = estimate.clientId, clientNameById[cid]?.localizedCaseInsensitiveContains(query) == true { return true }
        if let pid = estimate.projectId, projectTitleById[pid]?.localizedCaseInsensitiveContains(query) == true { return true }
        return false
    }

    /// A lead is a hit when the query matches its contact name, its title, the
    /// contact email or phone, the address, or the name of a linked client.
    static func matches(
        opportunity: Opportunity,
        query: String,
        clientNameById: [String: String]
    ) -> Bool {
        if opportunity.contactName.localizedCaseInsensitiveContains(query) { return true }
        if opportunity.title?.localizedCaseInsensitiveContains(query) == true { return true }
        if opportunity.contactEmail?.localizedCaseInsensitiveContains(query) == true { return true }
        if opportunity.contactPhone?.localizedCaseInsensitiveContains(query) == true { return true }
        if opportunity.address?.localizedCaseInsensitiveContains(query) == true { return true }
        if let cid = opportunity.clientId, clientNameById[cid]?.localizedCaseInsensitiveContains(query) == true { return true }
        return false
    }
}
