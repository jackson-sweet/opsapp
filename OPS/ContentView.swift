//
//  ContentView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @EnvironmentObject private var dataController: DataController
    @StateObject private var appState = AppState()
    
    @StateObject private var locationManager = LocationManager()
    
    // Add a state to track initial loading
    @State private var isCheckingAuth = true
    @State private var showLocationPermissionView = false
    
    var body: some View {
        Group {
            if isCheckingAuth {
                // Show a simple loading view while checking authentication
                SplashLoadingView()
            } else if !dataController.isAuthenticated {
                // Show login view with onboarding
                // The LoginView will handle onboarding presentation
                if AppConfiguration.UX.useConsolidatedOnboardingFlow {
                    // Use the new consolidated flow
                    LoginView()
                        .environment(\.useConsolidatedOnboarding, true)
                } else {
                    // Use the original flow
                    LoginView()
                }
            } else {
                // Only show main app if authenticated
                MainTabView()
                    .environmentObject(appState)
                    .environmentObject(locationManager)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Request Locations Permission if necessary
            // Use the enhanced version that logs more details
            locationManager.requestPermissionIfNeeded(requestAlways: true)
            print("ContentView: onAppear - requesting location permission")
            
            // Check if user is already authenticated
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                // Check if the user has an account but is in the middle of onboarding
                let hasUserId = UserDefaults.standard.string(forKey: "user_id") != nil
                let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
                
                if hasUserId && !onboardingCompleted {
                    // Set authentication to true if they created an account
                    // They'll be directed to the login view but will immediately see the onboarding flow
                    // from the step they left off
                    print("ContentView: User has account but needs to complete onboarding")
                    dataController.isAuthenticated = false
                    
                    // Set a flag in UserDefaults to indicate we need to resume onboarding
                    UserDefaults.standard.set(true, forKey: "resume_onboarding")
                }
                
                // Finish the loading phase to show the appropriate screen
                isCheckingAuth = false
            }
        }
        // Watch for changes to the location denied state
        .onChange(of: locationManager.isLocationDenied) { _, isDenied in
            if isDenied && dataController.isAuthenticated {
                print("ContentView: Location denied, showing permission view")
                showLocationPermissionView = true
            }
        }
        // Add the location permission overlay
        .locationPermissionOverlay(
            isPresented: $showLocationPermissionView,
            locationManager: locationManager,
            onRequestPermission: {
                locationManager.requestPermissionIfNeeded(requestAlways: true)
            }
        )
    }
}

// LoadingView has been moved to UIComponents.swift

// We won't redefine OnboardingPresenter here since it's already defined elsewhere
// Let's focus on making sure imports work properly

#Preview {
    ContentView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
