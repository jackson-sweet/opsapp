//
//  SpotlightDomainIdentifiers.swift
//  OPS
//
//  Domain identifiers group Spotlight items by entity type. Used for targeted
//  index clearing (e.g. re-index all invoices without touching projects) and
//  for decoding tapped search results.
//

import Foundation

enum SpotlightDomain {
    static let project  = "co.opsapp.spotlight.project"
    static let client   = "co.opsapp.spotlight.client"
    static let task     = "co.opsapp.spotlight.task"
    static let invoice  = "co.opsapp.spotlight.invoice"
    static let estimate = "co.opsapp.spotlight.estimate"

    static let all: [String] = [project, client, task, invoice, estimate]
}

/// Item identifiers are `"<domain>:<entityId>"` so we can decode which entity
/// type a tapped result belongs to.
enum SpotlightItemId {
    static func make(domain: String, id: String) -> String {
        return "\(domain):\(id)"
    }

    /// Decode a tapped item identifier back into (domain, entityId).
    static func decode(_ itemId: String) -> (domain: String, id: String)? {
        let parts = itemId.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}
