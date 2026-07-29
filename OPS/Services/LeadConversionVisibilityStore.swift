//
//  LeadConversionVisibilityStore.swift
//  OPS
//
//  Persists only the lead ids whose conversion is committed while the linked
//  project is inaccessible. No project id is retained. This presentation
//  marker prevents the won lead from being offered as "not converted" again
//  across sheet dismissal, refresh, or app restart.
//

import Foundation
import Combine

@MainActor
final class LeadConversionVisibilityStore: ObservableObject {
    static let shared = LeadConversionVisibilityStore()

    @Published private(set) var committedWithoutAccessibleProjectLeadIds: Set<String>

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "ops.leads.committedWithoutAccessibleProject.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.committedWithoutAccessibleProjectLeadIds = Set(
            defaults.stringArray(forKey: storageKey) ?? []
        )
    }

    func contains(_ leadId: String) -> Bool {
        committedWithoutAccessibleProjectLeadIds.contains(leadId)
    }

    func markCommittedWithoutAccessibleProject(_ leadId: String) {
        guard !leadId.isEmpty else { return }
        committedWithoutAccessibleProjectLeadIds.insert(leadId)
        persist()
    }

    func clear(_ leadId: String) {
        guard committedWithoutAccessibleProjectLeadIds.remove(leadId) != nil else {
            return
        }
        persist()
    }

    /// Self-repair for leads damaged before bug ced5b3cb was fixed.
    ///
    /// The old already-converted path read the RPC's hardcoded
    /// `project_accessible = false` as a real access denial: it nulled the
    /// lead's project link AND set this marker, which is persisted — so MATCH
    /// PROJECT stayed hidden on that lead across relaunches, forever, with no
    /// way back. A lead that demonstrably HAS a project link is proof the
    /// marker is stale. Clear it the next time the lead is opened; no operator
    /// action, no announcement.
    func repairIfLinked(leadId: String, projectId: String?) {
        guard let projectId,
              !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        clear(leadId)
    }

    private func persist() {
        defaults.set(
            committedWithoutAccessibleProjectLeadIds.sorted(),
            forKey: storageKey
        )
    }
}
