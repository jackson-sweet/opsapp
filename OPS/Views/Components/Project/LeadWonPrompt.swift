//
//  LeadWonPrompt.swift
//  OPS
//
//  D3 of the lead-identity design (bible:
//  specs/plans/2026-08-18-lead-project-identity-design.md) — bug 9a89b951.
//
//  A lead-linked project entering an active status PROPOSES winning its lead;
//  the app asks; a human decides. Until now the database trigger won the lead
//  silently on any active-status write, stamping stage_manually_set = true (a
//  flag that claims a human did it) and a stage transition with no actor. That
//  silent win is also why declining was impossible — there was no moment at
//  which anyone was asked. The trigger surgery
//  (project_opportunity_link_stop_stage_side_effect) removes the side effect,
//  and this prompt becomes the only path that wins a linked lead outside
//  conversion.
//
//  One choke point feeds it — DataController.updateProjectStatus, human writes
//  only — and one root-mounted OPSConfirm presents it (MainTabView, beside
//  .toastHost()). Task-driven auto-advance never asks: the actor there is a
//  crew member starting work, not an operator making a pipeline decision.
//
//  Evaluation verifies against the SERVER row. The local Opportunity cache is
//  pipeline-fed and can be stale or absent for a user who never opens the Leads
//  tab, and proposing a win from a stale row would be the app asserting
//  something it does not know. So the prompt does not fire offline; the next
//  qualifying status change re-evaluates, which is honest behaviour for a write
//  that is online-only anyway.
//

import Foundation
import SwiftUI
import SwiftData
import UIKit

/// Everything the confirm needs, resolved before it is shown.
struct LeadWonProposal: Identifiable, Equatable {
    let id = UUID()
    let opportunityId: String
    let projectId: String
    let companyId: String
    /// Job-first label, the LeadDetail precedent: title, else contact name.
    let leadLabel: String
    let userId: String
}

/// Pure decision core — unit-tested. Fetch and permission arrive as inputs, so
/// the rule can be read and asserted without a network or a store.
enum LeadWonPromptEvaluator {
    /// Project statuses that propose a win. D3: reaching ANY active status is
    /// the signal, because a job that is being worked was won, whichever door
    /// the operator walked through to say so.
    static let proposingStatuses: Set<Status> = [.accepted, .inProgress, .completed, .closed]

    static func proposal(
        newStatus: Status,
        projectId: String,
        companyId: String,
        opportunityId: String?,
        userId: String?,
        canEditLead: (_ assignedTo: String?) -> Bool,
        serverRow: OpportunityDTO?
    ) -> LeadWonProposal? {
        guard proposingStatuses.contains(newStatus) else { return nil }
        guard let oid = opportunityId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              !oid.isEmpty else { return nil }
        guard let userId, !userId.isEmpty else { return nil }
        // Offline, or a row this viewer cannot even read: say nothing rather
        // than guess. The next qualifying status change re-evaluates.
        guard let row = serverRow else { return nil }
        // Asked once, answered once.
        guard row.wonPromptDeclinedAt == nil else { return nil }
        let stage = PipelineStage(rawValue: row.stage)
        guard stage != .won, stage != .lost, stage != .discarded else { return nil }
        // Never surface an action the viewer cannot take.
        guard canEditLead(row.assignedTo) else { return nil }

        let label = nonBlank(row.title) ?? nonBlank(row.contactName) ?? "this lead"

        return LeadWonProposal(
            opportunityId: oid,
            projectId: projectId.lowercased(),
            companyId: companyId,
            leadLabel: label,
            userId: userId.lowercased()
        )
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// App-wide presenter, the ToastCenter pattern. Publishes at most one pending
/// proposal; the root-mounted modifier renders it as the house confirm.
@MainActor
final class LeadWonPromptCenter: ObservableObject {
    static let shared = LeadWonPromptCenter()

    @Published var pending: LeadWonProposal?
    private weak var dataController: DataController?

    /// Called from `DataController.updateProjectStatus` — human writes only.
    func propose(project: Project, newStatus: Status, dataController: DataController) {
        self.dataController = dataController

        guard LeadWonPromptEvaluator.proposingStatuses.contains(newStatus) else { return }
        guard let opportunityId = project.opportunityId?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !opportunityId.isEmpty else { return }

        let projectId = project.id
        let companyId = project.companyId
        guard !companyId.isEmpty else { return }

        let userId = dataController.currentUser?.id
            ?? SupabaseService.shared.currentUserId
            ?? UserDefaults.standard.string(forKey: "currentUserId")

        Task { [weak self] in
            let repository = OpportunityRepository(companyId: companyId)
            let row = try? await repository.fetchOne(opportunityId.lowercased())
            guard let self else { return }
            let proposal = LeadWonPromptEvaluator.proposal(
                newStatus: newStatus,
                projectId: projectId,
                companyId: companyId,
                opportunityId: opportunityId,
                userId: userId,
                canEditLead: { assignedTo in
                    PermissionStore.shared.leadAccessPolicy.can(.edit, assignedTo: assignedTo)
                },
                serverRow: row
            )
            if let proposal {
                self.publishWhenPresentationClear(proposal)
            }
        }
    }

    /// The status sheet dismisses itself shortly after saving, and a root-level
    /// alert raised while that sheet (or the completion checklist) is still up
    /// is dropped by SwiftUI. Wait for the presentation stack to clear, and cap
    /// the wait so a stuck sheet can only DELAY the ask, never swallow it.
    private func publishWhenPresentationClear(_ proposal: LeadWonProposal, attempt: Int = 0) {
        let presented = UIApplication.shared.rootViewController?.presentedViewController
        if presented == nil || attempt >= 16 {
            pending = proposal
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.publishWhenPresentationClear(proposal, attempt: attempt + 1)
            }
        }
    }

    func confirm(_ proposal: LeadWonProposal) {
        Task { @MainActor in
            do {
                let repository = OpportunityRepository(companyId: proposal.companyId)
                _ = try await repository.winLinkedOpportunity(
                    opportunityId: proposal.opportunityId,
                    projectId: proposal.projectId,
                    userId: proposal.userId
                )

                // Keep any cached local row honest immediately — the pipeline
                // refetch will confirm it. The ConvertToProjectSheet precedent.
                if let context = dataController?.modelContext {
                    let oid = proposal.opportunityId
                    let descriptor = FetchDescriptor<Opportunity>(
                        predicate: #Predicate<Opportunity> { $0.id == oid }
                    )
                    if let local = try? context.fetch(descriptor).first {
                        local.stage = .won
                        try? context.save()
                    }
                }

                NotificationCenter.default.post(name: .opsLeadsDidChange, object: nil)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(Toast(label: "// LEAD MARKED WON", tone: .success))
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                ToastCenter.shared.present(Toast(label: "// LEAD NOT UPDATED — TRY AGAIN", tone: .error))
            }
        }
    }

    func decline(_ proposal: LeadWonProposal) {
        Task {
            // A failed decline write just means we may ask once more later —
            // honest, and better than blocking the operator now over it.
            let repository = OpportunityRepository(companyId: proposal.companyId)
            _ = try? await repository.declineWonPrompt(
                opportunityId: proposal.opportunityId,
                userId: proposal.userId
            )
        }
    }
}

/// Root-mounted host. Sits beside `.toastHost()` on MainTabView so the ask
/// survives whichever screen the status was changed from.
struct LeadWonPromptHost: ViewModifier {
    @ObservedObject private var center = LeadWonPromptCenter.shared
    @State private var confirmConfig: OPSConfirmConfig?

    func body(content: Content) -> some View {
        content
            .opsConfirm($confirmConfig)
            .onReceive(center.$pending) { proposal in
                guard let proposal else { return }
                confirmConfig = OPSConfirmConfig(
                    title: "MARK LEAD WON?",
                    message: "This job came from \(proposal.leadLabel).",
                    verb: "MARK WON",
                    cancelLabel: "KEEP OPEN",
                    onCancel: { LeadWonPromptCenter.shared.decline(proposal) },
                    onConfirm: { LeadWonPromptCenter.shared.confirm(proposal) }
                )
                center.pending = nil
            }
    }
}

extension View {
    func leadWonPromptHost() -> some View { modifier(LeadWonPromptHost()) }
}
