//
//  ContentView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var dataController: DataController
    @StateObject private var appState = AppState()
    
    let locationManager = LocationManager()
    
    // Add a state to track initial loading
    @State private var isCheckingAuth = true
    
    var body: some View {
        Group {
            if isCheckingAuth {
                // Show a simple loading view while checking authentication
                LoadingView()
            } else if !dataController.isAuthenticated {
                // Show login view if not authenticated
                LoginView()
            } else {
                // Only show main app if authenticated
                MainTabView()
                    .environmentObject(appState)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            
            //Request Locations Permission if necessary
            locationManager.requestPermissionIfNeeded()
            // Check if user is already authenticated
            // This calls the existing authentication check processes
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                // Finish the loading phase to show the appropriate screen
                isCheckingAuth = false
                
                // Note: DataController.isAuthenticated should already be set correctly
                // by the checkExistingAuth method called during initialization
            }
        }
    }
}

/// Simple loading view shown while checking authentication status
struct LoadingView: View {
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                // Logo
                Image(systemName: "building.2.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                
                Text("OPS")
                    .font(OPSStyle.Typography.largeTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.bottom, 40)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    .scaleEffect(1.2)
                
                Spacer()
                
                // Version info
                Text("v1.0.0")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.bottom, OPSStyle.Layout.spacing3)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
