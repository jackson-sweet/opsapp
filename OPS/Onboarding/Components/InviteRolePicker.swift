//
//  InviteRolePicker.swift
//  OPS
//
//  Role picker for team invite flows.
//  Clean chip selector with expandable description for selected role.
//  Used in both onboarding invite sheet and settings team management.
//

import SwiftUI

// MARK: - Role Options

/// Static role options for invite flows.
/// Role IDs match the seeded roles in Supabase.
enum InviteRoleOption: String, CaseIterable, Identifiable {
    case crew       = "00000000-0000-0000-0000-000000000005"
    case operator_  = "00000000-0000-0000-0000-000000000004"
    case office     = "00000000-0000-0000-0000-000000000003"
    case admin      = "00000000-0000-0000-0000-000000000001"
    case unassigned = "00000000-0000-0000-0000-000000000006"

    var id: String { rawValue }

    /// Default role for invites
    static let defaultRoleId = InviteRoleOption.crew.rawValue

    var displayName: String {
        switch self {
        case .crew: return "Crew"
        case .operator_: return "Operator"
        case .office: return "Office"
        case .admin: return "Admin"
        case .unassigned: return "Unassigned"
        }
    }

    var icon: String {
        switch self {
        case .crew: return "hammer.fill"
        case .operator_: return "wrench.and.screwdriver.fill"
        case .office: return "desktopcomputer"
        case .admin: return "shield.checkered"
        case .unassigned: return "person.fill.questionmark"
        }
    }

    var description: String {
        switch self {
        case .crew:
            return "Field worker. Can view assigned projects and tasks, update task status, and log time. No access to financials or settings."
        case .operator_:
            return "Lead technician. Can manage assigned projects, create and edit tasks, quote jobs, and oversee crew work."
        case .office:
            return "Office staff. Full access to projects, clients, scheduling, and financial data. Cannot manage team roles or billing."
        case .admin:
            return "Full system access. Can manage team members, roles, permissions, billing, and all company settings."
        case .unassigned:
            return "No role assigned yet. Read-only access to their own assignments. You can assign a role later in team settings."
        }
    }

    /// Roles shown in the invite picker (excludes Owner — that's the company creator)
    static var inviteOptions: [InviteRoleOption] {
        [.crew, .operator_, .office, .admin, .unassigned]
    }

    /// Look up option by role ID
    static func from(roleId: String) -> InviteRoleOption? {
        inviteOptions.first { $0.rawValue == roleId }
    }
}

// MARK: - Role Picker View

struct InviteRolePicker: View {
    @Binding var selectedRoleId: String

    private var selectedRole: InviteRoleOption? {
        InviteRoleOption.from(roleId: selectedRoleId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Section label
            Text("ASSIGN ROLE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Role chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(InviteRoleOption.inviteOptions) { role in
                        roleChip(role)
                    }
                }
            }

            // Selected role description
            if let role = selectedRole {
                roleDescription(role)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(OPSStyle.Animation.standard, value: selectedRoleId)
    }

    // MARK: - Role Chip

    private func roleChip(_ role: InviteRoleOption) -> some View {
        let isSelected = selectedRoleId == role.rawValue

        return Button {
            selectedRoleId = role.rawValue
        } label: {
            HStack(spacing: 6) {
                Image(systemName: role.icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))

                Text(role.displayName.uppercased())
                    .font(OPSStyle.Typography.captionBold)
            }
            .foregroundColor(isSelected ? OPSStyle.Colors.background : OPSStyle.Colors.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? OPSStyle.Colors.primaryText
                    : Color.clear
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(
                        isSelected
                            ? Color.clear
                            : OPSStyle.Colors.inputFieldBorder,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
    }

    // MARK: - Role Description

    private func roleDescription(_ role: InviteRoleOption) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: role.icon)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 20)

            Text(role.description)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OPSStyle.Layout.spacing2_5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

// MARK: - Preview

#Preview("Default Selection") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()

        InviteRolePicker(selectedRoleId: .constant(InviteRoleOption.defaultRoleId))
            .padding(OPSStyle.Layout.spacing4)
    }
}

#Preview("Admin Selected") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()

        InviteRolePicker(selectedRoleId: .constant(InviteRoleOption.admin.rawValue))
            .padding(OPSStyle.Layout.spacing4)
    }
}
