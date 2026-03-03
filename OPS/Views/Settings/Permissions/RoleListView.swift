//
//  RoleListView.swift
//  OPS
//
//  Lists all roles from the roles table. Tap to edit permissions for a role.
//

import SwiftUI

struct RoleListView: View {
    @EnvironmentObject private var dataController: DataController

    @State private var roles: [AdminRoleRow] = []
    @State private var rolePermissionCounts: [String: Int] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedRole: AdminRoleRow?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        .scaleEffect(1.2)
                    Text("Loading roles...")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: OPSStyle.Icons.alert)
                        .font(.system(size: OPSStyle.Layout.IconSize.xl))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    Text(error)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Section header
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.shield.checkmark")
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Text("\(roles.count) ROLE\(roles.count == 1 ? "" : "S")")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.horizontal, 20)

                        // Roles card
                        VStack(spacing: 0) {
                            ForEach(roles) { role in
                                roleRow(role)

                                if role.id != roles.last?.id {
                                    Divider()
                                        .background(OPSStyle.Colors.cardBorder)
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
                    .padding(.vertical, 16)
                    .tabBarPadding()
                }
            }
        }
        .onAppear {
            loadRoles()
        }
        .fullScreenCover(item: $selectedRole) { role in
            NavigationStack {
                RoleDetailView(role: role)
                    .environmentObject(dataController)
            }
        }
    }

    // MARK: - Role Row

    private func roleRow(_ role: AdminRoleRow) -> some View {
        Button(action: {
            selectedRole = role
        }) {
            HStack(spacing: 14) {
                Image(systemName: PermissionRegistry.iconForRole(role.name))
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(PermissionRegistry.displayName(for: role.name).uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    let count = rolePermissionCounts[role.id] ?? 0
                    Text("\(count) permission\(count == 1 ? "" : "s")")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Data Loading

    private func loadRoles() {
        Task {
            do {
                let fetchedRoles = try await PermissionAdminService.fetchAllRoles()
                var counts: [String: Int] = [:]

                for role in fetchedRoles {
                    let perms = try await PermissionAdminService.fetchRolePermissions(roleId: role.id)
                    counts[role.id] = perms.count
                }

                await MainActor.run {
                    self.roles = fetchedRoles
                    self.rolePermissionCounts = counts
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load roles: \(error.localizedDescription)"
                    self.isLoading = false
                }
                print("[PERMISSIONS] Error loading roles: \(error)")
            }
        }
    }
}
