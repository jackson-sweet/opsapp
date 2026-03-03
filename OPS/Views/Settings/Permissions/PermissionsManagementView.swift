//
//  PermissionsManagementView.swift
//  OPS
//
//  Main container for permissions management. Two-tab layout: Roles | Team.
//  Admin-only, gated by settings.company permission.
//

import SwiftUI

struct PermissionsManagementView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case roles = "Roles"
        case team = "Team"
    }

    @State private var selectedTab: Tab = .roles

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Permissions",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)

                // Tab selector
                SegmentedControl(
                    selection: $selectedTab,
                    options: [
                        (.roles, "ROLES"),
                        (.team, "TEAM")
                    ]
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Tab content
                switch selectedTab {
                case .roles:
                    RoleListView()
                        .environmentObject(dataController)
                case .team:
                    UserPermissionsListView()
                        .environmentObject(dataController)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    PermissionsManagementView()
        .environmentObject(DataController())
        .environmentObject(PermissionStore.shared)
        .preferredColorScheme(.dark)
}
