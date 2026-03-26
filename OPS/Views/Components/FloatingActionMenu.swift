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
fileprivate struct FABMenuItem: Identifiable {
    let id: String
    let icon: String
    let label: String
    let permission: String?
    let disabledInTutorial: Bool
    let lockedMessage: String?
    let badge: Int?
    let action: () -> Void

    init(id: String, icon: String, label: String, permission: String?, disabledInTutorial: Bool, lockedMessage: String? = nil, badge: Int? = nil, action: @escaping () -> Void) {
        self.id = id
        self.icon = icon
        self.label = label
        self.permission = permission
        self.disabledInTutorial = disabledInTutorial
        self.lockedMessage = lockedMessage
        self.badge = badge
        self.action = action
    }
}

/// A group of related menu items with a header
fileprivate struct FABMenuGroup: Identifiable {
    let id: String
    let title: String
    let items: [FABMenuItem]
}

/// A flattened row for scroll-snap alignment
fileprivate struct FlatFABRow: Identifiable {
    let id: String
    let item: FABMenuItem
    let groupId: String
    let groupHeader: String?
    let showDivider: Bool
    let flatIndex: Int
}

struct FloatingActionMenu: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    @State private var showCreateMenu = false
    @State private var itemsRevealed = false
    @State private var showingCustomizeSheet = false
    @AppStorage("fabHiddenItems") private var hiddenItemsData: Data = Data()
    @AppStorage("fabItemOrder") private var itemOrderData: Data = Data()
    @AppStorage("fabSectionOrder") private var sectionOrderData: Data = Data()

    // Edit mode
    @State private var isEditMode = false
    @State private var draggingItemId: String?
    @State private var dragOffset: CGFloat = 0

    // Edit mode: snapshot for cancel
    @State private var editInitialHidden: Data = Data()
    @State private var editInitialOrder: Data = Data()

    // Review sheet states
    @State private var showTaskReviewFromFAB: Bool = false
    @State private var showPaymentReviewFromFAB: Bool = false
    @State private var showIncompleteReviewFromFAB: Bool = false
    @State private var showLockedAlert: Bool = false
    @State private var lockedAlertMessage: String = ""
    @State private var showPaymentReviewIntroFAB: Bool = false
    @State private var showTaskReviewIntroFAB: Bool = false

    // Sheet presentation states
    @State private var showingCreateProject = false
    @State private var showingCreateClient = false
    @State private var showingCreateTaskType = false
    @State private var showingCreateTask = false
    @State private var showingCreateInventoryItem = false
    @State private var showingCreateExpense = false
    @State private var showingCreateEstimate = false
    @State private var showingCreateInvoice = false
    @State private var showingRecordPayment = false
    @State private var showingPersonalEventSheet = false
    @State private var showingTimeOffSheet = false
    @State private var showingLogActivity = false

    // View models
    @StateObject private var expenseViewModel = ExpenseViewModel()
    @StateObject private var estimateViewModel = EstimateViewModel()
    @StateObject private var calendarViewModel = CalendarViewModel()

    // Parameters
    let currentTab: Int
    let hasInventoryAccess: Bool
    var isScheduleTab: Bool = false
    var isInventoryTab: Bool = false

    private let dragRowHeight: CGFloat = 64

    // MARK: - Hidden Items

    private var hiddenItemIds: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: hiddenItemsData)) ?? []
    }

    private func setHiddenItems(_ ids: Set<String>) {
        hiddenItemsData = (try? JSONEncoder().encode(ids)) ?? Data()
    }

    // MARK: - Item Order

    private var storedOrder: [String] {
        (try? JSONDecoder().decode([String].self, from: itemOrderData)) ?? []
    }

    private func setStoredOrder(_ order: [String]) {
        itemOrderData = (try? JSONEncoder().encode(order)) ?? Data()
    }

    // MARK: - Section Order

    private var sectionOrder: [String] {
        let stored = (try? JSONDecoder().decode([String].self, from: sectionOrderData)) ?? []
        if stored.isEmpty { return menuGroups.map(\.id) }
        let allGroupIds = menuGroups.map(\.id)
        var result = stored.filter { allGroupIds.contains($0) }
        for id in allGroupIds where !result.contains(id) {
            result.append(id)
        }
        return result
    }

    private func setSectionOrder(_ order: [String]) {
        sectionOrderData = (try? JSONEncoder().encode(order)) ?? Data()
    }

    // MARK: - Item Lookup

    private var itemLookup: [String: (item: FABMenuItem, groupId: String, groupTitle: String)] {
        var lookup: [String: (item: FABMenuItem, groupId: String, groupTitle: String)] = [:]
        for group in menuGroups {
            for item in group.items {
                lookup[item.id] = (item: item, groupId: group.id, groupTitle: group.title)
            }
        }
        return lookup
    }

    private var hasHiddenItems: Bool {
        let hidden = hiddenItemIds
        guard !hidden.isEmpty else { return false }
        return menuGroups.flatMap(\.items).contains { item in
            guard hidden.contains(item.id) else { return false }
            if let perm = item.permission { return permissionStore.can(perm) }
            return true
        }
    }

    private var canShowFAB: Bool {
        guard dataController.currentUser != nil else { return false }
        if appState.isInventorySelectionMode { return false }
        if isScheduleTab { return true }
        if isInventoryTab && hasInventoryAccess { return true }
        return permissionStore.can("projects.create")
            || permissionStore.can("tasks.create")
            || permissionStore.can("clients.create")
            || permissionStore.can("estimates.create")
            || permissionStore.can("expenses.create")
            || permissionStore.can("pipeline.manage")
    }

    private var isFABDisabledInTutorial: Bool {
        tutorialMode && (tutorialPhase == .fabTap || showCreateMenu)
    }

    // MARK: - Menu Groups

    private var menuGroups: [FABMenuGroup] {
        var workItems: [FABMenuItem] = []

        // Log Activity — only when pipeline feature is enabled
        if permissionStore.isFeatureEnabled("pipeline") {
            workItems.append(
                FABMenuItem(
                    id: "log-activity",
                    icon: "text.bubble",
                    label: "Log Activity",
                    permission: "pipeline.manage",
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        showingLogActivity = true
                    }
                )
            )
        }

        workItems.append(contentsOf: [
            FABMenuItem(
                id: "new-project",
                    icon: OPSStyle.Icons.addProject,
                    label: "New Project",
                    permission: "projects.create",
                    disabledInTutorial: false,
                    action: {
                        showCreateMenu = false
                        // Wizard system: notify create project tapped
                        NotificationCenter.default.post(
                            name: Notification.Name("WizardCreateProjectTapped"),
                            object: nil
                        )
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
                    id: "new-task",
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
                    id: "new-client",
                    icon: OPSStyle.Icons.client,
                    label: "New Client",
                    permission: "clients.create",
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        // Wizard system: notify create client tapped
                        NotificationCenter.default.post(
                            name: Notification.Name("WizardCreateClientTapped"),
                            object: nil
                        )
                        showingCreateClient = true
                    }
                ),
                FABMenuItem(
                    id: "new-task-type",
                    icon: OPSStyle.Icons.taskType,
                    label: "New Task Type",
                    permission: "tasks.create",
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        showingCreateTaskType = true
                    }
                ),
        ])

        var groups: [FABMenuGroup] = [
            FABMenuGroup(id: "work", title: "WORK", items: workItems),
        ]

        // Pipeline money items — only shown when the pipeline feature flag is enabled
        if permissionStore.isFeatureEnabled("pipeline") {
            groups.append(
                FABMenuGroup(id: "money", title: "MONEY", items: [
                    FABMenuItem(
                        id: "new-estimate",
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
                        id: "new-invoice",
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
                        id: "new-payment",
                        icon: OPSStyle.Icons.banknoteFill,
                        label: "New Payment",
                        permission: "expenses.create",
                        disabledInTutorial: true,
                        action: {
                            showCreateMenu = false
                            showingRecordPayment = true
                        }
                    ),
                ])
            )
        }

        // Expenses — standalone feature, gated by expenses.create RBAC permission (not feature flag)
        groups.append(
            FABMenuGroup(id: "expenses", title: "EXPENSES", items: [
                FABMenuItem(
                    id: "new-expense",
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
            ])
        )

        // Inventory — shown when user has inventory access
        if hasInventoryAccess {
            groups.append(
                FABMenuGroup(id: "inventory", title: "INVENTORY", items: [
                    FABMenuItem(
                        id: "new-inventory-item",
                        icon: "shippingbox.fill",
                        label: "New Inventory Item",
                        permission: "inventory.manage",
                        disabledInTutorial: true,
                        action: {
                            showCreateMenu = false
                            showingCreateInventoryItem = true
                        }
                    ),
                ])
            )
        }

        groups.append(
            FABMenuGroup(id: "scheduling", title: "SCHEDULING", items: [
                FABMenuItem(
                    id: "new-time-off",
                    icon: "clock.badge.questionmark",
                    label: "New Time Off",
                    permission: nil,
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        showingTimeOffSheet = true
                    }
                ),
                FABMenuItem(
                    id: "new-event",
                    icon: "calendar.badge.plus",
                    label: "New Event",
                    permission: nil,
                    disabledInTutorial: true,
                    action: {
                        showCreateMenu = false
                        showingPersonalEventSheet = true
                    }
                ),
            ])
        )

        let completedTaskCount = dataController.getAllTasks().filter { $0.status == .completed }.count
        let completedProjectCount = dataController.getProjects().filter { $0.status == .completed || $0.status == .closed }.count
        let taskReviewThreshold = 5
        let paymentReviewThreshold = 5
        let isTaskReviewLocked = completedTaskCount < taskReviewThreshold
        let isPaymentReviewLocked = completedProjectCount < paymentReviewThreshold

        // Compute review counts for badges
        let taskReviewCount = isTaskReviewLocked ? 0 : computeFABReviewableTasks().count
        let unassignedReviewCount = computeFABIncompleteTasks().count
        let completionReviewCount = isPaymentReviewLocked ? 0 : (computeFABOverdueProjects().count + computeFABCompletedProjects().count)

        groups.append(
            FABMenuGroup(id: "review", title: "REVIEW", items: [
                FABMenuItem(
                    id: "task-review",
                    icon: "checklist",
                    label: "Task Review",
                    permission: nil,
                    disabledInTutorial: true,
                    lockedMessage: isTaskReviewLocked ? "Complete \(taskReviewThreshold) tasks to unlock task review. You've completed \(completedTaskCount) so far." : nil,
                    badge: taskReviewCount > 0 ? taskReviewCount : nil,
                    action: {
                        showCreateMenu = false
                        if !UserDefaults.standard.bool(forKey: "review_task_intro_shown") {
                            UserDefaults.standard.set(true, forKey: "review_task_intro_shown")
                            showTaskReviewIntroFAB = true
                        } else {
                            showTaskReviewFromFAB = true
                        }
                    }
                ),
                FABMenuItem(
                    id: "unassigned-review",
                    icon: "calendar.badge.exclamationmark",
                    label: "Unassigned Review",
                    permission: "tasks.edit",
                    disabledInTutorial: true,
                    badge: unassignedReviewCount > 0 ? unassignedReviewCount : nil,
                    action: {
                        showCreateMenu = false
                        showIncompleteReviewFromFAB = true
                    }
                ),
                FABMenuItem(
                    id: "payment-review",
                    icon: "rectangle.stack.fill",
                    label: "Completion Review",
                    permission: "projects.edit",
                    disabledInTutorial: true,
                    lockedMessage: isPaymentReviewLocked ? "Complete \(paymentReviewThreshold) projects to unlock payment review. You've completed \(completedProjectCount) so far." : nil,
                    badge: completionReviewCount > 0 ? completionReviewCount : nil,
                    action: {
                        showCreateMenu = false
                        if !UserDefaults.standard.bool(forKey: "review_payment_intro_shown") {
                            UserDefaults.standard.set(true, forKey: "review_payment_intro_shown")
                            showPaymentReviewIntroFAB = true
                        } else {
                            showPaymentReviewFromFAB = true
                        }
                    }
                ),
            ])
        )

        return groups
    }

    /// All items the user has permission for
    private var allPermittedItems: [(group: FABMenuGroup, items: [FABMenuItem])] {
        menuGroups.compactMap { group in
            let permitted = group.items.filter { item in
                if let permission = item.permission {
                    return permissionStore.can(permission)
                }
                return true
            }
            guard !permitted.isEmpty else { return nil }
            return (group: group, items: permitted)
        }
    }

    // MARK: - Edit Mode Grouped Items

    /// All permitted items grouped by section in section order. Includes hidden items.
    private var editModeGroupedItems: [(groupId: String, groupTitle: String, items: [FABMenuItem])] {
        let order = sectionOrder
        var result: [(groupId: String, groupTitle: String, items: [FABMenuItem])] = []

        for groupId in order {
            guard let group = menuGroups.first(where: { $0.id == groupId }) else { continue }
            let permittedItems = group.items.filter { item in
                if let perm = item.permission { return permissionStore.can(perm) }
                return true
            }
            guard !permittedItems.isEmpty else { continue }

            let groupItemIds = Set(permittedItems.map(\.id))
            let ordered = storedOrder.filter { groupItemIds.contains($0) }
            let remaining = permittedItems.map(\.id).filter { !ordered.contains($0) }
            let finalOrder = ordered + remaining
            let sortedItems = finalOrder.compactMap { id in permittedItems.first(where: { $0.id == id }) }

            result.append((groupId: groupId, groupTitle: group.title, items: sortedItems))
        }

        return result
    }

    // MARK: - Flat Rows (normal mode)

    private var flatRows: [FlatFABRow] {
        let lookup = itemLookup
        let hidden = hiddenItemIds
        let order = sectionOrder

        var orderedIds: [String] = []
        for groupId in order {
            guard let group = menuGroups.first(where: { $0.id == groupId }) else { continue }
            let groupItemIds = group.items.compactMap { item -> String? in
                if hidden.contains(item.id) { return nil }
                if let perm = item.permission, !permissionStore.can(perm) { return nil }
                return item.id
            }

            let stored = storedOrder
            if !stored.isEmpty {
                let orderedInGroup = stored.filter { groupItemIds.contains($0) }
                let remaining = groupItemIds.filter { !orderedInGroup.contains($0) }
                orderedIds.append(contentsOf: orderedInGroup + remaining)
            } else {
                orderedIds.append(contentsOf: groupItemIds)
            }
        }

        var rows: [FlatFABRow] = []
        var lastGroupId: String?

        for (idx, id) in orderedIds.enumerated() {
            guard let entry = lookup[id] else { continue }
            let isNewGroup = entry.groupId != lastGroupId

            rows.append(FlatFABRow(
                id: id,
                item: entry.item,
                groupId: entry.groupId,
                groupHeader: isNewGroup ? entry.groupTitle : nil,
                showDivider: isNewGroup && lastGroupId != nil,
                flatIndex: idx
            ))
            lastGroupId = entry.groupId
        }

        return rows
    }

    private var staggerDelay: Double {
        let count = Double(flatRows.count)
        guard count > 1 else { return 0 }
        return 0.25 / (count - 1)
    }

    private func revealDelay(for row: FlatFABRow) -> Double {
        Double(flatRows.count - 1 - row.flatIndex) * staggerDelay
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dimmed overlay
            if showCreateMenu || isEditMode {
                LinearGradient(
                    stops: [
                        .init(color: Color(OPSStyle.Colors.background).opacity(isEditMode ? 0.6 : 0.5), location: 0.0),
                        .init(color: Color(OPSStyle.Colors.background).opacity(isEditMode ? 0.9 : 0.9), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .animation(.easeIn(duration: 0.2), value: showCreateMenu)
                .onTapGesture {
                    guard !tutorialMode, !isEditMode else { return }
                    closeMenu()
                }
            }

            if canShowFAB {
                if isEditMode {
                    // Edit mode: items fill available space, buttons at bottom-left
                    VStack(spacing: 0) {
                        Spacer()
                        HStack(alignment: .bottom) {
                            editModeActionButtons

                            Spacer()

                            editModeContent
                                .padding(.trailing, 36)
                        }
                        .padding(.bottom, 140)
                    }
                } else {
                    // Normal mode: FAB + menu at bottom-right
                    VStack {
                        Spacer()
                        HStack(alignment: .bottom) {
                            Spacer()

                            VStack(alignment: .trailing, spacing: 0) {
                                if showCreateMenu {
                                    normalMenuContent
                                }
                                fabButton
                            }
                            .padding(.trailing, 36)
                        }
                        .padding(.bottom, 140)
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
        .sheet(isPresented: $showingCustomizeSheet) {
            FABCustomizeSheet(groups: allPermittedItems, hiddenItemsData: $hiddenItemsData)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // TODO: Wire up when InvoiceFormSheet is implemented
        // .sheet(isPresented: $showingCreateInvoice) { InvoiceFormSheet() }
        // TODO: Wire up when RecordPaymentSheet is implemented
        // .sheet(isPresented: $showingRecordPayment) { RecordPaymentSheet() }
        .sheet(isPresented: $showTaskReviewFromFAB) {
            TaskCompletionReviewView(tasks: computeFABReviewableTasks())
                .environmentObject(appState)
                .environmentObject(PermissionStore.shared)
        }
        .sheet(isPresented: $showPaymentReviewFromFAB) {
            ProjectPaymentReviewView(
                overdueProjects: computeFABOverdueProjects(),
                completedProjects: computeFABCompletedProjects()
            )
            .environmentObject(appState)
            .environmentObject(PermissionStore.shared)
        }
        .sheet(isPresented: $showIncompleteReviewFromFAB) {
            UnscheduledTaskReviewView(tasks: computeFABIncompleteTasks())
                .environmentObject(dataController)
                .environmentObject(appState)
                .environmentObject(PermissionStore.shared)
        }
        .alert("Locked", isPresented: $showLockedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(lockedAlertMessage)
        }
        .alert("Payment Review", isPresented: $showPaymentReviewIntroFAB) {
            Button("Got It") {
                showPaymentReviewFromFAB = true
            }
        } message: {
            Text("Completed projects with outstanding payments will show up here for review.")
        }
        .alert("Task Review", isPresented: $showTaskReviewIntroFAB) {
            Button("Got It") {
                showTaskReviewFromFAB = true
            }
        } message: {
            Text("Tasks with end dates in the past will show up here so you can complete, reschedule, or cancel them.")
        }
        .sheet(isPresented: $showingPersonalEventSheet) {
            UserEventSheet(isPresented: $showingPersonalEventSheet, viewModel: calendarViewModel, mode: .personalEvent)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingTimeOffSheet) {
            UserEventSheet(isPresented: $showingTimeOffSheet, viewModel: calendarViewModel, mode: .timeOff)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingLogActivity) {
            LogActivitySheet()
        }
        .onChange(of: showingPersonalEventSheet) { _, showing in
            if !showing {
                NotificationCenter.default.post(name: Notification.Name("CalendarUserEventsDidChange"), object: nil)
            }
        }
        .onChange(of: showingTimeOffSheet) { _, showing in
            if !showing {
                NotificationCenter.default.post(name: Notification.Name("CalendarUserEventsDidChange"), object: nil)
            }
        }
        .onAppear {
            calendarViewModel.setDataController(dataController)
        }
    }

    // MARK: - Review Badge Count

    /// Total outstanding review items across all review types (for FAB badge)
    private var totalReviewBadgeCount: Int {
        guard !tutorialMode else { return 0 }
        let taskReviewItems = computeFABReviewableTasks().count
        let unassignedItems = computeFABIncompleteTasks().count
        let overdueItems = computeFABOverdueProjects().count
        let completedItems = computeFABCompletedProjects().count
        return taskReviewItems + unassignedItems + overdueItems + completedItems
    }

    // MARK: - FAB Button

    private var fabButton: some View {
        Button(action: {
            if !showCreateMenu {
                // Wizard system: notify FAB tapped
                NotificationCenter.default.post(
                    name: Notification.Name("WizardFABTapped"),
                    object: nil
                )
            }
            if tutorialMode && !showCreateMenu {
                NotificationCenter.default.post(
                    name: Notification.Name("TutorialFABTapped"),
                    object: nil
                )
            }
            if showCreateMenu {
                closeMenu()
            } else {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeOut(duration: 0.1)) {
                    showCreateMenu = true
                }
            }
        }) {
            Image(systemName: showCreateMenu ? "xmark" : "bolt")
                .font(.system(size: OPSStyle.Layout.IconSize.xl, weight: .semibold))
                .foregroundColor(isFABDisabledInTutorial ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.buttonText)
                .contentTransition(.symbolEffect(.replace))
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
                .overlay(alignment: .topTrailing) {
                    // Review count badge — only shown when menu is closed
                    if !showCreateMenu && totalReviewBadgeCount > 0 && !isFABDisabledInTutorial {
                        Text("\(totalReviewBadgeCount)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.invertedText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(OPSStyle.Colors.warningStatus)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .allowsHitTesting(!isFABDisabledInTutorial)
    }

    // MARK: - Normal Menu Content

    private var normalMenuContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 0) {
                Spacer().frame(height: 140)

                ForEach(flatRows) { row in
                    fabItemView(row: row)
                }

                Spacer().frame(height: 60)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: 500, alignment: .trailing)
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 70)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 56)
            }
        )
        .onAppear { itemsRevealed = true }
        .onDisappear { itemsRevealed = false }
    }

    // MARK: - Edit Mode Content

    private var editModeContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 16) {
                ForEach(Array(editModeGroupedItems.enumerated()), id: \.element.groupId) { _, section in
                    VStack(alignment: .trailing, spacing: 4) {
                        // Section header (static, no drag reorder)
                        Text(section.groupTitle)
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.trailing, 14)
                            .padding(.vertical, 6)

                        // Items in section
                        ForEach(section.items, id: \.id) { item in
                            let isHidden = hiddenItemIds.contains(item.id)
                            let isDragging = draggingItemId == item.id

                            editModeItemRow(item: item, isHidden: isHidden)
                                .offset(y: isDragging ? dragOffset : itemVisualOffset(for: item.id, in: section.items))
                                .zIndex(isDragging ? 10 : 0)
                                .scaleEffect(isDragging ? 1.05 : 1.0)
                                .opacity(isDragging ? 0.85 : 1.0)
                                .animation(isDragging ? nil : .easeInOut(duration: 0.15), value: itemVisualOffset(for: item.id, in: section.items))
                                .gesture(
                                    DragGesture(minimumDistance: 8)
                                        .onChanged { value in
                                            if draggingItemId == nil {
                                                draggingItemId = item.id
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }
                                            dragOffset = value.translation.height
                                        }
                                        .onEnded { _ in
                                            commitItemReorder(item.id, within: section.items, groupId: section.groupId)
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                dragOffset = 0
                                                draggingItemId = nil
                                            }
                                        }
                                )
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .scrollDisabled(draggingItemId != nil)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Edit Mode Action Buttons

    private var editModeActionButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()

            Button(action: { saveEditMode() }) {
                Text("SAVE")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.buttonText)
                    .frame(width: 120, height: 52)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }

            Button(action: { cancelEditMode() }) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 120, height: 52)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            }
        }
        .padding(.leading, 20)
    }

    // MARK: - Menu Actions

    private func closeMenu() {
        withAnimation(.easeIn(duration: 0.2)) {
            itemsRevealed = false
            isEditMode = false
            draggingItemId = nil
            dragOffset = 0
        }
        withAnimation(.easeIn(duration: 0.25)) {
            showCreateMenu = false
        }
    }

    private func enterEditMode() {
        editInitialHidden = hiddenItemsData
        editInitialOrder = itemOrderData
        withAnimation(.easeOut(duration: 0.2)) {
            isEditMode = true
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func saveEditMode() {
        withAnimation(.easeOut(duration: 0.2)) {
            isEditMode = false
            draggingItemId = nil
            dragOffset = 0
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func cancelEditMode() {
        hiddenItemsData = editInitialHidden
        itemOrderData = editInitialOrder
        withAnimation(.easeOut(duration: 0.2)) {
            isEditMode = false
            draggingItemId = nil
            dragOffset = 0
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Review Helpers

    private func computeFABReviewableTasks() -> [ProjectTask] {
        let calendar = Calendar.current
        let endOfToday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())

        let allTasks: [ProjectTask]
        if PermissionStore.shared.hasFullAccess("tasks.view") {
            allTasks = dataController.getAllTasks()
        } else if let userId = dataController.currentUser?.id {
            allTasks = dataController.getAllTasks().filter { task in
                task.getTeamMemberIds().contains(userId)
            }
        } else {
            allTasks = []
        }

        return allTasks.filter { task in
            task.status == .active
                && task.deletedAt == nil
                && task.startDate != nil
                && task.startDate! < endOfToday
        }
        .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    private func computeFABOverdueProjects() -> [Project] {
        let allProjects = dataController.getProjects()
        let threshold: Int
        if let companyId = dataController.currentUser?.companyId,
           let company = dataController.getCompany(id: companyId) {
            threshold = company.overdueReviewThresholdDays
        } else {
            threshold = 14
        }
        return OverdueProjectDetector.overdueProjects(from: allProjects, thresholdDays: threshold)
    }

    private func computeFABCompletedProjects() -> [Project] {
        return dataController.getProjects().filter { $0.status == .completed }
    }

    private func computeFABIncompleteTasks() -> [ProjectTask] {
        let allTasks: [ProjectTask]
        if PermissionStore.shared.hasFullAccess("tasks.view") {
            allTasks = dataController.getAllTasks()
        } else if let userId = dataController.currentUser?.id {
            allTasks = dataController.getAllTasks().filter { task in
                task.getTeamMemberIds().contains(userId)
            }
        } else {
            allTasks = []
        }

        return allTasks.filter { task in
            task.status == .active
                && task.deletedAt == nil
                && (task.startDate == nil || task.getTeamMemberIds().isEmpty)
        }
        .sorted { ($0.project?.title ?? "") < ($1.project?.title ?? "") }
    }

    // MARK: - Item Drag Reorder (within section)

    private func itemVisualOffset(for itemId: String, in sectionItems: [FABMenuItem]) -> CGFloat {
        guard let dragging = draggingItemId else { return 0 }
        guard sectionItems.contains(where: { $0.id == dragging }) else { return 0 }
        guard let draggingIdx = sectionItems.firstIndex(where: { $0.id == dragging }),
              let thisIdx = sectionItems.firstIndex(where: { $0.id == itemId })
        else { return 0 }

        if itemId == dragging { return 0 }

        let dragSteps = Int(round(dragOffset / dragRowHeight))
        let targetIdx = min(max(draggingIdx + dragSteps, 0), sectionItems.count - 1)

        if draggingIdx < targetIdx {
            if thisIdx > draggingIdx && thisIdx <= targetIdx {
                return -dragRowHeight
            }
        } else if draggingIdx > targetIdx {
            if thisIdx >= targetIdx && thisIdx < draggingIdx {
                return dragRowHeight
            }
        }

        return 0
    }

    private func commitItemReorder(_ itemId: String, within sectionItems: [FABMenuItem], groupId: String) {
        guard let fromIdx = sectionItems.firstIndex(where: { $0.id == itemId }) else { return }

        let steps = Int(round(dragOffset / dragRowHeight))
        let toIdx = min(max(fromIdx + steps, 0), sectionItems.count - 1)

        if fromIdx != toIdx {
            var reorderedIds = sectionItems.map(\.id)
            let moved = reorderedIds.remove(at: fromIdx)
            reorderedIds.insert(moved, at: toIdx)

            var newFullOrder: [String] = []
            for section in editModeGroupedItems {
                if section.groupId == groupId {
                    newFullOrder.append(contentsOf: reorderedIds)
                } else {
                    newFullOrder.append(contentsOf: section.items.map(\.id))
                }
            }

            setStoredOrder(newFullOrder)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    // MARK: - Normal Mode Item Views

    @ViewBuilder
    private func fabItemView(row: FlatFABRow) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let header = row.groupHeader {
                Text(header)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.trailing, 14)
                    .padding(.top, row.showDivider ? 12 : 0)
                    .padding(.bottom, 4)
            }

            fabMenuItemView(item: row.item)
                .offset(x: -10)
        }
        .padding(.vertical, 4)
        .opacity(itemsRevealed ? 1 : 0)
        .offset(x: itemsRevealed ? 0 : 60)
        .animation(
            .easeOut(duration: 0.08).delay(revealDelay(for: row)),
            value: itemsRevealed
        )
    }

    @ViewBuilder
    private func fabMenuItemView(item: FABMenuItem) -> some View {
        let isDisabledByTutorial = tutorialMode && item.disabledInTutorial
        let isLocked = item.lockedMessage != nil

        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let message = item.lockedMessage {
                lockedAlertMessage = message
                showLockedAlert = true
            } else {
                item.action()
            }
        }) {
            HStack(spacing: 12) {
                // Badge count inline with label (if present)
                if let badge = item.badge, badge > 0, !isLocked {
                    Text("\(badge)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(OPSStyle.Colors.warningStatus)
                        .clipShape(Capsule())
                }

                Text(item.label.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(isLocked ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)

                Image(systemName: item.icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(isLocked ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.buttonText)
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    guard !tutorialMode else { return }
                    enterEditMode()
                }
        )
    }

    // MARK: - Edit Mode Item Row

    @ViewBuilder
    private func editModeItemRow(item: FABMenuItem, isHidden: Bool) -> some View {
        HStack(spacing: 12) {
            // Toggle: minus to hide, plus to show (outline icons)
            Button(action: {
                var hidden = hiddenItemIds
                if isHidden {
                    hidden.remove(item.id)
                } else {
                    hidden.insert(item.id)
                }
                setHiddenItems(hidden)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }) {
                Image(systemName: isHidden ? "plus.circle" : "minus.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(isHidden ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.errorStatus)
            }

            Text(item.label.uppercased())
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(isHidden ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)

            Image(systemName: item.icon)
                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                .foregroundColor(isHidden ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.buttonText)
                .frame(width: 48, height: 48)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .opacity(isHidden ? 0.5 : 1.0)
        .padding(.vertical, 4)
    }
}

// MARK: - FAB Customize Sheet

fileprivate struct FABCustomizeSheet: View {
    let groups: [(group: FABMenuGroup, items: [FABMenuItem])]
    @Binding var hiddenItemsData: Data
    @Environment(\.dismiss) private var dismiss

    private var hiddenIds: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: hiddenItemsData)) ?? []
    }

    private func toggleItem(_ id: String) {
        var ids = hiddenIds
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        hiddenItemsData = (try? JSONEncoder().encode(ids)) ?? Data()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        VStack(spacing: 0) {
            // OPS-styled header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CUSTOMIZE MENU")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Choose which actions appear in your quick menu.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Text("DONE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groups, id: \.group.id) { entry in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.group.title)
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)

                            VStack(spacing: 0) {
                                ForEach(entry.items, id: \.id) { item in
                                    let isEnabled = !hiddenIds.contains(item.id)

                                    Button(action: { toggleItem(item.id) }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: item.icon)
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(isEnabled ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                                                .frame(width: 32)

                                            Text(item.label.uppercased())
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(isEnabled ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

                                            Spacer()

                                            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20))
                                                .foregroundColor(isEnabled ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                    }

                                    if item.id != entry.items.last?.id {
                                        Rectangle()
                                            .fill(OPSStyle.Colors.cardBorderSubtle)
                                            .frame(height: 1)
                                            .padding(.leading, 60)
                                    }
                                }
                            }
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .background(OPSStyle.Colors.background)
    }
}
