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
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var appState = AppState()
    @StateObject private var locationManager = LocationManager()
    
    
    init() {
        // This will run before body is evaluated
    }
    
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
                LoginView()
            } else {
                // Check if PIN authentication is required
                // Access the PIN manager directly as @ObservedObject to ensure proper state updates
                PINGatedView(dataController: dataController, appState: appState, locationManager: locationManager)
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LogoutInitiated"))) { _ in
            // Reset app state when logout is initiated
            appState.resetForLogout()
        }
        .onAppear {
            // DO NOT request location permissions here - wait for proper context in onboarding or when needed
            // Removed: locationManager.requestPermissionIfNeeded(requestAlways: true)
            
            // Allow more time for auth checking to complete
            let isAuthAlreadySet = dataController.isAuthenticated
            
            let isAuthenticatedInDefaults = UserDefaults.standard.bool(forKey: "is_authenticated")
            let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
            
            
            // Wait longer to ensure auth check completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                // Check for auth state again
                let finalAuthState = dataController.isAuthenticated
                
                // Check if the user has an account but is in the middle of onboarding
                let hasUserId = UserDefaults.standard.string(forKey: "user_id") != nil
                let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
                
                if hasUserId && !onboardingCompleted {
                    // Set authentication to false if they created an account but need to complete onboarding
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
                showLocationPermissionView = true
            }
        }
        // Add the location permission overlay
        .locationPermissionOverlay(
            isPresented: $showLocationPermissionView,
            locationManager: locationManager,
            onRequestPermission: {
                locationManager.requestPermissionIfNeeded(requestAlways: true) { isAllowed in
                    if !isAllowed {
                        // Permission is already denied, the overlay should handle showing settings prompt
                    }
                }
            }
        )
    }
}

// LoadingView has been moved to UIComponents.swift

// We won't redefine OnboardingPresenter here since it's already defined elsewhere
// Let's focus on making sure imports work properly

// Separate view to properly observe PIN manager state
struct PINGatedView: View {
    @ObservedObject var pinManager: SimplePINManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    let dataController: DataController
    let appState: AppState
    let locationManager: LocationManager
    
    init(dataController: DataController, appState: AppState, locationManager: LocationManager) {
        self.dataController = dataController
        self.pinManager = dataController.simplePINManager
        self.appState = appState
        self.locationManager = locationManager
    }
    
    var body: some View {
        
        // Check subscription lockout first
        if subscriptionManager.shouldShowLockout {
            SubscriptionLockoutView()
                .environmentObject(subscriptionManager)
                .environmentObject(dataController)
        } else {
            ZStack {
                // Main app content with grace period banner
                MainTabView()
                    .environmentObject(appState)
                    .environmentObject(locationManager)
                    .gracePeriodBanner() // Add grace period banner overlay
                    .onAppear {
                        // Set the appState reference in DataController for cross-component access
                        dataController.appState = appState
                    }
                    .opacity(pinManager.requiresPIN && !pinManager.isAuthenticated ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: pinManager.isAuthenticated)

                // PIN overlay
                if pinManager.requiresPIN && !pinManager.isAuthenticated {
                    SimplePINEntryView(pinManager: pinManager)
                        .environmentObject(dataController)
                        .transition(.opacity)
                        .zIndex(1)
                        .onReceive(pinManager.$isAuthenticated) { newValue in
                        }
                        .onReceive(pinManager.objectWillChange) { _ in
                        }
                }

                // Sync restored alert overlay
                SyncRestoredAlert(isPresented: Binding(
                    get: { dataController.showSyncRestoredAlert },
                    set: { dataController.showSyncRestoredAlert = $0 }
                ))
                .environmentObject(dataController)
                .zIndex(2)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
