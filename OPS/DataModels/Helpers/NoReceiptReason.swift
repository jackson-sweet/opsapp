//
//  NoReceiptReason.swift
//  OPS
//
//  Why an expense has no receipt photo when the company requires one.
//  Backs the require_receipt_photo escape hatch — the crew picks a reason so a
//  genuinely receiptless purchase still files, and the office sees why instead
//  of an unexplained blank. Codes match the `expenses.receipt_missing_reason`
//  CHECK constraint ('lost' | 'cash' | 'digital' | 'other').
//

import Foundation

enum NoReceiptReason: String, CaseIterable, Identifiable {
    case lost
    case cash
    case digital
    case other

    var id: String { rawValue }

    /// Persisted code (equals the raw value); written to
    /// `expenses.receipt_missing_reason`.
    var code: String { rawValue }

    /// Field-facing label. Sentence case, terse (OPS voice).
    var label: String {
        switch self {
        case .lost:    return "Lost or misplaced"
        case .cash:    return "Cash — no receipt given"
        case .digital: return "Digital or emailed"
        case .other:   return "Other"
        }
    }

    /// Rehydrate a persisted code into a reason. Nil for a missing or
    /// unrecognized (legacy) code, so old rows read cleanly.
    init?(code: String?) {
        guard let code, let value = NoReceiptReason(rawValue: code) else { return nil }
        self = value
    }
}
