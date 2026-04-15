//
//  AssignMemberRoleSheet.swift
//  OPS
//
//  Sheet triggered by a member_joined OneSignal push. Shows member
//  identity, conditional UNSEATED banner (unseated case), dynamic RBAC
//  role picker, save action. Uses dynamic roles from
//  PermissionAdminService.fetchAllRoles() rather than the hardcoded
//  UserRole enum so custom company roles work.
//

import SwiftUI
import SwiftData
import UIKit

struct AssignMemberRoleSheet: View {
    let memberId: String
    let wasSeated: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var dataController: DataController

    @State private var member: User?
    @State private var roles: [AdminRoleRow] = []
    @State private var selectedRoleId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isLoadingRoles = true

    private var firstName: String {
        let name = member?.firstName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "This member" : name
    }

    private var fullName: String {
        let parts = [member?.firstName, member?.lastName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: " ")
        if !joined.isEmpty { return joined }
        return member?.email ?? "This member"
    }

    /// Reads the live seat state from the user's current company in SwiftData.
    /// Falls back to the wasSeated flag from the push payload if the company
    /// row isn't in the local store (cold-launch edge case).
    private var isCurrentlySeated: Bool {
        guard let companyId = dataController.currentUser?.companyId,
              let context = dataController.modelContext else {
            return wasSeated
        }
        let descriptor = FetchDescriptor<Company>(
            predicate: #Predicate<Company> { $0.id == companyId }
        )
        if let company = (try? context.fetch(descriptor))?.first {
            return company.getSeatedEmployeeIds().contains(memberId)
        }
        return wasSeated
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    memberHeader

                    if !isCurrentlySeated {
                        seatBanner
                    }

                    roleSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    }
                }
                .padding(16)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("Assign role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        saveRole()
                    }
                    .disabled(selectedRoleId == nil || isSaving)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Sections

    private var memberHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .frame(width: 56, height: 56)
                Text(firstName.prefix(1).uppercased())
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(fullName)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                if let email = member?.email, !email.isEmpty {
                    Text(email)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var seatBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                Text("UNSEATED")
                    .font(OPSStyle.Typography.smallCaption.weight(.semibold))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }

            Text("\(firstName) joined your crew but can't access OPS until you shift a seat or upgrade your plan.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openWebSeats()
            } label: {
                HStack(spacing: 4) {
                    Text("Manage seats on web")
                        .font(OPSStyle.Typography.smallCaption.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(OPSStyle.Colors.warningStatus)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.warningStatus.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(OPSStyle.Colors.warningStatus.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROLE")
                .font(OPSStyle.Typography.smallCaption.weight(.semibold))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if isLoadingRoles {
                HStack {
                    ProgressView()
                    Text("Loading roles…")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(roles) { role in
                        RoleRow(
                            role: role,
                            isSelected: selectedRoleId == role.id,
                            onTap: {
                                // Discovery beat — selection feedback
                                UISelectionFeedbackGenerator().selectionChanged()
                                selectedRoleId = role.id
                            }
                        )
                        if role.id != roles.last?.id {
                            Divider()
                                .background(OPSStyle.Colors.cardBackgroundDark)
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    // MARK: - Actions

    private func loadData() async {
        // 1. Member — from local SwiftData cache via DataController
        let localMember = dataController.getUser(id: memberId)
        await MainActor.run { self.member = localMember }

        // 2. Roles — live fetch from PermissionAdminService (includes custom roles)
        do {
            let fetchedRoles = try await PermissionAdminService.fetchAllRoles()
            // 3. Current role — from user_roles table for pre-selection
            let currentRoleRow = try? await PermissionAdminService.fetchUserRole(userId: memberId)

            await MainActor.run {
                self.roles = fetchedRoles
                self.isLoadingRoles = false
                if let roleId = currentRoleRow?.role_id,
                   fetchedRoles.contains(where: { $0.id == roleId }) {
                    self.selectedRoleId = roleId
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Couldn't load roles: \(error.localizedDescription)"
                self.isLoadingRoles = false
            }
        }
    }

    private func saveRole() {
        guard let roleId = selectedRoleId else { return }
        isSaving = true
        errorMessage = nil

        // Commitment beat — thud at tap, confirmation bell after network returns
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                try await PermissionAdminService.assignUserRole(
                    userId: memberId,
                    roleId: roleId
                )
                // Also mark related role_needed notifications as read
                try? await NotificationRepository.shared.markRoleNeededNotificationsAsReadForMember(
                    memberId: memberId
                )
                await MainActor.run {
                    // Confirmation bell fires 200ms after commit — two-beat haptic
                    // communicates "received, and confirmed"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Couldn't save role: \(error.localizedDescription)"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func openWebSeats() {
        if let url = URL(string: "https://app.opsapp.co/settings?tab=team") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Role Row

private struct RoleRow: View {
    let role: AdminRoleRow
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(
                        isSelected
                            ? OPSStyle.Colors.primaryAccent
                            : OPSStyle.Colors.secondaryText
                    )

                Text(role.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
