//
//  TutorialLauncherView.swift
//  OPS
//
//  Entry point for the interactive tutorial system.
//  Seeds demo data, launches the appropriate flow based on user type,
//  and handles cleanup when the tutorial completes.
//

import SwiftUI
import SwiftData

/// Main entry point for the interactive tutorial
/// Handles demo data seeding, flow selection, and completion cleanup
struct TutorialLauncherView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.modelContext) private var modelContext

    /// Callback when tutorial completes or is dismissed
    let onComplete: () -> Void

    /// Determines which flow to show based on user role
    let flowType: TutorialFlowType

    /// State manager for the tutorial
    @StateObject private var stateManager: TutorialStateManager

    /// Cover screen state (shown before tutorial begins)
    @State private var showingCover = true

    /// Loading state for demo data seeding
    @State private var isSeeding = false

    /// Error state
    @State private var seedingError: String?

    /// Demo data manager
    @State private var demoDataManager: TutorialDemoDataManager?

    /// Completion state
    @State private var showingCompletion = false

    /// Finishing state (loading after user taps LET'S GO)
    @State private var isFinishing = false

    /// Console messages for finishing loading view
    @State private var finishingMessages: [String] = []

    /// Typewriter animation state
    @State private var displayedTitle = ""
    @State private var typewriterTimer: Timer?

    /// Title varies by flow type
    private var fullTitle: String {
        switch flowType {
        case .companyCreator:
            return "HERE'S HOW OPS WORKS"
        case .employee:
            return "YOUR DAILY WORKFLOW"
        }
    }

    /// Cover description varies by flow type
    private var coverDescription: String {
        switch flowType {
        case .companyCreator:
            return "You'll create a sample project and move it through your workflow—just like a real job. You'll learn to:"
        case .employee:
            return "See how to manage your assigned jobs from start to finish. You'll learn to:"
        }
    }

    /// Cover bullet points vary by flow type
    private var coverBulletPoints: [String] {
        switch flowType {
        case .companyCreator:
            return [
                "Create projects with tasks",
                "Assign work to your crew",
                "Track progress from start to finish",
                "View your schedule"
            ]
        case .employee:
            return [
                "View your assigned jobs",
                "Start and complete tasks",
                "Add notes and photos",
                "Check your schedule"
            ]
        }
    }

    /// Creates the tutorial launcher
    /// - Parameters:
    ///   - flowType: The type of tutorial flow (auto-detected from user role if nil)
    ///   - onComplete: Callback when tutorial finishes
    init(flowType: TutorialFlowType? = nil, onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        // Determine flow type from parameter or default to company creator
        let resolvedFlowType = flowType ?? .companyCreator
        self.flowType = resolvedFlowType

        // Initialize state manager with the resolved flow type
        _stateManager = StateObject(wrappedValue: TutorialStateManager(flowType: resolvedFlowType))
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            if showingCover {
                coverView
            } else if isSeeding {
                loadingView
            } else if let error = seedingError {
                errorView(error: error)
            } else if isFinishing {
                finishingLoadingView
            } else if showingCompletion {
                TutorialCompletionView(
                    manager: stateManager,
                    onDismiss: startFinishing
                )
            } else {
                tutorialFlowContent
            }
        }
        .onDisappear {
            // Cleanup if view disappears unexpectedly
            cleanupDemoDataIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialProjectFormComplete"))) { notification in
            // Register user-created project for cleanup
            if let projectId = notification.userInfo?["projectId"] as? String {
                demoDataManager?.registerUserCreatedProject(id: projectId)
            }
        }
    }

    // MARK: - Views

    /// Cover screen shown before tutorial begins
    private var coverView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // Title with typewriter animation
            VStack(alignment: .leading, spacing: 16) {
                Text(displayedTitle)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Description varies by flow type
                VStack(alignment: .leading, spacing: 12) {
                    Text(coverDescription)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(coverBulletPoints, id: \.self) { point in
                            tutorialBulletPoint(point)
                        }
                    }
                }
            }
            .padding(.bottom, 60)

            Spacer()

            // Begin button
            Button {
                typewriterTimer?.invalidate()
                withAnimation(.easeOut(duration: 0.3)) {
                    showingCover = false
                    isSeeding = true
                }
                setupAndSeedDemoData()
            } label: {
                Text("START TUTORIAL")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.white)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }

        }
        .padding(.horizontal, 32)
        .onAppear {
            startTypewriterAnimation()
        }
        .onDisappear {
            typewriterTimer?.invalidate()
        }
    }

    /// Helper view for bullet points
    private func tutorialBulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    /// Starts the typewriter animation for the title
    private func startTypewriterAnimation() {
        displayedTitle = ""
        var characterIndex = 0

        typewriterTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { timer in
            if characterIndex < fullTitle.count {
                let index = fullTitle.index(fullTitle.startIndex, offsetBy: characterIndex)
                displayedTitle += String(fullTitle[index])
                characterIndex += 1
            } else {
                timer.invalidate()
            }
        }
    }

    /// Loading view while seeding demo data
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.5)

            Text("Setting up sample data...")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    /// Console-style loading view shown after user taps LET'S GO
    private var finishingLoadingView: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo
                Image("LogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .opacity(0.8)

                // Loading bar
                TacticalLoadingBarAnimated(
                    barCount: 12,
                    barWidth: 3,
                    barHeight: 8,
                    spacing: 5,
                    emptyColor: OPSStyle.Colors.primaryAccent.opacity(0.2),
                    fillColor: OPSStyle.Colors.primaryAccent
                )

                // Console output
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(finishingMessages.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 8) {
                            Text(">")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(OPSStyle.Colors.primaryAccent.opacity(0.6))

                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .opacity(index == finishingMessages.count - 1 ? 1.0 : 0.5)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .frame(height: 100, alignment: .bottom)
                .padding(.horizontal, 40)

                Spacer()

                // Version info
                Text("[ VERSION \(AppConfiguration.AppInfo.version.uppercased()) ]")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.bottom, 48)
            }
        }
        .transition(.opacity)
    }

    /// Error view if seeding fails
    private func errorView(error: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.errorStatus)

            Text("COULDN'T LOAD TUTORIAL")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text(error)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                handleTutorialComplete()
            } label: {
                Text("SKIP FOR NOW")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.white)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
        }
    }

    /// The appropriate tutorial flow based on flow type
    @ViewBuilder
    private var tutorialFlowContent: some View {
        switch flowType {
        case .companyCreator:
            TutorialCreatorFlowWrapper(
                stateManager: stateManager,
                onComplete: handleFlowComplete
            )
            .environmentObject(dataController)
            .environmentObject(appState)
            .environmentObject(locationManager)

        case .employee:
            TutorialEmployeeFlowWrapper(
                stateManager: stateManager,
                onComplete: handleFlowComplete
            )
            .environmentObject(dataController)
            .environmentObject(appState)
            .environmentObject(locationManager)
        }
    }

    // MARK: - Demo Data Management

    /// Seeds demo data and starts the tutorial
    private func setupAndSeedDemoData() {
        Task { @MainActor in
            do {
                print("[TUTORIAL_LAUNCHER] Starting demo data seeding...")

                // Create demo data manager with current user's company ID
                guard let userCompanyId = dataController.currentUser?.companyId else {
                    print("[TUTORIAL_LAUNCHER] Error: No current user or company ID")
                    seedingError = "Unable to determine company. Please log in again."
                    isSeeding = false
                    return
                }
                let manager = TutorialDemoDataManager(context: modelContext, companyId: userCompanyId)
                demoDataManager = manager

                // Check if demo data already exists
                if manager.hasDemoData() {
                    print("[TUTORIAL_LAUNCHER] Demo data already exists, cleaning up first...")
                    try await manager.cleanupAllDemoData()
                }

                // Seed fresh demo data
                try await manager.seedAllDemoData()

                // For employee flow, assign current user to demo tasks
                if flowType == .employee, let userId = dataController.currentUser?.id {
                    try await manager.assignCurrentUserToTasks(userId: userId)
                }

                // Log demo data counts for debugging
                let counts = manager.getDemoDataCounts()
                print("[TUTORIAL_LAUNCHER] Demo data seeded - Projects: \(counts.projects), Tasks: \(counts.tasks), Events: \(counts.events)")

                // Seeding complete, start the tutorial
                isSeeding = false
                stateManager.start()

            } catch {
                print("[TUTORIAL_LAUNCHER] Error seeding demo data: \(error)")
                seedingError = error.localizedDescription
                isSeeding = false
            }
        }
    }

    /// Cleans up demo data when tutorial completes
    private func cleanupDemoData() async {
        guard let manager = demoDataManager else { return }

        do {
            print("[TUTORIAL_LAUNCHER] Cleaning up demo data...")
            try await manager.cleanupAllDemoData()
            print("[TUTORIAL_LAUNCHER] Demo data cleanup complete")
        } catch {
            print("[TUTORIAL_LAUNCHER] Error cleaning up demo data: \(error)")
            // Non-fatal - continue with completion
        }
    }

    /// Cleanup helper for unexpected dismissal
    private func cleanupDemoDataIfNeeded() {
        guard let manager = demoDataManager, manager.hasDemoData() else { return }

        Task { @MainActor in
            await cleanupDemoData()
        }
    }

    // MARK: - Completion Handling

    /// Called when a flow wrapper signals completion
    private func handleFlowComplete() {
        // Show completion view
        showingCompletion = true
    }

    /// Called when user taps LET'S GO on completion view
    /// Shows loading screen for minimum 5 seconds while cleanup happens in background
    private func startFinishing() {
        // Immediately show loading screen
        withAnimation(.easeOut(duration: 0.3)) {
            showingCompletion = false
            isFinishing = true
            finishingMessages = []
        }

        // Start showing console messages with delays
        let messages = [
            "CLEANING UP DEMO DATA...",
            "SYNCING USER DATA...",
            "LOADING YOUR PROJECTS...",
            "PREPARING WORKSPACE...",
            "ALMOST READY..."
        ]

        for (index, message) in messages.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.8) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    finishingMessages.append(message)
                    if finishingMessages.count > 5 {
                        finishingMessages.removeFirst()
                    }
                }
            }
        }

        // Start the actual cleanup in background
        Task { @MainActor in
            // Record start time to ensure minimum 5 second display
            let startTime = Date()

            // Do the actual cleanup and sync
            await performTutorialCleanup()

            // Calculate remaining time to reach 5 seconds minimum
            let elapsed = Date().timeIntervalSince(startTime)
            let remainingTime = max(0, 5.0 - elapsed)

            // Wait for remaining time if needed
            if remainingTime > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
            }

            // Now call the actual completion
            onComplete()
        }
    }

    /// Performs the actual tutorial cleanup (extracted from handleTutorialComplete)
    private func performTutorialCleanup() async {
        // Mark tutorial as completed for the user
        guard let user = dataController.currentUser else {
            print("[TUTORIAL_LAUNCHER] ❌ ERROR: No current user found - cannot mark tutorial complete!")
            return
        }

        print("[TUTORIAL_LAUNCHER] 📝 Marking tutorial complete for user: \(user.id)")
        user.hasCompletedAppTutorial = true
        user.needsSync = true

        do {
            try modelContext.save()
            print("[TUTORIAL_LAUNCHER] ✅ Tutorial completion saved to local user model")
        } catch {
            print("[TUTORIAL_LAUNCHER] ❌ Error saving tutorial completion locally: \(error)")
        }

        // Sync user to Bubble so backend knows tutorial is complete
        let fieldName = BubbleFields.User.hasCompletedAppTutorial
        print("[TUTORIAL_LAUNCHER] 🔄 Syncing to Bubble - field: '\(fieldName)', value: true, userId: \(user.id)")

        do {
            try await dataController.apiService.updateUser(userId: user.id, fields: [
                fieldName: true
            ])
            user.needsSync = false
            try modelContext.save()
            print("[TUTORIAL_LAUNCHER] ✅ Tutorial completion synced to Bubble successfully!")
        } catch {
            print("[TUTORIAL_LAUNCHER] ❌ FAILED to sync tutorial completion to Bubble!")
            print("[TUTORIAL_LAUNCHER] ❌ Error details: \(error)")
            print("[TUTORIAL_LAUNCHER] ❌ Error localized: \(error.localizedDescription)")
            // Keep needsSync = true so it syncs on next opportunity
        }

        // Cleanup demo data first
        await cleanupDemoData()

        // Perform full sync to get fresh data from backend
        // This ensures company subscription is up to date and prevents lockout
        print("[TUTORIAL_LAUNCHER] Starting full sync after tutorial completion...")
        await dataController.refreshProjectsFromBackend()
        print("[TUTORIAL_LAUNCHER] Full sync completed")

        // Also refresh company data to get latest subscription info
        if let user = dataController.currentUser, let companyId = user.companyId {
            do {
                try await dataController.forceRefreshCompany(id: companyId)
                print("[TUTORIAL_LAUNCHER] Company subscription data refreshed")
            } catch {
                print("[TUTORIAL_LAUNCHER] Warning: Failed to refresh company data: \(error)")
            }
        }
    }

    /// Called when user taps continue on completion view (legacy - now uses startFinishing)
    private func handleTutorialComplete() {
        Task { @MainActor in
            // Mark tutorial as completed for the user
            guard let user = dataController.currentUser else {
                print("[TUTORIAL_LAUNCHER] ❌ ERROR (legacy): No current user found!")
                return
            }

            print("[TUTORIAL_LAUNCHER] 📝 (legacy) Marking tutorial complete for user: \(user.id)")
            user.hasCompletedAppTutorial = true
            user.needsSync = true

            do {
                try modelContext.save()
                print("[TUTORIAL_LAUNCHER] ✅ (legacy) Tutorial completion saved locally")
            } catch {
                print("[TUTORIAL_LAUNCHER] ❌ (legacy) Error saving: \(error)")
            }

            // Sync user to Bubble so backend knows tutorial is complete
            let fieldName = BubbleFields.User.hasCompletedAppTutorial
            print("[TUTORIAL_LAUNCHER] 🔄 (legacy) Syncing to Bubble - field: '\(fieldName)', userId: \(user.id)")

            do {
                try await dataController.apiService.updateUser(userId: user.id, fields: [
                    fieldName: true
                ])
                user.needsSync = false
                try modelContext.save()
                print("[TUTORIAL_LAUNCHER] ✅ (legacy) Tutorial completion synced to Bubble!")
            } catch {
                print("[TUTORIAL_LAUNCHER] ❌ (legacy) FAILED to sync to Bubble: \(error)")
            }

            // Cleanup demo data first
            await cleanupDemoData()

            // Perform full sync to get fresh data from backend
            // This ensures company subscription is up to date and prevents lockout
            print("[TUTORIAL_LAUNCHER] Starting full sync after tutorial completion...")
            await dataController.refreshProjectsFromBackend()
            print("[TUTORIAL_LAUNCHER] Full sync completed")

            // Also refresh company data to get latest subscription info
            if let user = dataController.currentUser, let companyId = user.companyId {
                do {
                    try await dataController.forceRefreshCompany(id: companyId)
                    print("[TUTORIAL_LAUNCHER] Company subscription data refreshed")
                } catch {
                    print("[TUTORIAL_LAUNCHER] Warning: Failed to refresh company data: \(error)")
                }
            }

            // Call completion handler
            onComplete()
        }
    }
}

// MARK: - Flow Type Detection

extension TutorialLauncherView {
    /// Determines the appropriate flow type based on user role
    /// - Parameter user: The current user
    /// - Returns: The appropriate tutorial flow type
    static func detectFlowType(for user: User?) -> TutorialFlowType {
        guard let user = user else {
            return .companyCreator
        }

        switch user.role {
        case .admin, .officeCrew:
            return .companyCreator
        case .fieldCrew:
            return .employee
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TutorialLauncherView_Previews: PreviewProvider {
    static var previews: some View {
        TutorialLauncherView(
            flowType: .companyCreator,
            onComplete: {}
        )
    }
}
#endif
