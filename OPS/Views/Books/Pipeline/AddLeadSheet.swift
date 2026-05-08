//
//  AddLeadSheet.swift
//  OPS
//
//  Modal for creating a new pipeline opportunity. Fields per spec §6.6.
//  Title is optional (DB trigger backfills); contactName is required.
//

import SwiftUI

struct AddLeadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    var onCreated: (Opportunity) -> Void

    @State private var title: String = ""
    @State private var contactName: String = ""
    @State private var contactEmail: String = ""
    @State private var contactPhone: String = ""
    @State private var estimatedValueText: String = ""
    @State private var source: OpportunitySource? = nil
    @State private var description: String = ""

    @State private var isSaving = false
    @State private var saveError: String? = nil

    private var canSave: Bool {
        !contactName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
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
                    Button("ADD") { Task { await save() } }
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
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let estimatedValue: Double? = {
            let cleaned = estimatedValueText.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            return Double(cleaned)
        }()

        let dto = CreateOpportunityDTO(
            companyId: companyId,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            contactName: contactName.trimmingCharacters(in: .whitespacesAndNewlines),
            contactEmail: contactEmail.isEmpty ? nil : contactEmail,
            contactPhone: contactPhone.isEmpty ? nil : contactPhone,
            description: description.isEmpty ? nil : description,
            address: nil,
            estimatedValue: estimatedValue,
            source: source?.rawValue,
            priority: nil,
            assignedTo: nil,
            expectedCloseDate: nil,
            quoteDeliveryMethod: nil,
            clientId: nil
        )

        let repo = OpportunityRepository(companyId: companyId)
        do {
            let resultDTO = try await repo.create(dto)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCreated(resultDTO.toModel())
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
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
