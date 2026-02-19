//
//  MainTabView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// MainTabView.swift
import SwiftUI
import Combine
import MapKit

struct MainTabView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager

    @State private var selectedTab = 0
    @State private var previousTab = 0
    @State private var keyboardIsShowing = false
    @State private var sheetIsPresented = false
    @StateObject private var imageSyncProgressManager = ImageSyncProgressManager()
    @ObservedObject private var inProgressManager = InProgressManager.shared
    @State private var userRole: UserRole? = nil // Track user role changes explicitly
    
    // Observer for fetch active project notifications
    private let fetchProjectObserver = NotificationCenter.default
        .publisher(for: Notification.Name("FetchActiveProject"))
    
    // Observer for showing project details
    private let showProjectObserver = NotificationCenter.default
        .publisher(for: Notification.Name("ShowProjectDetailsRequest"))
    
    // Observer for navigating to map view
    private let navigateToMapObserver = NotificationCenter.default
        .publisher(for: Notification.Name("NavigateToMapView"))

    // Push notification deep linking observers
    private let openProjectDetailsObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenProjectDetails"))

    private let openTaskDetailsObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenTaskDetails"))

    private let openScheduleObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenSchedule"))

    private let openJobBoardObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenJobBoard"))
    
    // Keyboard observers
    private let keyboardWillShow = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillShowNotification)
    
    private let keyboardWillHide = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillHideNotification)
    
    // Whether the current user has Pipeline access (admin/office crew only)
    private var hasPipelineAccess: Bool {
        let role = dataController.currentUser?.role
        return role == .admin || role == .officeCrew
    }

    // Computed tab indices that adapt based on role
    private var pipelineTabIndex: Int? { hasPipelineAccess ? 1 : nil }
    private var jobBoardTabIndex: Int { hasPipelineAccess ? 2 : 1 }
    private var scheduleTabIndex: Int { hasPipelineAccess ? 3 : 2 }
    private var settingsTabIndex: Int { hasPipelineAccess ? 4 : 3 }

    // Dynamic tabs based on user role
    private var tabs: [TabItem] {
        var baseTabs: [TabItem] = [
            TabItem(iconName: "house.fill")
        ]

        // Add Pipeline tab for admin/office crew only
        if hasPipelineAccess {
            baseTabs.append(TabItem(iconName: OPSStyle.Icons.pipelineChart))
        }

        // Add Job Board tab for all users (admin, office crew, and field crew)
        baseTabs.append(TabItem(iconName: "briefcase.fill"))

        // Add Schedule and Settings for all users
        baseTabs.append(contentsOf: [
            TabItem(iconName: "calendar"),
            TabItem(iconName: "gearshape.fill")
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

    var body: some View {
        ZStack {
            // Main content structure with sliding transitions
            // Dynamic content based on tabs array
            let tabCount = tabs.count

            // Content views with transition - each complete view slides as a unit
            ZStack {
                // Tab content — indices adapt based on role (Pipeline tab for admin/office only)
                if selectedTab == 0 {
                    HomeView()
                } else if selectedTab == pipelineTabIndex {
                    PipelinePlaceholderView()
                } else if selectedTab == jobBoardTabIndex {
                    JobBoardView()
                } else if selectedTab == scheduleTabIndex {
                    ScheduleView()
                } else if selectedTab == settingsTabIndex {
                    SettingsView()
                } else {
                    HomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all, edges: .bottom)
            .transition(slideTransition)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedTab)
            
            // Image sync progress bar and sync status at top
            VStack(spacing: 8) {
                ImageSyncProgressView(syncManager: imageSyncProgressManager)

                // Sync status indicator
                HStack {
                    Spacer()
                    SyncStatusIndicator()
                        .environmentObject(dataController)
                        .padding(.trailing, 16)
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
            .animation(.easeInOut(duration: 0.25), value: keyboardIsShowing)
            .animation(.easeInOut(duration: 0.25), value: dataController.isPerformingInitialSync)
            .animation(.easeInOut(duration: 0.25), value: appState.isLoadingProjects)

            // Floating action menu - visible across all tabs except Settings and during initial sync/loading
            // IMPORTANT: Always render to preserve @State (sheet presentation) when app goes to background
            // Use opacity and allowsHitTesting instead of conditional rendering to prevent sheet dismissal
            FloatingActionMenu()
                .environmentObject(dataController)
                .opacity(!isSettingsTab && !dataController.isPerformingInitialSync && !appState.isLoadingProjects ? 1 : 0)
                .allowsHitTesting(!isSettingsTab && !dataController.isPerformingInitialSync && !appState.isLoadingProjects)
                .animation(.easeInOut(duration: 0.2), value: isSettingsTab)
                .animation(.easeInOut(duration: 0.2), value: dataController.isPerformingInitialSync)
                .animation(.easeInOut(duration: 0.2), value: appState.isLoadingProjects)

            // Project sheet container that overlays the whole app
            ProjectSheetContainer()
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
        
        // Handle navigation to map view
        .onReceive(navigateToMapObserver) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = 0 // Switch to home/map tab
            }
        }

        // MARK: - Push Notification Deep Linking Handlers

        // Handle opening project details from push notification
        .onReceive(openProjectDetailsObserver) { notification in
            if let projectId = notification.userInfo?["projectId"] as? String {
                print("[PUSH_NAVIGATION] Opening project details for: \(projectId)")
                Task {
                    await openProjectWithSync(projectId: projectId)
                }
            }
        }

        // Handle opening task details from push notification
        .onReceive(openTaskDetailsObserver) { notification in
            if let taskId = notification.userInfo?["taskId"] as? String,
               let projectId = notification.userInfo?["projectId"] as? String {
                print("[PUSH_NAVIGATION] Opening task details - Task: \(taskId), Project: \(projectId)")
                Task {
                    await openTaskWithSync(taskId: taskId, projectId: projectId)
                }
            }
        }

        // Handle opening schedule view from push notification
        .onReceive(openScheduleObserver) { _ in
            print("[PUSH_NAVIGATION] Opening schedule view")
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = scheduleTabIndex
            }
        }

        // Handle opening job board from push notification
        .onReceive(openJobBoardObserver) { _ in
            print("[PUSH_NAVIGATION] Opening job board")
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = jobBoardTabIndex
            }
        }

        // Track tab changes for slide transitions and analytics
        .onChange(of: selectedTab) { oldValue, newValue in
            previousTab = oldValue

            // Track tab selection for analytics — use computed indices for role-adaptive mapping
            let tabName: TabName = {
                if newValue == 0 { return .home }
                if newValue == pipelineTabIndex { return .pipeline }
                if newValue == jobBoardTabIndex { return .jobBoard }
                if newValue == scheduleTabIndex { return .schedule }
                if newValue == settingsTabIndex { return .settings }
                return .home
            }()
            AnalyticsManager.shared.trackTabSelected(tabName: tabName)
        }

        // Handle keyboard appearance - but ignore if from a sheet
        .onReceive(keyboardWillShow) { notification in
            // Check if keyboard is from current window context
            // Don't hide tab bar if keyboard is from a sheet
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                let keyboardHeight = keyboardFrame.cgRectValue.height
                // Only respond to keyboard if it's substantial (not from sheet)
                if keyboardHeight > 0 && !checkIfSheetIsPresented() {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        keyboardIsShowing = true
                    }
                }
            }
        }
        .onReceive(keyboardWillHide) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                keyboardIsShowing = false
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

    /// Open project details, syncing first if the project isn't in the local database
    private func openProjectWithSync(projectId: String) async {
        // Check if project exists locally
        if dataController.getProject(id: projectId) != nil {
            print("[PUSH_NAVIGATION] Project found locally, opening immediately")
            await MainActor.run {
                appState.viewProjectDetailsById(projectId)
            }
            return
        }

        // Project not found locally - sync first
        print("[PUSH_NAVIGATION] Project not found locally, triggering sync...")
        await syncAndOpenProject(projectId: projectId)
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

    /// Sync data and then open project details
    private func syncAndOpenProject(projectId: String) async {
        // Trigger sync
        if let syncManager = dataController.syncManager {
            print("[PUSH_NAVIGATION] Starting sync for project: \(projectId)")

            // Perform a full sync
            do {
                try await syncManager.syncAll()
            } catch {
                print("[PUSH_NAVIGATION] Sync failed: \(error)")
            }

            // Small delay for SwiftData to process
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Try to open the project again
            await MainActor.run {
                if dataController.getProject(id: projectId) != nil {
                    print("[PUSH_NAVIGATION] Project found after sync, opening")
                    appState.viewProjectDetailsById(projectId)
                } else {
                    print("[PUSH_NAVIGATION] Project still not found after sync")
                    // Could show an alert here if needed
                }
            }
        } else {
            print("[PUSH_NAVIGATION] No sync manager available")
        }
    }

    /// Sync data and then open task details
    private func syncAndOpenTask(taskId: String, projectId: String) async {
        // Trigger sync
        if let syncManager = dataController.syncManager {
            print("[PUSH_NAVIGATION] Starting sync for task: \(taskId)")

            // Perform a full sync
            do {
                try await syncManager.syncAll()
            } catch {
                print("[PUSH_NAVIGATION] Sync failed: \(error)")
            }

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
                    // Could show an alert here if needed
                }
            }
        } else {
            print("[PUSH_NAVIGATION] No sync manager available")
        }
    }
}
