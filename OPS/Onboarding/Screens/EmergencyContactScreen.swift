//
//  EmergencyContactScreen.swift
//  OPS
//
//  Emergency contact screen for employees (skippable).
//  Collects emergency contact name, phone, and relationship.
//  Uses phased animation system for entrance effects.
//

import SwiftUI
import Supabase

struct EmergencyContactScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    @State private var contactName: String = ""
    @State private var contactPhone: String = ""
    @State private var relationship: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    // Animation coordinator
    @StateObject private var animationCoordinator = OnboardingAnimationCoordinator()

    private let relationships = ["Parent", "Spouse", "Sibling", "Friend", "Other"]

    private enum Field {
        case name, phone
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back and skip
            HStack {
                // Back button
                Button {
                    manager.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: 44, height: 44)
                }

                Spacer()

                // Skip button
                Button {
                    skipAndContinue()
                } label: {
                    Text("SKIP")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)

            // Title section with phased typing animation
            PhasedOnboardingHeader(
                title: "EMERGENCY CONTACT",
                subtitle: "In case something happens on the job.",
                coordinator: animationCoordinator
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 16)

            Spacer()
                .frame(height: 48)

            // Content section - fades in upward
            PhasedContent(coordinator: animationCoordinator) {
                VStack(spacing: 20) {
                    // Contact Name
                    VStack(alignment: .leading, spacing: 8) {
                        PhasedLabel("CONTACT NAME", index: 0, coordinator: animationCoordinator)

                        TextField("", text: $contactName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .autocapitalization(.words)
                            .textContentType(.name)
                            .focused($focusedField, equals: .name)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }

                    // Contact Phone
                    VStack(alignment: .leading, spacing: 8) {
                        PhasedLabel("CONTACT PHONE", index: 1, coordinator: animationCoordinator)

                        TextField("", text: $contactPhone)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .focused($focusedField, equals: .phone)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    if focusedField == .phone {
                                        Spacer()
                                        Button {
                                            focusedField = nil
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text("Done")
                                                Image(systemName: "return")
                                            }
                                        }
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    }
                                }
                            }
                    }

                    // Relationship picker
                    VStack(alignment: .leading, spacing: 12) {
                        PhasedLabel("RELATIONSHIP", index: 2, isLast: true, coordinator: animationCoordinator)

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
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
            }

            // Continue button with phased animation
            PhasedPrimaryButton(
                "CONTINUE",
                isEnabled: true,
                isLoading: isSaving,
                loadingText: "Saving...",
                coordinator: animationCoordinator
            ) {
                saveAndContinue()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(OPSStyle.Colors.background)
        .onTapGesture {
            focusedField = nil
        }
        .onAppear {
            animationCoordinator.start()
        }
    }

    // MARK: - Actions

    private func skipAndContinue() {
        // Skip without saving emergency contact — go straight to code entry
        manager.goToScreen(.codeEntry)
    }

    private func saveAndContinue() {
        let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)

        // If all fields empty, treat as skip
        if name.isEmpty && phone.isEmpty && relationship.isEmpty {
            manager.goToScreen(.codeEntry)
            return
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                guard let userId = manager.state.userData.userId ?? dataController.currentUser?.id else {
                    throw OnboardingManagerError.noUserId
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
                    try await dataController.updateUserFields(userId: userId, fields: fields)

                    // Update local SwiftData user
                    if let currentUser = dataController.currentUser {
                        currentUser.emergencyContactName = name.isEmpty ? nil : name
                        currentUser.emergencyContactPhone = phone.isEmpty ? nil : phone
                        currentUser.emergencyContactRelationship = relationship.isEmpty ? nil : relationship
                        try? dataController.modelContext?.save()
                    }
                }

                await MainActor.run {
                    isSaving = false
                    manager.goToScreen(.codeEntry)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)
    manager.selectFlow(.employee)

    return EmergencyContactScreen(manager: manager)
        .environmentObject(dataController)
}
