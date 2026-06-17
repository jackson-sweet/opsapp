//
//  CompanyProfileCompletionSheet.swift
//  OPS
//
//  Sheet to collect missing company profile fields before beta access requests.
//

import SwiftUI
import SwiftData

struct CompanyProfileCompletionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let company: Company
    let onComplete: () -> Void

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var address: String = ""
    @State private var companySize: String = ""
    @State private var selectedIndustries: Set<String> = []
    @State private var isSaving = false

    private let sizeOptions = ["1-5", "6-15", "16-30", "31-50", "51-100", "100+"]

    private let industryOptions = [
        "Residential Construction", "Commercial Construction",
        "Electrical", "Plumbing", "HVAC",
        "Roofing", "Landscaping", "Painting",
        "Concrete", "Flooring", "General Contracting",
        "Solar", "Property Management", "Renovation",
        "Other"
    ]

    private var missingName: Bool { company.name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var missingEmail: Bool { (company.email ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    private var missingPhone: Bool { (company.phone ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    private var missingAddress: Bool { (company.address ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    private var missingSize: Bool { (company.companySize ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    private var missingIndustry: Bool { company.getIndustries().isEmpty }

    private var isFormValid: Bool {
        (!missingName || !name.trimmingCharacters(in: .whitespaces).isEmpty) &&
        (!missingEmail || !email.trimmingCharacters(in: .whitespaces).isEmpty) &&
        (!missingPhone || !phone.trimmingCharacters(in: .whitespaces).isEmpty) &&
        (!missingAddress || !address.trimmingCharacters(in: .whitespaces).isEmpty) &&
        (!missingSize || !companySize.isEmpty) &&
        (!missingIndustry || !selectedIndustries.isEmpty)
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "COMPLETE YOUR PROFILE",
                    showEditButton: false,
                    onBackTapped: { dismiss() }
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3_5) {
                        Text("We need a few details about your company before you can request beta access.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.top, OPSStyle.Layout.spacing3)

                        VStack(spacing: OPSStyle.Layout.spacing2_5) {
                            if missingName {
                                fieldRow(label: "Company Name", text: $name, placeholder: "Enter company name")
                            }

                            if missingEmail {
                                fieldRow(label: "Email", text: $email, placeholder: "company@example.com")
                            }

                            if missingPhone {
                                fieldRow(label: "Phone", text: $phone, placeholder: "(555) 555-5555")
                            }

                            if missingAddress {
                                fieldRow(label: "Address", text: $address, placeholder: "123 Main St, City, State")
                            }

                            if missingSize {
                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                    Text("COMPANY SIZE")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: OPSStyle.Layout.spacing2) {
                                        ForEach(sizeOptions, id: \.self) { size in
                                            Button {
                                                companySize = size
                                            } label: {
                                                Text(size)
                                                    .font(OPSStyle.Typography.caption)
                                                    .foregroundColor(companySize == size ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                                                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                                                    .padding(.vertical, OPSStyle.Layout.spacing2)
                                                    .frame(maxWidth: .infinity)
                                                    .background(companySize == size ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
                                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                            .stroke(companySize == size ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                                    )
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            }

                            if missingIndustry {
                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                    Text("INDUSTRY (SELECT ALL THAT APPLY)")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: OPSStyle.Layout.spacing2) {
                                        ForEach(industryOptions, id: \.self) { industry in
                                            Button {
                                                if selectedIndustries.contains(industry) {
                                                    selectedIndustries.remove(industry)
                                                } else {
                                                    selectedIndustries.insert(industry)
                                                }
                                            } label: {
                                                Text(industry)
                                                    .font(OPSStyle.Typography.caption)
                                                    .foregroundColor(selectedIndustries.contains(industry) ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                                                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                                                    .padding(.vertical, OPSStyle.Layout.spacing2)
                                                    .frame(maxWidth: .infinity)
                                                    .background(selectedIndustries.contains(industry) ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
                                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                            .stroke(selectedIndustries.contains(industry) ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                                    )
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            }
                        }

                        // Save button
                        Button {
                            saveAndComplete()
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .tint(OPSStyle.Colors.primaryText)
                                } else {
                                    Text("SAVE & CONTINUE")
                                        .font(OPSStyle.Typography.bodyBold)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isFormValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent.opacity(0.4))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .disabled(!isFormValid || isSaving)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.top, OPSStyle.Layout.spacing2)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func fieldRow(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(label.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextField(placeholder, text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(OPSStyle.Layout.spacing2_5)
                .background(OPSStyle.Colors.surfaceInput)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    private func saveAndComplete() {
        isSaving = true

        // Update company fields
        if missingName && !name.trimmingCharacters(in: .whitespaces).isEmpty {
            company.name = name.trimmingCharacters(in: .whitespaces)
        }
        if missingEmail && !email.trimmingCharacters(in: .whitespaces).isEmpty {
            company.email = email.trimmingCharacters(in: .whitespaces)
        }
        if missingPhone && !phone.trimmingCharacters(in: .whitespaces).isEmpty {
            company.phone = phone.trimmingCharacters(in: .whitespaces)
        }
        if missingAddress && !address.trimmingCharacters(in: .whitespaces).isEmpty {
            company.address = address.trimmingCharacters(in: .whitespaces)
        }
        if missingSize && !companySize.isEmpty {
            company.companySize = companySize
        }
        if missingIndustry && !selectedIndustries.isEmpty {
            company.setIndustries(Array(selectedIndustries))
        }

        company.needsSync = true

        dismiss()
        onComplete()
    }
}
