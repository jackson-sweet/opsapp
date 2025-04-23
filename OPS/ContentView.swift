//
//  ContentView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
// ContentView.swift (updating existing file)
import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var dataController: DataController
    @StateObject private var appState = AppState()
    @State private var showingOnboarding = false
    
    var body: some View {
        Group {
            if !dataController.isAuthenticated {
                LoginView()
            } else if showingOnboarding {
                Text("Onboarding placeholder")
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .onAppear {
                        // For now, skip onboarding
                        self.showingOnboarding = false
                    }
            } else {
                MainTabView()
                    .environmentObject(appState)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Check if this is the first launch
            let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
            showingOnboarding = firstLaunch
            
            if firstLaunch {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            }
        }
    }
}
