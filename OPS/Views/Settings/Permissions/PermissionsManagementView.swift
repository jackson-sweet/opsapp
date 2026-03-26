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
    @Environment(\.wizardTriggerService) private var wizardTriggerService

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
                .wizardTarget("switch_to_team")

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
        .trackScreen("Settings.Permissions")
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Wizard system: evaluate permissions wizard trigger
            if let wizard = WizardRegistry.contextualWizard(for: "permissions_roles") {
                wizardTriggerService?.evaluateTrigger(for: wizard, context: "permissions_visit")
            }
            // Wizard system: notify roles tab viewed (delayed to avoid timing race —
            // evaluateTrigger shows the banner; user must tap Launch before this fires)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                NotificationCenter.default.post(
                    name: Notification.Name("WizardRolesTabViewed"),
                    object: nil
                )
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .team {
                NotificationCenter.default.post(
                    name: Notification.Name("WizardTeamPermissionsViewed"),
                    object: nil
                )
            }
        }
    }
}

#Preview {
    PermissionsManagementView()
        .environmentObject(DataController())
        .environmentObject(PermissionStore.shared)
        .preferredColorScheme(.dark)
}
