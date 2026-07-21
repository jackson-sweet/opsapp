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
import SwiftData

struct AddLeadSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    var onSaved: (Opportunity) -> Void = { _ in }
    var onStartSiteVisit: ((Opportunity) -> Void)? = nil
    private let seedClient: Client?

    @State private var form: LeadForm

    /// `seedClient` pre-fills the form for a lead created from a client's page
    /// and binds that client's id directly on save (no fuzzy name match).
    /// Existing call sites keep working via the defaulted parameters.
    init(seedClient: Client? = nil,
         onSaved: @escaping (Opportunity) -> Void = { _ in },
         onStartSiteVisit: ((Opportunity) -> Void)? = nil) {
        self.seedClient = seedClient
        self.onSaved = onSaved
        self.onStartSiteVisit = onStartSiteVisit
        _form = State(initialValue: seedClient.map { LeadForm(fromClient: $0) } ?? LeadForm())
    }
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveAction: AddLeadSaveAction = .saveOnly

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
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
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
        HStack(spacing: OPSStyle.Layout.spacing2) {
            SheetTitleLabel(title: "NEW LEAD", size: .full)
            SheetCloseButton { dismiss() }
        }
        .padding(.leading, OPSStyle.Layout.spacing3_5)
        .padding(.trailing, 6)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing1)
    }

    // MARK: - Footer

    private var footerOverlay: some View {
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
                if onStartSiteVisit == nil {
                    SheetCTAButton(
                        label: "SAVE LEAD",
                        icon: "checkmark",
                        variant: .primary,
                        isLoading: isSaving,
                        action: { save(.saveOnly) }
                    )
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                } else {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        SheetCTAButton(
                            label: "SAVE",
                            icon: "checkmark",
                            variant: .secondary,
                            isLoading: isSaving && saveAction == .saveOnly,
                            action: { save(.saveOnly) }
                        )
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)

                        SheetCTAButton(
                            label: "VISIT",
                            icon: "camera.viewfinder",
                            variant: .primary,
                            isLoading: isSaving && saveAction == .startSiteVisit,
                            action: { save(.startSiteVisit) }
                        )
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                    }
                }
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
            .frame(height: 160)
            .allowsHitTesting(false),
            alignment: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Save

    private func save(_ action: AddLeadSaveAction) {
        guard canSave else { return }
        saveAction = action
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
                if action == .startSiteVisit, let onStartSiteVisit {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onStartSiteVisit(opportunity)
                    }
                }
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

        // Bug 1d5ab9aa — a saved lead creates (or links) its client, matching
        // the web email/lead-engine behavior. Runs BEFORE the opportunity
        // insert so the row lands with client_id set (the convert RPC carries
        // it onto the project). Never blocks the lead: failure → unlinked.
        // From a client's page, bind THAT client's id directly — no fuzzy match,
        // no duplicate client. Otherwise resolve/create by name as before.
        let clientId: String?
        if let seedClient {
            clientId = seedClient.id
        } else {
            clientId = await resolveClientId(companyId: companyId, name: trimmedName)
        }

        let dto = CreateOpportunityDTO(
            title: form.title.isEmpty ? nil : form.title,
            contactName: trimmedName,
            contactEmail: form.email.isEmpty ? nil : form.email,
            contactPhone: form.phone.isEmpty ? nil : form.phone,
            description: form.notes.isEmpty ? nil : form.notes,
            address: form.address.isEmpty ? nil : form.address,
            estimatedValue: form.estimatedValueDouble,
            source: form.source,
            priority: form.priority,
            expectedCloseDate: nil,
            quoteDeliveryMethod: nil,
            clientId: clientId,
            latitude: form.latitude,
            longitude: form.longitude
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

    /// Match-first (phone → email → name) against the local client cache so a
    /// repeat caller links to their existing record instead of forking a
    /// duplicate; otherwise create through `DataController.createClient` — the
    /// durable local-insert + sync-op path, so the client survives offline
    /// even though the lead insert itself needs the network.
    @MainActor
    private func resolveClientId(companyId: String, name: String) async -> String? {
        let email = form.email.isEmpty ? nil : form.email
        let phone = form.phone.isEmpty ? nil : form.phone

        var clients: [Client] = []
        if let context = dataController.modelContext {
            let cid: String? = companyId
            let descriptor = FetchDescriptor<Client>(
                predicate: #Predicate<Client> { $0.companyId == cid }
            )
            clients = (try? context.fetch(descriptor)) ?? []
        }

        if let existing = LeadClientMatcher.match(in: clients, name: name, email: email, phone: phone) {
            return existing.id
        }

        let dto = SupabaseClientDTO(
            id: UUID().uuidString.lowercased(),   // lowercase at generation — Postgres echoes lowercase uuids
            bubbleId: nil,
            companyId: companyId,
            name: name,
            email: email,
            phoneNumber: phone,
            address: form.address.isEmpty ? nil : form.address,
            latitude: form.latitude,
            longitude: form.longitude,
            notes: nil,
            profileImageUrl: nil,
            deletedAt: nil
        )
        do {
            return try await dataController.createClient(dto: dto)
        } catch {
            print("[ADD_LEAD] client autocreate failed — saving lead unlinked: \(error)")
            return nil
        }
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

private enum AddLeadSaveAction {
    case saveOnly
    case startSiteVisit
}
