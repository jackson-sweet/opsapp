//
//  ProjectLeadRow.swift
//  OPS
//
//  Bug a3c4e216 — "no way to match a project to a lead".
//
//  The 2026-07-22 conversion work shipped LEAD-side matching: standing on a
//  won lead, an operator could link it to an existing project. The PROJECT
//  side — where the bug was actually filed — had no lead UI at all. An
//  operator standing on a project that obviously came from a won lead had
//  nothing to tap, and nothing to tell them the two were unrelated.
//
//  Design decisions, and why:
//
//  · A LEAD row sits with CLIENT, not in a section of its own. Both answer
//    "where did this job come from?", and provenance is one glance, not a
//    content area.
//  · It borrows StatusSection's compact labelled-value grammar, not
//    ClientSection's glass card. Linking a lead happens once per project,
//    ever; a card would give a once-ever action permanent prime real estate.
//  · When there is nothing to match — no candidate leads, or no permission —
//    the row is ABSENT, not an em dash and not a disabled button. An
//    affordance advertising an impossible action is worse than no affordance,
//    and the server only accepts a link whose target shares the lead's
//    address, so most projects genuinely have no candidates.
//  · Committing goes through `LeadConversionService` with `linkToProjectId`,
//    never a direct patch: the four-column link contract, the disposition
//    audit row, and the estimate/task/photo carryover all live inside that one
//    transaction.
//

import SwiftUI
import SwiftData

enum ProjectLeadRow {

    // MARK: - State machine

    enum Presentation: Equatable {
        /// The project knows its lead. Tapping opens the lead.
        case linked(label: String)
        /// Unlinked, with real candidates and the permission to act.
        case match(candidateCount: Int)
        /// Nothing to offer. The row does not render.
        case hidden
    }

    static func presentation(
        opportunityId: String?,
        leadLabel: String?,
        candidateCount: Int,
        canMatch: Bool
    ) -> Presentation {
        if let opportunityId,
           !opportunityId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let name = leadLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .linked(label: name.isEmpty ? "LINKED LEAD" : name)
        }
        if canMatch, candidateCount > 0 {
            return .match(candidateCount: candidateCount)
        }
        return .hidden
    }

    // MARK: - Candidate rule

    /// The project side of a possible link.
    struct ProjectContext: Equatable {
        let companyId: String
        let clientId: String?
        let address: String?
    }

    /// A lead that might belong to this project.
    struct LeadCandidate: Equatable, Identifiable {
        let id: String
        let companyId: String
        let clientId: String?
        let address: String?
        let stage: PipelineStage
        let projectId: String?
        let label: String
    }

    /// Leads this project may legitimately be matched to.
    ///
    /// The address test is the load-bearing one: the conversion RPC refuses a
    /// link whose target project is not at the lead's normalized address, so
    /// offering a same-client lead from a different job site would walk the
    /// operator straight into a rejection. Same normalization the sheet's own
    /// create-address fingerprint uses, so the two agree about what "same
    /// address" means. The client is deliberately NOT a filter — the server
    /// does not require it either — but it orders the result, because when two
    /// leads share an address the one on this project's client is the likelier
    /// answer and should be the first thing the operator reads.
    static func matchableLeads(
        project: ProjectContext,
        leads: [LeadCandidate]
    ) -> [LeadCandidate] {
        let projectAddress = normalized(project.address)
        guard !projectAddress.isEmpty else { return [] }

        let matching = leads.filter { lead in
            guard lead.companyId == project.companyId else { return false }
            guard lead.stage == .won else { return false }
            guard (lead.projectId ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return normalized(lead.address) == projectAddress
        }

        guard let projectClientId = project.clientId, !projectClientId.isEmpty else {
            return matching
        }
        // Stable partition — same-client leads keep their relative order, and
        // so does everything else.
        return matching.filter { $0.clientId == projectClientId }
            + matching.filter { $0.clientId != projectClientId }
    }

    private static func normalized(_ address: String?) -> String {
        ProjectAutoNamer.canonicalizedAddress(address ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

// MARK: - Row view

/// Compact labelled-value row, mirroring `StatusSection`'s grammar.
struct ProjectLeadSection: View {
    let presentation: ProjectLeadRow.Presentation
    let onOpenLead: () -> Void
    let onMatchLead: () -> Void

    var body: some View {
        switch presentation {
        case .hidden:
            EmptyView()
        case .linked(let label):
            row(
                accessory: {
                    AnyView(
                        Text(label)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    )
                },
                accessibilityLabel: "Open lead \(label)",
                action: onOpenLead
            )
        case .match(let candidateCount):
            row(
                accessory: {
                    AnyView(
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Text("MATCH LEAD")
                                .font(OPSStyle.Typography.captionBold)
                                .tracking(0.9)
                                .textCase(.uppercase)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text(String(format: "%02d", min(candidateCount, 99)))
                                .font(OPSStyle.Typography.smallCaption)
                                .monospacedDigit()
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    )
                },
                accessibilityLabel: candidateCount == 1
                    ? "Match this project to its lead. 1 candidate."
                    : "Match this project to its lead. \(candidateCount) candidates.",
                action: onMatchLead
            )
        }
    }

    private func row(
        accessory: @escaping () -> AnyView,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Text("[ LEAD ]")
                        .font(OPSStyle.Typography.smallCaption)
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Spacer(minLength: 12)

                    accessory()

                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(accessibilityLabel)

            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing2)
        }
    }
}
