//
//  ActivityTarget.swift
//  OPS
//
//  The unified parent an activity is logged against. The `activities` table
//  accepts EXACTLY ONE parent per row (opportunity_id / client_id / project_id);
//  this enum makes that invariant unrepresentable-otherwise at the call boundary.
//  `ActivityRepository.buildDTO` reads `parentKey` to set the single column.
//
//  `.unbound` is the "no target chosen yet" state used by the generic FAB entry
//  point before the operator picks a lead / client / job.
//

import Foundation

/// The single parent an activity attaches to. Backs the unified Log Activity
/// capture: a lead (opportunity), a client, a job (project), or nothing yet.
enum ActivityTarget: Equatable {
    case opportunity(Opportunity)
    case client(Client)
    case project(Project)
    case unbound

    /// The one parent column + id this target writes to. `nil` for `.unbound`.
    /// Exactly one case is ever produced — the type guarantees the activities
    /// single-parent invariant.
    enum ParentKey: Equatable {
        case opportunity(String)
        case client(String)
        case project(String)
    }

    /// The parent column + id for this target, or `nil` when unbound.
    var parentKey: ParentKey? {
        switch self {
        case .opportunity(let opp): return .opportunity(opp.id)
        case .client(let client):   return .client(client.id)
        case .project(let project): return .project(project.id)
        case .unbound:              return nil
        }
    }

    /// Human name for the target row / locked-target chip. Uses each entity's
    /// real display field: opportunity → `contactName`, client → `name`,
    /// project → `title`.
    var displayName: String {
        switch self {
        case .opportunity(let opp): return opp.contactName
        case .client(let client):   return client.name
        case .project(let project): return project.title
        case .unbound:              return ""
        }
    }

    /// Secondary caption for the target row. Leads show their pipeline stage,
    /// jobs show their status, clients fall back to their address. `nil` when
    /// there is nothing meaningful to show (or unbound).
    var subtitle: String? {
        switch self {
        case .opportunity(let opp):
            return opp.stage.displayName
        case .project(let project):
            return project.status.displayName
        case .client(let client):
            return client.address?.trimmedNonEmpty
        case .unbound:
            return nil
        }
    }

    /// Source badge shown on the target row to disambiguate which surface a
    /// match came from. `nil` for unbound.
    var sourceBadge: String? {
        switch self {
        case .opportunity: return "LEAD"
        case .client:      return "CLIENT"
        case .project:     return "JOB"
        case .unbound:     return nil
        }
    }

    /// The bound entity's company id. `nil` when unbound (or, defensively, when
    /// a client row carries no company id).
    var companyId: String? {
        switch self {
        case .opportunity(let opp): return opp.companyId
        case .client(let client):   return client.companyId
        case .project(let project): return project.companyId
        case .unbound:              return nil
        }
    }
}

private extension String {
    /// Trimmed value, or `nil` when it is empty/whitespace after trimming.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
