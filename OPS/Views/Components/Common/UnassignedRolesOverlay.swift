//
//  UnassignedRolesOverlay.swift
//  OPS
//
//  Overlay that prompts admin/office crew to assign roles to employees
//  who don't have an employeeType set in Bubble.
//

import SwiftUI

/// Represents a user who needs a role assignment
struct UnassignedUser: Identifiable {
    let id: String
    let firstName: String
    let lastName: String
    let email: String?
    var selectedRole: UserRole?

    var fullName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? (email ?? "Unknown") : name
    }

    var initials: String {
        let first = firstName.prefix(1).uppercased()
        let last = lastName.prefix(1).uppercased()
        return first + last
    }
}

/// Overlay view for assigning roles to employees without an employeeType
struct UnassignedRolesOverlay: View {
    @EnvironmentObject private var dataController: DataController
    @Binding var isPresented: Bool
    @State var unassignedUsers: [UnassignedUser]

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var expandedUserId: String?

    var body: some View {
        ZStack {
            // Pure black background
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.top, 60)

                Spacer()

                // User list
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach($unassignedUsers) { $user in
                            userRow(user: $user)

                            if user.id != unassignedUsers.last?.id {
                                Rectangle()
                                    .fill(OPSStyle.Colors.tertiaryText.opacity(0.2))
                                    .frame(height: 1)
                                    .padding(.horizontal, 24)
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)

                Spacer()

                // Error message
                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                        Text(error.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    }
                    .padding(.bottom, 16)
                }

                // Footer buttons
                footerView
                    .padding(.bottom, 50)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ROLE ASSIGNMENT")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("\(unassignedUsers.count) team \(unassignedUsers.count == 1 ? "member needs" : "members need") a role")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            Image(systemName: "person.badge.plus")
                .font(.system(size: 20))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - User Row

    private func userRow(user: Binding<UnassignedUser>) -> some View {
        let isExpanded = expandedUserId == user.wrappedValue.id

        return VStack(spacing: 0) {
            // User info row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.wrappedValue.fullName)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    if let email = user.wrappedValue.email, !email.isEmpty {
                        Text(email)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }

                Spacer()

                // Role selection or current selection display
                if let role = user.wrappedValue.selectedRole {
                    HStack(spacing: 6) {
                        Text(role == .fieldCrew ? "FIELD" : "OFFICE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                } else {
                    Text("SELECT")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedUserId = nil
                    } else {
                        expandedUserId = user.wrappedValue.id
                    }
                }
            }

            // Expanded role selection
            if isExpanded {
                VStack(spacing: 16) {
                    // Field Crew option
                    roleOption(
                        title: "FIELD CREW",
                        description: "Works on job sites. Can view assigned projects, update task status, and log work. Limited access to scheduling and client info.",
                        isSelected: user.wrappedValue.selectedRole == .fieldCrew,
                        action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                user.wrappedValue.selectedRole = .fieldCrew
                                // Auto-collapse after brief delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedUserId = nil
                                    }
                                }
                            }
                        }
                    )

                    // Office Crew option
                    roleOption(
                        title: "OFFICE CREW",
                        description: "Manages operations from the office. Full access to scheduling, client management, project creation, and team coordination.",
                        isSelected: user.wrappedValue.selectedRole == .officeCrew,
                        action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                user.wrappedValue.selectedRole = .officeCrew
                                // Auto-collapse after brief delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedUserId = nil
                                    }
                                }
                            }
                        }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Role Option

    private func roleOption(title: String, description: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)

                    Text(description)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isSelected ? OPSStyle.Colors.subtleBackground : Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(isSelected ? OPSStyle.Colors.primaryText.opacity(0.2) : OPSStyle.Colors.tertiaryText.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 20) {
            // Save button - white on black, only enabled when all assigned
            Button(action: {
                Task {
                    await saveRoleAssignments()
                }
            }) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.8)
                    }
                    Text(isSaving ? "SAVING..." : "SAVE ROLES")
                        .font(OPSStyle.Typography.captionBold)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(allRolesAssigned ? Color.white : Color.white.opacity(0.3))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .disabled(!allRolesAssigned || isSaving)
            .padding(.horizontal, 24)

            // Later button
            Button(action: dismissAndRemindLater) {
                Text("REMIND ME LATER")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
    }

    // MARK: - Computed Properties

    private var allRolesAssigned: Bool {
        unassignedUsers.allSatisfy { $0.selectedRole != nil }
    }

    // MARK: - Actions

    private func dismissAndRemindLater() {
        UserDefaults.standard.set(Date(), forKey: "unassigned_roles_dismissed_at")
        isPresented = false
    }

    private func saveRoleAssignments() async {
        guard allRolesAssigned else { return }

        await MainActor.run {
            isSaving = true
            errorMessage = nil
        }

        do {
            for user in unassignedUsers {
                guard let role = user.selectedRole else { continue }

                let employeeTypeValue: String
                switch role {
                case .fieldCrew:
                    employeeTypeValue = "Field Crew"
                case .officeCrew:
                    employeeTypeValue = "Office Crew"
                case .admin:
                    employeeTypeValue = "Admin"
                }

                try await dataController.apiService.updateUser(
                    id: user.id,
                    userData: [BubbleFields.User.employeeType: employeeTypeValue]
                )

                print("[UNASSIGNED_ROLES] Updated \(user.fullName) → \(employeeTypeValue)")
            }

            await MainActor.run {
                isSaving = false
                isPresented = false
            }

        } catch {
            await MainActor.run {
                isSaving = false
                errorMessage = "Failed to save"
            }
            print("[UNASSIGNED_ROLES] Error: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    UnassignedRolesOverlay(
        isPresented: .constant(true),
        unassignedUsers: [
            UnassignedUser(id: "1", firstName: "John", lastName: "Smith", email: "john@example.com"),
            UnassignedUser(id: "2", firstName: "Jane", lastName: "Doe", email: "jane@example.com"),
            UnassignedUser(id: "3", firstName: "Mike", lastName: "Johnson", email: "mike@example.com")
        ]
    )
    .environmentObject(DataController())
    .preferredColorScheme(.dark)
}
