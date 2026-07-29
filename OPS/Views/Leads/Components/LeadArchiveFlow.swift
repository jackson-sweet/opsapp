//
//  LeadArchiveFlow.swift
//  OPS
//
//  One archive path for every lead surface — the dossier's ⋯ menu and the day
//  sheet's row action. Both used to raise their own confirm dialog, which meant
//  the same verb behaved differently depending on where you tapped it; now both
//  present the same sheet, write the same contract, and offer the same undo.
//  Mirrors `LeadDiscardFlow`.
//
//  Server degradation is built in: on a prod that has not taken the archive
//  migration yet the RPC answers PGRST202, and the flow falls through to the
//  legacy `archived_at` PATCH so the lead still leaves the board. The reason and
//  note are lost in that case — nothing else is.
//

import SwiftUI

extension View {
    func leadArchiveFlow(
        target: Binding<Opportunity?>,
        onCompleted: @escaping (Opportunity) -> Void = { _ in }
    ) -> some View {
        modifier(LeadArchiveFlow(target: target, onCompleted: onCompleted))
    }
}

private struct LeadArchiveFlow: ViewModifier {
    @Binding var target: Opportunity?
    let onCompleted: (Opportunity) -> Void

    @State private var sheetLead: Opportunity?
    @State private var idempotencyKeys = LeadDispositionIdempotencyKeys()

    func body(content: Content) -> some View {
        content
            .onChange(of: target?.id) { _, newID in
                guard newID != nil, let lead = target else { return }
                target = nil
                sheetLead = lead
            }
            .sheet(item: $sheetLead) { lead in
                LeadArchiveSheet(
                    opportunity: lead,
                    onArchive: { reason, note in
                        await archive(lead, reason: reason, note: note)
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }

    @MainActor
    private func archive(
        _ lead: Opportunity,
        reason: LeadArchiveReason?,
        note: String?
    ) async -> Bool {
        let repo = OpportunityRepository(companyId: lead.companyId)
        let idempotencyKey = idempotencyKeys.applyKey(
            for: lead.id,
            make: { "lead-archive:\(UUID().uuidString.lowercased())" }
        )

        do {
            let result = try await repo.applyLeadArchive(
                opportunityId: lead.id,
                reason: reason,
                note: note,
                idempotencyKey: idempotencyKey
            )
            idempotencyKeys.completeApply(for: lead.id)
            LeadArchiveLocalState.apply(result, to: lead)
            finish(lead)
            presentUndoableSuccess(result, for: lead)
            return true
        } catch {
            guard LeadArchiveCapability.shouldFallBackToLegacyArchive(forRPCError: error) else {
                ToastCenter.shared.present(
                    Toast(label: "// COULD NOT ARCHIVE · TRY AGAIN", tone: .error)
                )
                return false
            }
            // Pre-migration server: archive still has to work.
            do {
                try await repo.archive(lead.id)
                idempotencyKeys.completeApply(for: lead.id)
                lead.archivedAt = Date()
                finish(lead)
                ToastCenter.shared.present(Feedback.Lead.archived)
                return true
            } catch {
                ToastCenter.shared.present(
                    Toast(label: "// COULD NOT ARCHIVE · TRY AGAIN", tone: .error)
                )
                return false
            }
        }
    }

    @MainActor
    private func finish(_ lead: Opportunity) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        NotificationCenter.default.post(
            name: Notification.Name("LeadArchivedSuccess"),
            object: nil,
            userInfo: ["leadId": lead.id]
        )
        onCompleted(lead)
    }

    @MainActor
    private func presentUndoableSuccess(
        _ result: LeadArchiveResult,
        for lead: Opportunity
    ) {
        ToastCenter.shared.present(
            Toast(
                label: "// LEAD ARCHIVED",
                tone: .warning,
                autoDismissAfter: 6,
                action: ToastAction(label: "UNDO") {
                    Task { await undo(result, for: lead) }
                }
            )
        )
    }

    @MainActor
    private func undo(_ applied: LeadArchiveResult, for lead: Opportunity) async {
        let idempotencyKey = idempotencyKeys.undoKey(
            for: applied.feedbackId,
            make: { "lead-archive-undo:\(UUID().uuidString.lowercased())" }
        )
        do {
            let result = try await OpportunityRepository(companyId: lead.companyId)
                .undoLeadArchive(
                    feedbackId: applied.feedbackId,
                    idempotencyKey: idempotencyKey
                )
            idempotencyKeys.completeUndo(for: applied.feedbackId)
            LeadArchiveLocalState.applyUndo(result, to: lead)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationCenter.default.post(
                name: Notification.Name("LeadUpdatedSuccess"),
                object: nil,
                userInfo: ["leadId": lead.id]
            )
            ToastCenter.shared.present(
                Toast(label: "// LEAD RESTORED", tone: .success)
            )
        } catch {
            ToastCenter.shared.present(
                Toast(
                    label: "// COULD NOT UNDO · LEAD MAY HAVE CHANGED",
                    tone: .error,
                    autoDismissAfter: 0,
                    action: ToastAction(label: "RETRY") {
                        Task { await undo(applied, for: lead) }
                    }
                )
            )
        }
    }
}
