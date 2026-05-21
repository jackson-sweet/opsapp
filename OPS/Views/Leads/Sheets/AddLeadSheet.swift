//
//  AddLeadSheet.swift
//  OPS
//
//  Full-detent sheet for creating a new pipeline opportunity. Phase 4 of the
//  LEADS tab rebuild (docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md
//  §8.3).
//
//  Renders the shared `LeadFormView` inside an OPS sheet shell:
//
//    [×]            // NEW LEAD
//    [form scroller]
//    [SYNCING… / ERROR — …]   (when save is in-flight or just failed)
//    [CANCEL] [SAVE LEAD →]
//
//  Save calls `OpportunityRepository.create` and posts `LeadCreatedSuccess`
//  so `LeadsTabView` reloads. On failure the sheet stays open and surfaces
//  the error inline — see SheetStatusLine.
//

import SwiftUI

struct AddLeadSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    var onSaved: (Opportunity) -> Void = { _ in }

    @State private var form = LeadForm()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !form.contactName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        LeadFormView(form: $form)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
            }

            footerOverlay
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack {
                SheetCloseButton { dismiss() }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            SheetTitleLabel(title: "NEW LEAD")
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Footer

    private var footerOverlay: some View {
        VStack(spacing: 10) {
            Spacer()
            if let errorMessage {
                SheetStatusLine(mode: .error(errorMessage))
                    .padding(.horizontal, 20)
            } else if isSaving {
                SheetStatusLine(mode: .syncing)
                    .padding(.horizontal, 20)
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
                    label: "SAVE LEAD",
                    icon: "checkmark",
                    variant: .primary,
                    isLoading: isSaving,
                    action: save
                )
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
            }
            .padding(.horizontal, 20)
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
            .frame(height: 160)
            .allowsHitTesting(false),
            alignment: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        errorMessage = nil
        isSaving = true

        Task {
            do {
                let opportunity = try await performCreate()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(
                    name: Notification.Name("LeadCreatedSuccess"),
                    object: nil,
                    userInfo: ["leadId": opportunity.id]
                )
                onSaved(opportunity)
                dismiss()
            } catch {
                isSaving = false
                errorMessage = simplifyError(error)
            }
        }
    }

    private func performCreate() async throws -> Opportunity {
        guard let companyId = dataController.currentUser?.companyId, !companyId.isEmpty else {
            throw AddLeadError.missingCompany
        }
        let trimmedName = form.contactName.trimmingCharacters(in: .whitespaces)
        let dto = CreateOpportunityDTO(
            companyId: companyId,
            title: form.title.isEmpty ? nil : form.title,
            contactName: trimmedName,
            contactEmail: form.email.isEmpty ? nil : form.email,
            contactPhone: form.phone.isEmpty ? nil : form.phone,
            description: form.notes.isEmpty ? nil : form.notes,
            address: form.address.isEmpty ? nil : form.address,
            estimatedValue: form.estimatedValueDouble,
            source: form.source,
            priority: form.priority,
            assignedTo: dataController.currentUser?.id,
            expectedCloseDate: nil,
            quoteDeliveryMethod: nil,
            clientId: nil
        )
        let repository = OpportunityRepository(companyId: companyId)
        let resultDTO = try await repository.create(dto)
        let opp = resultDTO.toModel()

        // If the operator picked a non-default stage, advance the new
        // opportunity into it. The create endpoint always writes the
        // server default (`newLead`); a follow-up moveToStage call writes
        // the stage_transitions row for any other selection.
        if form.stage != .newLead {
            _ = try? await repository.moveToStage(
                opportunityId: opp.id,
                to: form.stage,
                userId: dataController.currentUser?.id
            )
            opp.stage = form.stage
        }
        return opp
    }

    private func simplifyError(_ error: Error) -> String {
        if let addError = error as? AddLeadError {
            return addError.userMessage
        }
        let description = String(describing: error).lowercased()
        if description.contains("network") || description.contains("offline") {
            return "OFFLINE — TAP SAVE TO RETRY"
        }
        if description.contains("permission") || description.contains("denied") {
            return "PERMISSION DENIED"
        }
        return "COULD NOT SAVE — TAP TO RETRY"
    }
}

// MARK: - Errors

private enum AddLeadError: LocalizedError {
    case missingCompany

    var userMessage: String {
        switch self {
        case .missingCompany: return "NO COMPANY ON SESSION"
        }
    }
}
