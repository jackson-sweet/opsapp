//
//  FloatingActionMenu.swift
//  OPS
//
//  Reusable floating action button with universal grouped menu for creating
//  projects, tasks, clients, estimates, expenses, invoices, payments, events, and time off.
//  Only visible to Office Crew and Admin roles.
//

import SwiftUI

// MARK: - FAB Menu Data Models

/// A single item in the FAB menu
private struct FABMenuItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let permission: String?  // nil means always visible
    let disabledInTutorial: Bool
    let action: () -> Void
}

/// A group of related menu items with a header
private struct FABMenuGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [FABMenuItem]
}

struct FloatingActionMenu: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    @State private var showCreateMenu = false

    // Sheet presentation states — existing
    @State private var showingCreateProject = false
    @State private var showingCreateClient = false
    @State private var showingCreateTaskType = false
    @State private var showingCreateTask = false
    @State private var showingCreateInventoryItem = false
    @State private var showingCreateExpense = false
    @State private var showingCreateEstimate = false

    // Sheet presentation states — new for Money group
    @State private var showingCreateInvoice = false
    @State private var showingRecordPayment = false

    // View models
    @StateObject private var expenseViewModel = ExpenseViewModel()
    @StateObject private var estimateViewModel = EstimateViewModel()

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

    // MARK: - Menu Groups

    /// Build the universal grouped menu items
    private var menuGroups: [FABMenuGroup] {
        [
            // Group 1: Work
            FABMenuGroup(title: "WORK", items: [
                FABMenuItem(
                    icon: OPSStyle.Icons.addProject,
                    label: "New Project",
                    permission: "projects.create",
                    disabledInTutorial: false,
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
                ),
                FABMenuItem(
                    icon: OPSStyle.Icons.task,
                    label: "New Task",
                    permission: "tasks.create",
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        showingCreateTask = true
                    }
                ),
                FABMenuItem(
                    icon: OPSStyle.Icons.client,
                    label: "New Client",
                    permission: "clients.create",
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        showingCreateClient = true
                    }
                ),
                FABMenuItem(
                    icon: OPSStyle.Icons.taskType,
                    label: "New Task Type",
                    permission: "tasks.create",
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        showingCreateTaskType = true
                    }
                ),
            ]),

            // Group 2: Money
            FABMenuGroup(title: "MONEY", items: [
                FABMenuItem(
                    icon: OPSStyle.Icons.estimateDoc,
                    label: "New Estimate",
                    permission: "estimates.create",
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                            estimateViewModel.setup(companyId: companyId)
                        }
                        showingCreateEstimate = true
                    }
                ),
                FABMenuItem(
                    icon: OPSStyle.Icons.invoiceReceipt,
                    label: "New Invoice",
                    permission: "estimates.create",
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        showingCreateInvoice = true
                    }
                ),
                FABMenuItem(
                    icon: OPSStyle.Icons.banknoteFill,
                    label: "New Payment",
                    permission: "expenses.create",
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        showingRecordPayment = true
                    }
                ),
                FABMenuItem(
                    icon: OPSStyle.Icons.expense,
                    label: "New Expense",
                    permission: "expenses.create",
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                            expenseViewModel.setup(companyId: companyId)
                        }
                        showingCreateExpense = true
                    }
                ),
            ]),

            // Group 3: Scheduling
            FABMenuGroup(title: "SCHEDULING", items: [
                FABMenuItem(
                    icon: "clock.badge.questionmark",
                    label: "New Time Off",
                    permission: nil,
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        NotificationCenter.default.post(
                            name: Notification.Name("ShowTimeOffRequestSheet"),
                            object: nil
                        )
                    }
                ),
                FABMenuItem(
                    icon: "calendar.badge.plus",
                    label: "New Event",
                    permission: nil,
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        NotificationCenter.default.post(
                            name: Notification.Name("ShowPersonalEventSheet"),
                            object: nil
                        )
                    }
                ),
            ]),
        ]
    }

    /// Filter groups to only include items the user has permission for,
    /// and exclude empty groups.
    private var visibleGroups: [FABMenuGroup] {
        menuGroups.compactMap { group in
            let visibleItems = group.items.filter { item in
                if let permission = item.permission {
                    return permissionStore.can(permission)
                }
                return true
            }
            guard !visibleItems.isEmpty else { return nil }
            return FABMenuGroup(title: group.title, items: visibleItems)
        }
    }

    // MARK: - Body

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
                    withAnimation(OPSStyle.Animation.fast) {
                        showCreateMenu = false
                    }
                }
            }

            if canShowFAB {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        VStack(alignment: .trailing, spacing: 0) {
                            // Grouped menu items (shown when expanded)
                            if showCreateMenu {
                                ScrollView(.vertical, showsIndicators: false) {
                                    VStack(alignment: .trailing, spacing: 12) {
                                        ForEach(Array(visibleGroups.enumerated()), id: \.element.id) { groupIndex, group in
                                            // Group divider (between groups, not before first)
                                            if groupIndex > 0 {
                                                Rectangle()
                                                    .fill(OPSStyle.Colors.separator)
                                                    .frame(width: 180, height: 1)
                                                    .padding(.vertical, 4)
                                            }

                                            // Group header
                                            Text(group.title)
                                                .font(OPSStyle.Typography.captionBold)
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                .padding(.trailing, 4)

                                            // Group items
                                            ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, item in
                                                let flatIndex = flatItemIndex(groupIndex: groupIndex, itemIndex: itemIndex)
                                                let delay = Double(flatIndex) * 0.05

                                                fabMenuItemView(item: item)
                                                    .offset(x: -10)
                                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                                    .animation(
                                                        OPSStyle.Animation.standard.delay(delay),
                                                        value: showCreateMenu
                                                    )
                                            }
                                        }
                                    }
                                    .scrollTargetLayout()
                                    .padding(.bottom, 16)
                                    .padding(.top, 8)
                                }
                                .frame(maxHeight: 320)
                                .scrollTargetBehavior(.viewAligned)
                                // Edge fade mask — items dissolve at top and bottom
                                .mask(
                                    VStack(spacing: 0) {
                                        LinearGradient(
                                            colors: [.clear, .black],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 40)
                                        Color.black
                                        LinearGradient(
                                            colors: [.black, .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 40)
                                    }
                                )
                                .transition(
                                    .opacity.combined(with: .scale(scale: 0.8, anchor: .bottomTrailing))
                                )
                            }

                            // Main plus button
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
                                if showCreateMenu {
                                    withAnimation(OPSStyle.Animation.fast) {
                                        showCreateMenu = false
                                    }
                                } else {
                                    withAnimation(OPSStyle.Animation.spring) {
                                        showCreateMenu = true
                                    }
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
        // TODO: Wire up when InvoiceFormSheet is implemented
        // .sheet(isPresented: $showingCreateInvoice) {
        //     InvoiceFormSheet()
        // }
        // TODO: Wire up when RecordPaymentSheet is implemented
        // .sheet(isPresented: $showingRecordPayment) {
        //     RecordPaymentSheet()
        // }
    }

    // MARK: - Helpers

    /// Calculate a flat index across all groups for staggered animation delays
    private func flatItemIndex(groupIndex: Int, itemIndex: Int) -> Int {
        var count = 0
        for g in 0..<groupIndex {
            count += visibleGroups[g].items.count
        }
        return count + itemIndex
    }

    /// Render a single FAB menu item row
    @ViewBuilder
    private func fabMenuItemView(item: FABMenuItem) -> some View {
        let isDisabledByTutorial = tutorialMode && item.disabledInTutorial

        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            item.action()
        }) {
            HStack(spacing: 12) {
                Text(item.label.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Image(systemName: item.icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 48, height: 48)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
        }
        .opacity(isDisabledByTutorial ? 0.4 : 1.0)
        .allowsHitTesting(!isDisabledByTutorial)
    }
}
