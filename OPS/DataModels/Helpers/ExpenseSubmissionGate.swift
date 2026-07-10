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
    static func passes(submit: Bool, required: Bool, hasArtifact: Bool, hasReason: Bool) -> Bool {
        guard submit, required else { return true }
        return hasArtifact || hasReason
    }
}
