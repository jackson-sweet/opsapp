//
//  UniversalSearchSheet.swift
//  OPS
//
//  Universal search across all data types, role-filtered.
//  Opened from header search button on Job Board and Schedule.
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

    // MARK: - Permission Filters

    private var isFieldCrew: Bool {
        !permissionStore.hasFullAccess("projects.view")
    }

    private var hasPipelineAccess: Bool {
        permissionStore.can("pipeline.view")
    }

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
        ZStack {
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
        }
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
                            SearchResultRow(
                                icon: "building.2.fill",
                                title: client.name,
                                subtitle: client.email ?? client.phoneNumber,
                                trailingText: nil,
                                accentColor: OPSStyle.Colors.primaryAccent
                            ) {
                                selectedClient = client
                            }
                        }
                    }
                }

                // Team Members
                if !matchingUsers.isEmpty {
                    searchSection("TEAM", icon: "person.fill", count: matchingUsers.count) {
                        ForEach(matchingUsers) { user in
                            SearchResultRow(
                                icon: "person.fill",
                                title: user.fullName,
                                subtitle: user.email,
                                trailingText: user.roleDisplay.uppercased(),
                                accentColor: user.roleColor
                            ) {
                                selectedUser = user
                            }
                        }
                    }
                }

                // Invoices
                if !matchingInvoices.isEmpty {
                    searchSection("INVOICES", icon: "doc.text.fill", count: matchingInvoices.count) {
                        ForEach(matchingInvoices) { invoice in
                            SearchResultRow(
                                icon: "doc.text.fill",
                                title: invoice.title ?? "Invoice #\(invoice.invoiceNumber)",
                                subtitle: formatCurrency(invoice.total),
                                trailingText: invoice.status.displayName,
                                accentColor: invoice.status.isPaid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent
                            ) {
                                selectedInvoice = invoice
                            }
                        }
                    }
                }

                // Estimates
                if !matchingEstimates.isEmpty {
                    searchSection("ESTIMATES", icon: "doc.plaintext.fill", count: matchingEstimates.count) {
                        ForEach(matchingEstimates) { estimate in
                            SearchResultRow(
                                icon: "doc.plaintext.fill",
                                title: estimate.title ?? "Estimate #\(estimate.estimateNumber)",
                                subtitle: formatCurrency(estimate.total),
                                trailingText: estimate.status.displayName,
                                accentColor: OPSStyle.Colors.primaryAccent
                            ) {
                                selectedEstimate = estimate
                            }
                        }
                    }
                }

                // Inventory
                if !matchingInventoryItems.isEmpty {
                    searchSection("INVENTORY", icon: "shippingbox.fill", count: matchingInventoryItems.count) {
                        ForEach(matchingInventoryItems) { item in
                            SearchResultRow(
                                icon: "shippingbox.fill",
                                title: item.name,
                                subtitle: item.sku != nil ? "SKU: \(item.sku!)" : item.itemDescription,
                                trailingText: item.quantityDisplay,
                                accentColor: item.effectiveThresholdStatus().color
                            ) {
                                selectedInventoryItem = item
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .animation(.accessibleEaseInOut(duration: 0.15), value: query)
    }

    // MARK: - Row Builders

    private func projectRow(_ project: Project) -> some View {
        SearchResultRow(
            icon: "folder.fill",
            title: project.title,
            subtitle: project.effectiveClientName.isEmpty ? project.address : project.effectiveClientName,
            trailingText: project.status.displayName,
            accentColor: project.status.color
        ) {
            navigateToProject(project)
        }
    }

    private func taskRow(_ task: ProjectTask) -> some View {
        SearchResultRow(
            icon: "checklist",
            title: task.displayTitle,
            subtitle: task.project?.title,
            trailingText: task.status.displayName,
            accentColor: task.status.color
        ) {
            navigateToTask(task)
        }
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
                withAnimation(.easeInOut(duration: 0.18)) {
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
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl, weight: .light))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Search projects, tasks, clients, and more")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Text("No results for \"\(query)\"")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
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
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let trailingText: String?
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Type icon
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(accentColor)
                    .frame(width: 28)

                // Title + subtitle
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Trailing badge
                if let trailingText, !trailingText.isEmpty {
                    Text(trailingText)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accentColor.opacity(0.15))
                        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
