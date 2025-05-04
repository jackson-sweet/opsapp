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
    
    var body: some View {
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
    }
}