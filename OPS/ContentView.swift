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
    
    
    init() {
        // This will run before body is evaluated
        print("ContentView: Initializing")
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
                if AppConfiguration.UX.useConsolidatedOnboardingFlow {
                    // Use the new consolidated flow
                    LoginView()
                        .environment(\.useConsolidatedOnboarding, true)
                } else {
                    // Use the original flow
                    LoginView()
                }
            } else {
                // Check if PIN authentication is required
                // Access the PIN manager directly as @ObservedObject to ensure proper state updates
                let _ = print("ContentView: Creating PINGatedView")
                PINGatedView(dataController: dataController, appState: appState, locationManager: locationManager)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Request Locations Permission if necessary
            // Use the enhanced version that logs more details
            locationManager.requestPermissionIfNeeded(requestAlways: true)
            print("ContentView: onAppear - requesting location permission")
            
            // Allow more time for auth checking to complete
            let isAuthAlreadySet = dataController.isAuthenticated
            print("ContentView: Initial authentication state: \(isAuthAlreadySet)")
            
            let isAuthenticatedInDefaults = UserDefaults.standard.bool(forKey: "is_authenticated")
            let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
            
            print("ContentView: UserDefaults auth state - is_authenticated=\(isAuthenticatedInDefaults), onboarding_completed=\(onboardingCompleted)")
            
            // Wait longer to ensure auth check completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                // Check for auth state again
                let finalAuthState = dataController.isAuthenticated
                print("ContentView: Final authentication state check: \(finalAuthState)")
                
                // Check if the user has an account but is in the middle of onboarding
                let hasUserId = UserDefaults.standard.string(forKey: "user_id") != nil
                let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
                
                if hasUserId && !onboardingCompleted {
                    // Set authentication to false if they created an account but need to complete onboarding
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

// Separate view to properly observe PIN manager state
struct PINGatedView: View {
    @ObservedObject var pinManager: SimplePINManager
    let dataController: DataController
    let appState: AppState
    let locationManager: LocationManager
    
    init(dataController: DataController, appState: AppState, locationManager: LocationManager) {
        self.dataController = dataController
        self.pinManager = dataController.simplePINManager
        self.appState = appState
        self.locationManager = locationManager
        print("PINGatedView: Initialized")
        print("PINGatedView: requiresPIN=\(dataController.simplePINManager.requiresPIN)")
        print("PINGatedView: isAuthenticated=\(dataController.simplePINManager.isAuthenticated)")
    }
    
    var body: some View {
        let _ = print("PINGatedView: body called - requiresPIN=\(pinManager.requiresPIN), isAuthenticated=\(pinManager.isAuthenticated)")
        
        ZStack {
            // Main app content (always rendered but hidden when PIN required)
            MainTabView()
                .environmentObject(appState)
                .environmentObject(locationManager)
                .onAppear {
                    // Set the appState reference in DataController for cross-component access
                    dataController.appState = appState
                    print("ContentView: Set appState reference in DataController")
                }
                .opacity(pinManager.requiresPIN && !pinManager.isAuthenticated ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: pinManager.isAuthenticated)
            
            // PIN overlay
            if pinManager.requiresPIN && !pinManager.isAuthenticated {
                SimplePINEntryView(pinManager: pinManager)
                    .transition(.opacity)
                    .zIndex(1)
                    .onReceive(pinManager.$isAuthenticated) { newValue in
                        print("PINGatedView: Received isAuthenticated change: \(newValue)")
                    }
                    .onReceive(pinManager.objectWillChange) { _ in
                        print("PINGatedView: PIN manager objectWillChange fired")
                    }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
