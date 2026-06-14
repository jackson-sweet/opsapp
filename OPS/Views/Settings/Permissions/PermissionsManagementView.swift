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
                .padding(.bottom, OPSStyle.Layout.spacing2)

                // Tab selector
                SegmentedControl(
                    selection: $selectedTab,
                    options: [
                        (.roles, "ROLES"),
                        (.team, "TEAM")
                    ]
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing3)
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
        .onDisappear {
            NotificationCenter.default.post(
                name: Notification.Name("WizardScreenDismissed"),
                object: nil,
                userInfo: ["screen": "Permissions"]
            )
        }
        .onAppear {
            // Wizard system: evaluate permissions wizard trigger
            if let wizard = WizardRegistry.contextualWizard(for: "permissions_roles") {
                wizardTriggerService?.evaluateTrigger(for: wizard, context: "permissions_visit")
            }
            // Wizard system: notify roles tab viewed after user has time to read the list.
            // Re-fires each time view appears (safe — observer auto-cancels after step completes)
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
        // Bug e33aa336 — settings search deep-link. When a result targets
        // "team" (e.g. "Team Permissions"), flip to the Team tab on arrival.
        // "roles" / "add_role" results stay on the Roles tab. Any unknown
        // section ID is a no-op so the view behaves exactly as before.
        .onReceive(NotificationCenter.default.publisher(for: SettingsDeepLink.permissions)) { notification in
            guard let section = notification.userInfo?[SettingsDeepLink.userInfoSectionKey] as? String else { return }
            switch section {
            case "team":
                if selectedTab != .team {
                    withAnimation(OPSStyle.Animation.spring) {
                        selectedTab = .team
                    }
                }
            case "roles", "add_role":
                if selectedTab != .roles {
                    withAnimation(OPSStyle.Animation.spring) {
                        selectedTab = .roles
                    }
                }
            default:
                break
            }
        }
        // Wizard: re-fire step 1 notification when wizard navigates here while the view is already visible.
        // Handles the race where .onAppear notifications fired before the wizard's step observer was listening.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardNavigateToTarget"))) { notification in
            if let targetScreen = notification.userInfo?["targetScreen"] as? String, targetScreen == "Permissions" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NotificationCenter.default.post(
                        name: Notification.Name("WizardRolesTabViewed"),
                        object: nil
                    )
                }
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
