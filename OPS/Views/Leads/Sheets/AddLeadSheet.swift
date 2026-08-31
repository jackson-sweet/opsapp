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
import Contacts

struct AddLeadSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    var onSaved: (Opportunity) -> Void = { _ in }
    var onStartSiteVisit: ((Opportunity) -> Void)? = nil

    @State private var form: LeadForm

    /// `seedClient` pre-fills the form for a lead created from a client's page
    /// and binds that client's id directly on save (no fuzzy name match). It
    /// seeds `linkedClient`, so such a sheet simply OPENS in the bound state
    /// the source rows lead to — one state machine, not two. Existing call
    /// sites keep working via the defaulted parameters.
    init(seedClient: Client? = nil,
         onSaved: @escaping (Opportunity) -> Void = { _ in },
         onStartSiteVisit: ((Opportunity) -> Void)? = nil) {
        self.onSaved = onSaved
        self.onStartSiteVisit = onStartSiteVisit
        _form = State(initialValue: seedClient.map { LeadForm(fromClient: $0) } ?? LeadForm())
        _linkedClient = State(initialValue: seedClient)
    }
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveAction: AddLeadSaveAction = .saveOnly

    // Bug 55f40233 — where a new lead's identity comes from. The two source
    // rows answer different questions (the device address book vs the OPS
    // client base), so they do not collapse into one entry point; both vanish
    // behind a single bound chip the moment a client is actually linked.
    /// The client this lead will be written against. Non-nil ⇒ bound: the save
    /// path uses this id directly instead of resolving one by name.
    @State private var linkedClient: Client?
    @State private var showingClientPicker = false
    @State private var showingContactImport = false

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
                        if let linkedClient {
                            boundClientChip(linkedClient)
                        } else {
                            sourceRows
                        }
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
        .sheet(isPresented: $showingClientPicker) {
            ClientPickerSheet(
                currentClientId: linkedClient?.id,
                companyId: dataController.currentUser?.companyId ?? "",
                context: .leadSeed,
                onSelect: { client in
                    linkedClient = client
                    form.adoptClient(client)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            )
            .environmentObject(dataController)
        }
        // NEVER `.sheet` — CNContactPickerViewController retires itself, and a
        // SwiftUI dismissal afterwards lands on the next modal up the chain
        // (bug 5d5df5b0). An invisible background anchor cannot do that.
        .background(
            ContactPicker(isPresented: $showingContactImport) { contact in
                // Value-typed application — never three inouts into one
                // struct, which is a Swift exclusivity violation. Import does
                // NOT bind a client: none exists yet, and the save path
                // resolves or creates one from the filled fields.
                form = ContactLeadFill.from(contact).applied(to: form)
            }
        )
    }

    // MARK: - Identity source (bug 55f40233)

    private var sourceRows: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            sourceRow(
                icon: "person.crop.circle.badge.plus",
                label: "IMPORT FROM CONTACTS",
                accessibility: "Import from phone contacts"
            ) { showingContactImport = true }
            sourceRow(
                icon: "person.text.rectangle",
                label: "USE EXISTING CLIENT",
                accessibility: "Use an existing client"
            ) { showingClientPicker = true }
        }
    }

    /// The capture panel's row chrome. Deliberately NOT shared cross-file —
    /// the pattern is the contract, each surface owns its copy (LeadFormView's
    /// scoping doctrine).
    private func sourceRow(
        icon: String,
        label: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(label)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetMin)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    /// Bound state — the operator's current reality, not every possible one.
    /// Unlinking keeps the prefilled fields: clearing text a human just
    /// reviewed is the app forgetting what it was told. Only the binding drops
    /// (the save then falls back to match-or-create by name).
    private func boundClientChip(_ client: Client) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(OPSStyle.Colors.oliveTextM)
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name.uppercased())
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
                Text("EXISTING CLIENT · LEAD WILL LINK")
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            Spacer(minLength: 0)
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                linkedClient = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unlink client")
        }
        .padding(.leading, OPSStyle.Layout.spacing3)
        // minHeight, not a fixed height: this chip carries a second line the
        // capture panel's does not, so a long client name grows instead of
        // clipping.
        .frame(minHeight: OPSStyle.Layout.inputHeight)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.oliveLineM, lineWidth: OPSStyle.Layout.Border.standard)
        )
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
            OPSStyle.Layout.Gradients.footerFloor
                .frame(height: OPSStyle.Layout.footerFloorHeight)
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
        if let linkedClient {
            clientId = linkedClient.id
        } else {
            let resolved = await resolveClient(companyId: companyId, name: trimmedName)
            clientId = resolved.id

            // Bug 13c66762 (same race, different surface) — a client created
            // just now exists LOCALLY first, and `create_opportunity_guarded`
            // rejects a lead whose client the server cannot see yet
            // (`client_not_found_in_company`), rolling the whole transaction
            // back. Wait for the parent before writing the child. If the wait
            // runs out the create proceeds and, on failure, stays retryable:
            // the client is durably saved locally and `resolveClient` matches
            // it on the next attempt rather than forking a duplicate.
            if resolved.isNew, let newClientId = resolved.id {
                _ = await ClientServerVisibility.wait(
                    clientId: newClientId,
                    companyId: companyId
                )
            }
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

    /// A resolved client for the lead about to be written, and whether this call
    /// is what created it. Only a brand-new client needs the server-visibility
    /// wait — a matched one is already server-side.
    private struct ResolvedLeadClient {
        let id: String?
        let isNew: Bool
    }

    /// Match-first (phone → email → name) against the local client cache so a
    /// repeat caller links to their existing record instead of forking a
    /// duplicate; otherwise create through `DataController.createClient` — the
    /// durable local-insert + sync-op path, so the client survives offline
    /// even though the lead insert itself needs the network.
    @MainActor
    private func resolveClient(companyId: String, name: String) async -> ResolvedLeadClient {
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
            return ResolvedLeadClient(id: existing.id, isNew: false)
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
            return ResolvedLeadClient(id: try await dataController.createClient(dto: dto), isNew: true)
        } catch {
            print("[ADD_LEAD] client autocreate failed — saving lead unlinked: \(error)")
            return ResolvedLeadClient(id: nil, isNew: false)
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
