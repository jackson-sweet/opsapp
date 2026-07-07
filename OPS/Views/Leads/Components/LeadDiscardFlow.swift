//
//  LeadDiscardFlow.swift
//  OPS
//
//  Shared discard education/confirm router. Both list surfaces (the triage
//  queue and the by-stage list) and the mark-as-lost sheet attach this. It
//  reads the shared `leads_discard_explainer_seen` flag: first run presents the
//  rich `DiscardExplainerSheet`, thereafter a lightweight `.confirmationDialog`
//  ("Discard this lead?"). The host supplies the actual discard via `perform`
//  (VM path vs direct-repo path), keeping this decoupled from either. On
//  success it fires the success haptic + `// LEAD DISCARDED` toast +
//  `LeadDiscardedSuccess` notification, then `onDiscarded`.
//

import SwiftUI

extension View {
    /// Attaches the discard education/confirm flow. Set `target` to a lead to
    /// start it; the modifier clears `target`, routes to the explainer (first
    /// run) or the quick confirm (repeat), runs `perform`, then fires feedback
    /// and `onDiscarded`.
    func leadDiscardFlow(
        target: Binding<Opportunity?>,
        perform: @escaping (Opportunity) async throws -> Void,
        onDiscarded: @escaping (Opportunity) -> Void = { _ in }
    ) -> some View {
        modifier(LeadDiscardFlow(target: target, perform: perform, onDiscarded: onDiscarded))
    }
}

private struct LeadDiscardFlow: ViewModifier {
    @Binding var target: Opportunity?
    let perform: (Opportunity) async throws -> Void
    let onDiscarded: (Opportunity) -> Void

    @AppStorage("leads_discard_explainer_seen") private var explainerSeen = false
    @State private var explainerLead: Opportunity?
    @State private var confirmLead: Opportunity?

    func body(content: Content) -> some View {
        content
            .onChange(of: target?.id) { _, newID in
                guard newID != nil, let lead = target else { return }
                target = nil
                if explainerSeen {
                    confirmLead = lead
                } else {
                    explainerLead = lead
                }
            }
            .sheet(item: $explainerLead) { lead in
                DiscardExplainerSheet(opportunity: lead, onConfirm: { await run(lead) })
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
                Button("DISCARD", role: .destructive) { Task { await run(lead) } }
                Button("CANCEL", role: .cancel) {}
            } message: { _ in
                Text("Comes off your board. Never counts as a lost deal.")
            }
    }

    private func run(_ lead: Opportunity) async {
        do {
            try await perform(lead)
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(Feedback.Lead.discarded)
                NotificationCenter.default.post(
                    name: Notification.Name("LeadDiscardedSuccess"),
                    object: nil,
                    userInfo: ["leadId": lead.id]
                )
                onDiscarded(lead)
            }
        } catch {
            await MainActor.run {
                ToastCenter.shared.present(Toast(label: "// COULD NOT DISCARD", tone: .error))
            }
        }
    }
}
