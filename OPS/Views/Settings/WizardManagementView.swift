//
//  WizardManagementView.swift
//  OPS
//
//  Settings view showing all available wizards with their
//  completion status. Users can start, resume, or restart wizards
//  and manage "don't show" preferences.
//
//  Data-dependent wizards show a lock label explaining what
//  the user needs before the wizard becomes useful.
//

import SwiftUI
import SwiftData

struct WizardManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wizardStateManager) private var optionalStateManager
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    private var availableWizards: [any WizardDefinitionProtocol] {
        guard let role = dataController.currentUser?.role else { return [] }
        return WizardRegistry.wizardsForDisplay(role: role)
    }

    /// Returns a lock reason if the wizard's prerequisites aren't met, or nil if unlocked.
    /// Checks permissions first, then data prerequisites.
    private func lockReason(for wizard: any WizardDefinitionProtocol) -> String? {
        // Permission check — wizard requires a permission the user doesn't have
        if let required = wizard.requiredPermission, !permissionStore.can(required) {
            switch required {
            case "projects.create":
                return "Requires project creation permission"
            case "team.manage":
                return "Requires team management permission"
            case "settings.company":
                return "Requires company settings permission"
            default:
                return "Requires additional permissions"
            }
        }

        // Data prerequisite checks
        guard let context = dataController.modelContext else { return nil }
        let companyId = dataController.currentUser?.companyId ?? ""

        switch wizard.wizardId {
        case "job_board", "documentation":
            let desc = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.companyId == companyId }
            )
            let count = (try? context.fetchCount(desc)) ?? 0
            return count == 0 ? "Create a project first" : nil

        case "scheduling_calendar":
            let desc = FetchDescriptor<ProjectTask>(
                predicate: #Predicate<ProjectTask> { $0.companyId == companyId }
            )
            let tasks = (try? context.fetch(desc)) ?? []
            let scheduled = tasks.filter { $0.startDate != nil }
            return scheduled.isEmpty ? "Schedule a task first" : nil

        case "task_review":
            let desc = FetchDescriptor<ProjectTask>(
                predicate: #Predicate<ProjectTask> { $0.companyId == companyId }
            )
            let tasks = (try? context.fetch(desc)) ?? []
            let now = Date()
            let overdue = tasks.filter { t in
                guard let end = t.endDate else { return false }
                return end < now && t.status != .completed
            }.count
            let completed = tasks.filter { $0.status == .completed }.count
            if overdue < 5 { return "\(5 - overdue) more overdue tasks to unlock" }
            if completed < 5 { return "\(5 - completed) more completed tasks to unlock" }
            return nil

        case "payment_review":
            let desc = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.companyId == companyId }
            )
            let projects = (try? context.fetch(desc)) ?? []
            let completed = projects.filter { $0.status == .completed }.count
            if completed < 5 { return "\(5 - completed) more completed projects to unlock" }
            return nil

        default:
            return nil
        }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Setup Guides",
                    onBackTapped: { dismiss() }
                )

                ScrollView {
                    VStack(spacing: 24) {
                        ForEach(Array(availableWizards.enumerated()), id: \.element.wizardId) { _, wizard in
                            wizardRow(wizard: wizard)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func wizardRow(wizard: any WizardDefinitionProtocol) -> some View {
        let state = optionalStateManager?.wizardState(for: wizard.wizardId)
        let locked = lockReason(for: wizard)

        if let locked {
            // Locked row — not tappable, shows lock reason
            HStack(spacing: 14) {
                Image(systemName: wizard.iconName)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(wizard.displayName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                        Text(locked)
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder.opacity(0.5), lineWidth: OPSStyle.Layout.Border.standard)
            )
        } else {
            // Unlocked row — tappable
            NavigationLink {
                WizardDetailView(wizard: wizard)
                    .environmentObject(dataController)
                    .environmentObject(permissionStore)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: wizard.iconName)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.wizardAccent)
                        .frame(width: 28, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(wizard.displayName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        statusText(for: state)
                    }

                    Spacer()

                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .buttonStyle(PlainButtonStyle())
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    @ViewBuilder
    private func statusText(for state: WizardState?) -> some View {
        if let state {
            switch state.status {
            case .completed:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.successStatus)
                    Text("Completed")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.successStatus)
                }
            case .inProgress:
                Text("\(state.currentStepIndex + 1) / \(WizardRegistry.wizard(for: state.wizardId)?.totalSteps ?? 0) steps")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            case .notStarted:
                if state.doNotShow {
                    Text("Dismissed")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                } else {
                    Text("Not started")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            case .dismissed:
                Text("Dismissed")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        } else {
            Text("Not started")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }
}
