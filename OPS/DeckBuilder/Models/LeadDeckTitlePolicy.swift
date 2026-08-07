//
//  LeadDeckTitlePolicy.swift
//  OPS
//

import Foundation

enum DeckDesignTitlePolicy {
    static func resolve(preferred: String?, fallback: String) -> String {
        if let preferred = preferred?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferred.isEmpty {
            return preferred
        }

        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "Untitled Deck" : fallback
    }
}

extension Opportunity {
    /// Decks created for a lead are job-site artifacts, so the site address is
    /// their stable title. Contact remains the safe fallback for legacy leads
    /// whose address is genuinely absent.
    var deckDesignTitle: String {
        DeckDesignTitlePolicy.resolve(
            preferred: address,
            fallback: displayContactName
        )
    }
}
