//
//  OpportunityFormSheet.swift
//  OPS
//
//  Create or edit a pipeline opportunity.
//

import SwiftUI

struct OpportunityFormSheet: View {
    @ObservedObject var viewModel: PipelineViewModel
    var editing: Opportunity? = nil

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var contactName = ""
    @State private var contactEmail = ""
    @State private var contactPhone = ""
    @State private var jobDescription = ""
    @State private var estimatedValue = ""
    @State private var source = ""
    @State private var isSaving = false

    private var isValid: Bool {
        !contactName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private let sourceOptions = ["Referral", "Website", "Email", "Phone", "Walk-in", "Social Media", "Other"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    // CONTACT section
                    sectionHeader("CONTACT")
                    VStack(spacing: 0) {
                        formField("Name", text: $contactName, placeholder: "Contact name")
                        Divider().background(Color.white.opacity(0.1))
                        formField("Phone", text: $contactPhone, placeholder: "Optional", keyboardType: .phonePad)
                        Divider().background(Color.white.opacity(0.1))
                        formField("Email", text: $contactEmail, placeholder: "Optional", keyboardType: .emailAddress)
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // DEAL DETAILS section
                    sectionHeader("DEAL DETAILS")
                    VStack(spacing: 0) {
                        formField("Job Description", text: $jobDescription, placeholder: "Optional")
                        Divider().background(Color.white.opacity(0.1))
                        formField("Estimated Value", text: $estimatedValue, placeholder: "$0", keyboardType: .decimalPad)
                        Divider().background(Color.white.opacity(0.1))
                        sourcePickerRow
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                }
                .padding(.top, OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationTitle(editing != nil ? "EDIT DEAL" : "NEW LEAD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                            .tint(OPSStyle.Colors.primaryAccent)
                    } else {
                        Button(editing != nil ? "SAVE" : "CREATE") { save() }
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(isValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                            .disabled(!isValid)
                    }
                }
            }
            .onAppear {
                if let opp = editing {
                    contactName = opp.contactName
                    contactEmail = opp.contactEmail ?? ""
                    contactPhone = opp.contactPhone ?? ""
                    jobDescription = opp.jobDescription ?? ""
                    estimatedValue = opp.estimatedValue.map { String(format: "%.0f", $0) } ?? ""
                    source = opp.source ?? ""
                }
            }
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String, keyboardType: UIKeyboardType = .default) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 120, alignment: .leading)
            TextField(placeholder, text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .keyboardType(keyboardType)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    private var sourcePickerRow: some View {
        HStack {
            Text("Source")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 120, alignment: .leading)
            Spacer()
            Menu {
                ForEach(sourceOptions, id: \.self) { option in
                    Button(option) { source = option }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(source.isEmpty ? "Select" : source)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(source.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    // MARK: - Save

    private func save() {
        guard isValid else { return }
        isSaving = true
        let companyId = dataController.currentUser?.companyId ?? ""
        let value = Double(estimatedValue)

        if let opp = editing {
            Task {
                await viewModel.updateOpportunity(
                    opp,
                    contactName: contactName,
                    contactEmail: contactEmail.isEmpty ? nil : contactEmail,
                    contactPhone: contactPhone.isEmpty ? nil : contactPhone,
                    jobDescription: jobDescription.isEmpty ? nil : jobDescription,
                    estimatedValue: value,
                    source: source.isEmpty ? nil : source
                )
                dismiss()
            }
        } else {
            Task {
                await viewModel.createOpportunity(
                    contactName: contactName,
                    contactEmail: contactEmail.isEmpty ? nil : contactEmail,
                    contactPhone: contactPhone.isEmpty ? nil : contactPhone,
                    jobDescription: jobDescription.isEmpty ? nil : jobDescription,
                    estimatedValue: value,
                    source: source.isEmpty ? nil : source,
                    companyId: companyId
                )
                dismiss()
            }
        }
    }
}
