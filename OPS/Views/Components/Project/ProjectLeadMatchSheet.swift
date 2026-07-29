//
//  ProjectLeadMatchSheet.swift
//  OPS
//
//  Bug a3c4e216 — the project side of lead matching.
//
//  Picks the won, unconverted lead this project came from and commits the link
//  through the canonical guarded conversion (`linkToProjectId` = this
//  project). Never a direct patch: the four-column link contract, the
//  disposition audit row, and the estimate / task / photo carryover all belong
//  to that one transaction.
//
//  Candidates are restricted to leads at this project's address, because the
//  RPC rejects anything else — the picker must not offer a choice the commit
//  will refuse.
//

import SwiftUI
import SwiftData

struct ProjectLeadMatchSheet: View {
    let project: Project
    let candidates: [Opportunity]

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedLeadId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                        provenanceNote
                        ForEach(candidates) { lead in
                            leadRow(lead)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing1)
                    .padding(.bottom, 160)
                }
                .scrollIndicators(.hidden)
            }

            footer
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            SheetTitleLabel(title: "MATCH LEAD", size: .full)
            SheetCloseButton { dismiss() }
        }
        .padding(.leading, OPSStyle.Layout.spacing3_5)
        .padding(.trailing, 6)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing1)
    }

    private var provenanceNote: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("// ")
                .foregroundColor(OPSStyle.Colors.textMute)
            Text("Won leads at this address that have not been converted yet. Matching marks the lead won against this project and carries its estimates, tasks and photos across.")
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .font(OPSStyle.Typography.miniLabel)
        .kerning(0.4)
        .lineSpacing(2)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
        )
    }

    // MARK: - Rows

    private func leadRow(_ lead: Opportunity) -> some View {
        let isSelected = selectedLeadId == lead.id

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedLeadId = isSelected ? nil : lead.id
            errorMessage = nil
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(displayTitle(for: lead))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(lead.shortDisplayId)
                            .monospacedDigit()
                        if let value = lead.actualValue ?? lead.estimatedValue, value > 0 {
                            Text("·")
                            Text(BooksFormat.currency(value))
                                .monospacedDigit()
                        }
                    }
                    .font(OPSStyle.Typography.miniLabel)
                    .kerning(1.0)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .textCase(.uppercase)
                }

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.oliveTextM)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                    .fill(isSelected ? OPSStyle.Colors.oliveFillM : OPSStyle.Colors.surfaceHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                    .strokeBorder(isSelected ? OPSStyle.Colors.oliveLineM : OPSStyle.Colors.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isSaving)
        .accessibilityLabel(
            isSelected
                ? "Selected lead \(displayTitle(for: lead))"
                : "Select lead \(displayTitle(for: lead))"
        )
    }

    private func displayTitle(for lead: Opportunity) -> String {
        let title = lead.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        let contact = lead.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !contact.isEmpty { return contact }
        return lead.address ?? "Untitled lead"
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Spacer()
            if let errorMessage {
                SheetStatusLine(mode: .error(errorMessage))
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            } else if isSaving {
                SheetStatusLine(mode: .syncing)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }

            SheetFooterButtonRow {
                SheetCTAButton(
                    label: "CANCEL",
                    variant: .secondary,
                    action: { dismiss() }
                )
                .disabled(isSaving)
            } primary: {
                SheetCTAButton(
                    label: "MATCH LEAD",
                    icon: "arrow.right",
                    variant: .primary,
                    isLoading: isSaving,
                    action: commit
                )
                .disabled(selectedLeadId == nil || isSaving)
                .opacity(selectedLeadId == nil || isSaving ? 0.5 : 1)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, 28)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.95),
                    .black,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .allowsHitTesting(false),
            alignment: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Commit

    private func commit() {
        guard let selectedLeadId,
              let lead = candidates.first(where: { $0.id == selectedLeadId }),
              !isSaving else { return }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                let service = LeadConversionService(
                    companyId: lead.companyId,
                    modelContext: modelContext
                )
                let outcome = try await service.convertOpportunityToProject(
                    lead: lead,
                    actualValue: lead.actualValue,
                    titleOverride: nil,
                    notes: nil,
                    linkToProjectId: project.id,
                    userId: dataController.currentUser?.id
                )

                let linkedProjectId: String
                switch outcome {
                case .project(let linked):
                    linkedProjectId = linked.id
                case .committedWithKnownProject(let projectId):
                    linkedProjectId = projectId
                case .committedWithoutAccessibleProject:
                    // The operator is standing ON this project, so it is
                    // demonstrably theirs to see. Use the id we came in with.
                    linkedProjectId = project.id
                }

                lead.stage = .won
                lead.projectId = linkedProjectId
                lead.stageEnteredAt = Date()
                lead.stageManuallySet = true
                LeadConversionVisibilityStore.shared.clear(lead.id)

                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Revives the orphaned channel LeadsTabView and
                // ClientLeadsSection have observed since the 07-22 work landed
                // without anything ever posting it.
                NotificationCenter.default.post(
                    name: Notification.Name("LeadLinkedProjectSuccess"),
                    object: nil,
                    userInfo: [
                        "leadId": lead.id,
                        "projectId": linkedProjectId,
                    ]
                )
                dismiss()
            } catch {
                isSaving = false
                errorMessage = simplifyError(error)
            }
        }
    }

    private func simplifyError(_ error: Error) -> String {
        if let conversionError = error as? LeadConversionError {
            switch conversionError {
            case .opportunityNotFound:   return "LEAD NOT FOUND"
            case .accessDenied:          return "PERMISSION DENIED"
            case .assignmentChanged:     return "ASSIGNMENT CHANGED — REFRESH"
            case .leadChanged:           return "LEAD CHANGED — REFRESH"
            case .projectLinkUnavailable(let reason):
                return ConvertToProjectSheet.projectLinkFailureCopy(reason)
            case .unverifiedResult:      return "MATCH NOT VERIFIED — REFRESH"
            }
        }
        let description = String(describing: error).lowercased()
        if description.contains("network") || description.contains("offline") {
            return "CHECK CONNECTION — RETRY"
        }
        return "COULD NOT MATCH — TAP TO RETRY"
    }
}
