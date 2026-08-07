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
//  · A LEAD row sits directly under CLIENT inside the project-info card, not
//    in a section of its own. Both answer "where did this job come from?", and
//    provenance is one glance, not a content area.
//  · It renders in the project-info DOCUMENT grammar — `DocRow`, the shared
//    58pt mono label column, `ProjectInfoDoc` type, `InfoActionChip` for the
//    way in — so LEAD reads as one more field of the same document rather than
//    a guest with its own manners. Linking a lead happens once per project,
//    ever; a card of its own would give a once-ever action permanent prime real
//    estate. The card owns the hairline above it — see DetailsTabView.shows(_:).
//  · When there is nothing to match — no eligible won leads, or no permission
//    — the row is ABSENT, not an em dash and not a disabled button. Address
//    and client identity rank likely provenance first; they never hide a valid
//    manual choice.
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

    /// Leads this project may legitimately be matched to. Company, Won state,
    /// and an unused project link are hard gates. Address/client identity are
    /// suggestions only: exact address + client first, then address, then
    /// client, then every remaining eligible lead in stable source order.
    static func matchableLeads(
        project: ProjectContext,
        leads: [LeadCandidate]
    ) -> [LeadCandidate] {
        let projectAddress = normalized(project.address)
        let eligible = leads.filter { lead in
            guard lead.companyId == project.companyId else { return false }
            guard lead.stage == .won else { return false }
            guard (lead.projectId ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return true
        }
        let projectClientId = project.clientId?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return eligible.enumerated().sorted { lhs, rhs in
            let lhsRank = suggestionRank(
                lhs.element,
                projectAddress: projectAddress,
                projectClientId: projectClientId
            )
            let rhsRank = suggestionRank(
                rhs.element,
                projectAddress: projectAddress,
                projectClientId: projectClientId
            )
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }.map(\.element)
    }

    private static func suggestionRank(
        _ lead: LeadCandidate,
        projectAddress: String,
        projectClientId: String?
    ) -> Int {
        let addressMatches = !projectAddress.isEmpty
            && normalized(lead.address) == projectAddress
        let clientMatches = projectClientId?.isEmpty == false
            && lead.clientId == projectClientId
        switch (addressMatches, clientMatches) {
        case (true, true): return 0
        case (true, false): return 1
        case (false, true): return 2
        case (false, false): return 3
        }
    }

    private static func normalized(_ address: String?) -> String {
        ProjectAutoNamer.canonicalizedAddress(address ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

// MARK: - Row view

/// LEAD, as one field of the project-info document (DetailsTabView) — the same
/// `DocRow` anatomy, label column, type and chip shape every other field uses.
/// Separators belong to the card, not here: it draws the hairline above every
/// row it holds from one `shows(_:)` answer, so a row that drew its own rule
/// would double the line under CLIENT.
struct ProjectLeadSection: View {
    let presentation: ProjectLeadRow.Presentation
    let onOpenLead: () -> Void
    let onMatchLead: () -> Void

    var body: some View {
        switch presentation {
        case .hidden:
            EmptyView()

        case .linked(let label):
            // A filled field: the lead's name as the document's value line,
            // tappable to the lead itself, chevron-signalled — identical to the
            // CLIENT row's filled state.
            DocRow(label: "LEAD", labelWidth: ProjectInfoDoc.labelColumnWidth) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onOpenLead()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(label)
                            .font(ProjectInfoDoc.valueFont)
                            .foregroundColor(OPSStyle.Colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        Image(systemName: OPSStyle.Icons.chevronRight)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(OPSStyle.Colors.text3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Open lead \(label)")
            }

        case .match(let candidateCount):
            // An empty field this viewer can fill: the document's invitation
            // chip at the start of the content region, exactly like ASSIGN
            // CLIENT. The count rides beneath as the document's meta line so
            // the operator knows whether the tap ends in one confirmation or a
            // list — it never becomes a second affordance.
            DocRow(label: "LEAD", labelWidth: ProjectInfoDoc.labelColumnWidth) {
                VStack(alignment: .leading, spacing: 6) {
                    InfoActionChip(icon: OPSStyle.Icons.plus, title: "MATCH LEAD") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onMatchLead()
                    }
                    .accessibilityLabel(
                        candidateCount == 1
                            ? "Match this project to its lead. 1 candidate."
                            : "Match this project to its lead. \(candidateCount) candidates."
                    )

                    Text(candidateCount == 1 ? "1 CANDIDATE" : "\(candidateCount) CANDIDATES")
                        .font(ProjectInfoDoc.metaFont)
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.text3)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
