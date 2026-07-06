//
//  NoProjectReason.swift
//  OPS
//
//  Why an expense has no project when the company requires one.
//  Backs the require_project_assignment escape hatch — the crew picks a reason
//  so a genuinely project-less purchase (overhead, shop supplies) still files,
//  and the office sees why instead of an unexplained blank. Codes match the
//  `expenses.project_missing_reason` CHECK ('overhead' | 'general' | 'other').
//

import Foundation

enum NoProjectReason: String, CaseIterable, Identifiable {
    case overhead
    case general
    case other

    var id: String { rawValue }

    /// Persisted code (equals the raw value); written to
    /// `expenses.project_missing_reason`.
    var code: String { rawValue }

    /// Field-facing label. Sentence case, terse (OPS voice).
    var label: String {
        switch self {
        case .overhead: return "Overhead — not job-specific"
        case .general:  return "General / shop supplies"
        case .other:    return "Other"
        }
    }

    /// Rehydrate a persisted code into a reason. Nil for a missing or
    /// unrecognized (legacy) code, so old rows read cleanly.
    init?(code: String?) {
        guard let code, let value = NoProjectReason(rawValue: code) else { return nil }
        self = value
    }
}
