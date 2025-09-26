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
    @State private var keyboardIsShowing = false
    @State private var sheetIsPresented = false
    @StateObject private var imageSyncProgressManager = ImageSyncProgressManager()
    @ObservedObject private var inProgressManager = InProgressManager.shared
    
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
    
    private let tabs = [
        TabItem(iconName: "house.fill"),
        TabItem(iconName: "calendar"),
        TabItem(iconName: "gearshape.fill")
    ]
    
    var body: some View {
        ZStack {
            // Main content structure
            if selectedTab == 0 {
                // Home tab - header overlays content
                ZStack {
                    // Main content views - full screen
                    HomeView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea(.all, edges: .bottom)
                       
                    
                    // Persistent navigation header overlay
                    VStack {
                        PersistentNavigationHeader(selectedTab: selectedTab)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.3), value: inProgressManager.isRouting)
                            .zIndex(100) // Keep on top
                        Spacer()
                    }
                }
            } else {
                // Other tabs - header overlays content
                ZStack {
                    // Main content views - full screen
                    Group {
                        switch selectedTab {
                        case 1:
                            ScheduleView()
                        case 2:
                            SettingsView()
                        default:
                            HomeView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all, edges: .bottom)
                    
                    // Persistent navigation header overlay
                    VStack {
                        PersistentNavigationHeader(selectedTab: selectedTab)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: inProgressManager.isRouting)
                            .zIndex(100) // Keep on top
                        Spacer()
                    }
                }
            }
            
            // Image sync progress bar at top
            VStack {
                ImageSyncProgressView(syncManager: imageSyncProgressManager)
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
            .opacity(keyboardIsShowing ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: keyboardIsShowing)
            
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
