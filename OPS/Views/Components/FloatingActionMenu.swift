//
//  FloatingActionMenu.swift
//  OPS
//
//  Reusable floating action button menu for creating projects, tasks, clients, and task types
//  Only visible to Office Crew and Admin roles
//

import SwiftUI

struct FloatingActionMenu: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    @State private var showCreateMenu = false
    @State private var showingCreateProject = false
    @State private var showingCreateClient = false
    @State private var showingCreateTaskType = false
    @State private var showingCreateTask = false
    @State private var showingCreateInventoryItem = false
    @State private var showingCreateExpense = false
    @State private var showingCreateEstimate = false
    @State private var showingCreateLead = false
    @StateObject private var expenseViewModel = ExpenseViewModel()
    @StateObject private var estimateViewModel = EstimateViewModel()
    @StateObject private var pipelineViewModel = PipelineViewModel()

    // Parameters to determine which tab we're on
    let currentTab: Int
    let hasInventoryAccess: Bool
    var isScheduleTab: Bool = false

    // Inventory tab is index 2 when user has inventory access
    private var isInventoryTab: Bool {
        hasInventoryAccess && currentTab == 2
    }

    // Check if current user can see FAB
    private var canShowFAB: Bool {
        guard dataController.currentUser != nil else { return false }
        if appState.isInventorySelectionMode { return false }
        if isScheduleTab { return true }
        return permissionStore.can("projects.create")
            || permissionStore.can("tasks.create")
            || permissionStore.can("clients.create")
            || permissionStore.can("estimates.create")
            || permissionStore.can("expenses.create")
    }

    /// In tutorial mode, FAB is disabled during fabTap phase or when menu is open
    /// (user needs to tap Create Project instead of closing the menu)
    private var isFABDisabledInTutorial: Bool {
        tutorialMode && (tutorialPhase == .fabTap || showCreateMenu)
    }

    var body: some View {
        ZStack {
            // Dimmed overlay when menu is open
            if showCreateMenu {
                LinearGradient(
                    colors: [Color(OPSStyle.Colors.background).opacity(0.85), .clear],
                    startPoint: .trailing,
                    endPoint: .leading
                )
                .ignoresSafeArea()
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(OPSStyle.Animation.standard, value: showCreateMenu)
                .onTapGesture {
                    // In tutorial mode, don't allow closing menu by tapping background
                    guard !tutorialMode else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showCreateMenu = false
                    }
                }
            }
            

            if canShowFAB {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        VStack(alignment: .trailing, spacing: 24) {
                            // Floating menu items (shown when expanded)
                            if showCreateMenu {
                                // Schedule tab: Request Time Off
                                if isScheduleTab {
                                    FloatingActionItem(
                                        icon: "clock.badge.questionmark",
                                        label: "Request Time Off",
                                        action: {
                                            showCreateMenu = false
                                            NotificationCenter.default.post(
                                                name: Notification.Name("ShowTimeOffRequestSheet"),
                                                object: nil
                                            )
                                        }
                                    )
                                    .offset(x: -10)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(OPSStyle.Animation.standard.delay(1.05), value: showCreateMenu)

                                    // Schedule tab: Personal Event
                                    FloatingActionItem(
                                        icon: "calendar.badge.plus",
                                        label: "Personal Event",
                                        action: {
                                            showCreateMenu = false
                                            NotificationCenter.default.post(
                                                name: Notification.Name("ShowPersonalEventSheet"),
                                                object: nil
                                            )
                                        }
                                    )
                                    .offset(x: -10)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(OPSStyle.Animation.standard.delay(0.90), value: showCreateMenu)
                                }

                                // Permission-gated menu items
                                if permissionStore.can("tasks.create") {
                                    // New Task Type - disabled in tutorial mode
                                    FloatingActionItem(
                                        icon: OPSStyle.Icons.taskType,
                                        label: "New Task Type",
                                        action: {
                                            showCreateMenu = false
                                            showingCreateTaskType = true
                                        }
                                    )
                                    .offset(x: -10)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(OPSStyle.Animation.standard.delay(0.9), value: showCreateMenu)
                                    .opacity(tutorialMode ? 0.4 : 1.0)
                                    .allowsHitTesting(!tutorialMode)
                                }

                                if permissionStore.can("tasks.create") {
                                    // Create Task - disabled in tutorial mode
                                    FloatingActionItem(
                                        icon: OPSStyle.Icons.task,
                                        label: "Create Task",
                                        action: {
                                            showCreateMenu = false
                                            showingCreateTask = true
                                        }
                                    )
                                    .offset(x: -10)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(OPSStyle.Animation.standard.delay(0.75), value: showCreateMenu)
                                    .opacity(tutorialMode ? 0.4 : 1.0)
                                    .allowsHitTesting(!tutorialMode)
                                }

                                if permissionStore.can("projects.create") {
                                    // Create Project - always enabled
                                    FloatingActionItem(
                                        icon: OPSStyle.Icons.project,
                                        label: "Create Project",
                                        action: {
                                            showCreateMenu = false
                                            if tutorialMode {
                                                NotificationCenter.default.post(
                                                    name: Notification.Name("TutorialCreateProjectTapped"),
                                                    object: nil
                                                )
                                            } else {
                                                showingCreateProject = true
                                            }
                                        }
                                    )
                                    .offset(x: -10)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(OPSStyle.Animation.standard.delay(0.6), value: showCreateMenu)
                                }

                                if permissionStore.can("clients.create") {
                                    // Create Client - disabled in tutorial mode
                                    FloatingActionItem(
                                        icon: OPSStyle.Icons.client,
                                        label: "Create Client",
                                        action: {
                                            showCreateMenu = false
                                            showingCreateClient = true
                                        }
                                    )
                                    .offset(x: -10)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(OPSStyle.Animation.standard.delay(0.45), value: showCreateMenu)
                                    .opacity(tutorialMode ? 0.4 : 1.0)
                                    .allowsHitTesting(!tutorialMode)
                                }

                                if permissionStore.can("estimates.create") {
                                    // New Estimate - disabled in tutorial mode
                                    FloatingActionItem(
                                        icon: OPSStyle.Icons.estimateDoc,
                                        label: "New Estimate",
                                        action: {
                                            showCreateMenu = false
                                            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                                                estimateViewModel.setup(companyId: companyId)
                                            }
                                            showingCreateEstimate = true
                                        }
                                    )
                                    .offset(x: -10)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(OPSStyle.Animation.standard.delay(0.3), value: showCreateMenu)
                                    .opacity(tutorialMode ? 0.4 : 1.0)
                                    .allowsHitTesting(!tutorialMode)
                                }

                                if permissionStore.can("pipeline.manage") {
                                    // New Lead - disabled in tutorial mode
                                    FloatingActionItem(
                                        icon: OPSStyle.Icons.pipelineChart,
                                        label: "New Lead",
                                        action: {
                                            showCreateMenu = false
                                            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                                                pipelineViewModel.setup(companyId: companyId)
                                            }
                                            showingCreateLead = true
                                        }
                                    )
                                    .offset(x: -10)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(OPSStyle.Animation.standard.delay(0.15), value: showCreateMenu)
                                    .opacity(tutorialMode ? 0.4 : 1.0)
                                    .allowsHitTesting(!tutorialMode)
                                }

                                if permissionStore.can("expenses.create") {
                                    // Add Expense - disabled in tutorial mode
                                    FloatingActionItem(
                                        icon: OPSStyle.Icons.invoiceReceipt,
                                        label: "Add Expense",
                                        action: {
                                            showCreateMenu = false
                                            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                                                expenseViewModel.setup(companyId: companyId)
                                            }
                                            showingCreateExpense = true
                                        }
                                    )
                                    .offset(x: -10)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(OPSStyle.Animation.standard.delay(0.0), value: showCreateMenu)
                                    .opacity(tutorialMode ? 0.4 : 1.0)
                                    .allowsHitTesting(!tutorialMode)
                                }
                            }

                            // Main plus button
                            // In tutorial fabTap phase: FAB is disabled and greyed out
                            Button(action: {
                                // On inventory tab, directly show inventory form
                                if isInventoryTab {
                                    showingCreateInventoryItem = true
                                    return
                                }

                                // Tutorial mode: notify FAB tapped
                                if tutorialMode && !showCreateMenu {
                                    NotificationCenter.default.post(
                                        name: Notification.Name("TutorialFABTapped"),
                                        object: nil
                                    )
                                }
                                withAnimation(OPSStyle.Animation.standard) {
                                    showCreateMenu.toggle()
                                }
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: OPSStyle.Layout.IconSize.xl))
                                    .foregroundColor(isFABDisabledInTutorial ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.buttonText)
                                    .rotationEffect(.degrees(showCreateMenu ? 225 : 0))
                                    .frame(width: 64, height: 64)
                                    .background {
                                        if isFABDisabledInTutorial {
                                            Circle().fill(OPSStyle.Colors.overlayStrong)
                                        } else {
                                            Circle().fill(.ultraThinMaterial.opacity(0.8))
                                        }
                                    }
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle()
                                            .stroke(isFABDisabledInTutorial ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.buttonText, lineWidth: OPSStyle.Layout.Border.thick)
                                    }
                            }
                            .allowsHitTesting(!isFABDisabledInTutorial)
                        }
                        .padding(.trailing, 36)
                        .padding(.bottom, 140) // Position above tab bar
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateClient) {
            ClientSheet(mode: .create) { _ in }
        }
        .sheet(isPresented: $showingCreateProject) {
            ProjectFormSheet(mode: .create) { _ in }
        }
        .sheet(isPresented: $showingCreateTaskType) {
            TaskTypeSheet(mode: .create { _ in })
        }
        .sheet(isPresented: $showingCreateTask) {
            TaskFormSheet(mode: .create) { _ in }
        }
        .sheet(isPresented: $showingCreateInventoryItem) {
            InventoryFormSheet(item: nil)
        }
        .sheet(isPresented: $showingCreateExpense) {
            ExpenseFormSheet(viewModel: expenseViewModel)
        }
        .sheet(isPresented: $showingCreateEstimate) {
            EstimateFormSheet(viewModel: estimateViewModel)
        }
        .sheet(isPresented: $showingCreateLead) {
            OpportunityFormSheet(viewModel: pipelineViewModel)
        }
    }
}

