//
//  UniversalSearchSheet.swift
//  OPS
//
//  Universal search across all data types, role-filtered.
//  Opened from header search button on Job Board and Schedule.
//
//  Bug 62f9f1f0 — task results now expose start/end dates as a smart pill
//  (OVERDUE / TODAY / TOMORROW / IN Xd / MMM d / UNSCHEDULED), and every
//  row carries up to two inline quick actions (Schedule, Add Task, Complete,
//  Reschedule, Call, Add Project, Message) plus a "QUICK CREATE" rail on
//  the empty state. The intent is one-tap field workflows from search.
//

import SwiftUI
import SwiftData

struct UniversalSearchSheet: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // SwiftData queries
    @Query private var allProjects: [Project]
    @Query private var allClients: [Client]
    @Query private var allUsers: [User]
    @Query private var allInventoryItems: [InventoryItem]
    @Query(filter: #Predicate<Invoice> { $0.deletedAt == nil }) private var allLocalInvoices: [Invoice]
    @Query(filter: #Predicate<Estimate> { $0.deletedAt == nil }) private var allLocalEstimates: [Estimate]

    // ViewModels — kept for mutation methods; list data now comes from @Query above
    @StateObject private var invoiceVM = InvoiceViewModel()
    @StateObject private var estimateVM = EstimateViewModel()

    @FocusState private var searchFocused: Bool
    @State private var query: String = ""

    // Detail sheet states
    @State private var selectedClient: Client?
    @State private var selectedUser: User?
    @State private var selectedInvoice: Invoice?
    @State private var selectedEstimate: Estimate?
    @State private var selectedInventoryItem: InventoryItem?

    // Collapsed-by-default inactive folders (bug f2f87911). Closed/archived
    // projects and completed/cancelled tasks live behind a disclosure so the
    // active results aren't drowned in old work.
    @State private var showInactiveProjects: Bool = false
    @State private var showInactiveTasks: Bool = false

    // Quick-action sheet state (bug 62f9f1f0)
    @State private var schedulingProject: Project?
    @State private var schedulingTask: ProjectTask?
    @State private var addingTaskForProjectId: String?
    @State private var addingProjectForClient: Client?
    @State private var showingNewProject: Bool = false
    @State private var showingNewTask: Bool = false
    @State private var showingNewClient: Bool = false

    // Undo banner state — surfaces after one-tap Complete so a mis-tap is
    // recoverable inside 3 seconds without a confirm dialog blocking flow.
    @State private var undoTask: ProjectTask?
    @State private var undoPreviousStatus: TaskStatus?
    @State private var undoExpiresAt: Date?

    // MARK: - Permission Filters

    private var isFieldCrew: Bool {
        !permissionStore.hasFullAccess("projects.view")
    }

    private var hasPipelineAccess: Bool {
        permissionStore.can("pipeline.view")
    }

    private var canCreateProjects: Bool { permissionStore.can("projects.create") }
    private var canCreateTasks: Bool    { permissionStore.can("tasks.create") }
    private var canCreateClients: Bool  { permissionStore.can("clients.create") }
    private var canEditTasks: Bool      { permissionStore.can("tasks.edit") }
    private var canEditProjects: Bool   { permissionStore.can("projects.edit") }

    // MARK: - Available Data (role-filtered)

    private var availableProjects: [Project] {
        guard let userId = dataController.currentUser?.id else { return [] }
        var projects = allProjects.filter { $0.deletedAt == nil }
        if isFieldCrew {
            // Bug G9 — include mention-granted projects. Search is an explicit
            // wide surface; users need to be able to reach projects they've been
            // tagged into via search (no Job Board entry for mention-only).
            projects = projects.filter { ProjectAccessHelper.wideVisible($0, userId: userId) }
        }
        if !hasPipelineAccess {
            projects = projects.filter { $0.status != .rfq && $0.status != .estimated }
        }
        return projects
    }

    private var availableTasks: [ProjectTask] {
        availableProjects.flatMap { $0.tasks.filter { $0.deletedAt == nil } }
    }

    private var availableClients: [Client] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return allClients.filter { $0.deletedAt == nil && $0.companyId == companyId }
    }

    private var availableUsers: [User] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return allUsers.filter { $0.deletedAt == nil && $0.companyId == companyId }
    }

    private var availableInventoryItems: [InventoryItem] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return allInventoryItems.filter { $0.deletedAt == nil && $0.companyId == companyId }
    }

    // MARK: - Search Results

    private var matchingProjects: [Project] {
        guard !query.isEmpty else { return [] }
        let q = query
        return availableProjects.filter { project in
            if project.title.localizedCaseInsensitiveContains(q) { return true }
            if project.effectiveClientName.localizedCaseInsensitiveContains(q) { return true }
            if project.address?.localizedCaseInsensitiveContains(q) == true { return true }
            // Match by sub-client name / title / email / phone (so searching a
            // site contact like "Mitchell" surfaces the project it's attached to)
            if let subClients = project.client?.subClients {
                for sub in subClients where sub.deletedAt == nil {
                    if sub.name.localizedCaseInsensitiveContains(q) { return true }
                    if sub.title?.localizedCaseInsensitiveContains(q) == true { return true }
                    if sub.email?.localizedCaseInsensitiveContains(q) == true { return true }
                    if sub.phoneNumber?.localizedCaseInsensitiveContains(q) == true { return true }
                }
            }
            return false
        }
    }

    private var matchingTasks: [ProjectTask] {
        guard !query.isEmpty else { return [] }
        let q = query
        return availableTasks.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(q) ||
            ($0.taskNotes?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var matchingClients: [Client] {
        guard !query.isEmpty else { return [] }
        let q = query
        return availableClients.filter { client in
            if client.name.localizedCaseInsensitiveContains(q) { return true }
            if client.email?.localizedCaseInsensitiveContains(q) == true { return true }
            if client.phoneNumber?.localizedCaseInsensitiveContains(q) == true { return true }
            // Surface the parent client when the query matches one of their
            // sub-contacts (name, title, email, or phone).
            for sub in client.subClients where sub.deletedAt == nil {
                if sub.name.localizedCaseInsensitiveContains(q) { return true }
                if sub.title?.localizedCaseInsensitiveContains(q) == true { return true }
                if sub.email?.localizedCaseInsensitiveContains(q) == true { return true }
                if sub.phoneNumber?.localizedCaseInsensitiveContains(q) == true { return true }
            }
            return false
        }
    }

    private var matchingUsers: [User] {
        guard !query.isEmpty else { return [] }
        let q = query
        return availableUsers.filter {
            $0.fullName.localizedCaseInsensitiveContains(q) ||
            ($0.email?.localizedCaseInsensitiveContains(q) ?? false) ||
            ($0.phone?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var matchingInventoryItems: [InventoryItem] {
        guard !query.isEmpty else { return [] }
        let q = query
        return availableInventoryItems.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.itemDescription?.localizedCaseInsensitiveContains(q) ?? false) ||
            ($0.sku?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var matchingInvoices: [Invoice] {
        guard !query.isEmpty else { return [] }
        let q = query
        return allLocalInvoices.filter {
            $0.invoiceNumber.localizedCaseInsensitiveContains(q) ||
            ($0.title?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var matchingEstimates: [Estimate] {
        guard !query.isEmpty else { return [] }
        let q = query
        return allLocalEstimates.filter {
            $0.estimateNumber.localizedCaseInsensitiveContains(q) ||
            ($0.title?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var hasResults: Bool {
        !matchingProjects.isEmpty || !matchingTasks.isEmpty ||
        !matchingClients.isEmpty || !matchingUsers.isEmpty ||
        !matchingInventoryItems.isEmpty || !matchingInvoices.isEmpty ||
        !matchingEstimates.isEmpty
    }

    // MARK: - Active / Inactive Splits
    //
    // Inactive = work the user is unlikely to be searching for. Keeping these
    // visible but collapsed stops old projects from drowning out the two
    // active jobs the field user actually needs to pull up.

    /// Project statuses that are considered archived — hidden behind a
    /// disclosure in search results.
    private static let inactiveProjectStatuses: Set<Status> = [.completed, .closed, .archived]

    /// Task statuses that are considered archived — hidden behind a disclosure.
    private static let inactiveTaskStatuses: Set<TaskStatus> = [.completed, .cancelled]

    private var matchingActiveProjects: [Project] {
        matchingProjects.filter { !Self.inactiveProjectStatuses.contains($0.status) }
    }

    private var matchingInactiveProjects: [Project] {
        matchingProjects.filter { Self.inactiveProjectStatuses.contains($0.status) }
    }

    private var matchingActiveTasks: [ProjectTask] {
        matchingTasks.filter { !Self.inactiveTaskStatuses.contains($0.status) }
    }

    private var matchingInactiveTasks: [ProjectTask] {
        matchingTasks.filter { Self.inactiveTaskStatuses.contains($0.status) }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Black-tinted ultra thin material background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 0) {
                // Floating search bar
                searchBar
                    .padding(.top, 20)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // Content
                if query.isEmpty {
                    emptyQueryState
                } else if !hasResults {
                    noResultsState
                } else {
                    resultsView
                }
            }

            undoBanner
        }
        .animation(.accessibleEaseInOut(duration: 0.18), value: undoTask?.id)
        .onAppear {
            searchFocused = true
            loadSupabaseData()
        }
        // Detail sheets
        .sheet(item: $selectedClient) { client in
            ContactDetailView(client: client, project: nil)
                .environmentObject(dataController)
        }
        .sheet(item: $selectedUser) { user in
            ContactDetailView(user: user)
                .environmentObject(dataController)
        }
        .sheet(item: $selectedInvoice) { invoice in
            NavigationStack {
                InvoiceDetailView(invoice: invoice, viewModel: invoiceVM)
            }
        }
        .sheet(item: $selectedEstimate) { estimate in
            NavigationStack {
                EstimateDetailView(estimate: estimate, viewModel: estimateVM)
            }
        }
        .sheet(item: $selectedInventoryItem) { item in
            InventoryFormSheet(item: item)
                .environmentObject(dataController)
        }
        // Quick-action sheets — scheduler
        .sheet(item: $schedulingProject) { project in
            CalendarSchedulerSheet(
                isPresented: Binding(
                    get: { schedulingProject != nil },
                    set: { if !$0 { schedulingProject = nil } }
                ),
                itemType: .project(project),
                currentStartDate: project.startDate,
                currentEndDate: project.endDate,
                onScheduleUpdate: { start, end in
                    Task {
                        try? await dataController.updateProjectDates(
                            project: project,
                            startDate: start,
                            endDate: end
                        )
                    }
                }
            )
            .environmentObject(dataController)
        }
        .sheet(item: $schedulingTask) { task in
            CalendarSchedulerSheet(
                isPresented: Binding(
                    get: { schedulingTask != nil },
                    set: { if !$0 { schedulingTask = nil } }
                ),
                itemType: .task(task),
                currentStartDate: task.startDate,
                currentEndDate: task.endDate,
                onScheduleUpdate: { start, end in
                    Task {
                        try? await dataController.updateTaskSchedule(
                            task: task,
                            startDate: start,
                            endDate: end
                        )
                        // Mirror UniversalJobBoardCard: pull parent project
                        // dates outward when the task's new span crosses them.
                        if let project = task.project {
                            let datedTasks = project.tasks.filter { $0.startDate != nil }
                            if !datedTasks.isEmpty {
                                let earliest = datedTasks.compactMap { $0.startDate }.min() ?? start
                                let latest   = datedTasks.compactMap { $0.endDate   }.max() ?? end
                                if project.startDate != earliest || project.endDate != latest {
                                    try? await dataController.updateProjectDates(
                                        project: project,
                                        startDate: earliest,
                                        endDate: latest
                                    )
                                }
                            }
                        }
                    }
                }
            )
            .environmentObject(dataController)
        }
        // Quick-action sheets — create
        .sheet(item: $addingProjectForClient) { client in
            ProjectFormSheet(mode: .create, preselectedClient: client) { _ in }
                .environmentObject(dataController)
        }
        .sheet(isPresented: Binding(
            get: { addingTaskForProjectId != nil },
            set: { if !$0 { addingTaskForProjectId = nil } }
        )) {
            if let projectId = addingTaskForProjectId {
                TaskFormSheet(mode: .create, preselectedProjectId: projectId) { _ in }
                    .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingNewProject) {
            ProjectFormSheet(mode: .create) { _ in }
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingNewTask) {
            TaskFormSheet(mode: .create) { _ in }
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingNewClient) {
            ClientSheet(mode: .create) { _ in }
                .environmentObject(dataController)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextField("Search everything...", text: $query)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .autocorrectionDisabled()
                .focused($searchFocused)

            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Button("CANCEL") {
                dismiss()
            }
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Results

    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {

                // Projects — active results expanded; closed/archived/completed
                // tucked behind a disclosure so they don't bury active work.
                if !matchingProjects.isEmpty {
                    searchSection("PROJECTS", icon: "folder.fill", count: matchingProjects.count) {
                        ForEach(matchingActiveProjects) { project in
                            projectRow(project)
                        }
                        inactiveDisclosure(
                            label: "CLOSED & ARCHIVED",
                            count: matchingInactiveProjects.count,
                            isOpen: $showInactiveProjects
                        ) {
                            ForEach(matchingInactiveProjects) { project in
                                projectRow(project)
                            }
                        }
                    }
                }

                // Tasks — active expanded; completed/cancelled tucked behind a
                // disclosure for the same reason.
                if !matchingTasks.isEmpty {
                    searchSection("TASKS", icon: "checklist", count: matchingTasks.count) {
                        ForEach(matchingActiveTasks) { task in
                            taskRow(task)
                        }
                        inactiveDisclosure(
                            label: "COMPLETED & CANCELLED",
                            count: matchingInactiveTasks.count,
                            isOpen: $showInactiveTasks
                        ) {
                            ForEach(matchingInactiveTasks) { task in
                                taskRow(task)
                            }
                        }
                    }
                }

                // Clients
                if !matchingClients.isEmpty {
                    searchSection("CLIENTS", icon: "building.2.fill", count: matchingClients.count) {
                        ForEach(matchingClients) { client in
                            clientRow(client)
                        }
                    }
                }

                // Team Members
                if !matchingUsers.isEmpty {
                    searchSection("TEAM", icon: "person.fill", count: matchingUsers.count) {
                        ForEach(matchingUsers) { user in
                            teamRow(user)
                        }
                    }
                }

                // Invoices
                if !matchingInvoices.isEmpty {
                    searchSection("INVOICES", icon: "doc.text.fill", count: matchingInvoices.count) {
                        ForEach(matchingInvoices) { invoice in
                            SearchResultRow(
                                icon: "doc.text.fill",
                                accentColor: invoice.status.isPaid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent,
                                title: invoice.title ?? "Invoice #\(invoice.invoiceNumber)",
                                subtitle: formatCurrency(invoice.total),
                                pill: SearchPill(
                                    text: invoice.status.displayName.uppercased(),
                                    color: invoice.status.isPaid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent
                                ),
                                quickActions: [],
                                onTap: { selectedInvoice = invoice }
                            )
                        }
                    }
                }

                // Estimates
                if !matchingEstimates.isEmpty {
                    searchSection("ESTIMATES", icon: "doc.plaintext.fill", count: matchingEstimates.count) {
                        ForEach(matchingEstimates) { estimate in
                            SearchResultRow(
                                icon: "doc.plaintext.fill",
                                accentColor: OPSStyle.Colors.primaryAccent,
                                title: estimate.title ?? "Estimate #\(estimate.estimateNumber)",
                                subtitle: formatCurrency(estimate.total),
                                pill: SearchPill(
                                    text: estimate.status.displayName.uppercased(),
                                    color: OPSStyle.Colors.primaryAccent
                                ),
                                quickActions: [],
                                onTap: { selectedEstimate = estimate }
                            )
                        }
                    }
                }

                // Inventory
                if !matchingInventoryItems.isEmpty {
                    searchSection("INVENTORY", icon: "shippingbox.fill", count: matchingInventoryItems.count) {
                        ForEach(matchingInventoryItems) { item in
                            SearchResultRow(
                                icon: "shippingbox.fill",
                                accentColor: item.effectiveThresholdStatus().color,
                                title: item.name,
                                subtitle: item.sku != nil ? "SKU: \(item.sku!)" : item.itemDescription,
                                pill: SearchPill(
                                    text: item.quantityDisplay.uppercased(),
                                    color: item.effectiveThresholdStatus().color
                                ),
                                quickActions: [],
                                onTap: { selectedInventoryItem = item }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, undoTask != nil ? 80 : 40)
        }
        .animation(.accessibleEaseInOut(duration: 0.15), value: query)
    }

    // MARK: - Row Builders

    private func projectRow(_ project: Project) -> some View {
        var actions: [QuickActionSpec] = []
        if canEditProjects {
            actions.append(QuickActionSpec(
                id: "schedule",
                icon: OPSStyle.Icons.schedule,
                accessibilityLabel: "Schedule project",
                tint: OPSStyle.Colors.primaryAccent
            ) {
                schedulingProject = project
            })
        }
        if canCreateTasks {
            actions.append(QuickActionSpec(
                id: "addTask",
                icon: "plus.app.fill",
                accessibilityLabel: "Add task to project",
                tint: OPSStyle.Colors.primaryAccent
            ) {
                addingTaskForProjectId = project.id
            })
        }

        return SearchResultRow(
            icon: "folder.fill",
            accentColor: project.status.color,
            title: project.title,
            subtitle: project.effectiveClientName.isEmpty ? project.address : project.effectiveClientName,
            pill: SearchPill(
                text: project.status.displayName.uppercased(),
                color: project.status.color
            ),
            quickActions: actions,
            onTap: { navigateToProject(project) }
        )
    }

    private func taskRow(_ task: ProjectTask) -> some View {
        var actions: [QuickActionSpec] = []
        if canEditTasks && task.status == .active {
            actions.append(QuickActionSpec(
                id: "complete",
                icon: OPSStyle.Icons.complete,
                accessibilityLabel: "Mark task complete",
                tint: OPSStyle.Colors.successStatus
            ) {
                completeTask(task)
            })
        }
        if canEditTasks && !task.status.isTerminal {
            actions.append(QuickActionSpec(
                id: "reschedule",
                icon: OPSStyle.Icons.schedule,
                accessibilityLabel: "Reschedule task",
                tint: OPSStyle.Colors.primaryAccent
            ) {
                schedulingTask = task
            })
        }

        return SearchResultRow(
            icon: "checklist",
            accentColor: task.status.color,
            title: task.displayTitle,
            subtitle: task.project?.title,
            pill: taskDatePill(task),
            quickActions: actions,
            onTap: { navigateToTask(task) }
        )
    }

    private func clientRow(_ client: Client) -> some View {
        var actions: [QuickActionSpec] = []
        if let phone = client.phoneNumber, !phone.isEmpty {
            actions.append(QuickActionSpec(
                id: "call",
                icon: OPSStyle.Icons.phoneFill,
                accessibilityLabel: "Call client",
                tint: OPSStyle.Colors.primaryAccent
            ) {
                openTel(phone)
            })
        }
        if canCreateProjects {
            actions.append(QuickActionSpec(
                id: "addProject",
                icon: OPSStyle.Icons.addProject,
                accessibilityLabel: "Add project for client",
                tint: OPSStyle.Colors.primaryAccent
            ) {
                addingProjectForClient = client
            })
        }

        return SearchResultRow(
            icon: "building.2.fill",
            accentColor: OPSStyle.Colors.primaryAccent,
            title: client.name,
            subtitle: client.email ?? client.phoneNumber,
            pill: nil,
            quickActions: actions,
            onTap: { selectedClient = client }
        )
    }

    private func teamRow(_ user: User) -> some View {
        var actions: [QuickActionSpec] = []
        if let phone = user.phone, !phone.isEmpty {
            actions.append(QuickActionSpec(
                id: "call",
                icon: OPSStyle.Icons.phoneFill,
                accessibilityLabel: "Call team member",
                tint: OPSStyle.Colors.primaryAccent
            ) {
                openTel(phone)
            })
            actions.append(QuickActionSpec(
                id: "sms",
                icon: "message.fill",
                accessibilityLabel: "Message team member",
                tint: OPSStyle.Colors.primaryAccent
            ) {
                openSMS(phone)
            })
        }

        return SearchResultRow(
            icon: "person.fill",
            accentColor: user.roleColor,
            title: user.fullName,
            subtitle: user.email,
            pill: SearchPill(
                text: user.roleDisplay.uppercased(),
                color: user.roleColor
            ),
            quickActions: actions,
            onTap: { selectedUser = user }
        )
    }

    // MARK: - Inactive Disclosure

    /// Collapsible footer inside a search section. When there are inactive
    /// matches, renders a tap target that reveals them — otherwise it's a
    /// no-op so empty sections stay tight. Designed for gloved taps: 44pt
    /// vertical hit region.
    @ViewBuilder
    private func inactiveDisclosure<Content: View>(
        label: String,
        count: Int,
        isOpen: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if count > 0 {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(OPSStyle.Animation.fast) {
                    isOpen.wrappedValue.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isOpen.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("[ \(label) · \(count) ]")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .tracking(1.1)
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isOpen.wrappedValue ? "Hide" : "Show") \(count) \(label.lowercased()) results")

            if isOpen.wrappedValue {
                VStack(spacing: 6) {
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Section Builder

    private func searchSection<Content: View>(
        _ title: String,
        icon: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            VStack(spacing: 6) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        } header: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("[ \(title) ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("\(count)")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.9))
        }
    }

    // MARK: - Empty States

    private var emptyQueryState: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: OPSStyle.Layout.IconSize.xxl, weight: .light))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("Search projects, tasks, clients, and more")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            quickCreateRail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 60)
    }

    private var noResultsState: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: OPSStyle.Layout.IconSize.xl, weight: .light))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("No results for \"\(query)\"")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            quickCreateRail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 60)
    }

    // MARK: - Quick Create Rail
    //
    // Top-level creation entry points when the user is in search with nothing
    // typed (or a query that returned nothing). Mirrors the FAB but lives in
    // the same surface they already opened, so they don't need to dismiss to
    // create the thing they were just trying to find.

    @ViewBuilder
    private var quickCreateRail: some View {
        let chips: [QuickCreateChipSpec] = quickCreateChips
        if !chips.isEmpty {
            VStack(spacing: 10) {
                Text("[ QUICK CREATE ]")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .tracking(1.1)

                HStack(spacing: 8) {
                    ForEach(chips, id: \.id) { chip in
                        QuickCreateChip(spec: chip)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var quickCreateChips: [QuickCreateChipSpec] {
        var chips: [QuickCreateChipSpec] = []
        if canCreateProjects {
            chips.append(QuickCreateChipSpec(
                id: "newProject",
                icon: OPSStyle.Icons.addProject,
                label: "PROJECT"
            ) {
                showingNewProject = true
            })
        }
        if canCreateTasks {
            chips.append(QuickCreateChipSpec(
                id: "newTask",
                icon: "plus.app.fill",
                label: "TASK"
            ) {
                showingNewTask = true
            })
        }
        if canCreateClients {
            chips.append(QuickCreateChipSpec(
                id: "newClient",
                icon: "person.crop.circle.badge.plus",
                label: "CLIENT"
            ) {
                showingNewClient = true
            })
        }
        return chips
    }

    // MARK: - Task Date Pill
    //
    // Replaces the redundant "ACTIVE" badge with a date-aware status that's
    // useful at a glance: OVERDUE Xd / TODAY / TOMORROW / IN Xd / MMM d /
    // UNSCHEDULED. Completed and cancelled tasks keep terminal-state badges.

    private func taskDatePill(_ task: ProjectTask) -> SearchPill {
        let colors = OPSStyle.Colors.self

        switch task.status {
        case .completed:
            return SearchPill(text: "DONE", color: colors.successStatus)
        case .cancelled:
            return SearchPill(text: "CANCELLED", color: colors.inactiveStatus)
        case .active:
            return activeTaskDatePill(task)
        }
    }

    private func activeTaskDatePill(_ task: ProjectTask) -> SearchPill {
        let colors = OPSStyle.Colors.self
        guard let start = task.startDate, let end = task.endDate else {
            return SearchPill(text: "UNSCHEDULED", color: colors.tertiaryText)
        }

        let cal = Calendar.current
        let today    = cal.startOfDay(for: Date())
        let startDay = cal.startOfDay(for: start)
        let endDay   = cal.startOfDay(for: end)
        let daysToStart = cal.dateComponents([.day], from: today, to: startDay).day ?? 0
        let daysSinceEnd = cal.dateComponents([.day], from: endDay, to: today).day ?? 0
        let spanDays = max(1, (cal.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1)
        let spanSuffix = spanDays > 1 ? " · \(spanDays)D" : ""

        // Overdue: end date in the past, task still active.
        if endDay < today {
            let amount = max(daysSinceEnd, 1)
            return SearchPill(text: "OVERDUE \(amount)D", color: colors.errorStatus)
        }

        // In progress: started in the past, end is today or future.
        if startDay < today && endDay >= today {
            return SearchPill(text: "IN PROGRESS\(spanSuffix)", color: colors.primaryAccent)
        }

        if cal.isDateInToday(start) {
            return SearchPill(text: "TODAY\(spanSuffix)", color: colors.primaryAccent)
        }

        if cal.isDateInTomorrow(start) {
            return SearchPill(text: "TOMORROW\(spanSuffix)", color: colors.primaryAccent)
        }

        if daysToStart > 1 && daysToStart <= 7 {
            return SearchPill(text: "IN \(daysToStart)D\(spanSuffix)", color: colors.secondaryText)
        }

        // Beyond 7 days — absolute date, uppercase, JetBrains tabular numerics.
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let label = fmt.string(from: start).uppercased() + spanSuffix
        return SearchPill(text: label, color: colors.secondaryText)
    }

    // MARK: - Task Completion (with Undo)

    private func completeTask(_ task: ProjectTask) {
        let previous = task.status
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            do {
                try await dataController.updateTaskStatus(task: task, to: .completed)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(OPSStyle.Animation.fast) {
                    undoTask = task
                    undoPreviousStatus = previous
                    undoExpiresAt = Date().addingTimeInterval(3.0)
                }
                // Auto-dismiss after 3s. The Date guard prevents a stale
                // dispatch from clobbering a fresh banner if the user
                // completes another task inside the window.
                let myExpiry = undoExpiresAt
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if undoExpiresAt == myExpiry {
                    withAnimation(OPSStyle.Animation.fast) {
                        undoTask = nil
                        undoPreviousStatus = nil
                        undoExpiresAt = nil
                    }
                }
            } catch {
                print("[UniversalSearch] Failed to complete task: \(error)")
            }
        }
    }

    private func revertCompletion() {
        guard let task = undoTask, let previous = undoPreviousStatus else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { @MainActor in
            do {
                try await dataController.updateTaskStatus(task: task, to: previous)
                withAnimation(OPSStyle.Animation.fast) {
                    undoTask = nil
                    undoPreviousStatus = nil
                    undoExpiresAt = nil
                }
            } catch {
                print("[UniversalSearch] Failed to revert task: \(error)")
            }
        }
    }

    // MARK: - Undo Banner

    @ViewBuilder
    private var undoBanner: some View {
        if let task = undoTask {
            HStack(spacing: 10) {
                Image(OPSStyle.Icons.complete)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.successStatus)

                VStack(alignment: .leading, spacing: 2) {
                    Text("MARKED COMPLETE")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .tracking(1.0)
                    Text(task.displayTitle.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Button(action: revertCompletion) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        Text("UNDO")
                            .font(OPSStyle.Typography.captionBold)
                            .tracking(0.8)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo mark complete")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Navigation

    private func navigateToProject(_ project: Project) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            appState.viewProjectDetails(project)
        }
    }

    private func navigateToTask(_ task: ProjectTask) {
        guard let project = task.project else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            appState.viewProjectDetails(project)
        }
    }

    // MARK: - Helpers

    private func loadSupabaseData() {
        guard let companyId = dataController.currentUser?.companyId else { return }
        invoiceVM.setup(companyId: companyId, modelContext: modelContext)
        estimateVM.setup(companyId: companyId, modelContext: modelContext)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    private func openTel(_ phone: String) {
        let cleaned = phone.filter { "0123456789+".contains($0) }
        guard let url = URL(string: "tel:\(cleaned)") else { return }
        UIApplication.shared.open(url)
    }

    private func openSMS(_ phone: String) {
        let cleaned = phone.filter { "0123456789+".contains($0) }
        guard let url = URL(string: "sms:\(cleaned)") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Search Pill

private struct SearchPill: Equatable {
    let text: String
    let color: Color
}

// MARK: - Quick Action Spec

private struct QuickActionSpec: Identifiable {
    let id: String
    let icon: String
    let accessibilityLabel: String
    let tint: Color
    let action: () -> Void
}

// MARK: - Quick Create Chip Spec

private struct QuickCreateChipSpec: Identifiable {
    let id: String
    let icon: String
    let label: String
    let action: () -> Void
}

// MARK: - Search Result Row
//
// Layout: [type icon] [title + subtitle] [pill] [quick actions...] [chevron]
// The title/subtitle column is a Button (row tap → detail), and each quick
// action is its own Button so taps don't compete. 44pt hit targets minimum.

private struct SearchResultRow: View {
    let icon: String
    let accentColor: Color
    let title: String
    let subtitle: String?
    let pill: SearchPill?
    let quickActions: [QuickActionSpec]
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Type icon
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(accentColor)
                .frame(width: 24)

            // Title + subtitle + pill — primary tap area for row navigation
            Button(action: onTap) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title.uppercased())
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if let pill {
                        Text(pill.text)
                            .font(OPSStyle.Typography.smallCaption)
                            .monospacedDigit()
                            .foregroundColor(pill.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(pill.color.opacity(0.15))
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                            .layoutPriority(1)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Inline quick actions
            ForEach(quickActions) { spec in
                QuickActionIconButton(spec: spec)
            }

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.leading, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

// MARK: - Quick Action Icon Button

private struct QuickActionIconButton: View {
    let spec: QuickActionSpec

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            spec.action()
        } label: {
            Image(systemName: spec.icon)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(spec.tint)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spec.accessibilityLabel)
    }
}

// MARK: - Quick Create Chip

private struct QuickCreateChip: View {
    let spec: QuickCreateChipSpec

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            spec.action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: spec.icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Text(spec.label)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .tracking(0.8)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create new \(spec.label.lowercased())")
    }
}
