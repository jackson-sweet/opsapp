//
//  ManageTeamView.swift
//  OPS
//
//  Team management view for editing roles, removing team members, and inviting new members
//

import SwiftUI

struct ManageTeamView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var teamMembers: [User] = []
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

    private var company: Company? {
        dataController.getCurrentUserCompany()
    }

    private var isCompanyAdmin: Bool {
        dataController.currentUser?.isCompanyAdmin == true || dataController.currentUser?.role == .admin
    }

    private var filteredMembers: [User] {
        if searchText.isEmpty {
            return teamMembers
        }
        return teamMembers.filter { member in
            member.fullName.localizedCaseInsensitiveContains(searchText) ||
            member.email?.localizedCaseInsensitiveContains(searchText) == true ||
            member.roleDisplay.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Manage Team",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)

                if isLoading {
                    loadingView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Search bar
                            SearchBar(searchText: $searchText, placeholder: "Search team members...")
                                .padding(.horizontal, 20)

                            // Team count header
                            HStack {
                                Text("\(filteredMembers.count) TEAM MEMBER\(filteredMembers.count == 1 ? "" : "S")")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                Spacer()
                            }
                            .padding(.horizontal, 20)

                            // Error message
                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(OPSStyle.Colors.errorStatus)

                                    Text(error)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.errorStatus)
                                }
                                .padding(.horizontal, 20)
                            }

                            // Team members list
                            if filteredMembers.isEmpty {
                                emptyStateView
                                    .padding(.horizontal, 20)
                            } else {
                                SectionCard(
                                    icon: "person.3.fill",
                                    title: "Team Members",
                                    contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                                ) {
                                    VStack(spacing: 0) {
                                        ForEach(filteredMembers) { member in
                                            teamMemberRow(member)

                                            if member.id != filteredMembers.last?.id {
                                                Divider()
                                                    .background(OPSStyle.Colors.cardBorder)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }

                            // Add Team Members button (admin only)
                            if isCompanyAdmin {
                                Button(action: { showInviteSheet = true }) {
                                    HStack {
                                        Image(systemName: "person.badge.plus")
                                            .font(.system(size: 14))
                                            .foregroundColor(OPSStyle.Colors.primaryText)

                                        Text("ADD TEAM MEMBERS")
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.buttonBorder, lineWidth: 1)
                                    )
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.vertical, 16)
                        .tabBarPadding()
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadTeamMembers()
        }
        .sheet(isPresented: $showEditSheet) {
            if let member = selectedMember {
                EditTeamMemberSheet(
                    member: member,
                    onSave: { updatedRole in
                        Task {
                            await updateMemberRole(member, newRole: updatedRole)
                        }
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
        .alert("Remove Team Member", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {
                memberToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let member = memberToRemove {
                    Task {
                        await removeMember(member)
                    }
                }
            }
        } message: {
            if let member = memberToRemove {
                Text("Are you sure you want to remove \(member.fullName) from the team? They will lose access to the company.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TeamInvitesSent"))) { notification in
            if let count = notification.userInfo?["count"] as? Int {
                inviteSentCount = count
                showInviteSentMessage = true
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

    // MARK: - Team Member Row

    private func teamMemberRow(_ member: User) -> some View {
        let isCurrentUser = member.id == dataController.currentUser?.id

        return Button(action: {
            memberToView = member
        }) {
            HStack(spacing: 12) {
                // Avatar
                UserAvatar(user: member, size: 44)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(member.fullName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        if isCurrentUser {
                            Text("YOU")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(OPSStyle.Colors.primaryAccent.opacity(0.2))
                                .cornerRadius(4)
                        }

                        if member.isCompanyAdmin {
                            Text("ADMIN")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(OPSStyle.Colors.warningStatus.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(member.roleDisplay.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        if let email = member.email, !email.isEmpty {
                            Text("•")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text(email)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Admin actions menu (only for admins, not for self)
                if isCompanyAdmin && !isCurrentUser {
                    Menu {
                        Button(action: {
                            selectedMember = member
                            showEditSheet = true
                        }) {
                            Label("Edit Role", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive, action: {
                            memberToRemove = member
                            showRemoveConfirmation = true
                        }) {
                            Label("Remove from Team", systemImage: "person.badge.minus")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }

                // Chevron indicator for navigation
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
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

    // MARK: - Data Loading

    private func loadTeamMembers() {
        guard let companyId = company?.id else {
            isLoading = false
            return
        }

        teamMembers = dataController.getTeamMembers(companyId: companyId)
            .sorted { user1, user2 in
                // Sort: current user first, then admins, then alphabetical
                if user1.id == dataController.currentUser?.id { return true }
                if user2.id == dataController.currentUser?.id { return false }
                if user1.isCompanyAdmin && !user2.isCompanyAdmin { return true }
                if !user1.isCompanyAdmin && user2.isCompanyAdmin { return false }
                return user1.firstName < user2.firstName
            }

        isLoading = false
    }

    // MARK: - Actions

    private func updateMemberRole(_ member: User, newRole: UserRole) async {
        errorMessage = nil

        let employeeTypeValue: String
        switch newRole {
        case .fieldCrew:
            employeeTypeValue = "Field Crew"
        case .officeCrew:
            employeeTypeValue = "Office Crew"
        case .admin:
            employeeTypeValue = "Admin"
        }

        do {
            try await dataController.apiService.updateUser(
                id: member.id,
                userData: [BubbleFields.User.employeeType: employeeTypeValue]
            )

            // Update local model
            await MainActor.run {
                member.role = newRole
                try? dataController.modelContext?.save()
                loadTeamMembers() // Refresh list
            }

            print("[MANAGE_TEAM] Updated \(member.fullName) role to \(employeeTypeValue)")

        } catch {
            await MainActor.run {
                errorMessage = "Failed to update role"
            }
            print("[MANAGE_TEAM] Error updating role: \(error)")
        }
    }

    private func removeMember(_ member: User) async {
        errorMessage = nil

        do {
            // Remove company association from user
            try await dataController.apiService.updateUser(
                id: member.id,
                userData: [BubbleFields.User.company: NSNull()]
            )

            // Remove from local list
            await MainActor.run {
                teamMembers.removeAll { $0.id == member.id }
                memberToRemove = nil
            }

            print("[MANAGE_TEAM] Removed \(member.fullName) from team")

        } catch {
            await MainActor.run {
                errorMessage = "Failed to remove team member"
                memberToRemove = nil
            }
            print("[MANAGE_TEAM] Error removing member: \(error)")
        }
    }
}

// MARK: - Team Invite Sheet

struct TeamInviteSheet: View {
    let companyId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @State private var inviteEmails: [String] = [""]
    @State private var emailErrors: [String?] = [nil]
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("INVITE TEAM MEMBERS")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Text("Team members will receive an email with instructions to download the app and join your organization.")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.horizontal, 20)

                        // Email fields
                        VStack(spacing: 16) {
                            ForEach(inviteEmails.indices, id: \.self) { index in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("TEAM MEMBER \(index + 1)")
                                            .font(OPSStyle.Typography.captionBold)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)

                                        Spacer()

                                        if inviteEmails.count > 1 {
                                            Button(action: {
                                                removeEmail(at: index)
                                            }) {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                                    .font(.system(size: 18))
                                            }
                                        }
                                    }

                                    TextField("", text: Binding(
                                        get: { inviteEmails[index] },
                                        set: { inviteEmails[index] = $0; validateEmail(at: index) }
                                    ))
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(
                                                emailErrors[index] != nil ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.inputFieldBorder,
                                                lineWidth: 1
                                            )
                                    )

                                    if let error = emailErrors[index] {
                                        Text(error)
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.errorStatus)
                                    }
                                }
                            }

                            // Add another button
                            if inviteEmails.count < 10 {
                                Button(action: addEmailField) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                                        Text("Add another team member")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Info box
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: OPSStyle.Icons.info)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                Text("What happens next?")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                bulletPoint("Team members will receive an email invite")
                                bulletPoint("They will download the app and create account")
                                bulletPoint("They will join using your company code")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)

                        // Error message
                        if let error = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
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
                actionText: "Send",
                isActionEnabled: hasValidEmails && !isLoading,
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

    // MARK: - Helpers

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text(text)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    private var hasValidEmails: Bool {
        let validEmails = inviteEmails.enumerated().compactMap { index, email in
            return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && emailErrors[index] == nil ? email : nil
        }
        return !validEmails.isEmpty
    }

    private func addEmailField() {
        inviteEmails.append("")
        emailErrors.append(nil)
    }

    private func removeEmail(at index: Int) {
        guard inviteEmails.count > 1 else { return }
        inviteEmails.remove(at: index)
        emailErrors.remove(at: index)
    }

    private func validateEmail(at index: Int) {
        guard index < emailErrors.count else { return }

        let email = inviteEmails[index].trimmingCharacters(in: .whitespacesAndNewlines)

        if email.isEmpty {
            emailErrors[index] = nil
        } else if !isValidEmail(email) {
            emailErrors[index] = "Please enter a valid email address"
        } else {
            emailErrors[index] = nil
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func sendInvitations() async {
        guard hasValidEmails else { return }

        let validEmails = inviteEmails.enumerated().compactMap { index, email in
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmedEmail.isEmpty && emailErrors[index] == nil ? trimmedEmail : nil
        }

        guard !validEmails.isEmpty else { return }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Use OnboardingService to send invites
            let onboardingService = OnboardingService()
            _ = try await onboardingService.sendInvites(emails: validEmails, companyId: companyId)

            await MainActor.run {
                isLoading = false

                // Success haptic
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Post notification for push-in message
                NotificationCenter.default.post(
                    name: Notification.Name("TeamInvitesSent"),
                    object: nil,
                    userInfo: ["count": validEmails.count]
                )

                // Dismiss immediately
                dismiss()
            }

            print("[TEAM_INVITE] Successfully sent \(validEmails.count) invitations")

        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "Failed to send invitations"

                // Error haptic
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
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
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
                                roleOption(
                                    role: .fieldCrew,
                                    title: "Field Crew",
                                    description: "Works on job sites. Can view assigned projects, update task status, and log work. Limited access to scheduling and client info."
                                )

                                roleOption(
                                    role: .officeCrew,
                                    title: "Office Crew",
                                    description: "Manages operations from the office. Full access to scheduling, client management, project creation, and team coordination."
                                )
                            }
                        }
                        .padding(.horizontal, 20)

                        // Info text
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text("Admin status is managed separately through company settings.")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
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
                    .font(.system(size: 20))
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
                    .stroke(selectedRole == role ? OPSStyle.Colors.primaryAccent.opacity(0.3) : OPSStyle.Colors.cardBorder, lineWidth: 1)
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
