//
//  SiteVisitDeckDesignResolver.swift
//  OPS
//
//  The site visit's DECK action continues an existing design instead of
//  forking a duplicate. Priority:
//
//    1. The visit's OWN sketch — the newest active deck artifact whose
//       design still exists (covers the checklist row's EDIT button, which
//       previously created a second design and silently re-linked).
//    2. The LEAD's design — the same display-candidate rule the lead page
//       uses (most recently updated with drawable geometry), so a deck
//       started while quoting carries straight into the visit.
//    3. Nothing — the caller creates a fresh canvas.
//
//  Pure over arrays so the decision is directly testable; fetching stays at
//  the call site.
//

import Foundation

enum SiteVisitDeckDesignResolver {

    /// The design the DECK action should open, or nil to create new.
    ///
    /// - Parameters:
    ///   - preferredDesignId: the design a caller wants opened by exact id —
    ///     the checklist row's EDIT knows precisely which design it linked, so
    ///     this takes priority over any re-derivation. Bug (site-visit report):
    ///     EDIT used to fall through to re-derivation and open a blank/new
    ///     design; anchoring on the linked id makes EDIT deterministic.
    ///   - artifactDesignIds: deck-artifact design ids from THIS visit,
    ///     newest first (`activeArtifacts` order).
    ///   - opportunityId: the lead bound to the visit, when there is one.
    ///   - designs: the local design store (soft-deleted rows are skipped
    ///     here and by the display-candidate rule).
    static func existingDesign(
        preferredDesignId: String? = nil,
        artifactDesignIds: [String],
        opportunityId: String?,
        in designs: [DeckDesign]
    ) -> DeckDesign? {
        // 0. Open the exact design the caller asked for. Canonicalize the id
        //    (artifacts/answers can carry UPPERCASE UUIDs; the store is
        //    lowercase) before matching.
        if let preferredDesignId {
            let canonical = DeckDesign.canonicalUUIDString(preferredDesignId)
            if let match = designs.first(where: { $0.deletedAt == nil && $0.id == canonical }) {
                return match
            }
        }

        // 1. Continue the visit's own sketch. Ids canonicalize before
        //    comparing — artifacts can carry UPPERCASE UUIDs while the
        //    design store is lowercase (the Postgres echo convention).
        for artifactId in artifactDesignIds {
            let canonical = DeckDesign.canonicalUUIDString(artifactId)
            if let match = designs.first(where: {
                $0.deletedAt == nil && $0.id == canonical
            }) {
                return match
            }
        }

        // 2. Continue the lead's design — identical selection rule to the
        //    lead page, so both surfaces always open the SAME deck. A
        //    converted lead's deck (project_id set) still qualifies: the
        //    record is shared, not copied.
        if let opportunityId {
            return DeckDesign.displayCandidate(in: designs, forOpportunityId: opportunityId)
        }

        return nil
    }
}
