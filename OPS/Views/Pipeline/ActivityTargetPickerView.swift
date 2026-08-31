//
//  ActivityTargetPickerView.swift
//  OPS
//
//  State-aware TARGET picker for the unified activity logger — lets the
//  operator log an activity against a lead, a client, or a job from one
//  searchable list. Generalizes OpportunityPickerView (leads-only) to all
//  three ActivityTarget sources; reuses its exact tokens, row treatment,
//  search field, and "+ New Lead" inline-create affordance verbatim.
//
//  Design judgment: one unified searchable list with a source badge per row
//  is correct — the operator is looking for "the thing I'm logging this
//  against," not choosing a source first. Per-source tabs would force a
//  decision the operator hasn't made yet and can't always answer (is this
//  contact a lead or an existing client?). The badge disambiguates after
//  the fact; it never gates the search.
//

import SwiftUI
import SwiftData
import Contacts

/// Which target sources the picker offers. `.all` is the activity logger's
/// original behavior; `.leadsOnly` serves affordances that can only act on
/// a lead (visit booking).
enum ActivityTargetPickerSources: Equatable {
    case all
    case leadsOnly
}

struct ActivityTargetPickerView: View {
    let companyId: String
    let onSelect: (ActivityTarget) -> Void
    /// Defaulted so the activity logger's existing call site is untouched.
    var sources: ActivityTargetPickerSources = .all

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var allTargets: [ActivityTarget] = []

    // Inline "+ New Lead" state — mirrors OpportunityPickerView / LogActivityViewModel.
    @State private var isCreatingNewLead: Bool = false
    @State private var newLeadName: String = ""
    @State private var newLeadPhone: String = ""
    @State private var newLeadEmail: String = ""
    @State private var isSavingNewLead: Bool = false
    @State private var newLeadError: String?

    /// Bug 55f40233 — the client row currently resolving into a bookable lead.
    /// Non-nil blocks every other row so a double-tap cannot mint two leads.
    @State private var materializingClientId: String?

    // Bug f8951223 — pull the person straight out of the phone's address book
    // instead of retyping them. FILL semantics: nothing is created until the
    // operator commits with CREATE LEAD.
    @State private var showingContactImport = false
    /// The picked contact's postal address. The inline form has no address
    /// input, but a site visit needs somewhere to go — so it rides along to
    /// the created lead and is shown (and clearable) as a quiet mono line.
    @State private var importedAddress: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar — verbatim OpportunityPickerView treatment.
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .font(.system(size: 16))

                TextField(
                    sources == .leadsOnly ? "Search leads or clients..." : "Search leads, clients, jobs...",
                    text: $searchText
                )
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing2_5)

            Divider()
                .padding(.top, OPSStyle.Layout.spacing2_5)

            // Unified target list
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filteredTargets.isEmpty && !isCreatingNewLead {
                        emptyState
                    } else {
                        ForEach(filteredTargets, id: \.rowId) { target in
                            targetRow(target)
                            Divider()
                                .padding(.leading, OPSStyle.Layout.spacing3_5)
                        }
                    }

                    // + New Lead row — leads only, same affordance as OpportunityPickerView.
                    newLeadRow()
                }
            }

            // Client-materialization errors surface here. The inline create
            // form owns its own error line, so this renders only when the
            // disclosure is closed — never two copies of the same message.
            if let newLeadError, !isCreatingNewLead {
                Text(newLeadError)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing2_5)
            }
        }
        .background(OPSStyle.Colors.background)
        .onAppear(perform: loadTargets)
        // NEVER `.sheet` — this picker is itself sheet content over the FAB,
        // and the self-retiring CNContactPickerViewController would trigger
        // the chain-dismissal that killed site visits (bug 5d5df5b0).
        .background(
            ContactPicker(isPresented: $showingContactImport) { contact in
                applyImportedContact(contact)
            }
        )
    }

    // MARK: - Data

    private func loadTargets() {
        var loaded = ActivityTargetLoader.load(companyId: companyId, modelContext: modelContext)
        if case .leadsOnly = sources {
            loaded = loaded.filter(Self.leadsOnlyFilter)
        }
        allTargets = loaded
    }

    /// Visit booking: a repeat customer is as bookable as an open lead —
    /// selecting a client materializes their lead (bug 55f40233). Jobs stay
    /// out: a booking anchors to an opportunity, and a job's own lead is
    /// reachable from the job itself (bug 7d94c9f3).
    static func leadsOnlyFilter(_ target: ActivityTarget) -> Bool {
        switch target {
        case .opportunity, .client: return true
        case .project, .unbound:    return false
        }
    }

    /// The bookable lead among a client's linked leads: the newest still-open
    /// one. WON / LOST / discarded leads are finished business — a repeat
    /// customer booking new work gets a fresh lead instead.
    static func firstOpenLead(in models: [Opportunity]) -> Opportunity? {
        models.first { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }
    }

    /// The lead a repeat customer's booking mints when they hold no open one.
    /// `repeat_client` is both schema-legal (`opportunities_source_check`) and
    /// semantically exact. Title is omitted — the DTO derives it from the
    /// contact name.
    static func materializationDTO(for client: Client) -> CreateOpportunityDTO {
        CreateOpportunityDTO(
            contactName: client.name,
            contactEmail: client.email,
            contactPhone: client.phoneNumber,
            address: client.address,
            source: "repeat_client",
            clientId: client.id,
            latitude: client.latitude,
            longitude: client.longitude
        )
    }

    /// Multi-field lowercase-contains across name/subtitle/source badge,
    /// mirroring `SiteVisitIdentitySuggestion.matches`.
    private var filteredTargets: [ActivityTarget] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return allTargets }
        let query = searchText.lowercased()
        return allTargets.filter { target in
            [target.displayName, target.subtitle, target.sourceBadge]
                .contains { $0?.lowercased().contains(query) == true }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("—")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(searchText.isEmpty
                 ? (sources == .leadsOnly ? "NO LEADS OR CLIENTS" : "NO LEADS, CLIENTS, OR JOBS")
                 : "NO MATCHES")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }

    // MARK: - Target Row

    @ViewBuilder
    private func targetRow(_ target: ActivityTarget) -> some View {
        Button {
            select(target)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                // Initial circle — same treatment as OpportunityPickerView's contact avatar.
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.background)
                        .frame(width: 40, height: 40)
                    Text(String(target.displayName.prefix(1)).uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    if let subtitle = target.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // While a client row is resolving into a bookable lead it owns
                // the trailing slot, so the operator sees exactly which tap is
                // working. Same treatment as the inline create's spinner.
                if isMaterializing(target) {
                    ProgressView()
                        .tint(OPSStyle.Colors.tertiaryText)
                } else if let badge = target.sourceBadge {
                    // Source badge — neutral tag, never accent/earth-tone/green.
                    sourceBadgeView(badge)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(TargetRowButtonStyle())
        .disabled(materializingClientId != nil || isSavingNewLead)
    }

    /// True only for the client row whose lead is being resolved right now.
    private func isMaterializing(_ target: ActivityTarget) -> Bool {
        guard let materializingClientId,
              case .client(let client) = target else { return false }
        return client.id == materializingClientId
    }

    /// Neutral source-disambiguation tag: JetBrains Mono, text3-on-line —
    /// the same neutral-badge language SiteVisitIdentitySuggestion uses
    /// ("LEAD" / "CLIENT" / "JOB" as plain caption text), formalized here as
    /// a bordered chip so it reads as a tag rather than a data field.
    @ViewBuilder
    private func sourceBadgeView(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.smallCaption)
            .tracking(0.12 * 10)
            .foregroundColor(OPSStyle.Colors.text3)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    // MARK: - New Lead Row (leads only — verbatim OpportunityPickerView pattern)

    @ViewBuilder
    private func newLeadRow() -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(OPSStyle.Animation.panel) {
                    isCreatingNewLead.toggle()
                }
                // Collapsing abandons the draft — the imported address goes
                // with it rather than silently riding the next create.
                if !isCreatingNewLead { importedAddress = "" }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    ZStack {
                        Circle()
                            .fill(OPSStyle.Colors.surfaceInput)
                            .frame(width: 40, height: 40)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    Text("New Lead")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    if isSavingNewLead {
                        ProgressView()
                            .tint(OPSStyle.Colors.tertiaryText)
                    } else {
                        Image(systemName: isCreatingNewLead ? "chevron.up" : "chevron.down")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .font(.system(size: 14))
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSavingNewLead)

            // Inline create form
            if isCreatingNewLead {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                    importFromContactsRow

                    inlineField(text: $newLeadName, placeholder: "Contact name *")
                    inlineField(text: $newLeadPhone, placeholder: "Phone (optional)")
                    inlineField(text: $newLeadEmail, placeholder: "Email (optional)")

                    if !importedAddress.isEmpty {
                        importedAddressLine
                    }

                    if let newLeadError {
                        Text(newLeadError)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    }

                    Button {
                        Task { await createNewLead() }
                    } label: {
                        Text("CREATE LEAD")
                            .font(OPSStyle.Typography.smallButton)
                            .foregroundColor(canCreateNewLead ? OPSStyle.Colors.background : OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .background(canCreateNewLead ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.surfaceInput)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                    }
                    .disabled(!canCreateNewLead || isSavingNewLead)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var canCreateNewLead: Bool {
        !newLeadName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Contact import (bug f8951223)

    /// The capture panel's row chrome, verbatim — one coherent pattern for
    /// "pull this person out of my phone" across every surface that offers it.
    private var importFromContactsRow: some View {
        Button {
            showingContactImport = true
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("IMPORT FROM CONTACTS")
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
        .accessibilityLabel("Import from phone contacts")
    }

    /// A quiet mono line, not a field: the operator cannot type an address
    /// here (the inline form is deliberately three fields), but they must see
    /// what will ride onto the lead — and be able to drop it.
    private var importedAddressLine: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text("// ADDRESS · \(importedAddress.uppercased())")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                importedAddress = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear imported address")
        }
    }

    /// FILL, never create: only the fields the contact actually carries are
    /// written, so a partly typed form survives an import. Opens the
    /// disclosure if it somehow fired while closed, so the filled values are
    /// never invisible.
    private func applyImportedContact(_ contact: CNContact) {
        let fill = ContactLeadFill.from(contact)
        if !isCreatingNewLead {
            withAnimation(OPSStyle.Animation.panel) { isCreatingNewLead = true }
        }
        fill.apply(name: &newLeadName, phone: &newLeadPhone, email: &newLeadEmail)
        if let address = fill.address { importedAddress = address }
    }

    @ViewBuilder
    private func inlineField(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    // MARK: - Selection

    /// A lead / job / client tap. In the booking lane a CLIENT is not a
    /// bookable target on its own — booking anchors to an opportunity — so the
    /// tap resolves the client to a lead first. Every other case passes
    /// straight through, so the activity logger's behavior is unchanged.
    private func select(_ target: ActivityTarget) {
        if case .client(let client) = target, sources == .leadsOnly {
            guard materializingClientId == nil, !isSavingNewLead else { return }
            Task { await materializeLead(for: client) }
            return
        }
        onSelect(target)
        dismiss()
    }

    /// A client tap in the booking lane resolves to a bookable lead:
    /// the newest OPEN linked lead when one exists (remote-first — the local
    /// cache may be stale), else a fresh `repeat_client` lead bound to the
    /// client. A failed lookup NEVER falls through to create — that is how
    /// duplicate leads are minted, and booking needs signal anyway.
    @MainActor
    private func materializeLead(for client: Client) async {
        materializingClientId = client.id
        newLeadError = nil
        defer { materializingClientId = nil }

        let repository = OpportunityRepository(companyId: companyId)
        let linked: [OpportunityDTO]
        do {
            linked = try await repository.fetchAllLinked(toClientId: client.id)
        } catch {
            newLeadError = "COULD NOT CHECK LEADS FOR \(client.name.uppercased()) — TRY AGAIN"
            return
        }

        if let open = Self.firstOpenLead(in: linked.map { $0.toModel() }) {
            finishSelection(with: open)
            return
        }

        do {
            let created = try await repository.create(Self.materializationDTO(for: client))
            finishSelection(with: created.toModel())
        } catch {
            newLeadError = error.localizedDescription
        }
    }

    /// Upsert-by-id then hand back — blind inserts fork duplicate local rows
    /// (the UUID-case lesson).
    @MainActor
    private func finishSelection(with model: Opportunity) {
        let id = model.id
        var descriptor = FetchDescriptor<Opportunity>(
            predicate: #Predicate<Opportunity> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        let resolved: Opportunity
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            resolved = existing
        } else {
            modelContext.insert(model)
            try? modelContext.save()
            resolved = model
        }
        onSelect(.opportunity(resolved))
        dismiss()
    }

    /// Creates the opportunity server-side (same repository call LogActivityViewModel.save
    /// uses for the voice-log new-lead path), inserts the resulting model locally, then
    /// hands it back through `onSelect` as `.opportunity(newlyCreated)`.
    private func createNewLead() async {
        guard canCreateNewLead else { return }
        isSavingNewLead = true
        newLeadError = nil

        let repository = OpportunityRepository(companyId: companyId)
        let dto = CreateOpportunityDTO(
            contactName: newLeadName.trimmingCharacters(in: .whitespaces),
            contactEmail: newLeadEmail.isEmpty ? nil : newLeadEmail,
            contactPhone: newLeadPhone.isEmpty ? nil : newLeadPhone,
            description: nil,
            // Bug f8951223 — an imported contact's postal address rides onto
            // the lead, so a visit booked from here has somewhere to go.
            address: importedAddress.isEmpty ? nil : importedAddress,
            estimatedValue: nil,
            source: "log_activity",
            quoteDeliveryMethod: nil
        )

        do {
            let created = try await repository.create(dto)
            isSavingNewLead = false
            // Upsert-by-id rather than a blind insert: the create can echo a
            // row this device already holds.
            finishSelection(with: created.toModel())
        } catch {
            isSavingNewLead = false
            newLeadError = error.localizedDescription
        }
    }
}

/// Selection highlight = white surface shift on press, matching the picker's
/// row-tap feedback. Never accent/earth-tone — this is a scan surface, not a
/// status indicator.
private struct TargetRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? OPSStyle.Colors.surfaceActive : Color.clear)
    }
}

private extension ActivityTarget {
    /// Stable identity for `ForEach` across the three wrapped model types.
    var rowId: String {
        switch self {
        case .opportunity(let opp): return "lead-\(opp.id)"
        case .client(let client):   return "client-\(client.id)"
        case .project(let project): return "job-\(project.id)"
        case .unbound:              return "unbound"
        }
    }
}
