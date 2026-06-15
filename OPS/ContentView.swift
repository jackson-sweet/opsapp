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
    @EnvironmentObject private var variantManager: OnboardingVariantManager
    @StateObject private var appState = AppState()
    @StateObject private var locationManager = LocationManager()
    
    
    init() {
        // This will run before body is evaluated
    }
    
    // Add a state to track initial loading
    @State private var isCheckingAuth = true
    @State private var showLocationPermissionView = false
    @State private var showABTestOnboarding = false
    @State private var showExistingLogin = false
    @State private var onboardingManagerInstance: OnboardingManager?
    @State private var hasCompletedInitialAuthCheck = false

    // MARK: - Returning-Login Workspace Preload Gate (bug 95bf7c82)
    //
    // Returning-login users were dropped straight into the app while projects,
    // photos, and comments streamed in behind spinners. This gate covers that
    // gap: armed at the exact moment a returning login flips `isAuthenticated`,
    // it overlays the app until the initial load/sync settles, then crossfades
    // to reveal MainTabView. It is deliberately NOT shown for onboarding (which
    // owns AppSetupScreen) or on app foreground — only an explicit returning
    // login arms it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set the instant a returning login is initiated, BEFORE we know it will
    /// succeed. It scopes the gate to returning logins only: the gate arms when
    /// the post-login initial sync actually begins (`isPerformingInitialSync`
    /// flips true) AND this flag is set — so an onboarding sync or a foreground
    /// refresh never trips it. Cleared the moment the gate arms (consumed) or
    /// the login is abandoned.
    @State private var pendingReturningLogin = false
    /// `true` while the preload gate is covering the authenticated app.
    @State private var workspacePreloadActive = false
    /// When the gate was armed — drives the minimum-dwell floor below.
    @State private var workspacePreloadArmedAt: Date?
    /// Watchdog that force-dismisses the gate if it is somehow still up after a
    /// generous ceiling (belt-and-suspenders beyond the in-gate escape hatch).
    @State private var workspacePreloadWatchdog: Task<Void, Never>?
    /// Minimum time the gate stays up once armed. Closes a race: some returning
    /// paths (email/password) already finished `fullSync` before the gate
    /// appears, so `isWorkspaceReady` reads true for a beat *before* HomeView
    /// mounts and flips `isLoadingProjects`. Holding briefly lets the real load
    /// state assert itself, and gives the entrance choreography room to land.
    private let workspacePreloadMinimumDwell: TimeInterval = 0.8

    private var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: "onboarding_completed")
    }

    /// `true` when this device has ever had a signed-in user. Used alongside
    /// `hasCompletedOnboarding` to gate the offline screen — logout clears
    /// `onboarding_completed`, so a returning user who logs out looks like a
    /// fresh install to that flag alone. Checking SwiftData for any cached
    /// User row gives us a stable "has been signed in before" signal that
    /// survives logout's UserDefaults wipe (the SwiftData wipe runs after
    /// a 1s delay, and the Firebase session also survives).
    private var hasAnyCachedUser: Bool {
        // Prefer the Firebase session as the authoritative signal.
        if FirebaseAuthService.shared.firebaseUID != nil {
            return true
        }
        // Fall back to SwiftData cache during the logout-wipe race window.
        let descriptor = FetchDescriptor<User>()
        if let users = try? dataController.modelContext?.fetch(descriptor),
           !users.isEmpty {
            return true
        }
        return false
    }

    private var cachedAccountName: String? {
        guard let userId = UserDefaults.standard.string(forKey: "currentUserId"),
              !userId.isEmpty else { return nil }
        // Try to find cached user in SwiftData
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == userId })
        if let user = try? dataController.modelContext?.fetch(descriptor).first {
            return user.fullName
        }
        return nil
    }

    private func loginWithCachedAccount() {
        armWorkspacePreload()
        dataController.isAuthenticated = true
    }

    // MARK: - Workspace Preload Gate Control

    /// Arms the returning-login preload gate so it covers the initial sync.
    /// Two callers: cached-account login (offline gate) arms directly, and the
    /// `isPerformingInitialSync` watcher arms it the instant a returning login's
    /// sync begins — scoped by `pendingReturningLogin` so onboarding and ordinary
    /// foregrounds never trigger it.
    private func armWorkspacePreload() {
        guard !workspacePreloadActive else { return }
        pendingReturningLogin = false // consumed — the gate is now up
        workspacePreloadActive = true
        workspacePreloadArmedAt = Date()

        // Watchdog ceiling. The gate's own escape hatch hands the user an
        // "ENTER ANYWAY" button at 20s; this independent timer guarantees the
        // gate can never persist indefinitely even if no one taps it (e.g. the
        // phone is set down mid-sync). 30s is comfortably past a healthy sync.
        workspacePreloadWatchdog?.cancel()
        workspacePreloadWatchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            forceRevealWorkspace()
        }

        // Re-check once the minimum dwell elapses: if the load already settled
        // during the hold (and HomeView had its chance to assert loading),
        // reveal now rather than waiting for the next signal change.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(workspacePreloadMinimumDwell * 1_000_000_000))
            attemptRevealWorkspace()
        }
    }

    /// Reveals the app *if* the load has settled AND the minimum dwell has
    /// elapsed. Called from the sync-signal watchers and the post-dwell check.
    private func attemptRevealWorkspace() {
        // `isAuthenticated` is the load-bearing guard for arm-on-sync-start: the
        // initial sync runs INSIDE login() and the auth flip is deliberately
        // deferred to AFTER it (DataController.fetchUserFromAPI). Until that flip
        // the app isn't mounted yet — only the login page sits behind the gate —
        // and `isWorkspaceReady` reads true both before the sync starts and in
        // the ~0.8s window between sync-end and the flip. Revealing in either
        // window would flash the login page. Holding for `isAuthenticated`
        // collapses both races: it's true only once the app is genuinely ready.
        guard workspacePreloadActive, dataController.isAuthenticated, isWorkspaceReady else { return }
        if let armedAt = workspacePreloadArmedAt,
           Date().timeIntervalSince(armedAt) < workspacePreloadMinimumDwell {
            return // still within the dwell floor — the post-dwell check will retry
        }
        forceRevealWorkspace()
    }

    /// Tears the gate down WITHOUT revealing the app — for logins that end
    /// without entering: a wrong password, a cancelled social sign-in, or a
    /// route into onboarding. Also clears the pending-arm flag so a later,
    /// unrelated sync can't resurrect the gate. No success haptic (nothing was
    /// achieved); the underlying login/landing page simply returns.
    private func disarmWorkspacePreload() {
        pendingReturningLogin = false
        workspacePreloadWatchdog?.cancel()
        workspacePreloadWatchdog = nil
        workspacePreloadArmedAt = nil
        guard workspacePreloadActive else { return }
        if reduceMotion {
            workspacePreloadActive = false
        } else {
            withAnimation(OPSStyle.Animation.standard) {
                workspacePreloadActive = false
            }
        }
    }

    /// Unconditionally dismisses the preload gate and reveals the app. Fires a
    /// success haptic at the moment of reveal (the achievement beat: "workspace
    /// ready") and honors Reduce Motion by skipping the crossfade timing. Used
    /// by the escape hatch and the watchdog; gated callers go through
    /// `attemptRevealWorkspace()`.
    private func forceRevealWorkspace() {
        guard workspacePreloadActive else { return }

        workspacePreloadWatchdog?.cancel()
        workspacePreloadWatchdog = nil
        workspacePreloadArmedAt = nil

        // Haptic is not motion — it fires regardless of Reduce Motion.
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if reduceMotion {
            workspacePreloadActive = false
        } else {
            withAnimation(OPSStyle.Animation.standard) {
                workspacePreloadActive = false
            }
        }
    }

    /// True once the initial data load/sync has settled. Reuses the exact
    /// signals MainTabView already gates its own content reveal on:
    /// `DataController.isPerformingInitialSync` (post-login full sync) and
    /// `AppState.isLoadingProjects` (HomeView's first project load).
    private var isWorkspaceReady: Bool {
        !dataController.isPerformingInitialSync && !appState.isLoadingProjects
    }

    var body: some View {
        ZStack {
        Group {
            if isCheckingAuth {
                // Show the splash loading view first, BEFORE evaluating the
                // offline gate. On a fresh launch `isConnected` defaults to
                // false until the first connectivity check completes — if
                // the offline gate check runs first, the "NO CONNECTION"
                // screen flashes for a fraction of a second before the
                // initial auth+connectivity checks complete.
                SplashLoadingView()
            } else if !dataController.isConnected
                && !dataController.isAuthenticated
                && !hasCompletedOnboarding
                && !hasAnyCachedUser {
                // Offline gate ONLY for fresh installs with no cached account.
                // Returning users who logged out keep a Firebase session (and
                // usually a SwiftData cache during the 1s logout-wipe race)
                // — they should see the landing/login page so they can sign
                // back in, not get trapped in the offline lockout screen.
                OfflineGateView(
                    cachedUserName: cachedAccountName,
                    onCachedLogin: loginWithCachedAccount
                )
            } else if showABTestOnboarding && variantManager.isReady, let manager = onboardingManagerInstance {
                // A/B/C test onboarding for new users
                OnboardingABTestCoordinator(
                    variantManager: variantManager,
                    onboardingManager: manager,
                    onComplete: {
                        // OnboardingABTestCoordinator already waited for the
                        // server ACK before invoking this callback.
                        dataController.isAuthenticated = true
                        showABTestOnboarding = false
                        onboardingManagerInstance = nil
                    },
                    onShowLogin: {
                        withAnimation(OPSStyle.Animation.standard) {
                            showABTestOnboarding = false
                            showExistingLogin = true
                        }
                        onboardingManagerInstance = nil
                    }
                )
                .environmentObject(dataController)
                .environmentObject(appState)
                .environmentObject(locationManager)
            } else if showExistingLogin {
                // "I already have an account" from A/B test → direct login form
                LoginView(
                    onBack: {
                        // Go back to A/B test splash
                        showExistingLogin = false
                        onboardingManagerInstance = OnboardingManager(dataController: dataController)
                        showABTestOnboarding = true
                    },
                    onNeedsOnboarding: {
                        // User logged in but hasn't completed onboarding — route to A/B test
                        showExistingLogin = false
                        onboardingManagerInstance = OnboardingManager(dataController: dataController)
                        showABTestOnboarding = true
                    },
                    onLoginInitiated: {
                        // Returning login started — mark it pending so the gate
                        // arms the instant the initial sync begins, covering the
                        // sync rather than freezing the login button (bug 95bf7c82).
                        pendingReturningLogin = true
                    },
                    onLoginAbandoned: {
                        // Login ended without entering the app (wrong password,
                        // cancelled sign-in, or a route into onboarding) — tear
                        // the gate down and clear the pending flag.
                        disarmWorkspacePreload()
                    }
                )
                .environmentObject(appState)
                .environmentObject(locationManager)
            } else if !dataController.isAuthenticated {
                // General unauthenticated state → landing page
                LandingView(
                    onLoginInitiated: { pendingReturningLogin = true },
                    onLoginAbandoned: { disarmWorkspacePreload() }
                )
                    .environmentObject(appState)
                    .environmentObject(locationManager)
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
            
            
            // Guard against re-running after Google auth UI dismissal triggers onAppear again
            guard !hasCompletedInitialAuthCheck else { return }

            // Wait longer to ensure auth check completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                print("[CONTENT_VIEW] ========== AUTH CHECK ==========")
                print("[CONTENT_VIEW] isAuthenticated: \(dataController.isAuthenticated)")
                print("[CONTENT_VIEW] currentUser: \(dataController.currentUser?.id ?? "nil")")

                // Check if we need to show onboarding using new system
                let (shouldShowOnboarding, _) = OnboardingManager.shouldShowOnboarding(dataController: dataController)
                print("[CONTENT_VIEW] shouldShowOnboarding: \(shouldShowOnboarding)")

                if shouldShowOnboarding {
                    // Check if this is a brand new user (never completed onboarding)
                    // vs a returning user who needs to redo onboarding
                    let hasEverCompletedOnboarding = UserDefaults.standard.bool(forKey: "onboarding_completed")

                    if !hasEverCompletedOnboarding {
                        if variantManager.isReady {
                            // New user, variant ready → A/B/C test onboarding
                            print("[CONTENT_VIEW] -> Showing A/B/C test onboarding (variant: \(variantManager.variant.rawValue))")
                            onboardingManagerInstance = OnboardingManager(dataController: dataController)
                            showABTestOnboarding = true
                        } else {
                            // New user, variant still loading → wait for it
                            // The .onChange(of: variantManager.isReady) handler below will route them
                            print("[CONTENT_VIEW] -> Waiting for variant manager before showing onboarding")
                        }
                        dataController.isAuthenticated = false
                    } else {
                        // Returning user → existing LandingView with onboarding
                        print("[CONTENT_VIEW] -> Showing onboarding (LandingView)")
                        dataController.isAuthenticated = false
                    }
                }

                // Finish the loading phase to show the appropriate screen
                isCheckingAuth = false
                hasCompletedInitialAuthCheck = true
                print("[CONTENT_VIEW] ========== END AUTH CHECK ==========")
            }
        }
        // Watch for authentication changes
        .onChange(of: dataController.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && !isCheckingAuth {
                // Clear ALL onboarding routing flags so user proceeds to main app.
                // Fixes race condition where onAppear timer fires after Google auth UI
                // dismissal but before loginWithGoogle completes, incorrectly routing
                // to onboarding.
                showExistingLogin = false
                showABTestOnboarding = false
                onboardingManagerInstance = nil
            }
            // The returning-login gate holds for `isAuthenticated` (see
            // attemptRevealWorkspace) and the deferred auth flip lands at the END
            // of the initial sync. Re-anchor the dwell floor here so the gate
            // holds a final beat for MainTabView/HomeView to mount and assert its
            // first project load — revealing straight to a ready Home instead of
            // flashing a half-loaded one for the instant before onAppear runs.
            // The isLoadingProjects watcher reveals once that (now-local, fast)
            // load settles; this post-dwell re-check covers the nothing-to-load
            // case.
            if isAuthenticated, workspacePreloadActive {
                workspacePreloadArmedAt = Date()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(workspacePreloadMinimumDwell * 1_000_000_000))
                    attemptRevealWorkspace()
                }
            }
        }
        // Watch for changes to the location denied state
        .onChange(of: locationManager.isLocationDenied) { _, isDenied in
            if isDenied && dataController.isAuthenticated {
                showLocationPermissionView = true
            }
        }
        // Watch for variant manager becoming ready (fixes race condition for new users)
        .onChange(of: variantManager.isReady) { _, isReady in
            if isReady && !isCheckingAuth && !showABTestOnboarding && !dataController.isAuthenticated {
                let hasEverCompletedOnboarding = UserDefaults.standard.bool(forKey: "onboarding_completed")
                if !hasEverCompletedOnboarding {
                    print("[CONTENT_VIEW] Variant manager became ready — showing A/B/C onboarding (variant: \(variantManager.variant.rawValue))")
                    onboardingManagerInstance = OnboardingManager(dataController: dataController)
                    showABTestOnboarding = true
                }
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
        // MARK: - Returning-Login Workspace Preload Gate reveal watchers
        //
        // Dismiss the gate the moment the initial load/sync settles, by watching
        // the same two signals MainTabView gates its own content on. Reveal is
        // additionally floored by a minimum dwell (see `attemptRevealWorkspace`)
        // so the gate can't blink away during the brief window between the
        // auth-flip and HomeView asserting its project-load state.
        .onChange(of: dataController.isPerformingInitialSync) { _, isSyncing in
            // Arm the gate the instant the post-login initial sync begins — but
            // only when a returning login set it in motion (pendingReturningLogin),
            // never for onboarding or a foreground refresh. This is where the long
            // sync starts inside login()/loginWithApple/loginWithGoogle, so the
            // gate now covers the sync instead of the login button freezing behind
            // a spinner (bug 95bf7c82).
            if isSyncing, pendingReturningLogin, !workspacePreloadActive {
                armWorkspacePreload()
            }
            attemptRevealWorkspace()
        }
        .onChange(of: appState.isLoadingProjects) { _, _ in
            attemptRevealWorkspace()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LogoutInitiated"))) { _ in
            // Logout clears the gate so a stale preload can't bleed into the
            // landing page or the next account's session.
            pendingReturningLogin = false
            workspacePreloadWatchdog?.cancel()
            workspacePreloadWatchdog = nil
            workspacePreloadArmedAt = nil
            workspacePreloadActive = false
        }

            // Preload gate overlay — top of the ZStack so it covers PINGatedView
            // / MainTabView during a returning login. Only ever rendered when
            // explicitly armed; a transition keeps the reveal a clean crossfade.
            // The escape hatch reveals unconditionally (bypasses the dwell floor).
            if workspacePreloadActive {
                WorkspacePreloadGate(onEnterAnyway: forceRevealWorkspace)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// LoadingView has been moved to UIComponents.swift

// We won't redefine OnboardingPresenter here since it's already defined elsewhere
// Let's focus on making sure imports work properly

// Separate view to properly observe PIN manager state
struct PINGatedView: View {
    @ObservedObject var pinManager: SimplePINManager
    @ObservedObject var appState: AppState
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    let dataController: DataController
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
    @State private var createdClientId: String? = nil
    // Bug 321e65c8 — every new client also creates a pipeline lead. Track
    // whether the lead made it through so the toast can confirm the lead or
    // state that the pipeline link is queued.
    @State private var createdClientLeadCreated: Bool = false

    // Permission change overlay — sits above all navigation stacks, sheets, and modals
    @State private var showPermissionChangeOverlay = false

    // Bug reporting
    @State private var lastShakeTime: Date = .distantPast

    // Wizard system
    @StateObject private var wizardStateManager = WizardStateManager()
    @StateObject private var wizardTriggerService = WizardTriggerService()
    @State private var hasConfiguredWizards = false

    // Company setup prompt (2nd+ launch)
    @State private var showCompanySetupPrompt = false
    @State private var hasCheckedCompanySetup = false

    init(dataController: DataController, appState: AppState, locationManager: LocationManager) {
        self.dataController = dataController
        self.pinManager = dataController.simplePINManager
        self._appState = ObservedObject(wrappedValue: appState)
        self.locationManager = locationManager
    }

    /// Subtitle shown under "CLIENT CREATED" in the success banner.
    /// Bug 321e65c8 — every new client also creates a pipeline lead. This
    /// surfaces that fact to the user, or states that the link is queued
    /// when the direct opportunity insert cannot finish immediately.
    private var clientCreatedSubtitle: String? {
        let trimmedName = createdClientName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return createdClientLeadCreated ? "LEAD ADDED TO PIPELINE" : "PIPELINE LINK QUEUED"
        }
        if createdClientLeadCreated {
            return "\(trimmedName) · LEAD ADDED"
        }
        return "\(trimmedName) · PIPELINE LINK QUEUED"
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
                    .wizardActive(wizardStateManager.isActive)
                    .environment(\.wizardStateManager, wizardStateManager)
                    .environment(\.wizardTriggerService, wizardTriggerService)
                    .wizardBanner(stateManager: wizardStateManager)
                    .wizardOverlay(stateManager: wizardStateManager)
                    .gracePeriodBanner() // Add grace period banner overlay
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        // Reset wizard session tracking on return from background so wizards re-evaluate each session
                        wizardTriggerService.resetSessionTracking()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LogoutInitiated"))) { _ in
                        // Tear down wizard overlay window on logout to avoid dangling references
                        WizardOverlayController.shared.teardown()
                        hasConfiguredWizards = false
                    }
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

                        // Track project creation for Google Ads
                        Task {
                            let projectCount = await dataController.getProjectCount()
                            let userType = dataController.currentUser?.userType
                            AnalyticsManager.shared.trackCreateProject(projectCount: projectCount, userType: userType)
                            AnalyticsService.shared.track(
                                eventType: .action,
                                eventName: "project_created",
                                properties: ["project_count": projectCount]
                            )
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ClientCreatedSuccess"))) { notification in
                        // Show success message when client is created
                        if let clientName = notification.userInfo?["clientName"] as? String {
                            createdClientName = clientName
                        } else {
                            createdClientName = ""
                        }
                        createdClientId = notification.userInfo?["clientId"] as? String
                        // Bug 321e65c8 — read the auto-create-lead flag so the
                        // toast subtitle can confirm "lead added" or state
                        // that the pipeline link is queued.
                        createdClientLeadCreated = (notification.userInfo?["leadCreated"] as? Bool) ?? false
                        showClientCreatedMessage = true
                    }
                    .onAppear {
                        // Set the appState reference in DataController for cross-component access
                        dataController.appState = appState

                        // Configure wizard system (once per session)
                        if !hasConfiguredWizards,
                           let context = dataController.modelContext,
                           let user = dataController.currentUser {
                            let role = user.role
                            wizardStateManager.configure(
                                modelContext: context,
                                userId: user.id,
                                userRole: role,
                                syncEngine: dataController.syncEngine
                            )
                            wizardTriggerService.configure(
                                stateManager: wizardStateManager,
                                userRole: role,
                                permissionCheck: { PermissionStore.shared.can($0) },
                                isTutorialComplete: { [weak dataController] in
                                    dataController?.currentUser?.hasCompletedAppTutorial ?? false
                                }
                            )
                            // Clear per-session tracking so wizards can evaluate fresh
                            wizardTriggerService.resetSessionTracking()

                            // Install window-level overlay for instruction bar (persists across sheets/covers)
                            WizardOverlayController.shared.install(stateManager: wizardStateManager)

                            hasConfiguredWizards = true
                        }

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

                        // Check for company setup prompt (2nd+ launch, once per session)
                        if !hasCheckedCompanySetup {
                            hasCheckedCompanySetup = true
                            Task {
                                // Wait for data to be loaded and UI to settle
                                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                                await MainActor.run {
                                    let company = dataController.getCurrentUserCompany()
                                    if CompanySetupPromptView.shouldShowPrompt(company: company) {
                                        showCompanySetupPrompt = true
                                    }
                                }
                            }
                        }

                    }
                    .opacity(pinManager.requiresPIN && !pinManager.isAuthenticated ? 0 : 1)
                    .animation(OPSStyle.Animation.standard, value: pinManager.isAuthenticated)

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

                // Client created success notification.
                // Bug 321e65c8 — when the client also produces a pipeline
                // lead, the subtitle reads "<name> · LEAD ADDED" so the user
                // knows new clients are now trackable in the pipeline. If
                // the lead failed to create (offline / network error) we
                // tell them sync is pending instead.
                PushInMessage(
                    isPresented: $showClientCreatedMessage,
                    title: "CLIENT CREATED",
                    subtitle: clientCreatedSubtitle,
                    type: .success,
                    autoDismissAfter: 5.0,
                    actionLabel: "VIEW",
                    onAction: {
                        // Navigate to Job Board → Clients tab
                        NotificationCenter.default.post(
                            name: Notification.Name("NavigateToClients"),
                            object: nil,
                            userInfo: createdClientId != nil ? ["clientId": createdClientId!] : nil
                        )
                    }
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

                // Permission contraction overlay — blocks everything until user acknowledges
                if showPermissionChangeOverlay {
                    PermissionChangeOverlay(isPresented: $showPermissionChangeOverlay) {
                        handlePermissionRefresh()
                    }
                    .transition(.opacity)
                    .zIndex(9999)
                }
            }
                .animation(OPSStyle.Animation.standard, value: showUnassignedRolesOverlay)
                .animation(OPSStyle.Animation.standard, value: activeAppMessage?.id)
                .animation(OPSStyle.Animation.standard, value: showPermissionChangeOverlay)
                .onReceive(NotificationCenter.default.publisher(for: .permissionScopeContracted)) { _ in
                    withAnimation(OPSStyle.Animation.standard) {
                        showPermissionChangeOverlay = true
                    }
                }
            }
        }
        .task {
            // Check for app messages on view load (only once per session)
            if !hasCheckedForAppMessage {
                hasCheckedForAppMessage = true
                await checkForAppMessage()
            }
        }
        // Deep-link resume trigger: when the user unlocks their PIN, any
        // link that arrived while the PIN overlay was up is re-drained so
        // MainTabView's observer can route it now that the screen is safe
        // to reveal project data on.
        .onChange(of: pinManager.isAuthenticated) { _, authenticated in
            if authenticated {
                DeepLinkCoordinator.shared.drain(context: "pin_unlocked")
            }
        }
        // MentionAccessIndex freshness on user switch. The index is
        // rebuilt on every full sync (SyncEngine.swift:569), but a
        // same-session account swap would leave user A's mention grants
        // visible to user B until the next sync — a window where a deep
        // link could misroute. Rebuild immediately on user-id change.
        .onChange(of: dataController.currentUser?.id) { _, newUserId in
            guard let userId = newUserId,
                  let context = dataController.modelContext else { return }
            MentionAccessIndex.shared.rebuild(context: context, userId: userId)
        }
        // MARK: - Global Project Completion Checklist Sheet
        .sheet(isPresented: $appState.showingGlobalCompletionChecklist) {
            if let project = appState.projectPendingCompletion {
                TaskCompletionChecklistSheet(
                    project: project,
                    onComplete: {
                        // Mark project as completed after tasks are done
                        project.status = .completed
                        project.completedAt = Date()
                        project.needsSync = true

                        Task {
                            do {
                                try await dataController.updateProjectStatus(project: project, to: .completed)
                                print("[PROJECT_COMPLETION] ✅ Project '\(project.title)' marked as completed via global sheet")
                            } catch {
                                print("[PROJECT_COMPLETION] ❌ Failed to update project status: \(error)")
                            }
                        }

                        appState.clearCompletionRequest()
                    }
                )
                .environmentObject(dataController)
            }
        }
        // MARK: - Subscription Plan Selection (deep linked from trial expiry notifications)
        .sheet(isPresented: $appState.showingPlanSelection, onDismiss: {
            appState.pendingPromoCode = nil
        }) {
            PlanSelectionView(initialPromoCode: appState.pendingPromoCode)
                .environmentObject(dataController)
                .environmentObject(subscriptionManager)
        }
        // MARK: - Photo Storage (deep linked from photo_storage_limit rail notifications)
        .sheet(isPresented: $appState.showPhotoStorage) {
            PhotoStorageManagementView(allProjects: currentCompanyProjects())
                .environmentObject(dataController)
        }
        // MARK: - Bug Report Sheet (Shake-to-Report)
        .sheet(isPresented: $appState.showingBugReport, onDismiss: {
            appState.bugReportScreenshot = nil
        }) {
            BugReportSheet(screenshot: appState.bugReportScreenshot)
                .environmentObject(appState)
                .environmentObject(dataController)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            handleShake()
        }
        // MARK: - Company Setup Prompt Sheet (2nd+ launch)
        .sheet(isPresented: $showCompanySetupPrompt) {
            if let company = dataController.getCurrentUserCompany() {
                CompanySetupPromptView(company: company)
                    .environmentObject(dataController)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ConnectivityManager.connectivityChangedNotification)) { _ in
            // Drain offline bug report queue when connectivity returns
            if dataController.connectivity?.shouldAttemptSync ?? false {
                Task {
                    await BugReportSubmissionService.shared.drainOfflineQueue(dataController: dataController)
                }
            }
        }
    }

    // MARK: - Photo Storage Sheet Helper

    /// Non-deleted projects scoped to the current user's company. Consumed by
    /// the Photo Storage management sheet presented at this level (see
    /// `.sheet(isPresented: $appState.showPhotoStorage)` above).
    private func currentCompanyProjects() -> [Project] {
        guard let ctx = dataController.modelContext else { return [] }
        let companyId = dataController.currentUser?.companyId ?? ""
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.companyId == companyId }
        )
        let projects = (try? ctx.fetch(descriptor)) ?? []
        return projects.filter { $0.deletedAt == nil }
    }

    // MARK: - Permission Refresh

    /// Called when the user taps "REFRESH APP" on the permission contraction overlay.
    /// Purges non-permitted data, runs a full sync, dismisses the overlay, and navigates home.
    private func handlePermissionRefresh() {
        Task {
            await dataController.purgeNonPermittedData()
            await dataController.triggerFullSync()

            await MainActor.run {
                withAnimation(OPSStyle.Animation.standard) {
                    showPermissionChangeOverlay = false
                }
            }
        }
    }

    // MARK: - Shake Handler

    private func handleShake() {
        // Debounce: ignore shakes within 3 seconds
        let now = Date()
        guard now.timeIntervalSince(lastShakeTime) > 3.0 else { return }

        // Don't trigger during tutorial
        // TutorialStateManager is not available here as EnvironmentObject,
        // but we can check via the dataController or UserDefaults
        if appState.shouldRestartTutorial { return }

        // Don't trigger if already showing
        guard !appState.showingBugReport else { return }

        // Don't trigger if not authenticated
        guard dataController.isAuthenticated else { return }

        lastShakeTime = now

        // Capture screenshot BEFORE showing the sheet
        let screenshot = BugReportCaptureService.shared.captureScreenshot()
        appState.bugReportScreenshot = screenshot
        appState.showingBugReport = true

        DebugLogger.shared.log("Bug report triggered via shake", level: .info, category: "BugReport")
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
