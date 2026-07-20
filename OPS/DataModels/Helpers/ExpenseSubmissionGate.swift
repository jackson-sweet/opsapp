//
//  ExpenseSubmissionGate.swift
//  OPS
//
//  The pure decision behind the expense submit gates — require_receipt_photo
//  and require_project_assignment. Extracted from ExpenseFormSheet so the
//  enforcement rule is unit-testable without a view or a simulator, and so a
//  future refactor can't silently re-open the hole where a photo-less expense
//  could be submitted at a company that requires one.
//
//  The rule is identical for both gates: saving a draft never blocks, and a
//  company that doesn't require the artifact never blocks. When a submit meets
//  a company requirement, it proceeds only if the artifact is present OR an
//  explicit "missing" reason was supplied (the no-receipt / no-project escape
//  hatch). The view keeps its own side effects (haptic + fork dialog); this
//  type owns only the yes/no.
//

import Foundation

enum ExpenseSubmissionGate {
    /// Whether a save may proceed.
    /// - Parameters:
    ///   - submit: true for a submit, false for a draft save or in-place edit.
    ///   - required: whether the company requires the artifact for submission.
    ///   - hasArtifact: whether the artifact (a receipt photo / a project) is present.
    ///   - hasReason: whether an explicit "missing" reason was supplied.
    /// - Returns: false only when a submit meets a live requirement with neither
    ///   the artifact nor a reason; true in every other case.
    static func passes(
        submit: Bool,
        policyResolved: Bool = true,
        required: Bool,
        hasArtifact: Bool,
        hasReason: Bool
    ) -> Bool {
        guard submit else { return true }
        guard policyResolved else { return false }
        guard required else { return true }
        return hasArtifact || hasReason
    }
}

enum ExpenseAllocationPercentageTotal {
    /// Percentages are stored with at most two decimal places. Compare their
    /// integer basis points so 99.99 and 100.01 cannot slip through a floating
    /// tolerance that the database correctly rejects.
    static func isExactlyComplete(_ percentages: [String]) -> Bool {
        guard !percentages.isEmpty else { return true }

        var totalBasisPoints = 0
        for rawValue in percentages {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let decimal = Decimal(
                string: trimmed,
                locale: Locale(identifier: "en_US_POSIX")
            ) else { return false }

            let scaled = decimal * 100
            let number = NSDecimalNumber(decimal: scaled)
            guard number != .notANumber,
                  Decimal(number.intValue) == scaled else {
                return false
            }
            totalBasisPoints += number.intValue
        }
        return totalBasisPoints == 10_000
    }
}

/// Submission rules after applying the live database defaults. A missing
/// `expense_settings` row is a valid resolved state, not permission to fail
/// open: receipts default to required and project assignment defaults to off.
struct ExpenseSubmissionRequirements: Equatable {
    let requireReceiptPhoto: Bool
    let requireProjectAssignment: Bool

    init(settings: ExpenseSettingsDTO?) {
        requireReceiptPhoto = settings?.requireReceiptPhoto ?? true
        requireProjectAssignment = settings?.requireProjectAssignment ?? false
    }
}

/// Copy and edit-state policy for a database response that proves the atomic
/// transaction did not commit. Transient/unknown transport failures return nil
/// so the form retains its exact command and stays locked for idempotent retry.
struct ExpenseAtomicSaveRejection: Equatable {
    let title: String
    let message: String
    let requiresClose: Bool
}

enum ExpenseAtomicSaveFailurePolicy {
    static func rejection(for kind: UploadErrorKind) -> ExpenseAtomicSaveRejection? {
        guard case .permanent(let errorCode, _) = kind else { return nil }

        switch errorCode {
        case "PG_P0001":
            return ExpenseAtomicSaveRejection(
                title: "// EXPENSE CHANGED",
                message: "This expense changed after you opened it. Close and reopen it before saving.",
                requiresClose: true
            )
        case "PG_23503":
            return ExpenseAtomicSaveRejection(
                title: "// UPDATE REQUIRED",
                message: "A selected category or project is no longer available. Update the form and try again.",
                requiresClose: false
            )
        case "PG_23514":
            return ExpenseAtomicSaveRejection(
                title: "// REQUIREMENTS CHANGED",
                message: "Company expense requirements changed. Review the receipt and project details, then try again.",
                requiresClose: false
            )
        case "PG_42501":
            return ExpenseAtomicSaveRejection(
                title: "// SAVE BLOCKED",
                message: "You no longer have permission to save this expense. Close the form and reload.",
                requiresClose: true
            )
        case "PG_22023":
            return ExpenseAtomicSaveRejection(
                title: "// CHECK EXPENSE",
                message: "Review the date, amount, tax, and project split, then try again.",
                requiresClose: false
            )
        default:
            return ExpenseAtomicSaveRejection(
                title: "// SAVE REJECTED",
                message: "The expense could not be accepted. Review the form and try again.",
                requiresClose: false
            )
        }
    }
}

/// The result returned by the form save pipeline. Only `.complete` permits the
/// sheet to dismiss; every retry state keeps the captured image and local form
/// in place, while a general failure keeps every editable field on screen.
enum ExpenseSaveOutcome: Equatable {
    case complete
    case receiptRetryRequired
    case failed

    var shouldDismiss: Bool { self == .complete }
}

/// A definitive server rejection can schedule deletion of the staged receipt
/// immediately. The corrected retry must use a fresh object identity so that
/// the asynchronous cleanup of the rejected attempt can never delete the new
/// upload after it succeeds.
enum ExpenseReceiptRetryIdentity {
    static func rotatedUploadID(after current: String, candidate: UUID = UUID()) -> String {
        var next = candidate.uuidString.lowercased()
        while next == current {
            next = UUID().uuidString.lowercased()
        }
        return next
    }
}

/// Identifies receipt objects that are no longer referenced after a confirmed
/// replacement. Cleanup is deliberately derived from both URL pairs so a
/// thumbnail that reuses the full-size object is deleted once, while any URL
/// still referenced by the new row is never touched.
enum ExpenseReceiptCleanup {
    static func supersededURLs(
        previousImageURL: String?,
        previousThumbnailURL: String?,
        replacementImageURL: String?,
        replacementThumbnailURL: String?
    ) -> [String] {
        let retained = Set(
            [replacementImageURL, replacementThumbnailURL]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        var seen = Set<String>()

        return [previousImageURL, previousThumbnailURL]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !retained.contains($0) && seen.insert($0).inserted }
    }
}

/// Confirms an ambiguous RPC result against the authoritative, fully hydrated
/// expense row. A match proves the entire atomic command committed; a partial
/// content write, stale nullable field, missing allocation, or unplaced submit
/// never qualifies the form for dismissal.
enum ExpenseAtomicSaveReadback {
    static func matches(command: ExpenseAtomicSaveCommand, expense: ExpenseDTO) -> Bool {
        guard expense.id == command.expenseId,
              expense.companyId == command.companyId,
              expense.submittedBy == command.submittedBy,
              expense.deletedAt == nil,
              expense.categoryId == command.categoryId,
              expense.merchantName == command.merchantName,
              expense.description == command.description,
              scaledMoney(expense.amount) == scaledMoney(command.amount),
              scaledMoney(expense.taxAmount) == scaledMoney(command.taxAmount),
              expense.currency == command.currency,
              dateOnly(expense.expenseDate) == dateOnly(command.expenseDate),
              expense.paymentMethod == command.paymentMethod,
              expense.receiptImageUrl == command.receiptImageUrl,
              expense.receiptThumbnailUrl == command.receiptThumbnailUrl,
              expense.receiptMissingReason == command.receiptMissingReason,
              expense.receiptMissingNote == command.receiptMissingNote,
              expense.projectMissingReason == command.projectMissingReason,
              expense.projectMissingNote == command.projectMissingNote,
              expense.ocrRawData == command.ocrRawData,
              scaledConfidence(expense.ocrConfidence) == scaledConfidence(command.ocrConfidence),
              allocationsMatch(command: command.allocations, expense: expense.allocations) else {
            return false
        }

        if command.submit {
            guard ["submitted", "approved", "reimbursed"].contains(expense.status),
                  expense.batchId != nil else {
                return false
            }
        } else {
            guard expense.status == (command.expectedStatus ?? "draft") else { return false }
            if ["submitted", "approved", "reimbursed"].contains(expense.status),
               expense.batchId == nil {
                return false
            }
        }

        return true
    }

    private static func allocationsMatch(
        command: [ExpenseAtomicAllocationCommand],
        expense: [ExpenseAllocationDTO]?
    ) -> Bool {
        guard let expense else { return false }
        guard command.count == expense.count else { return false }

        let expected = command.map {
            AllocationFingerprint(
                projectId: $0.projectId,
                percentage: scaledPercentage($0.percentage),
                amount: scaledMoney($0.amount)
            )
        }.sorted()
        let observed = expense.map {
            AllocationFingerprint(
                projectId: $0.projectId,
                percentage: scaledPercentage($0.percentage),
                amount: scaledMoney($0.amount)
            )
        }.sorted()
        return expected == observed
    }

    private static func dateOnly(_ value: String?) -> String? {
        guard let value, value.count >= 10 else { return value }
        return String(value.prefix(10))
    }

    private static func scaledMoney(_ value: Double?) -> Int64? {
        value.map { Int64(($0 * 100).rounded()) }
    }

    private static func scaledPercentage(_ value: Double) -> Int64 {
        Int64((value * 100).rounded())
    }

    private static func scaledConfidence(_ value: Double?) -> Int64? {
        value.map { Int64(($0 * 10_000).rounded()) }
    }

    private struct AllocationFingerprint: Comparable {
        let projectId: String
        let percentage: Int64
        let amount: Int64?

        static func < (lhs: AllocationFingerprint, rhs: AllocationFingerprint) -> Bool {
            if lhs.projectId != rhs.projectId { return lhs.projectId < rhs.projectId }
            if lhs.percentage != rhs.percentage { return lhs.percentage < rhs.percentage }
            return (lhs.amount ?? .min) < (rhs.amount ?? .min)
        }
    }
}
