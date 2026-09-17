//
//  ProductOptionDefaultPolicy.swift
//  OPS
//
//  Which product options carry a catalogue default. A select or boolean does:
//  a new estimate line opens on it. An integer count does not: a count is the
//  job's geometry (end posts, corners), the estimate editors never fill one,
//  and acceptance refuses a blank one — so the option form offers no default
//  for a count, saving a count clears any default it still carries, and a
//  stored count default is never shown as if it did something. Mirrors
//  ops-web's product option form (2026-09-17).
//

import Foundation

enum ProductOptionDefaultPolicy {
    /// Whether the option form offers a default for this kind.
    static func offersDefault(for kind: ProductOptionKind) -> Bool {
        kind != .integer
    }

    /// The default an option saves with: the trimmed draft, or none when the
    /// draft is empty or the option is a count.
    static func savedDefault(_ draft: String, kind: ProductOptionKind) -> String? {
        guard offersDefault(for: kind) else { return nil }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The default to show for a stored option, or nil when there is nothing
    /// that takes effect.
    static func displayedDefault(for option: ProductOption) -> String? {
        guard offersDefault(for: option.kind) else { return nil }
        let trimmed = option.defaultValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
