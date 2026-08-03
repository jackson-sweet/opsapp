//
//  LeadDiscardFlow.swift
//  OPS
//
//  One guarded disposition path for every lead surface. The server chooses the
//  Phase C gate, derives actor/company/source evidence, records the feedback,
//  and applies the canonical lifecycle result atomically. The client renders
//  the authoritative receipt and offers an idempotent Undo.
//

import SwiftUI

extension View {
    func leadDiscardFlow(
        target: Binding<Opportunity?>,
        onCompleted: @escaping (Opportunity, LeadDispositionResult) -> Void = { _, _ in }
    ) -> some View {
        modifier(
            LeadDiscardFlow(
                target: target,
                onCompleted: onCompleted
            )
        )
    }
}

private struct LeadDiscardFlow: ViewModifier {
    @Binding var target: Opportunity?
    let onCompleted: (Opportunity, LeadDispositionResult) -> Void

    @AppStorage("leads_discard_explainer_seen") private var explainerSeen = false
    @State private var reasonLead: Opportunity?
    @State private var explainerLead: Opportunity?
    @State private var confirmLead: Opportunity?
    @State private var isRouting = false
    @State private var idempotencyKeys = LeadDispositionIdempotencyKeys()

    func body(content: Content) -> some View {
        content
            .onChange(of: target?.id) { _, newID in
                guard newID != nil, let lead = target, !isRouting else { return }
                target = nil
                Task { await route(lead) }
            }
            .sheet(item: $reasonLead) { lead in
                LeadDispositionReasonSheet(
                    opportunity: lead,
                    onSelect: { reason, note in
                        await apply(reason: reason, note: note, to: lead)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $explainerLead) { lead in
                DiscardExplainerSheet(
                    opportunity: lead,
                    onConfirm: {
                        await apply(reason: .legacyUnspecified, note: nil, to: lead)
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "Discard this lead?",
                isPresented: Binding(
                    get: { confirmLead != nil },
                    set: { if !$0 { confirmLead = nil } }
                ),
                titleVisibility: .visible,
                presenting: confirmLead
            ) { lead in
                Button("DISCARD", role: .destructive) {
                    Task {
                        if await apply(reason: .legacyUnspecified, note: nil, to: lead) {
                            confirmLead = nil
                        }
                    }
                }
                Button("CANCEL", role: .cancel) {}
            } message: { _ in
                Text("Comes off your board. Never counts as a lost deal.")
            }
    }

    @MainActor
    private func route(_ lead: Opportunity) async {
        isRouting = true
        defer { isRouting = false }

        let route: LeadDispositionInteractionRoute
        do {
            let context = try await OpportunityRepository(companyId: lead.companyId)
                .fetchLeadDispositionContext(opportunityId: lead.id)
            route = LeadDispositionInteractionPolicy.route(
                phaseCEnabled: context.phaseCEnabled,
                explainerSeen: explainerSeen
            )
        } catch {
            // The gate could not be read — offline, or the RPC failed. Discard
            // still has to work in the field, so fall through to the legacy
            // path rather than stranding the operator on an error toast. The
            // apply RPC re-checks the gate under the row lock regardless, so
            // this can never smuggle a structured reason past a disabled
            // company.
            route = LeadDispositionInteractionPolicy.routeWhenContextUnavailable(
                explainerSeen: explainerSeen
            )
        }

        switch route {
        case .structuredReason:
            reasonLead = lead
        case .legacyExplainer:
            explainerLead = lead
        case .legacyConfirmation:
            confirmLead = lead
        }
    }

    @MainActor
    private func apply(
        reason: LeadDispositionReason,
        note: String?,
        to lead: Opportunity
    ) async -> Bool {
        let idempotencyKey = idempotencyKeys.applyKey(for: lead.id)
        do {
            let result = try await OpportunityRepository(companyId: lead.companyId)
                .applyLeadDisposition(
                    opportunityId: lead.id,
                    reason: reason,
                    note: note,
                    idempotencyKey: idempotencyKey
                )
            idempotencyKeys.completeApply(for: lead.id)
            LeadDispositionLocalState.apply(result, to: lead)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            presentSuccess(result, for: lead)
            onCompleted(lead, result)
            return true
        } catch {
            ToastCenter.shared.present(
                Toast(label: "// COULD NOT UPDATE LEAD · TRY AGAIN", tone: .error)
            )
            return false
        }
    }

    @MainActor
    private func presentSuccess(
        _ result: LeadDispositionResult,
        for lead: Opportunity
    ) {
        let label: String
        switch result.outcome {
        case .discarded:
            label = "// LEAD DISCARDED"
        case .lost:
            label = "// MARKED LOST"
        case .duplicateReview:
            label = "// DUPLICATE HELD FOR REVIEW"
        case .reviewDeferred:
            label = "// HELD FOR REVIEW"
        }

        ToastCenter.shared.present(
            Toast(
                label: label,
                tone: .warning,
                autoDismissAfter: 6,
                action: ToastAction(label: "UNDO") {
                    Task { await undo(result, for: lead) }
                }
            )
        )
    }

    @MainActor
    private func undo(
        _ appliedResult: LeadDispositionResult,
        for lead: Opportunity
    ) async {
        let idempotencyKey = idempotencyKeys.undoKey(for: appliedResult.feedbackId)
        do {
            let result = try await OpportunityRepository(companyId: lead.companyId)
                .undoLeadDisposition(
                    feedbackId: appliedResult.feedbackId,
                    idempotencyKey: idempotencyKey
                )
            idempotencyKeys.completeUndo(for: appliedResult.feedbackId)
            LeadDispositionLocalState.applyUndo(result, to: lead)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                        Task { await undo(appliedResult, for: lead) }
                    }
                )
            )
        }
    }
}
