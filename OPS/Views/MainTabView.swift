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
    }
}