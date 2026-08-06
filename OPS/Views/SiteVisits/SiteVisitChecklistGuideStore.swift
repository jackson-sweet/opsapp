//
//  SiteVisitChecklistGuideStore.swift
//  OPS
//
//  User-scoped persistence for the one-time checklist settings guide.
//

import Foundation

struct SiteVisitChecklistGuideStore {
    private static let keyPrefix = "site_visit_checklist_settings_guide_suppressed_v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shouldPresent(userId: String?) -> Bool {
        guard let key = key(userId: userId) else { return false }
        return !defaults.bool(forKey: key)
    }

    func suppress(userId: String?) {
        guard let key = key(userId: userId) else { return }
        defaults.set(true, forKey: key)
    }

    private func key(userId: String?) -> String? {
        guard let canonicalId = userId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !canonicalId.isEmpty else {
            return nil
        }
        return "\(Self.keyPrefix):\(canonicalId)"
    }
}
