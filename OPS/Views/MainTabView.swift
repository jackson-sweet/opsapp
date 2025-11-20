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
    
    // Keyboard observers
    private let keyboardWillShow = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillShowNotification)
    
    private let keyboardWillHide = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillHideNotification)
    
    // Dynamic tabs based on user role
    private var tabs: [TabItem] {
        var baseTabs: [TabItem] = [
            TabItem(iconName: "house.fill")
        ]

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
                // All users now have Job Board access
                switch selectedTab {
                case 0:
                    HomeView()
                case 1:
                    JobBoardView()
                case 2:
                    ScheduleView()
                case 3:
                    SettingsView()
                default:
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
            if !isSettingsTab && !dataController.isPerformingInitialSync && !appState.isLoadingProjects {
                FloatingActionMenu()
                    .environmentObject(dataController)
            }

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

        // Track tab changes for slide transitions
        .onChange(of: selectedTab) { oldValue, newValue in
            previousTab = oldValue
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
}
