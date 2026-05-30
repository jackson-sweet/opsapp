//
//  EmployeeEmergencyContactView.swift
//  OPS
//
//  Emergency contact collection for employees during onboarding.
//  Fully optional — user can skip entirely.
//

import SwiftUI
import Supabase

struct EmployeeEmergencyContactView: View {
    @ObservedObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var contactName = ""
    @State private var contactPhone = ""
    @State private var relationship = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

    private let relationships = ["Parent", "Spouse", "Sibling", "Friend", "Other"]

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack(alignment: .bottom) {
                        Image("LogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .padding(.bottom, 8)
                        Text("OPS")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()

                        // Skip button
                        Button(action: onSkip) {
                            Text("SKIP")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    .padding(.leading, 4)

                    Spacer().frame(height: 40)

                    // Headline
                    HStack(spacing: 6) {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Text("EMERGENCY CONTACT")
                            .font(OPSStyle.Typography.heading)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                    }

                    HStack {
                        Text("In case something happens on the job.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                    }
                    .padding(.top, 8)

                    Spacer().frame(height: 32)

                    // Fields
                    VStack(spacing: 24) {
                        underlineField("Contact Name", text: $contactName, contentType: .name)
                        underlineField("Contact Phone", text: $contactPhone, contentType: .telephoneNumber, keyboard: .phonePad)
                    }

                    Spacer().frame(height: 32)

                    // Relationship picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RELATIONSHIP")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .tracking(1)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(relationships, id: \.self) { rel in
                                    Button {
                                        relationship = (relationship == rel) ? "" : rel
                                    } label: {
                                        Text(rel.uppercased())
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(relationship == rel ? OPSStyle.Colors.background : OPSStyle.Colors.secondaryText)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(
                                                relationship == rel
                                                    ? OPSStyle.Colors.primaryText
                                                    : Color.clear
                                            )
                                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                    .stroke(
                                                        relationship == rel
                                                            ? Color.clear
                                                            : OPSStyle.Colors.inputFieldBorder,
                                                        lineWidth: OPSStyle.Layout.Border.standard
                                                    )
                                            )
                                    }
                                }
                            }
                        }
                    }

                    Spacer().frame(height: 32)

                    // Error
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .padding(.bottom, 12)
                    }

                    // Finish button (last step of onboarding)
                    Button(action: saveAndContinue) {
                        ZStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                            } else {
                                HStack {
                                    Text("FINISH")
                                        .font(OPSStyle.Typography.bodyBold)
                                    Spacer()
                                    Image(OPSStyle.Icons.checkmark)
                                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                                }
                            }
                        }
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(OPSStyle.Colors.primaryText)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .disabled(isLoading)

                    Spacer().frame(height: 20)
                }
                .padding(40)
            }
        }
        .onAppear { OnboardingSupabaseAnalytics.shared.trackStepView("emergency_contact") }
    }

    // MARK: - Underline Field

    private func underlineField(
        _ placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType? = nil,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(spacing: 8) {
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(OPSStyle.Colors.secondaryText))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .autocapitalization(keyboard == .phonePad ? .none : .words)

            Rectangle()
                .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                .frame(height: 1)
        }
    }

    // MARK: - Save

    private func saveAndContinue() {
        let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)

        // If nothing entered, just continue (same as skip)
        guard !name.isEmpty || !phone.isEmpty else {
            onComplete()
            return
        }

        isLoading = true
        errorMessage = ""

        Task { @MainActor in
            do {
                guard let userId = onboardingManager.state.userData.userId ?? dataController.currentUser?.id else {
                    onComplete()
                    return
                }

                var fields: [String: AnyJSON] = [:]
                if !name.isEmpty {
                    fields["emergency_contact_name"] = .string(name)
                }
                if !phone.isEmpty {
                    fields["emergency_contact_phone"] = .string(phone)
                }
                if !relationship.isEmpty {
                    fields["emergency_contact_relationship"] = .string(relationship)
                }

                if !fields.isEmpty {
                    let userRepo = UserRepository(companyId: dataController.currentUser?.companyId ?? "")
                    try await userRepo.updateFields(userId: userId, fields: fields)

                    // Update local SwiftData
                    if let currentUser = dataController.currentUser {
                        if !name.isEmpty { currentUser.emergencyContactName = name }
                        if !phone.isEmpty { currentUser.emergencyContactPhone = phone }
                        if !relationship.isEmpty { currentUser.emergencyContactRelationship = relationship }
                        try? dataController.modelContext?.save()
                    }
                }

                isLoading = false
                onComplete()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
