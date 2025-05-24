//
//  MainTabView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// MainTabView.swift
import SwiftUI
import Combine

struct MainTabView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    
    @State private var selectedTab = 0
    @State private var keyboardIsShowing = false
    
    // Observer for fetch active project notifications
    private let fetchProjectObserver = NotificationCenter.default
        .publisher(for: Notification.Name("FetchActiveProject"))
    
    // Observer for showing project details
    private let showProjectObserver = NotificationCenter.default
        .publisher(for: Notification.Name("ShowProjectDetailsRequest"))
    
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
            // Main content views - fill entire screen
            Group {
                switch selectedTab {
                case 0:
                    HomeView()
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
            
            // Custom tab bar overlaid at bottom
            VStack {
                Spacer()
                CustomTabBar(selectedTab: $selectedTab, tabs: tabs)
            }
            .preferredColorScheme(.dark)
            .opacity(keyboardIsShowing ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: keyboardIsShowing)
            
            // Project sheet container that overlays the whole app
            ProjectSheetContainer()
        }
        // Add notification handler for project fetching
        .onReceive(fetchProjectObserver) { notification in
            if let projectID = notification.userInfo?["projectID"] as? String {
                print("MainTabView: Received notification to fetch project: \(projectID)")
                if let project = dataController.getProject(id: projectID) {
                    // Update app state with the fetched project
                    DispatchQueue.main.async {
                        print("MainTabView: Found project \(project.id), calling setActiveProject")
                        appState.setActiveProject(project)
                        
                        // Debug to check project mode after setting
                        print("MainTabView: After setActiveProject - isInProjectMode: \(appState.isInProjectMode), activeProjectID: \(String(describing: appState.activeProjectID)), activeProject: \(String(describing: appState.activeProject?.id))")
                    }
                } else {
                    print("MainTabView: Could not find project with ID: \(projectID)")
                }
            }
        }
        
        // Add notification handler for showing project details
        .onReceive(showProjectObserver) { notification in
            if let projectID = notification.userInfo?["projectID"] as? String {
                print("MainTabView: Received notification to show project details: \(projectID)")
                
                // Make sure we're on the main thread
                DispatchQueue.main.async {
                    if let project = dataController.getProject(id: projectID) {
                        print("MainTabView: Found project to show: \(project.title)")
                        
                        // Set the active project before setting showProjectDetails
                        appState.isViewingDetailsOnly = true
                        appState.activeProjectID = project.id
                        appState.activeProject = project
                        
                        // The important part - we set the flag AFTER setting the project
                        print("MainTabView: Setting showProjectDetails=true")
                        appState.showProjectDetails = true
                    } else {
                        print("MainTabView: Could not find project with ID: \(projectID)")
                    }
                }
            }
        }
        
        // Handle keyboard appearance
        .onReceive(keyboardWillShow) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                keyboardIsShowing = true
            }
        }
        .onReceive(keyboardWillHide) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                keyboardIsShowing = false
            }
        }
    }
}