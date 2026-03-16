//
//  ManageTeamView.swift
//  OPS
//
//  Team management view for editing roles, removing team members, and inviting new members
//

import SwiftUI
import Supabase

// MARK: - Pending Invitation Model

struct PendingInvitation: Identifiable {
    let id: String
    let email: String?
    let phone: String?
    let roleId: String?
    let roleName: String?
    let invitedBy: String
    let inviteCode: String
    let createdAt: Date
    let expiresAt: Date

    var contactDisplay: String {
        email ?? phone ?? "Unknown"
    }

    var isExpired: Bool {
        expiresAt < Date()
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(createdAt)
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}

// MARK: - Manage Team View

struct ManageTeamView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss

    @State private var teamMembers: [User] = []
    @State private var pendingInvitations: [PendingInvitation] = []
    @State private var isLoading = true
    @State private var selectedMember: User?
    @State private var showEditSheet = false
    @State private var showRemoveConfirmation = false
    @State private var memberToRemove: User?
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var showInviteSheet = false
    @State private var showInviteSentMessage = false
    @State private var inviteSentCount = 0
    @State private var memberToView: User? = nil
    @State private var showSeatManagement = false
    @State private var permissionsMember: User?
    @State private var invitationToRevoke: PendingInvitation?
    @State private var showRevokeConfirmation = false

    private var company: Company? {
        dataController.getCurrentUserCompany()
    }

    private var isCompanyAdmin: Bool {
        permissionStore.can("team.manage")
    }

    // MARK: - Grouped Members

    private var filteredMembers: [User] {
        let members = searchText.isEmpty ? teamMembers : teamMembers.filter { member in
            member.fullName.localizedCaseInsensitiveContains(searchText) ||
            member.email?.localizedCaseInsensitiveContains(searchText) == true ||
            member.role.displayName.localizedCaseInsensitiveContains(searchText)
        }
        return members
    }

    private var adminMembers: [User] {
        // Owners first, then admins
        filteredMembers.filter { $0.role == .admin || $0.role == .owner }
            .sorted { u1, u2 in
                if u1.role == .owner && u2.role != .owner { return true }
                if u2.role == .owner && u1.role != .owner { return false }
                return u1.firstName < u2.firstName
            }
    }

    private var operatorMembers: [User] {
        filteredMembers.filter { $0.role == .operator }
    }

    private var officeMembers: [User] {
        filteredMembers.filter { $0.role == .office }
    }

    private var crewMembers: [User] {
        filteredMembers.filter { $0.role == .crew }
    }

    private var unassignedMembers: [User] {
        filteredMembers.filter { $0.role == .unassigned }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Manage Team",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)

                if isLoading {
                    loadingView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Search + seat count
                            headerSection

                            // Error
                            if let error = errorMessage {
                                errorBanner(error)
                            }

                            // Team member sections by role
                            if filteredMembers.isEmpty {
                                emptyStateView
                                    .padding(.horizontal, 20)
                            } else {
                                teamSections
                            }

                            // Pending invitations (admin only)
                            if isCompanyAdmin && !pendingInvitations.isEmpty {
                                pendingInvitesSection
                            }

                            // Invite button (admin only)
                            if isCompanyAdmin {
                                inviteButton
                            }
                        }
                        .padding(.vertical, 16)
                        .tabBarPadding()
                    }
                }
            }
        }
        .trackScreen("Settings.ManageTeam")
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadTeamMembers()
            if isCompanyAdmin {
                Task { await loadPendingInvitations() }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let member = selectedMember {
                EditTeamMemberSheet(
                    member: member,
                    onSave: { updatedRole in
                        Task { await updateMemberRole(member, newRole: updatedRole) }
                    }
                )
                .environmentObject(dataController)
            }
        }
        .sheet(item: $memberToView) { member in
            ContactDetailView(user: member)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showInviteSheet) {
            TeamInviteSheet(companyId: company?.id ?? "")
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showSeatManagement) {
            SeatManagementView()
                .environmentObject(dataController)
                .environmentObject(subscriptionManager)
        }
        .sheet(item: $permissionsMember) { member in
            UserPermissionDetailView(member: member, companyId: company?.id ?? "")
                .environmentObject(dataController)
        }
        .alert("Remove Team Member", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) { memberToRemove = nil }
            Button("Remove", role: .destructive) {
                if let member = memberToRemove {
                    Task { await removeMember(member) }
                }
            }
        } message: {
            if let member = memberToRemove {
                Text("Are you sure you want to remove \(member.fullName)? They will lose access to the company.")
            }
        }
        .alert("Revoke Invitation", isPresented: $showRevokeConfirmation) {
            Button("Cancel", role: .cancel) { invitationToRevoke = nil }
            Button("Revoke", role: .destructive) {
                if let invite = invitationToRevoke {
                    Task { await revokeInvitation(invite) }
                }
            }
        } message: {
            if let invite = invitationToRevoke {
                Text("Revoke the invitation to \(invite.contactDisplay)?")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TeamInvitesSent"))) { notification in
            if let count = notification.userInfo?["count"] as? Int {
                inviteSentCount = count
                showInviteSentMessage = true
                // Refresh pending invites
                Task { await loadPendingInvitations() }
            }
        }
        .overlay {
            PushInMessage(
                isPresented: $showInviteSentMessage,
                title: "INVITATIONS SENT",
                subtitle: "\(inviteSentCount) team member\(inviteSentCount == 1 ? "" : "s") invited",
                type: .success,
                autoDismissAfter: 3.0
            )
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            SearchBar(searchText: $searchText, placeholder: "Search team members...")

            // Seat usage bar
            HStack(spacing: 12) {
                Text("\(teamMembers.count) MEMBER\(teamMembers.count == 1 ? "" : "S")")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                if isCompanyAdmin {
                    Button(action: { showSeatManagement = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.rectangle.stack")
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            Text("SEATS")
                                .font(OPSStyle.Typography.smallCaption)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Team Sections

    private var teamSections: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !adminMembers.isEmpty {
                roleSection(title: "ADMINS", icon: "shield.checkered", members: adminMembers, color: OPSStyle.Colors.warningStatus)
            }
            if !officeMembers.isEmpty {
                roleSection(title: "OFFICE", icon: "desktopcomputer", members: officeMembers, color: OPSStyle.Colors.primaryAccent)
            }
            if !operatorMembers.isEmpty {
                roleSection(title: "OPERATORS", icon: "wrench.and.screwdriver.fill", members: operatorMembers, color: OPSStyle.Colors.primaryAccent)
            }
            if !crewMembers.isEmpty {
                roleSection(title: "CREW", icon: "hammer.fill", members: crewMembers, color: OPSStyle.Colors.secondaryText)
            }
            if !unassignedMembers.isEmpty {
                roleSection(title: "UNASSIGNED", icon: "person.fill.questionmark", members: unassignedMembers, color: OPSStyle.Colors.tertiaryText)
            }
        }
    }

    // MARK: - Role Section

    private func roleSection(title: String, icon: String, members: [User], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(color)
                Text("\(title) (\(members.count))")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, 20)

            // Members card
            VStack(spacing: 0) {
                ForEach(members) { member in
                    teamMemberRow(member, accentColor: color)

                    if member.id != members.last?.id {
                        Divider()
                            .background(OPSStyle.Colors.cardBorder)
                            .padding(.leading, 72) // Align with text, past avatar
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Team Member Row

    private func teamMemberRow(_ member: User, accentColor: Color) -> some View {
        let isCurrentUser = member.id == dataController.currentUser?.id

        return Button(action: { memberToView = member }) {
            HStack(spacing: 12) {
                // Avatar with role accent
                UserAvatar(user: member, size: 44)

                // Name + role
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(member.fullName.isEmpty ? (member.email ?? "Unknown") : member.fullName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)

                        if member.role == .owner {
                            Text("OWNER")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(OPSStyle.Colors.warningStatus.opacity(0.15))
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        }

                        if isCurrentUser {
                            Text("YOU")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(OPSStyle.Colors.separator)
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(member.role.displayName.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(accentColor)

                        if let email = member.email, !email.isEmpty {
                            Text(email)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Inline role change (admin only, not for self)
                if isCompanyAdmin && !isCurrentUser {
                    Menu {
                        // Role change options
                        Section("Change Role") {
                            ForEach(UserRole.allCases.filter { $0 != .owner }.sorted(by: { $0.hierarchy < $1.hierarchy }), id: \.rawValue) { role in
                                Button {
                                    Task { await updateMemberRole(member, newRole: role) }
                                } label: {
                                    HStack {
                                        Text(role.displayName)
                                        if member.role == role {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }

                        Section {
                            Button(action: { permissionsMember = member }) {
                                Label("Permissions", systemImage: "person.badge.key")
                            }

                            Button(role: .destructive) {
                                memberToRemove = member
                                showRemoveConfirmation = true
                            } label: {
                                Label("Remove", systemImage: "person.badge.minus")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                } else {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Pending Invitations Section

    private var pendingInvitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                Text("PENDING INVITES (\(pendingInvitations.count))")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(pendingInvitations) { invite in
                    pendingInviteRow(invite)

                    if invite.id != pendingInvitations.last?.id {
                        Divider()
                            .background(OPSStyle.Colors.cardBorder)
                            .padding(.leading, 72)
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, 20)
        }
    }

    private func pendingInviteRow(_ invite: PendingInvitation) -> some View {
        HStack(spacing: 12) {
            // Icon avatar
            ZStack {
                Circle()
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
                    )

                Image(systemName: invite.email != nil ? "envelope.fill" : "phone.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(invite.contactDisplay)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let roleName = invite.roleName, roleName.lowercased() != "unassigned" {
                        Text(roleName.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }

                    Text("Sent \(invite.timeAgo)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    if invite.isExpired {
                        Text("EXPIRED")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    }
                }
            }

            Spacer()

            // Revoke button
            Button {
                invitationToRevoke = invite
                showRevokeConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    // MARK: - Invite Button

    private var inviteButton: some View {
        Button(action: { showInviteSheet = true }) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                Text("INVITE TEAM MEMBERS")
                    .font(OPSStyle.Typography.bodyBold)
            }
            .foregroundColor(OPSStyle.Colors.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Supporting Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.2)
            Text("Loading team...")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "person.3",
            title: searchText.isEmpty ? "No team members" : "No results",
            message: searchText.isEmpty
                ? "Team members will appear here once they join your organization."
                : "No team members match '\(searchText)'"
        )
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.errorStatus)
            Text(error)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.errorStatus)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Data Loading

    private func loadTeamMembers() {
        guard let companyId = company?.id else {
            isLoading = false
            return
        }

        teamMembers = dataController.getTeamMembers(companyId: companyId)
            .sorted { user1, user2 in
                if user1.id == dataController.currentUser?.id { return true }
                if user2.id == dataController.currentUser?.id { return false }
                if user1.role.hierarchy < user2.role.hierarchy { return true }
                if user1.role.hierarchy > user2.role.hierarchy { return false }
                return user1.firstName < user2.firstName
            }

        isLoading = false
    }

    private func loadPendingInvitations() async {
        guard let companyId = company?.id else { return }

        do {
            struct InvitationRow: Decodable {
                let id: String
                let email: String?
                let phone: String?
                let role_id: String?
                let invited_by: String
                let invite_code: String
                let created_at: String
                let expires_at: String
                let status: String
            }

            let rows: [InvitationRow] = try await SupabaseService.shared.client
                .from("team_invitations")
                .select()
                .eq("company_id", value: companyId)
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .execute()
                .value

            // Look up role names
            var roleNames: [String: String] = [:]
            let roleIds = Set(rows.compactMap { $0.role_id })
            if !roleIds.isEmpty {
                struct RoleRow: Decodable { let id: String; let name: String }
                let roles: [RoleRow] = try await SupabaseService.shared.client
                    .from("roles")
                    .select("id, name")
                    .in("id", values: Array(roleIds))
                    .execute()
                    .value
                for r in roles { roleNames[r.id] = r.name }
            }

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let invitations = rows.compactMap { row -> PendingInvitation? in
                guard let created = dateFormatter.date(from: row.created_at),
                      let expires = dateFormatter.date(from: row.expires_at) else { return nil }
                return PendingInvitation(
                    id: row.id,
                    email: row.email,
                    phone: row.phone,
                    roleId: row.role_id,
                    roleName: row.role_id.flatMap { roleNames[$0] },
                    invitedBy: row.invited_by,
                    inviteCode: row.invite_code,
                    createdAt: created,
                    expiresAt: expires
                )
            }

            await MainActor.run {
                pendingInvitations = invitations
            }
        } catch {
            print("[MANAGE_TEAM] Failed to load pending invitations: \(error)")
        }
    }

    // MARK: - Actions

    private func updateMemberRole(_ member: User, newRole: UserRole) async {
        errorMessage = nil

        do {
            // Write to user_roles table (RBAC)
            let roleId = try await PermissionAdminService.resolveRoleId(for: newRole)
            try await PermissionAdminService.assignUserRole(userId: member.id, roleId: roleId)

            // Also update the legacy role field
            try await dataController.syncManager.updateUserFields(
                userId: member.id,
                fields: ["role": .string(newRole.rawValue)]
            )

            await MainActor.run {
                member.role = newRole
                try? dataController.modelContext?.save()
                loadTeamMembers()
            }

            print("[MANAGE_TEAM] Updated \(member.fullName) to \(newRole.displayName)")

        } catch {
            await MainActor.run { errorMessage = "Failed to update role" }
            print("[MANAGE_TEAM] Error updating role: \(error)")
        }
    }

    private func removeMember(_ member: User) async {
        errorMessage = nil

        do {
            try await dataController.syncManager.deleteUser(userId: member.id)

            await MainActor.run {
                teamMembers.removeAll { $0.id == member.id }
                memberToRemove = nil
            }

            print("[MANAGE_TEAM] Removed \(member.fullName)")

        } catch {
            await MainActor.run {
                errorMessage = "Failed to remove team member"
                memberToRemove = nil
            }
            print("[MANAGE_TEAM] Error removing member: \(error)")
        }
    }

    private func revokeInvitation(_ invite: PendingInvitation) async {
        do {
            try await SupabaseService.shared.client
                .from("team_invitations")
                .update(["status": "cancelled"])
                .eq("id", value: invite.id)
                .execute()

            await MainActor.run {
                pendingInvitations.removeAll { $0.id == invite.id }
                invitationToRevoke = nil
            }

            print("[MANAGE_TEAM] Revoked invitation for \(invite.contactDisplay)")
        } catch {
            print("[MANAGE_TEAM] Failed to revoke invitation: \(error)")
        }
    }
}

// MARK: - Team Invite Sheet

struct TeamInviteSheet: View {
    let companyId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @State private var inviteInputs: [String] = [""]
    @State private var inputErrors: [String?] = [nil]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedRoleId: String = InviteRoleOption.defaultRoleId
    @State private var showCopiedFeedback = false

    private var companyCode: String {
        dataController.getCurrentUserCompany()?.externalId ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("INVITE TEAM MEMBERS")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Text("Send an invite via email or phone. They'll get instructions to download OPS and join your crew.")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.horizontal, 20)

                        // Company code section
                        if !companyCode.isEmpty {
                            companyCodeCard
                                .padding(.horizontal, 20)
                        }

                        // Input fields
                        VStack(spacing: 12) {
                            ForEach(inviteInputs.indices, id: \.self) { index in
                                inviteInputRow(index: index)
                            }

                            // Add another button
                            if inviteInputs.count < 10 {
                                Button(action: addInputField) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                                        Text("Add another")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Role picker
                        InviteRolePicker(selectedRoleId: $selectedRoleId)
                            .padding(.horizontal, 20)

                        // Error message
                        if let error = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.errorStatus)

                                Text(error)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
            .standardSheetToolbar(
                title: "Invite Team Members",
                actionText: "Send Invites",
                isActionEnabled: hasValidInputs && !isLoading,
                isSaving: isLoading,
                onCancel: { dismiss() },
                onAction: {
                    Task {
                        await sendInvitations()
                    }
                }
            )
        }
    }

    // MARK: - Company Code Card

    private var companyCodeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CREW CODE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Button {
                UIPasteboard.general.string = companyCode
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                showCopiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showCopiedFeedback = false
                }
            } label: {
                HStack {
                    Text("[\(companyCode)]")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        Text(showCopiedFeedback ? "COPIED" : "COPY")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(showCopiedFeedback ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent)
                }
                .padding(14)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(showCopiedFeedback ? OPSStyle.Colors.successStatus.opacity(0.5) : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }

            Text("Share this code directly — they can enter it when they join.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Input Row

    private func inviteInputRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Detect input type and show indicator
                let input = inviteInputs[index].trimmingCharacters(in: .whitespacesAndNewlines)
                let inputType = detectInputType(input)

                if !input.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: inputType == .phone ? "phone.fill" : "envelope.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        Text(inputType == .phone ? "PHONE" : "EMAIL")
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                if inviteInputs.count > 1 {
                    Button {
                        removeInput(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: 28, height: 28)
                    }
                }
            }

            ZStack(alignment: .leading) {
                if inviteInputs[index].isEmpty {
                    Text("Email or phone number")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.placeholderText)
                        .padding(.horizontal, 16)
                }

                TextField("", text: Binding(
                    get: { inviteInputs[index] },
                    set: { inviteInputs[index] = $0; validateInput(at: index) }
                ))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 14)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(
                        inputErrors[index] != nil ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.inputFieldBorder,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )

            if let error = inputErrors[index] {
                Text(error)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
            }
        }
    }

    // MARK: - Input Type Detection

    private enum InputType {
        case email, phone, unknown
    }

    private func detectInputType(_ input: String) -> InputType {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .unknown }
        if trimmed.contains("@") { return .email }
        // Check if mostly digits (phone number)
        let digits = trimmed.filter { $0.isNumber }
        if digits.count >= 7 { return .phone }
        return .unknown
    }

    // MARK: - Helpers

    private var hasValidInputs: Bool {
        inviteInputs.enumerated().contains { index, input in
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && inputErrors[index] == nil
        }
    }

    private func addInputField() {
        inviteInputs.append("")
        inputErrors.append(nil)
    }

    private func removeInput(at index: Int) {
        guard inviteInputs.count > 1 else { return }
        inviteInputs.remove(at: index)
        inputErrors.remove(at: index)
    }

    private func validateInput(at index: Int) {
        guard index < inputErrors.count else { return }

        let input = inviteInputs[index].trimmingCharacters(in: .whitespacesAndNewlines)

        if input.isEmpty {
            inputErrors[index] = nil
            return
        }

        let type = detectInputType(input)
        switch type {
        case .email:
            if !isValidEmail(input) {
                inputErrors[index] = "Enter a valid email address"
            } else {
                inputErrors[index] = nil
            }
        case .phone:
            let digits = input.filter { $0.isNumber }
            if digits.count < 10 {
                inputErrors[index] = "Enter a valid phone number"
            } else {
                inputErrors[index] = nil
            }
        case .unknown:
            inputErrors[index] = "Enter an email or phone number"
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func sendInvitations() async {
        guard hasValidInputs else { return }

        // Separate inputs into emails and phones
        var validEmails: [String] = []
        var validPhones: [String] = []

        for (index, input) in inviteInputs.enumerated() {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, inputErrors[index] == nil else { continue }

            let type = detectInputType(trimmed)
            switch type {
            case .email:
                validEmails.append(trimmed)
            case .phone:
                let digits = trimmed.filter { $0.isNumber }
                // Format with +1 if no country code
                let formatted = digits.hasPrefix("1") && digits.count == 11 ? "+\(digits)" : "+1\(digits)"
                validPhones.append(formatted)
            case .unknown:
                // Treat as email by default
                validEmails.append(trimmed)
            }
        }

        guard !validEmails.isEmpty || !validPhones.isEmpty else { return }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let onboardingService = OnboardingService()
            _ = try await onboardingService.sendInvites(
                emails: validEmails,
                phones: validPhones.isEmpty ? nil : validPhones,
                companyId: companyId,
                roleId: selectedRoleId
            )

            await MainActor.run {
                isLoading = false

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                let totalSent = validEmails.count + validPhones.count
                NotificationCenter.default.post(
                    name: Notification.Name("TeamInvitesSent"),
                    object: nil,
                    userInfo: ["count": totalSent]
                )

                dismiss()
            }

            print("[TEAM_INVITE] Sent \(validEmails.count) emails, \(validPhones.count) SMS invitations")

        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "Failed to send invitations"

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
            print("[TEAM_INVITE] Error sending invitations: \(error)")
        }
    }
}

// MARK: - Edit Team Member Sheet

struct EditTeamMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let member: User
    let onSave: (UserRole) -> Void

    @State private var selectedRole: UserRole
    @State private var isSaving = false

    init(member: User, onSave: @escaping (UserRole) -> Void) {
        self.member = member
        self.onSave = onSave
        self._selectedRole = State(initialValue: member.role)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Member info header
                        HStack(spacing: 16) {
                            UserAvatar(user: member, size: 56)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(member.fullName)
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                if let email = member.email {
                                    Text(email)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 20)

                        // Role selection
                        SectionCard(
                            icon: "person.badge.key",
                            title: "Employee Role"
                        ) {
                            VStack(spacing: 12) {
                                ForEach(UserRole.allCases.sorted(by: { $0.hierarchy < $1.hierarchy }), id: \.rawValue) { role in
                                    roleOption(
                                        role: role,
                                        title: role.displayName,
                                        description: role.roleDescription
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Edit Role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isSaving = true
                        onSave(selectedRole)
                        dismiss()
                    }) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                .scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(selectedRole != member.role ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .disabled(selectedRole == member.role || isSaving)
                }
            }
        }
    }

    private func roleOption(role: UserRole, title: String, description: String) -> some View {
        Button(action: {
            selectedRole = role
        }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedRole == role ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(selectedRole == role ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(selectedRole == role ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)

                    Text(description)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(16)
            .background(selectedRole == role ? OPSStyle.Colors.subtleBackground : Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(selectedRole == role ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ManageTeamView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
