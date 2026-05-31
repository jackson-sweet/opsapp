//
//  EditLeadSheet.swift
//  OPS
//
//  Full-detent sheet for editing an existing pipeline opportunity. Phase 4 of
//  the LEADS tab rebuild
//  (docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md §8.4).
//
//  Renders the same `LeadFormView` as AddLeadSheet, pre-filled from the
//  opportunity, with a danger-zone block (archive + delete) appended.
//
//    [×]            // EDIT · <id-prefix>
//    [form scroller — pre-filled]
//    [DANGER ZONE]   [ARCHIVE]  [DELETE]
//    [SYNCING… / ERROR — …]
//    [CANCEL] [SAVE →]
//

import SwiftUI

struct EditLeadSheet: View {
    let opportunity: Opportunity

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var form: LeadForm
    @State private var isSaving = false
    @State private var isArchiving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false

    init(opportunity: Opportunity) {
        self.opportunity = opportunity
        _form = State(initialValue: LeadForm(from: opportunity))
    }

    private var canSave: Bool {
        !form.contactName.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSaving
            && !isArchiving
    }

    private var titleText: String {
        let prefix = String(opportunity.id.prefix(6)).uppercased()
        return "EDIT · \(prefix)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        LeadFormView(
                            form: $form,
                            isEdit: true,
                            onArchive: archive,
                            onDelete: { showDeleteConfirm = true }
                        )
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
        .interactiveDismissDisabled(isSaving || isArchiving)
        .confirmationDialog(
            "Delete this lead?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("DELETE", role: .destructive) { delete() }
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text("This soft-deletes the lead. It can be restored from the trash.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            SheetTitleLabel(title: titleText, size: .full)
            SheetCloseButton { dismiss() }
        }
        .padding(.leading, 20)
        .padding(.trailing, 6)
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
            } else if isSaving || isArchiving {
                SheetStatusLine(mode: .syncing)
                    .padding(.horizontal, 20)
            }

            SheetFooterButtonRow {
                SheetCTAButton(
                    label: "CANCEL",
                    variant: .secondary,
                    action: { dismiss() }
                )
                .disabled(isSaving || isArchiving)
            } primary: {
                SheetCTAButton(
                    label: "SAVE",
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
                try await performUpdate()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(
                    name: Notification.Name("LeadUpdatedSuccess"),
                    object: nil,
                    userInfo: ["leadId": opportunity.id]
                )
                dismiss()
            } catch {
                isSaving = false
                errorMessage = simplifyError(error)
            }
        }
    }

    private func performUpdate() async throws {
        let trimmedName = form.contactName.trimmingCharacters(in: .whitespaces)
        let companyId = opportunity.companyId
        let repository = OpportunityRepository(companyId: companyId)

        // Full-form patch that emits explicit nulls so clearing a field (e.g.
        // deleting the phone) actually persists. A plain UpdateOpportunityDTO
        // would omit the nil key and silently keep the old value. (review I-12)
        let patch = EditOpportunityPatch(
            title:          form.title.isEmpty   ? nil : form.title,
            contactName:    trimmedName,
            contactEmail:   form.email.isEmpty   ? nil : form.email,
            contactPhone:   form.phone.isEmpty   ? nil : form.phone,
            description:    form.notes.isEmpty   ? nil : form.notes,
            address:        form.address.isEmpty ? nil : form.address,
            estimatedValue: form.estimatedValueDouble,
            source:         form.source,
            priority:       form.priority
        )

        let updatedDTO = try await repository.update(opportunity.id, patch: patch)

        // Apply the field update to the local cache (the update() above
        // succeeded).
        let fresh = updatedDTO.toModel()
        opportunity.title = fresh.title
        opportunity.contactName = fresh.contactName
        opportunity.contactEmail = fresh.contactEmail
        opportunity.contactPhone = fresh.contactPhone
        opportunity.descriptionText = fresh.descriptionText
        opportunity.address = fresh.address
        opportunity.estimatedValue = fresh.estimatedValue
        opportunity.source = fresh.source
        opportunity.priority = fresh.priority
        opportunity.updatedAt = fresh.updatedAt

        // Stage change is a separate RPC. Skip it entirely for a terminal
        // (won/lost/discarded) lead: the STAGE chip group can't represent
        // terminal stages, so LeadForm coerces them to .newLead and a diff is
        // spurious — firing it would silently revive a closed deal (review
        // C-11). For a genuine open-stage move, do NOT swallow the RPC error
        // (review W-6): let it propagate so save() surfaces it and the local
        // stage is left untouched on failure (never shows a false stage).
        if !opportunity.stage.isTerminal && form.stage != opportunity.stage {
            _ = try await repository.moveToStage(
                opportunityId: opportunity.id,
                to: form.stage,
                userId: dataController.currentUser?.id
            )
            opportunity.stage = form.stage
            opportunity.stageEnteredAt = Date()
            opportunity.stageManuallySet = true
        }
    }

    // MARK: - Archive

    private func archive() {
        errorMessage = nil
        isArchiving = true
        Task {
            do {
                let companyId = opportunity.companyId
                try await OpportunityRepository(companyId: companyId)
                    .archive(opportunity.id)
                opportunity.archivedAt = Date()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(
                    name: Notification.Name("LeadArchivedSuccess"),
                    object: nil,
                    userInfo: ["leadId": opportunity.id]
                )
                dismiss()
            } catch {
                isArchiving = false
                errorMessage = simplifyError(error)
            }
        }
    }

    // MARK: - Delete

    private func delete() {
        errorMessage = nil
        isArchiving = true
        Task {
            do {
                let companyId = opportunity.companyId
                try await OpportunityRepository(companyId: companyId)
                    .softDelete(opportunity.id)
                opportunity.deletedAt = Date()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(
                    name: Notification.Name("LeadDeletedSuccess"),
                    object: nil,
                    userInfo: ["leadId": opportunity.id]
                )
                dismiss()
            } catch {
                isArchiving = false
                errorMessage = simplifyError(error)
            }
        }
    }

    private func simplifyError(_ error: Error) -> String {
        let description = String(describing: error).lowercased()
        if description.contains("network") || description.contains("offline") {
            return "OFFLINE — TAP TO RETRY"
        }
        if description.contains("permission") || description.contains("denied") {
            return "PERMISSION DENIED"
        }
        return "COULD NOT SAVE — TAP TO RETRY"
    }
}
