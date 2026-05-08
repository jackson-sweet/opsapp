//
//  EditLeadSheet.swift
//  OPS
//
//  Modal for editing an existing pipeline opportunity. Mirrors AddLeadSheet
//  (T16) plus a stage Picker. On save, diffs old vs new and PATCHes only the
//  changed fields. If stage changed, calls moveToStage first so the
//  stage_transitions row is recorded by the RPC.
//

import SwiftUI

struct EditLeadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let opportunity: Opportunity
    @ObservedObject var pipelineVM: PipelineViewModel

    @State private var title: String
    @State private var contactName: String
    @State private var contactEmail: String
    @State private var contactPhone: String
    @State private var estimatedValueText: String
    @State private var source: OpportunitySource?
    @State private var description: String
    @State private var stage: PipelineStage

    @State private var isSaving = false
    @State private var saveError: String? = nil

    init(opportunity: Opportunity, pipelineVM: PipelineViewModel) {
        self.opportunity = opportunity
        self.pipelineVM = pipelineVM
        _title = State(initialValue: opportunity.title ?? "")
        _contactName = State(initialValue: opportunity.contactName)
        _contactEmail = State(initialValue: opportunity.contactEmail ?? "")
        _contactPhone = State(initialValue: opportunity.contactPhone ?? "")
        _estimatedValueText = State(initialValue: opportunity.estimatedValue.map { String(Int($0)) } ?? "")
        _source = State(initialValue: opportunity.source.flatMap { OpportunitySource(rawValue: $0) })
        _description = State(initialValue: opportunity.descriptionText ?? "")
        _stage = State(initialValue: opportunity.stage)
    }

    private var canSave: Bool {
        !contactName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                        sectionHeader("STAGE")
                        stagePicker

                        sectionHeader("DEAL")
                        labeledField("TITLE (OPTIONAL)", text: $title, placeholder: "e.g. Devlin roof replacement")

                        sectionHeader("CONTACT")
                        labeledField("NAME *", text: $contactName, placeholder: "Eric Devlin")
                        labeledField("EMAIL", text: $contactEmail, placeholder: "eric@example.com", keyboard: .emailAddress)
                        labeledField("PHONE", text: $contactPhone, placeholder: "555-1234", keyboard: .phonePad)

                        sectionHeader("DETAILS")
                        labeledField("ESTIMATED VALUE", text: $estimatedValueText, placeholder: "0", keyboard: .decimalPad)
                        sourcePicker
                        labeledTextEditor("DESCRIPTION", text: $description)

                        if let saveError {
                            Text(saveError)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("SAVE") { Task { await save() } }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(canSave ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Save

    private func save() async {
        guard let companyId = dataController.currentUser?.companyId else { return }
        let userId = dataController.currentUser?.id
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        // 1. If stage changed, move via RPC first so stage_transitions gets a row.
        if stage != opportunity.stage {
            do {
                try await pipelineVM.moveToStage(opportunityId: opportunity.id, to: stage, userId: userId)
            } catch {
                saveError = "Stage update failed: \(error.localizedDescription)"
                return
            }
        }

        // 2. Build a diff-only PATCH for non-stage fields.
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedValue: Double? = {
            let cleaned = estimatedValueText.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            return Double(cleaned)
        }()

        var fields = UpdateOpportunityDTO()
        var changed = false

        if trimmedTitle != (opportunity.title ?? "") {
            fields.title = trimmedTitle.isEmpty ? nil : trimmedTitle
            changed = true
        }
        if trimmedName != opportunity.contactName {
            fields.contactName = trimmedName
            changed = true
        }
        if trimmedEmail != (opportunity.contactEmail ?? "") {
            fields.contactEmail = trimmedEmail.isEmpty ? nil : trimmedEmail
            changed = true
        }
        if trimmedPhone != (opportunity.contactPhone ?? "") {
            fields.contactPhone = trimmedPhone.isEmpty ? nil : trimmedPhone
            changed = true
        }
        if parsedValue != opportunity.estimatedValue {
            fields.estimatedValue = parsedValue
            changed = true
        }
        if source?.rawValue != opportunity.source {
            fields.source = source?.rawValue
            changed = true
        }
        if trimmedDesc != (opportunity.descriptionText ?? "") {
            fields.description = trimmedDesc.isEmpty ? nil : trimmedDesc
            changed = true
        }

        if changed {
            let repo = OpportunityRepository(companyId: companyId)
            do {
                let updatedDTO = try await repo.update(opportunity.id, fields: fields)
                // Reflect into the in-memory pipeline list.
                if let idx = pipelineVM.allOpportunities.firstIndex(where: { $0.id == opportunity.id }) {
                    pipelineVM.allOpportunities[idx] = updatedDTO.toModel()
                }
            } catch {
                saveError = error.localizedDescription
                return
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    // MARK: - Subviews

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(.top, OPSStyle.Layout.spacing2)
    }

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>, placeholder: String = "", keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextField(placeholder, text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .keyboardType(keyboard)
                .padding(OPSStyle.Layout.spacing2_5)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
    }

    @ViewBuilder
    private func labeledTextEditor(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextEditor(text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
                .padding(OPSStyle.Layout.spacing2)
                .frame(minHeight: 100)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
    }

    private var stagePicker: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Menu {
                ForEach(PipelineStage.allCases) { s in
                    Button(s.displayName) { stage = s }
                }
            } label: {
                HStack {
                    Text(stage.displayName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(OPSStyle.Layout.spacing2_5)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("SOURCE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Menu {
                Button("NONE") { source = nil }
                ForEach(OpportunitySource.allCases) { src in
                    Button(src.displayName) { source = src }
                }
            } label: {
                HStack {
                    Text(source?.displayName ?? "SELECT…")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(source != nil ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(OPSStyle.Layout.spacing2_5)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
        }
    }
}
