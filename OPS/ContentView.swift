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

    // State for unassigned roles overlay
    @State private var showUnassignedRolesOverlay = false
    @State private var unassignedUsers: [UnassignedUser] = []
    @State private var hasCheckedForUnassignedRoles = false

    // State for app messages
    @State private var activeAppMessage: AppMessageDTO?
    @State private var hasCheckedForAppMessage = false

    // State for task creation success message
    @State private var showTaskCreatedMessage = false
    @State private var createdTaskTypeName: String = ""

    // State for project creation success message
    @State private var showProjectCreatedMessage = false
    @State private var createdProjectTitle: String = ""

    // State for client creation success message
    @State private var showClientCreatedMessage = false
    @State private var createdClientName: String = ""

    init(dataController: DataController, appState: AppState, locationManager: LocationManager) {
        self.dataController = dataController
        self.pinManager = dataController.simplePINManager
        self.appState = appState
        self.locationManager = locationManager
    }

    var body: some View {
        Group {
            // Check for blocking app message first (mandatory updates, etc.)
            if let message = activeAppMessage, !(message.dismissable ?? true) {
                // Non-dismissable message blocks the entire app
                AppMessageView(
                    message: message,
                    onDismiss: nil
                )
            }
            // Check subscription lockout next
            else if subscriptionManager.shouldShowLockout {
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
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TaskCreatedSuccess"))) { notification in
                        // Show success message when task is created
                        if let taskTypeName = notification.userInfo?["taskTypeName"] as? String {
                            createdTaskTypeName = taskTypeName
                        } else {
                            createdTaskTypeName = ""
                        }
                        showTaskCreatedMessage = true
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProjectCreatedSuccess"))) { notification in
                        // Show success message when project is created
                        if let projectTitle = notification.userInfo?["projectTitle"] as? String {
                            createdProjectTitle = projectTitle
                        } else {
                            createdProjectTitle = ""
                        }
                        showProjectCreatedMessage = true
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ClientCreatedSuccess"))) { notification in
                        // Show success message when client is created
                        if let clientName = notification.userInfo?["clientName"] as? String {
                            createdClientName = clientName
                        } else {
                            createdClientName = ""
                        }
                        showClientCreatedMessage = true
                    }
                    .onAppear {
                        // Set the appState reference in DataController for cross-component access
                        dataController.appState = appState

                        // Check for unassigned employee roles (only once per session)
                        if !hasCheckedForUnassignedRoles {
                            hasCheckedForUnassignedRoles = true
                            Task {
                                // Small delay to let the UI settle
                                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                                let users = await dataController.checkForUnassignedEmployeeRoles()
                                if !users.isEmpty {
                                    await MainActor.run {
                                        unassignedUsers = users
                                        showUnassignedRolesOverlay = true
                                    }
                                }
                            }
                        }

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

                // Sync restored notification
                PushInMessage(
                    isPresented: Binding(
                        get: { dataController.showSyncRestoredAlert },
                        set: { dataController.showSyncRestoredAlert = $0 }
                    ),
                    title: "SYNCING \(dataController.pendingSyncCount) ITEM\(dataController.pendingSyncCount == 1 ? "" : "S")...",
                    subtitle: "Connection restored",
                    type: .info,
                    autoDismissAfter: 4.0
                )
                .zIndex(2)

                // Task created success notification
                PushInMessage(
                    isPresented: $showTaskCreatedMessage,
                    title: "TASK CREATED",
                    subtitle: createdTaskTypeName.isEmpty ? nil : createdTaskTypeName,
                    type: .success,
                    autoDismissAfter: 3.0
                )
                .zIndex(2)

                // Project created success notification
                PushInMessage(
                    isPresented: $showProjectCreatedMessage,
                    title: "PROJECT CREATED",
                    subtitle: createdProjectTitle.isEmpty ? nil : createdProjectTitle,
                    type: .success,
                    autoDismissAfter: 3.0
                )
                .zIndex(2)

                // Client created success notification
                PushInMessage(
                    isPresented: $showClientCreatedMessage,
                    title: "CLIENT CREATED",
                    subtitle: createdClientName.isEmpty ? nil : createdClientName,
                    type: .success,
                    autoDismissAfter: 3.0
                )
                .zIndex(2)

                // Unassigned roles overlay
                if showUnassignedRolesOverlay {
                    UnassignedRolesOverlay(
                        isPresented: $showUnassignedRolesOverlay,
                        unassignedUsers: unassignedUsers
                    )
                    .environmentObject(dataController)
                    .zIndex(3)
                    .transition(.opacity)
                }

                // Dismissable app message overlay
                if let message = activeAppMessage, message.dismissable ?? true {
                    AppMessageView(
                        message: message,
                        onDismiss: {
                            activeAppMessage = nil
                        }
                    )
                    .zIndex(4)
                    .transition(.opacity)
                }
            }
                .animation(.easeInOut(duration: 0.3), value: showUnassignedRolesOverlay)
                .animation(.easeInOut(duration: 0.3), value: activeAppMessage?.id)
            }
        }
        .task {
            // Check for app messages on view load (only once per session)
            if !hasCheckedForAppMessage {
                hasCheckedForAppMessage = true
                await checkForAppMessage()
            }
        }
    }

    /// Check for active app messages and filter by user role
    private func checkForAppMessage() async {
        print("[APP_MESSAGE] 🔍 Checking for active app messages...")

        let service = AppMessageService()

        guard let message = await service.fetchActiveMessage() else {
            print("[APP_MESSAGE] ❌ No active message found")
            return
        }

        print("[APP_MESSAGE] ✅ Found message: \(message.title ?? "No title")")
        print("[APP_MESSAGE]   - ID: \(message.id)")
        print("[APP_MESSAGE]   - Type: \(message.messageType ?? "unknown")")
        print("[APP_MESSAGE]   - Dismissable: \(message.dismissable ?? true)")
        print("[APP_MESSAGE]   - Target users: \(message.targetUserTypes ?? [])")

        // Check if message should be shown to this user's role
        let userRole = dataController.currentUser?.role
        print("[APP_MESSAGE]   - Current user role: \(String(describing: userRole))")

        guard service.shouldShowMessage(message, forUserRole: userRole) else {
            print("[APP_MESSAGE] ⚠️ Message not targeted at user role: \(String(describing: userRole))")
            return
        }

        print("[APP_MESSAGE] 🎯 Showing message to user")
        await MainActor.run {
            activeAppMessage = message
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
