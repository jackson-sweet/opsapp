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

struct ActivityTargetPickerView: View {
    let companyId: String
    let onSelect: (ActivityTarget) -> Void

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

    var body: some View {
        VStack(spacing: 0) {
            // Search bar — verbatim OpportunityPickerView treatment.
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .font(.system(size: 16))

                TextField("Search leads, clients, jobs...", text: $searchText)
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
        }
        .background(OPSStyle.Colors.background)
        .onAppear(perform: loadTargets)
    }

    // MARK: - Data

    private func loadTargets() {
        allTargets = ActivityTargetLoader.load(companyId: companyId, modelContext: modelContext)
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
            Text(searchText.isEmpty ? "NO LEADS, CLIENTS, OR JOBS" : "NO MATCHES")
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
            onSelect(target)
            dismiss()
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

                // Source badge — neutral tag, never accent/earth-tone/green.
                if let badge = target.sourceBadge {
                    sourceBadgeView(badge)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(TargetRowButtonStyle())
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
                    inlineField(text: $newLeadName, placeholder: "Contact name *")
                    inlineField(text: $newLeadPhone, placeholder: "Phone (optional)")
                    inlineField(text: $newLeadEmail, placeholder: "Email (optional)")

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
            estimatedValue: nil,
            source: "log_activity",
            quoteDeliveryMethod: nil
        )

        do {
            let created = try await repository.create(dto)
            let model = created.toModel()
            modelContext.insert(model)
            try? modelContext.save()

            isSavingNewLead = false
            onSelect(.opportunity(model))
            dismiss()
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
