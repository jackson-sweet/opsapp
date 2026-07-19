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

    private func persist() {
        defaults.set(
            committedWithoutAccessibleProjectLeadIds.sorted(),
            forKey: storageKey
        )
    }
}
