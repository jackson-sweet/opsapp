//
//  MainTabView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// MainTabView.swift
import SwiftUI
import SwiftData
import Combine
import MapKit

struct MainTabView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.wizardTriggerService) private var wizardTriggerService
    @Environment(\.wizardStateManager) private var wizardStateManager

    @State private var selectedTab = 0
    @State private var hasEvaluatedWizards = false
    @State private var needsWizardRetry = false
    @State private var previousTab = 0
    @State private var keyboardIsShowing = false
    @State private var sheetIsPresented = false

    // Bug 706a4d32 — shared namespace for persistent header buttons. The
    // outgoing and incoming tab views both render an AppHeader; matching by
    // stable button IDs in this namespace lets SwiftUI keep those elements
    // visually still while the rest of the tab content slides.
    @Namespace private var persistentHeaderNamespace

    /// Transient loading banner shown while a deep-linked project is being
    /// fetched from the server (cold-cache case). Dismissed when resolution
    /// completes (success, denial, or offline bail).
    @State private var showDeepLinkLoading = false

    /// In-flight project deep-link resolution Task. Cancelled when a newer
    /// link arrives so concurrent taps can't double-present.
    @State private var inFlightDeepLinkTask: Task<Void, Never>?
    // PermissionChangeOverlay moved to PINGatedView (ContentView.swift) so it sits above all sheets
    @StateObject private var imageSyncProgressManager = ImageSyncProgressManager()
    @ObservedObject private var inProgressManager = InProgressManager.shared
    @State private var userRole: UserRole? = nil // Track user role changes explicitly

    // member_joined push → AssignMemberRoleSheet state
    @State private var showAssignRoleSheet = false
    @State private var assignRoleMemberId: String?
    @State private var assignRoleWasSeated: Bool = false

    private var hasCatalogAccess: Bool {
        permissionStore.can("catalog.view", requiredScope: "all")
    }

    // LEADS tab is gated by `pipeline.view` permission AND the `pipeline` feature
    // flag. When the flag is off, the entire tab is hidden — even for users
    // with the permission.
    private var hasLeadsAccess: Bool {
        permissionStore.can("pipeline.view") && permissionStore.isFeatureEnabled("pipeline")
    }
    
    // Observer for fetch active project notifications
    private let fetchProjectObserver = NotificationCenter.default
        .publisher(for: Notification.Name("FetchActiveProject"))
    
    // Observer for showing project details
    private let showProjectObserver = NotificationCenter.default
        .publisher(for: Notification.Name("ShowProjectDetailsRequest"))
    
    // Observer for navigating to map view
    private let navigateToMapObserver = NotificationCenter.default
        .publisher(for: Notification.Name("NavigateToMapView"))

    // Permission scope contraction observer — moved to PINGatedView

    // Push notification deep linking observers
    private let openProjectDetailsObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenProjectDetails"))

    private let openTaskDetailsObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenTaskDetails"))

    private let openClientDetailsObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenClientDetails"))

    // Bug G4 — observer for Spotlight taps on sub-client results. The subclient
    // id is resolved to its parent client id here, then routed through the
    // existing client detail path so the user lands on the parent's contact
    // profile (which displays sub-client rows).
    private let openSubClientDetailsObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenSubClientDetails"))

    private let openInvoiceDetailsObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenInvoiceDetails"))

    private let openEstimateDetailsObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenEstimateDetails"))

    private let showAccessDeniedObserver = NotificationCenter.default
        .publisher(for: Notification.Name("ShowAccessDenied"))

    private let spotlightReindexObserver = NotificationCenter.default
        .publisher(for: Notification.Name("SpotlightReindexRequested"))

    private let openScheduleObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenSchedule"))

    private let openJobBoardObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenJobBoard"))

    private let openCatalogObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenCatalog"))

    private let openSubscriptionObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenSubscription"))

    private let openMemberRoleAssignmentObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenMemberRoleAssignment"))

    private let openAppFromWebObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenAppFromWeb"))

    // Bug 8ed0d2ed — wire the OpenExpenses notification (posted by AppDelegate
    // for push and by NotificationListView for in-app expense rows). Without
    // this listener, both paths posted into the void.
    private let openExpensesObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenExpenses"))

    private let openInvoicesObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenInvoices"))

    // Cashflow forecast deep-link. Posted by NotificationListView for
    // forecast_dip / forecast_cleared rail entries. Switches to BOOKS, then
    // posts OpenCashflowForecast so BooksTabView presents the forecast screen.
    private let openBooksObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenBooks"))

    private let openProjectsNeedingTasksObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenProjectsNeedingTasks"))

    // Keyboard observers
    private let keyboardWillShow = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillShowNotification)
    
    private let keyboardWillHide = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillHideNotification)
    
    // BOOKS tab is visible to anyone with at least one of the three financial-area
    // permissions. The hub itself filters segments per-permission; users with a
    // single visible segment auto-skip the hub via `booksAutoSkipDestination`.
    //
    // Books Phase 2 (2026-05-11): `pipeline.view` no longer gates BOOKS — Pipeline
    // is its own top-level tab (see `PIPELINE TAB - P1-1`).
    private var hasBooksAccess: Bool {
        permissionStore.can("finances.view")
            || permissionStore.can("estimates.view")
            || permissionStore.can("expenses.view")
    }

    private var visibleBooksSegments: [BooksSection] {
        BooksSection.allCases.filter { permissionStore.can($0.requiredPermission) }
    }

    /// When the user has exactly one visible BOOKS segment, route them straight
    /// to that segment's list view instead of the hub. This matters most for
    /// Crew, who only have `expenses.view` (own scope) and never need to see
    /// the carousel or the segmented chrome.
    private var booksAutoSkipDestination: AnyView? {
        let segs = visibleBooksSegments
        guard segs.count == 1, let only = segs.first else { return nil }
        switch only {
        case .invoices:
            return AnyView(NavigationStack { InvoicesListView() })
        case .estimates:
            return AnyView(NavigationStack { EstimatesListView() })
        case .expenses:
            let scopeIsOwn = !permissionStore.hasFullAccess("expenses.view")
            if scopeIsOwn {
                return AnyView(NavigationStack { MyExpensesView() })
            } else {
                return AnyView(NavigationStack { ExpensesListView() })
            }
        }
    }

    // Computed tab indices that adapt based on visible tabs (LEADS + BOOKS + catalog).
    private var leadsTabIndex: Int? { hasLeadsAccess ? 1 : nil }
    private var booksTabIndex: Int? {
        guard hasBooksAccess else { return nil }
        return hasLeadsAccess ? 2 : 1
    }
    private var jobBoardTabIndex: Int {
        var idx = 1
        if hasLeadsAccess { idx += 1 }
        if hasBooksAccess { idx += 1 }
        return idx
    }
    private var catalogTabIndex: Int? {
        guard hasCatalogAccess else { return nil }
        return jobBoardTabIndex + 1
    }
    private var scheduleTabIndex: Int {
        var idx = jobBoardTabIndex + 1
        if hasCatalogAccess { idx += 1 }
        return idx
    }
    private var settingsTabIndex: Int {
        return scheduleTabIndex + 1
    }

    // Dynamic tabs based on user role
    private var tabs: [TabItem] {
        var baseTabs: [TabItem] = [
            TabItem(iconName: "house.fill", wizardStepId: "welcome_home")
        ]

        // Add LEADS tab for users with pipeline.view + pipeline feature flag
        if hasLeadsAccess {
            baseTabs.append(TabItem(
                iconName: "point.3.connected.trianglepath.dotted",
                wizardStepId: "welcome_leads"
            ))
        }

        // Add BOOKS tab for users with any of the three financial-area perms
        if hasBooksAccess {
            baseTabs.append(TabItem(iconName: "chart.line.uptrend.xyaxis", wizardStepId: "welcome_books"))
        }

        // Add Job Board tab for all users (admin, office crew, and field crew)
        baseTabs.append(TabItem(iconName: "briefcase.fill", wizardStepId: "welcome_job_board"))

        // Add Catalog tab if user has catalog access
        if hasCatalogAccess {
            baseTabs.append(TabItem(iconName: "square.stack.3d.up.fill", wizardStepId: "welcome_catalog"))
        }

        // Add Schedule and Settings for all users
        baseTabs.append(contentsOf: [
            TabItem(iconName: "calendar", wizardStepId: "welcome_schedule"),
            TabItem(iconName: "gearshape.fill", wizardStepId: "welcome_settings")
        ])

        return baseTabs
    }

    // Check if currently on Settings tab
    private var isSettingsTab: Bool {
        let tabCount = tabs.count
        // Settings is always the last tab
        // For admin/office crew (4 tabs): Settings is tab 3
        // For field crew (3 tabs): Settings is tab 2
        return selectedTab == (tabCount - 1)
    }

    // Check if currently on BOOKS tab (Pipeline section lives inside Books until
    // Reconstruction lands; this flag tracks the financial hub, not the new
    // standalone LEADS tab).
    private var isBooksTab: Bool {
        if let idx = booksTabIndex { return selectedTab == idx }
        return false
    }

    // Check if currently on the new standalone LEADS tab. Used by
    // FloatingActionMenu to surface "Add Lead" first in the MONEY group.
    private var isLeadsTab: Bool {
        if let idx = leadsTabIndex { return selectedTab == idx }
        return false
    }

    /// Bug 706a4d32 — single search button rendered outside the sliding tab
    /// content so it stays visually stationary during tab swaps. Behavior
    /// branches on the current tab so Settings still gets its expand-in-place
    /// input while every other tab opens the universal search sheet.
    @ViewBuilder
    private var persistentSearchButton: some View {
        Button {
            let onSettings = isSettingsTab
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if onSettings {
                withAnimation(OPSStyle.Animation.spring) {
                    appState.isSettingsSearchActive = true
                }
            } else {
                appState.showingUniversalSearch = true
            }
        } label: {
            Image(OPSStyle.Icons.search)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 44, height: 44)
                .background(OPSStyle.Colors.cardBackground)
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var slideTransition: AnyTransition {
        if selectedTab > previousTab {
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }

    // FAB visibility expression hoisted out of the modifier chain so the
    // view-builder type-checker isn't asked to resolve the same 6-term
    // boolean twice inline. Stays in lockstep with `allowsHitTesting`.
    private var isFABVisible: Bool {
        !isSettingsTab
            && !dataController.isPerformingInitialSync
            && !appState.isLoadingProjects
            && !appState.isScheduleSelectionMode
            && !appState.isShowingMapOverlay
            && !appState.isInProjectMode
    }

    // Floating action menu wrapper — extracted from `body` to stay under
    // the SwiftUI view-builder type-check complexity budget once the LEADS
    // tab landed.
    @ViewBuilder
    private var floatingActionMenu: some View {
        FloatingActionMenu(
            currentTab: selectedTab,
            hasCatalogAccess: hasCatalogAccess,
            isScheduleTab: selectedTab == scheduleTabIndex,
            isCatalogTab: catalogTabIndex != nil && selectedTab == catalogTabIndex,
            isLeadsTab: isLeadsTab
        )
        .environmentObject(dataController)
        .environmentObject(appState)
        .opacity(isFABVisible ? 1 : 0)
        .allowsHitTesting(isFABVisible)
        .animation(OPSStyle.Animation.fast, value: isSettingsTab)
        .animation(OPSStyle.Animation.fast, value: dataController.isPerformingInitialSync)
        .animation(OPSStyle.Animation.fast, value: appState.isLoadingProjects)
        .animation(OPSStyle.Animation.fast, value: appState.isInventorySelectionMode)
        .animation(OPSStyle.Animation.fast, value: appState.isScheduleSelectionMode)
        .animation(OPSStyle.Animation.fast, value: appState.isShowingMapOverlay)
        .animation(OPSStyle.Animation.fast, value: appState.isInProjectMode)
    }

    // Tab content router — extracted from `body` so the compiler can
    // type-check the if/else chain (each new tab added to the chain
    // multiplies the type-check work, hence the extraction).
    @ViewBuilder
    private var tabContent: some View {
        if selectedTab == 0 {
            HomeView()
        } else if selectedTab == leadsTabIndex {
            LeadsTabView()
        } else if selectedTab == booksTabIndex {
            if let destination = booksAutoSkipDestination {
                destination
            } else {
                BooksTabView()
            }
        } else if selectedTab == jobBoardTabIndex {
            JobBoardView()
        } else if selectedTab == catalogTabIndex {
            CatalogView()
        } else if selectedTab == scheduleTabIndex {
            ScheduleView()
        } else if selectedTab == settingsTabIndex {
            SettingsView()
        } else {
            HomeView()
        }
    }

    var body: some View {
        ZStack {
            // Main content structure with sliding transitions
            // Dynamic content based on tabs array
            let tabCount = tabs.count

            // Content views with transition — each complete view slides as a
            // unit. Wrapping the tab content in a Group with `.id(selectedTab)`
            // forces SwiftUI to treat tab swaps as a view identity change,
            // which is what actually lets `.transition(slideTransition)` fire.
            // Without the `.id`, the outer container is re-used across tabs and
            // the inner if/else branches just fade in/out (the bug we're fixing).
            Group {
                tabContent
            }
            .id(selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all, edges: .bottom)
            // Bug 706a4d32 — inject the shared header namespace so each tab's
            // AppHeader can match-geometry its tab-specific persistent buttons
            // (filter, scope, month, review). The universal search button is
            // hosted by the overlay below instead — matchedGeometryEffect with
            // two simultaneous isSource=true views during a tab swap doesn't
            // reliably keep the element stationary, so we lift the only truly
            // cross-tab element out of the sliding container entirely. Tab
            // content reserves layout space so the other right-aligned buttons
            // keep their horizontal position.
            .environment(\.persistentHeaderNamespace, persistentHeaderNamespace)
            .environment(\.hostsPersistentSearchButton, selectedTab != 0)
            .transition(slideTransition)
            .animation(OPSStyle.Animation.smooth, value: selectedTab)

            // Persistent search button overlay — rendered OUTSIDE the sliding
            // .transition above so it stays visually still while tab content
            // slides. Position matches AppHeader's right-aligned button slot
            // (20pt horizontal padding, 12pt vertical padding). Hidden on
            // the home tab where AppHeader doesn't show a search button.
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if selectedTab != 0 {
                        persistentSearchButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                Spacer()
            }
            .allowsHitTesting(selectedTab != 0)
            .zIndex(3)

            // Image sync progress bar and sync status at top
            VStack(spacing: 8) {
                ImageSyncProgressView(syncManager: imageSyncProgressManager)

                // Sync status indicator — hidden when sync restored banner is showing
                if !dataController.showSyncRestoredAlert {
                    HStack {
                        Spacer()
                        SyncStatusIndicator()
                            .environmentObject(dataController)
                            .padding(.trailing, 16)
                    }
                }

                Spacer()
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .zIndex(1) // Ensure it appears above content
            
            // Custom tab bar overlaid at bottom
            VStack {
                Spacer()
                CustomTabBar(selectedTab: $selectedTab, tabs: tabs)
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .preferredColorScheme(.dark)
            .opacity(keyboardIsShowing || dataController.isPerformingInitialSync || appState.isLoadingProjects ? 0 : 1)
            .animation(OPSStyle.Animation.standard, value: keyboardIsShowing)
            .animation(OPSStyle.Animation.standard, value: dataController.isPerformingInitialSync)
            .animation(OPSStyle.Animation.standard, value: appState.isLoadingProjects)

            // Floating action menu - visible across all tabs except Settings and during initial sync/loading
            // IMPORTANT: Always render to preserve @State (sheet presentation) when app goes to background
            // Use opacity and allowsHitTesting instead of conditional rendering to prevent sheet dismissal
            floatingActionMenu

            // Project sheet container that overlays the whole app
            ProjectSheetContainer()

            // Permission contraction overlay — moved to PINGatedView (ContentView.swift)

            // Deep-link loading banner — shown only while a tapped project
            // link is awaiting a server fetch (cold-cache case). Local-cache
            // hits skip this entirely. autoDismissAfter=0 means "manual
            // dismiss only" — the `showDeepLinkLoading` flag is flipped off
            // by openProjectWithSync's `defer` block when resolution lands.
            PushInMessage(
                isPresented: $showDeepLinkLoading,
                title: "LOADING PROJECT",
                subtitle: "Fetching the latest data...",
                type: .info,
                autoDismissAfter: 0
            )
            .zIndex(2)
        }
        // Toast surface for LEADS sheet-action confirmations. Mounted at the
        // app root (not the LEADS tab) so a confirmation survives a tab swap
        // — the operator who saves a lead and immediately switches to PROJECTS
        // still sees the "// LEAD CREATED" pill. Overlay sits above the
        // ZStack (and therefore above PushInMessage at zIndex 2).
        .toastHost()
        .leadsToastSubscriber()
        .sheet(isPresented: $appState.showingUniversalSearch) {
            UniversalSearchSheet()
                .environmentObject(dataController)
                .environmentObject(appState)
        }
        // Client detail sheet (from Spotlight / deep link).
        //
        // Bug G1 — Spotlight taps on a client should open the READ-ONLY contact
        // view, not the edit form. ClientSheet(mode: .edit(...)) was the legacy
        // behavior; it dumped the user straight into a form with fields active.
        // ContactDetailView is the canonical surface used from every other
        // client-surface tap (JobBoard card, UniversalSearchSheet, task details);
        // deep-links from Spotlight should match that contract. From the detail
        // view, the user can still tap the pencil to edit when they need to.
        .sheet(isPresented: $appState.showClientDetails) {
            if let clientId = appState.selectedClientId,
               let ctx = dataController.modelContext,
               let client = try? ctx.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })).first {
                ContactDetailView(client: client, project: nil)
                    .environmentObject(dataController)
                    .environmentObject(permissionStore)
            }
        }
        // Invoice detail sheet (from Spotlight / deep link)
        .sheet(isPresented: $appState.showInvoiceDetails) {
            if let invoiceId = appState.selectedInvoiceId,
               let ctx = dataController.modelContext,
               let invoice = try? ctx.fetch(FetchDescriptor<Invoice>(predicate: #Predicate { $0.id == invoiceId })).first,
               let companyId = dataController.currentUser?.companyId {
                NavigationStack {
                    InvoiceDetailViewDeepLinkWrapper(
                        invoice: invoice,
                        companyId: companyId
                    )
                }
                .environmentObject(dataController)
                .environmentObject(permissionStore)
            }
        }
        // Estimate detail sheet (from Spotlight / deep link)
        .sheet(isPresented: $appState.showEstimateDetails) {
            if let estimateId = appState.selectedEstimateId,
               let ctx = dataController.modelContext,
               let estimate = try? ctx.fetch(FetchDescriptor<Estimate>(predicate: #Predicate { $0.id == estimateId })).first,
               let companyId = dataController.currentUser?.companyId {
                NavigationStack {
                    EstimateDetailViewDeepLinkWrapper(
                        estimate: estimate,
                        companyId: companyId
                    )
                }
                .environmentObject(dataController)
                .environmentObject(permissionStore)
            }
        }
        // Access denied sheet (tapped result no longer permitted)
        .sheet(isPresented: $appState.showAccessDenied) {
            AccessDeniedSheet(message: appState.accessDeniedMessage ?? "Access denied.")
        }
        // Add notification handler for project fetching
        .onReceive(fetchProjectObserver) { notification in
            if let projectID = notification.userInfo?["projectID"] as? String {
                if let project = dataController.getProject(id: projectID) {
                    // Update app state with the fetched project
                    DispatchQueue.main.async {
                        appState.setActiveProject(project)
                        
                        // Debug to check project mode after setting
                    }
                } else {
                }
            }
        }
        
        // Add notification handler for showing project details
        .onReceive(showProjectObserver) { notification in
            if let projectID = notification.userInfo?["projectID"] as? String {
                
                // Make sure we're on the main thread
                DispatchQueue.main.async {
                    if let project = dataController.getProject(id: projectID) {
                        
                        // Set the active project before setting showProjectDetails
                        appState.isViewingDetailsOnly = true
                        appState.activeProjectID = project.id
                        
                        // The important part - we set the flag AFTER setting the project
                        appState.showProjectDetails = true
                    } else {
                    }
                }
            }
        }
        
        // Permission scope contraction handler — moved to PINGatedView

        // Handle navigation to map view
        .onReceive(navigateToMapObserver) { _ in
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = 0 // Switch to home/map tab
            }
        }

        // MARK: - Push Notification Deep Linking Handlers

        // Handle opening project details from push notification, universal
        // link, or custom-scheme tap. Cancels any in-flight resolution so
        // two rapid taps resolve the newest one only — prevents double-
        // present races at the AppState sheet layer.
        .onReceive(openProjectDetailsObserver) { notification in
            guard let projectId = notification.userInfo?["projectId"] as? String else { return }
            let deepLinkId = notification.userInfo?[DeepLinkCoordinator.deepLinkIdUserInfoKey] as? String
            print("[PUSH_NAVIGATION] Opening project details for: \(projectId) (deepLinkId=\(deepLinkId ?? "nil"))")

            inFlightDeepLinkTask?.cancel()
            inFlightDeepLinkTask = Task { [projectId, deepLinkId] in
                await openProjectWithSync(projectId: projectId, deepLinkId: deepLinkId)
            }
        }

        // Web-to-app return bridge
        .onReceive(openAppFromWebObserver) { notification in
            let from = (notification.userInfo?["from"] as? String) ?? ""
            print("[OpenAppFromWeb] Received inside MainTabView (user already signed in), from=\(from)")
        }

        // Handle opening task details from push notification or Spotlight tap.
        .onReceive(openTaskDetailsObserver) { notification in
            guard let taskId = notification.userInfo?["taskId"] as? String else { return }
            let providedProjectId = notification.userInfo?["projectId"] as? String
            Task {
                let projectId: String
                if let providedProjectId = providedProjectId {
                    projectId = providedProjectId
                } else if let resolved = await resolveProjectId(forTask: taskId) {
                    projectId = resolved
                } else {
                    print("[PUSH_NAVIGATION] Task \(taskId) not found locally — showing access denied")
                    await MainActor.run {
                        appState.presentAccessDenied(message: "This task is no longer available.")
                    }
                    return
                }
                print("[PUSH_NAVIGATION] Opening task details - Task: \(taskId), Project: \(projectId)")
                await openTaskWithSync(taskId: taskId, projectId: projectId)
            }
        }

        // Handle opening client details (from Spotlight tap / universal link / push)
        .onReceive(openClientDetailsObserver) { notification in
            if let clientId = notification.userInfo?["clientId"] as? String {
                print("[PUSH_NAVIGATION] Opening client details for: \(clientId)")
                openClientWithSync(clientId: clientId)
            }
        }

        // Bug G4 — Spotlight tap on a sub-client result. Look up the subclient's
        // parent in SwiftData and route to the parent's ContactDetailView. If
        // the subclient isn't present locally (sync lag / purge), fall back to
        // an access-denied message; triggering a full sync here would surprise
        // the user with a several-second hang on a tap.
        .onReceive(openSubClientDetailsObserver) { notification in
            guard let subClientId = notification.userInfo?["subClientId"] as? String else { return }
            guard let context = dataController.modelContext else { return }
            let descriptor = FetchDescriptor<SubClient>(predicate: #Predicate { $0.id == subClientId })
            if let sub = try? context.fetch(descriptor).first,
               let parentId = sub.client?.id {
                print("[PUSH_NAVIGATION] Opening sub-client \(subClientId) via parent \(parentId)")
                openClientWithSync(clientId: parentId)
            } else {
                appState.presentAccessDenied(message: "This contact is no longer available.")
            }
        }

        // Handle opening invoice details
        .onReceive(openInvoiceDetailsObserver) { notification in
            if let invoiceId = notification.userInfo?["invoiceId"] as? String {
                print("[PUSH_NAVIGATION] Opening invoice details for: \(invoiceId)")
                openInvoiceWithSync(invoiceId: invoiceId)
            }
        }

        // Handle opening estimate details
        .onReceive(openEstimateDetailsObserver) { notification in
            if let estimateId = notification.userInfo?["estimateId"] as? String {
                print("[PUSH_NAVIGATION] Opening estimate details for: \(estimateId)")
                openEstimateWithSync(estimateId: estimateId)
            }
        }

        // Handle access denied presentations (tapped Spotlight result no longer permitted)
        .onReceive(showAccessDeniedObserver) { notification in
            let message = (notification.userInfo?["message"] as? String) ?? "Access denied."
            appState.presentAccessDenied(message: message)
        }

        // Role change → clear + rebuild Spotlight index under the new scope
        .onReceive(spotlightReindexObserver) { _ in
            guard let ctx = dataController.modelContext else { return }
            Task { @MainActor in
                await SpotlightIndexManager.shared.clearAll()
                await SpotlightIndexManager.shared.backfill(context: ctx)
            }
        }

        // Handle opening schedule view from push notification
        .onReceive(openScheduleObserver) { _ in
            print("[PUSH_NAVIGATION] Opening schedule view")
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = scheduleTabIndex
            }
        }

        // Handle opening subscription/plan selection from push notification
        .onReceive(openSubscriptionObserver) { _ in
            print("[PUSH_NAVIGATION] Opening subscription plan selection")
            appState.showingPlanSelection = true
        }

        // Handle opening job board from push notification
        .onReceive(openJobBoardObserver) { _ in
            print("[PUSH_NAVIGATION] Opening job board")
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = jobBoardTabIndex
            }
        }

        // Handle opening catalog from notification rail / deep link
        .onReceive(openCatalogObserver) { _ in
            guard let idx = catalogTabIndex else { return }
            print("[PUSH_NAVIGATION] Opening catalog")
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = idx
            }
        }

        // Bug 8ed0d2ed — Open expenses from notification rail / push.
        // Switch to the BOOKS tab (where Expenses lives), then ask BooksTabView
        // to select the expenses segment. For users without books access (rare,
        // but possible if expenses.view is the only finance permission), the
        // booksAutoSkipDestination already routes them straight to the right
        // expenses list, so flipping the tab is enough.
        .onReceive(openExpensesObserver) { _ in
            print("[PUSH_NAVIGATION] Opening expenses")
            guard hasBooksAccess, let idx = booksTabIndex else {
                print("[PUSH_NAVIGATION] No books access — expense deep link suppressed")
                return
            }
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = idx
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(
                    name: Notification.Name("BooksSelectSegment"),
                    object: nil,
                    userInfo: ["segment": BooksSection.expenses.rawValue]
                )
            }
        }

        .onReceive(openInvoicesObserver) { _ in
            print("[PUSH_NAVIGATION] Opening invoices")
            guard hasBooksAccess, let idx = booksTabIndex else { return }
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = idx
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(
                    name: Notification.Name("BooksSelectSegment"),
                    object: nil,
                    userInfo: ["segment": BooksSection.invoices.rawValue]
                )
            }
        }

        // Cashflow forecast — switch to BOOKS so BooksTabView's secondary
        // OpenCashflowForecast listener can present the forecast screen.
        .onReceive(openBooksObserver) { _ in
            print("[PUSH_NAVIGATION] Opening books for cashflow forecast")
            guard hasBooksAccess, let idx = booksTabIndex else {
                print("[PUSH_NAVIGATION] No books access — cashflow deep link suppressed")
                return
            }
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = idx
            }
        }

        // Bug 78309d78 — Open the "projects needing tasks" review sheet from
        // a push deep link. The in-app rail uses appState directly, so this
        // path only runs when the user lands here via a push tap.
        .onReceive(openProjectsNeedingTasksObserver) { _ in
            print("[PUSH_NAVIGATION] Opening projects-needing-tasks review")
            appState.showProjectsNeedingTasksReview = true
        }

        // Handle member_joined push → present AssignMemberRoleSheet
        .onReceive(openMemberRoleAssignmentObserver) { notification in
            guard let userInfo = notification.userInfo,
                  let memberId = userInfo["memberId"] as? String else { return }
            print("[PUSH_NAVIGATION] Opening member role assignment for \(memberId)")
            assignRoleMemberId = memberId
            assignRoleWasSeated = (userInfo["wasSeated"] as? Bool) ?? false
            showAssignRoleSheet = true
        }
        .sheet(isPresented: $showAssignRoleSheet) {
            if let memberId = assignRoleMemberId {
                AssignMemberRoleSheet(memberId: memberId, wasSeated: assignRoleWasSeated)
                    .environmentObject(dataController)
            }
        }

        // Bug 78309d78 — sheet for the "accepted projects with no tasks"
        // rail notification. Mounted at MainTabView so it presents reliably
        // after the notification rail dismisses, regardless of which tab the
        // user was on when they tapped the rail entry.
        .sheet(isPresented: $appState.showProjectsNeedingTasksReview) {
            ProjectsWithoutTasksReviewView()
                .environmentObject(dataController)
                .environmentObject(appState)
        }


        // Handle navigating to Clients tab in Job Board
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NavigateToClients"))) { _ in
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = jobBoardTabIndex
            }
            // Post follow-up notification to switch to Clients section within Job Board
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(
                    name: Notification.Name("SwitchToClientsSection"),
                    object: nil
                )
            }
        }

        // Track tab changes for slide transitions and analytics
        .onChange(of: selectedTab) { oldValue, newValue in
            previousTab = oldValue
            let tabName = analyticsTabName(for: newValue)
            AnalyticsManager.shared.trackTabSelected(tabName: tabName)
            AnalyticsService.shared.track(
                eventType: .action,
                eventName: "tab_selected",
                properties: ["tab_name": tabName.rawValue, "tab_index": tabName.index]
            )
        }

        // Handle keyboard appearance - but ignore if from a sheet
        .onReceive(keyboardWillShow) { notification in
            // Check if keyboard is from current window context
            // Don't hide tab bar if keyboard is from a sheet
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                let keyboardHeight = keyboardFrame.cgRectValue.height
                // Only respond to keyboard if it's substantial (not from sheet)
                if keyboardHeight > 0 && !checkIfSheetIsPresented() {
                    withAnimation(OPSStyle.Animation.standard) {
                        keyboardIsShowing = true
                    }
                }
            }
        }
        .onReceive(keyboardWillHide) { _ in
            withAnimation(OPSStyle.Animation.standard) {
                keyboardIsShowing = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardOpenMostRecentProject"))) { _ in
            handleWizardOpenMostRecentProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardNavigateToTarget"))) { notification in
            guard let tabTarget = notification.userInfo?["tabTarget"] as? String else { return }
            switch tabTarget {
            case "Home":
                withAnimation { selectedTab = 0 }
            case "Pipeline":
                if let idx = leadsTabIndex {
                    withAnimation { selectedTab = idx }
                }
            case "Books":
                if let idx = booksTabIndex {
                    withAnimation { selectedTab = idx }
                }
            case "JobBoard":
                withAnimation { selectedTab = jobBoardTabIndex }
            case "Schedule":
                withAnimation { selectedTab = scheduleTabIndex }
            case "Catalog":
                if let idx = catalogTabIndex {
                    withAnimation { selectedTab = idx }
                }
            case "Settings":
                withAnimation { selectedTab = settingsTabIndex }
            default:
                break
            }
        }
        // Wizard deep nav for settings sub-screens — handled here because SettingsView's
        // modifier stack is too deep for additional .onReceive handlers
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardOpenSecuritySettings"))) { _ in
            withAnimation { selectedTab = settingsTabIndex }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("SettingsOpenSecurity"), object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardOpenNotificationSettings"))) { _ in
            withAnimation { selectedTab = settingsTabIndex }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("SettingsOpenNotifications"), object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardOpenManageTeam"))) { _ in
            // Bug 4014b472 — Manage Team is a top-level Settings row in the new
            // IA, so wizards can land there directly instead of the previous
            // two-hop dance through Organization → ManageTeamFromOrg.
            withAnimation { selectedTab = settingsTabIndex }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("SettingsOpenManageTeam"), object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardOpenPermissions"))) { _ in
            withAnimation { selectedTab = settingsTabIndex }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("SettingsOpenPermissions"), object: nil)
            }
        }
        // Bug G3 — Re-evaluate review stacks when the app returns from
        // background so the persistent rail notifications fire on the session
        // where the user actually sees them. Without this the service only
        // ran at launch and a queue that crossed threshold overnight would
        // stay silent until the next cold start.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            ReviewThresholdService.evaluate(dataController: dataController)
        }
        // Bug G3 — Re-evaluate review stacks after every sync completes
        // (isSyncing transitions true → false). New tasks / completed projects
        // arriving via sync are the most common way a stack crosses threshold,
        // so this is the highest-signal trigger moment.
        .onChange(of: dataController.syncEngine.isSyncing) { wasSyncing, isSyncing in
            if wasSyncing && !isSyncing {
                ReviewThresholdService.evaluate(dataController: dataController)
            }
        }
        .onAppear {
            // Clear all pending image syncs on app bootup
            clearPendingImageSyncs()

            // Initialize user role
            userRole = dataController.currentUser?.role
            print("[MAIN_TAB_VIEW] onAppear - Initial user role: \(String(describing: userRole))")
            print("[MAIN_TAB_VIEW] onAppear - Current user: \(String(describing: dataController.currentUser?.fullName))")
            print("[MAIN_TAB_VIEW] onAppear - Tab count: \(tabs.count)")

            // Check for overdue payment reviews after giving sync time to complete.
            // This also kicks ReviewThresholdService via checkOverdueProjects so
            // the initial evaluation runs once sync has had time to populate.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                appState.checkOverdueProjects(dataController: dataController)
            }

            // Evaluate wizard triggers after data has had time to load
            if !hasEvaluatedWizards {
                hasEvaluatedWizards = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    evaluateWizardTriggers()
                }
            }

            // Deep-link resume: if a link arrived while MainTabView wasn't
            // mounted (splash, logged-out, lockout, blocking app message),
            // re-post it now that our `.onReceive` observers are attached.
            // Idempotent — safe to call on every onAppear; drain is a no-op
            // when nothing is pending.
            DispatchQueue.main.async {
                DeepLinkCoordinator.shared.drain(context: "main_tab_appear")
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            NotificationCenter.default.post(
                name: Notification.Name("WizardCurrentTabChanged"),
                object: nil,
                userInfo: ["tabName": wizardTabName(for: newTab)]
            )
        }
        .onChange(of: dataController.currentUser?.role) { oldRole, newRole in
            print("[MAIN_TAB_VIEW] User role changed from \(String(describing: oldRole)) to \(String(describing: newRole))")
            userRole = newRole
            print("[MAIN_TAB_VIEW] After role change - Tab count: \(tabs.count)")

            // Ensure selected tab is valid for new tab count
            let newTabCount = tabs.count
            if selectedTab >= newTabCount {
                selectedTab = 0 // Reset to home if current tab no longer exists
            }
        }
        .onChange(of: dataController.currentUser?.id) { oldUserId, newUserId in
            print("[MAIN_TAB_VIEW] currentUser ID changed")
            print("[MAIN_TAB_VIEW]   Old ID: \(String(describing: oldUserId))")
            print("[MAIN_TAB_VIEW]   New ID: \(String(describing: newUserId))")
            let newUser = dataController.currentUser

            // Update userRole when currentUser changes
            if let newRole = newUser?.role {
                userRole = newRole
                print("[MAIN_TAB_VIEW] Updated userRole to: \(newRole)")
            }
        }
        .onChange(of: permissionStore.permissions) { oldValue, newValue in
            print("[MAIN_TAB_VIEW] Permissions changed - Tab count: \(tabs.count)")

            // Ensure selected tab is valid for new tab count
            let newTabCount = tabs.count
            if selectedTab >= newTabCount {
                selectedTab = 0 // Reset to home if current tab no longer exists
            }
        }
        // C2: Re-evaluate wizard triggers once initial sync completes
        .onChange(of: dataController.isPerformingInitialSync) { _, isLoading in
            if !isLoading && needsWizardRetry {
                evaluateWizardTriggers()
            }
        }
        .onChange(of: appState.isLoadingProjects) { _, isLoading in
            if !isLoading && needsWizardRetry {
                evaluateWizardTriggers()
            }
        }
    }
    
    // handlePermissionRefresh moved to PINGatedView (ContentView.swift)

    /// Maps a tab index to its `TabName` for analytics. Extracted from `body`
    /// because the inline closure form pushed the type-checker over its
    /// complexity budget once the LEADS tab was added.
    private func analyticsTabName(for index: Int) -> TabName {
        if index == 0 { return .home }
        if index == leadsTabIndex { return .pipeline }
        if index == booksTabIndex { return .books }
        if index == jobBoardTabIndex { return .jobBoard }
        if index == scheduleTabIndex { return .schedule }
        if index == settingsTabIndex { return .settings }
        if let cat = catalogTabIndex, index == cat { return .inventory }
        return .home
    }

    /// Maps a tab index to the string name broadcast via
    /// `WizardCurrentTabChanged` for wizard context tracking. The "Pipeline"
    /// string is intentionally retained for the LEADS tab so existing wizard
    /// scripts that target Pipeline continue to work post-rename.
    private func wizardTabName(for index: Int) -> String {
        switch index {
        case 0: return "Home"
        case jobBoardTabIndex: return "JobBoard"
        case scheduleTabIndex: return "Schedule"
        case settingsTabIndex: return "Settings"
        default:
            if let cat = catalogTabIndex, index == cat { return "Catalog" }
            if let leads = leadsTabIndex, index == leads { return "Pipeline" }
            if let books = booksTabIndex, index == books { return "Books" }
            return "Unknown"
        }
    }

    /// Handles the `WizardOpenMostRecentProject` deep-nav: prefer a stored
    /// project id (CONTINUE GUIDE), otherwise fetch the most recent project
    /// scoped to crew/operator assignment when applicable. Extracted from the
    /// `body` closure to keep the SwiftUI view-builder under the type-check
    /// complexity budget.
    private func handleWizardOpenMostRecentProject() {
        guard let modelContext = dataController.modelContext else { return }

        if let storedId = wizardStateManager?.deepNavProjectId {
            let storedDescriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.id == storedId }
            )
            if let existing = (try? modelContext.fetch(storedDescriptor))?.first {
                appState.viewProjectDetails(existing)
                return
            }
        }

        let companyId = dataController.currentUser?.companyId ?? ""
        let userId = dataController.currentUser?.id ?? ""
        let isFieldRole = dataController.currentUser?.role == .crew || dataController.currentUser?.role == .operator

        let descriptor: FetchDescriptor<Project>
        if isFieldRole {
            descriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { project in
                    project.companyId == companyId &&
                    project.teamMemberIdsString.contains(userId)
                },
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { project in
                    project.companyId == companyId
                },
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
        }

        if let project = (try? modelContext.fetch(descriptor))?.first {
            wizardStateManager?.deepNavProjectId = project.id
            appState.viewProjectDetails(project)
        }
    }

    /// Evaluate wizard triggers based on current data state.
    /// Checks both sequenced wizards (project lifecycle) and data-condition wizards (task/payment review).
    private func evaluateWizardTriggers() {
        guard let triggerService = wizardTriggerService else { return }
        guard let modelContext = dataController.modelContext else { return }

        // C2: Don't evaluate while initial sync is in progress — re-schedule via onChange
        guard !dataController.isPerformingInitialSync, !appState.isLoadingProjects else {
            needsWizardRetry = true
            return
        }
        needsWizardRetry = false

        // C3: Don't start wizards while the interactive tutorial is still in progress
        guard dataController.currentUser?.hasCompletedAppTutorial == true else { return }

        // H2: Don't start wizards for unassigned users (pre-role-assignment)
        guard dataController.currentUser?.role != .unassigned else { return }

        let companyId = dataController.currentUser?.companyId ?? ""

        // Count projects for the current user's company (used by welcome tour + sequenced wizards)
        var projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.companyId == companyId
            }
        )
        projectDescriptor.propertiesToFetch = []
        let projectCount = (try? modelContext.fetchCount(projectDescriptor)) ?? 0

        // Welcome tour: auto-start on first app entry or resume if interrupted (C1)
        if let stateManager = wizardStateManager, !stateManager.isActive {
            let welcomeWizard = WelcomeTourWizard(permissionStore: permissionStore)
            if welcomeWizard.steps.count > 0,
               let state = stateManager.wizardState(for: "welcome_tour") {

                if state.status == .notStarted {
                    // Existing users updating to this version already have projects —
                    // silently mark the tour as completed so they don't get an unwanted tour.
                    if projectCount > 0 {
                        state.markCompleted()
                        try? modelContext.save()
                    } else {
                        stateManager.startWizardDirectly(welcomeWizard)
                        return
                    }
                } else if state.status == .inProgress {
                    // Resume an interrupted tour
                    stateManager.startWizardDirectly(welcomeWizard)
                    return
                }
            }
        }

        // Sequenced wizards (e.g., ProjectLifecycleWizard triggers when 0 projects)
        triggerService.evaluateSequencedWizards(projectCount: projectCount)

        // Data-condition wizards: count overdue tasks and completed projects
        // Fetch all tasks for the company and filter in memory (avoids complex #Predicate)
        let taskDescriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { task in
                task.companyId == companyId
            }
        )
        let allTasks = (try? modelContext.fetch(taskDescriptor)) ?? []
        let now = Date()
        let overdueCount = allTasks.filter { task in
            guard let endDate = task.endDate else { return false }
            return endDate < now && task.status != .completed
        }.count

        // Fetch all company projects and filter in memory (enum predicates not supported in #Predicate)
        let allProjectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.companyId == companyId
            }
        )
        let allProjects = (try? modelContext.fetch(allProjectDescriptor)) ?? []
        let completedCount = allProjects.filter { $0.status == .completed }.count
        let completedTaskCount = allTasks.filter { $0.status == .completed }.count

        triggerService.evaluateDataConditions(
            overdueTaskCount: overdueCount,
            completedProjectCount: completedCount,
            completedTaskCount: completedTaskCount
        )
    }

    private func clearPendingImageSyncs() {
        
        // Get the image sync manager from dataController
        if let imageSyncManager = dataController.imageSyncManager {
            // Get pending uploads before clearing
            let pendingUploads = imageSyncManager.getPendingUploads()
            
            if !pendingUploads.isEmpty {
                
                // Show progress bar for pending uploads
                imageSyncProgressManager.startSync(with: imageSyncManager, pendingUploads: pendingUploads)
                
                // Don't clear them - let the sync complete
                // The sync manager will handle clearing them after successful upload
            } else {
            }
            
            // Clear all pending uploads to prevent issues with large/stuck uploads
            imageSyncManager.clearAllPendingUploads()
        }
    }
    
    private func checkIfSheetIsPresented() -> Bool {
        // Check if any common sheets are presented
        // This is a simple check - you can expand based on your app's sheets
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            // Check if there's a presented view controller (sheet)
            return window.rootViewController?.presentedViewController != nil
        }
        return false
    }

    // MARK: - Push Notification Sync Helpers

    /// Open project details for a deep link (shareable URL, push, or Spotlight),
    /// applying the full access-control chain before presenting.
    ///
    /// Layered checks — each emits a distinct `deep_link_denied` event and
    /// shows an AccessDeniedSheet with a reason-specific message:
    ///
    ///   0. **PIN gate** — if the screen is PIN-protected and not yet
    ///      unlocked, return without clearing so the link resolves after
    ///      the user enters their PIN. Critical for preventing project
    ///      data from rendering behind the PIN overlay (sheets are root-VC
    ///      modals above the SwiftUI ZStack).
    ///   1. **Feature flag** — `projects.view` blocked by a disabled flag.
    ///   2. **Permission exists** — user's role has no `projects.view` at
    ///      any scope.
    ///   3. **Offline + not cached** — no connectivity and the project
    ///      isn't locally available; distinct reason so the user knows to
    ///      reconnect rather than thinking the project is gone.
    ///   4. **Project resolvable** — local cache first, then `getProjectDetails`
    ///      awaits a sync (no more `triggerFullSync + 0.5s sleep` race). If
    ///      Bubble doesn't return the project (RLS / 404 / wrong company),
    ///      the generic "not found" reason fires — we can't distinguish
    ///      server-denied from genuinely missing without leaking information.
    ///   5. **Not deleted** — `deletedAt == nil`. Tombstones fail here.
    ///   6. **Scope + mention** — `PermissionStore.canViewProject` enforces
    ///      `all` vs `assigned` scope and Bug G9 mention-grant access.
    ///
    /// `deepLinkId` is the correlation UUID threaded from the coordinator
    /// so every analytics event in the funnel can be joined on a single ID.
    ///
    /// The cross-company check that used to sit between (4) and (6) was
    /// removed: Bubble RLS prevents cross-company reads, so a mismatched
    /// local cache would only occur with a stale tombstone — in which case
    /// "not found" is the more honest message.
    @MainActor
    private func openProjectWithSync(projectId: String, deepLinkId: String?) async {
        // Layer 0 — PIN gate. Return without clearing so the link is
        // re-drained after PIN unlock (see PINGatedView.onChange).
        if dataController.simplePINManager.requiresPIN &&
           !dataController.simplePINManager.isAuthenticated {
            print("[DEEP_LINK] Deferring project \(projectId) — PIN required")
            return
        }

        // Layer 1 — feature flag (overrides RBAC)
        if permissionStore.isBlockedByFlag("projects.view") {
            denyProject(projectId: projectId, deepLinkId: deepLinkId,
                        reason: "feature_flag",
                        message: "Project access is not available on your account.")
            return
        }

        // Layer 2 — permission granted at any scope
        guard permissionStore.scope(for: "projects.view") != nil else {
            denyProject(projectId: projectId, deepLinkId: deepLinkId,
                        reason: "no_permission",
                        message: "You don't have permission to view projects.")
            return
        }

        // Layer 3 — resolve project (local cache → awaited sync, with
        // explicit offline handling so the user sees a useful message).
        let project: Project?
        if let local = dataController.getProject(id: projectId) {
            project = local
        } else if !dataController.isConnected {
            denyProject(projectId: projectId, deepLinkId: deepLinkId,
                        reason: "offline",
                        message: "You're offline. Connect to internet to open this project.")
            return
        } else {
            print("[DEEP_LINK] Project \(projectId) not cached — awaiting sync")
            showDeepLinkLoading = true
            defer { showDeepLinkLoading = false }

            do {
                project = try await dataController.getProjectDetails(projectId: projectId)
            } catch is CancellationError {
                // A newer deep-link tap cancelled us — silent exit, no
                // denial, no clear. The newer tap owns the stash now.
                print("[DEEP_LINK] Resolution cancelled for \(projectId)")
                return
            } catch {
                print("[DEEP_LINK] getProjectDetails failed: \(error.localizedDescription)")
                project = nil
            }

            // Honor cancellation that landed between await points.
            if Task.isCancelled { return }
        }

        guard let project = project else {
            denyProject(projectId: projectId, deepLinkId: deepLinkId,
                        reason: "not_found",
                        message: "This project is no longer available or you don't have access.")
            return
        }

        // Layer 5 — deleted check
        if project.deletedAt != nil {
            denyProject(projectId: projectId, deepLinkId: deepLinkId,
                        reason: "deleted",
                        message: "This project has been deleted.")
            return
        }

        // Layer 6 — scope-aware viewing (assigned / all / mention grant).
        // canViewProject already handles the feature-flag short-circuit
        // (redundant with Layer 1) plus own-scope denial.
        guard let userId = dataController.currentUser?.id else {
            denyProject(projectId: projectId, deepLinkId: deepLinkId,
                        reason: "no_user",
                        message: "You don't have permission to view this project.")
            return
        }
        guard permissionStore.canViewProject(project, userId: userId) else {
            denyProject(projectId: projectId, deepLinkId: deepLinkId,
                        reason: "scope",
                        message: "You don't have permission to view this project.")
            return
        }

        // All gates passed — open the sheet and clear the stash.
        AnalyticsService.shared.track(
            eventType: .action,
            eventName: "deep_link_resolved",
            properties: [
                "entity": "projects",
                "project_id": projectId,
                DeepLinkCoordinator.deepLinkIdUserInfoKey: deepLinkId ?? ""
            ]
        )
        DeepLinkCoordinator.shared.clear()
        appState.viewProjectDetailsById(projectId)
    }

    /// Centralized access-denied path for the project deep-link flow.
    /// Presents AccessDeniedSheet, clears the stash (the link has been
    /// "handled" from the user's perspective — they got feedback), and
    /// emits `deep_link_denied` with a machine-readable `reason` code so
    /// drop patterns are queryable.
    @MainActor
    private func denyProject(projectId: String, deepLinkId: String?, reason: String, message: String) {
        print("[DEEP_LINK] Project \(projectId) denied — \(reason)")
        appState.presentAccessDenied(message: message)
        AnalyticsService.shared.track(
            eventType: .action,
            eventName: "deep_link_denied",
            properties: [
                "entity": "projects",
                "project_id": projectId,
                "reason": reason,
                DeepLinkCoordinator.deepLinkIdUserInfoKey: deepLinkId ?? ""
            ]
        )
        DeepLinkCoordinator.shared.clear()
    }

    /// Resolve a task's parent project ID from SwiftData. Used when a Spotlight
    /// tap arrives with only a taskId — we look up the task's project before
    /// routing through `openTaskWithSync`.
    @MainActor
    private func resolveProjectId(forTask taskId: String) async -> String? {
        guard let context = dataController.modelContext else { return nil }
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.id == taskId }
        )
        if let task = try? context.fetch(descriptor).first {
            return task.project?.id ?? task.projectId
        }
        return nil
    }

    /// Open a client detail sheet. Fetches from SwiftData; surfaces access-denied if stale.
    @MainActor
    private func openClientWithSync(clientId: String) {
        guard let context = dataController.modelContext else { return }
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
        if (try? context.fetch(descriptor).first) != nil {
            appState.viewClientDetailsById(clientId)
        } else {
            appState.presentAccessDenied(message: "This client is no longer available.")
        }
    }

    /// Open an invoice detail sheet. Re-checks permissions at tap time; refreshes from server if stale.
    /// Gated by `pipeline.view` — the same permission that controls access to the Money tab where
    /// invoices normally live.
    @MainActor
    private func openInvoiceWithSync(invoiceId: String) {
        guard permissionStore.can("pipeline.view") else {
            appState.presentAccessDenied(message: "You don't have permission to view invoices.")
            return
        }
        guard let context = dataController.modelContext else { return }
        let descriptor = FetchDescriptor<Invoice>(predicate: #Predicate { $0.id == invoiceId })
        if (try? context.fetch(descriptor).first) != nil {
            appState.viewInvoiceDetailsById(invoiceId)
        } else {
            // Not in local store — trigger a sync and open afterwards
            Task {
                await dataController.triggerFullSync()
                await MainActor.run {
                    appState.viewInvoiceDetailsById(invoiceId)
                }
            }
        }
    }

    /// Open an estimate detail sheet. Re-checks permissions at tap time.
    /// Gated by `pipeline.view` (Money tab access) AND `estimates.view` if role defines it.
    @MainActor
    private func openEstimateWithSync(estimateId: String) {
        let hasPipelineGate = permissionStore.can("pipeline.view")
        let hasExplicitGate = permissionStore.can("estimates.view")
        guard hasPipelineGate || hasExplicitGate else {
            appState.presentAccessDenied(message: "You don't have permission to view estimates.")
            return
        }
        guard let context = dataController.modelContext else { return }
        let descriptor = FetchDescriptor<Estimate>(predicate: #Predicate { $0.id == estimateId })
        if (try? context.fetch(descriptor).first) != nil {
            appState.viewEstimateDetailsById(estimateId)
        } else {
            Task {
                await dataController.triggerFullSync()
                await MainActor.run {
                    appState.viewEstimateDetailsById(estimateId)
                }
            }
        }
    }

    /// Open task details, syncing first if the task/project isn't in the local database
    private func openTaskWithSync(taskId: String, projectId: String) async {
        // Check if project and task exist locally
        if let project = dataController.getProject(id: projectId),
           project.tasks.contains(where: { $0.id == taskId }) {
            print("[PUSH_NAVIGATION] Task found locally, opening immediately")
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("ShowTaskDetailsFromHome"),
                    object: nil,
                    userInfo: ["taskID": taskId, "projectID": projectId]
                )
            }
            return
        }

        // Task/project not found locally - sync first
        print("[PUSH_NAVIGATION] Task not found locally, triggering sync...")
        await syncAndOpenTask(taskId: taskId, projectId: projectId)
    }

    /// Sync data and then open task details
    private func syncAndOpenTask(taskId: String, projectId: String) async {
        print("[PUSH_NAVIGATION] Starting sync for task: \(taskId)")

        // Perform a full sync via DataController
        await dataController.triggerFullSync()

        // Small delay for SwiftData to process
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Try to open the task again
        await MainActor.run {
            if let project = dataController.getProject(id: projectId),
               project.tasks.contains(where: { $0.id == taskId }) {
                print("[PUSH_NAVIGATION] Task found after sync, opening")
                NotificationCenter.default.post(
                    name: Notification.Name("ShowTaskDetailsFromHome"),
                    object: nil,
                    userInfo: ["taskID": taskId, "projectID": projectId]
                )
            } else {
                print("[PUSH_NAVIGATION] Task still not found after sync")
            }
        }
    }
}
