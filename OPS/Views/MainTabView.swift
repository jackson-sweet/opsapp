//
//  MainTabView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// MainTabView.swift
import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    
    // Observer for fetch active project notifications
    private let fetchProjectObserver = NotificationCenter.default
        .publisher(for: Notification.Name("FetchActiveProject"))
    
    var body: some View {
        ZStack {
            // TabView with all the main screens
            TabView {
                HomeView()
                    .tabItem {
                        Image(systemName: "house.fill")
                    }
                
                ScheduleView()
                    .tabItem {
                        Image(systemName: "calendar")
                    }
                
                SettingsView()
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                    }
            }
            .accentColor(OPSStyle.Colors.primaryAccent)
            .preferredColorScheme(.dark)
            .onAppear {
                let tabBarAppearance = UITabBarAppearance()
                tabBarAppearance.configureWithOpaqueBackground()
                tabBarAppearance.backgroundColor = UIColor(OPSStyle.Colors.cardBackgroundDark).withAlphaComponent(0.7)
                
                // Apply blur effect
                let blurEffect = UIBlurEffect(style: .systemThinMaterialDark)
                tabBarAppearance.backgroundEffect = blurEffect
                
                // Remove the separator line
                tabBarAppearance.shadowColor = .clear
                
                UITabBar.appearance().standardAppearance = tabBarAppearance
                if #available(iOS 15.0, *) {
                    UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
                }
            }
            
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
    }
}