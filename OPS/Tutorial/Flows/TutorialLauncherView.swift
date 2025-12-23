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

    /// Typewriter animation state
    @State private var displayedTitle = ""
    @State private var typewriterTimer: Timer?
    private let fullTitle = "HERE'S HOW OPS WORKS"

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
            } else if showingCompletion {
                TutorialCompletionView(
                    manager: stateManager,
                    onDismiss: handleTutorialComplete
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

                // Description of what tutorial achieves
                VStack(alignment: .leading, spacing: 12) {
                    Text("You'll create a sample project and move it through your workflow—just like a real job. You'll learn to:")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    VStack(alignment: .leading, spacing: 8) {
                        tutorialBulletPoint("Create projects with tasks")
                        tutorialBulletPoint("Assign work to your crew")
                        tutorialBulletPoint("Track progress from start to finish")
                        tutorialBulletPoint("View your schedule")
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

            // Skip button
            Button {
                typewriterTimer?.invalidate()
                handleTutorialComplete()
            } label: {
                Text("SKIP FOR NOW")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .padding(.bottom, 20)
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

            Button("SKIP FOR NOW") {
                handleTutorialComplete()
            }
            .buttonStyle(OPSButtonStyle.Secondary())
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

    /// Called when user taps continue on completion view
    private func handleTutorialComplete() {
        Task { @MainActor in
            // Mark tutorial as completed for the user
            if let user = dataController.currentUser {
                user.hasCompletedAppTutorial = true
                user.needsSync = true

                do {
                    try modelContext.save()
                    print("[TUTORIAL_LAUNCHER] Tutorial completion saved to user model")
                } catch {
                    print("[TUTORIAL_LAUNCHER] Error saving tutorial completion: \(error)")
                }

                // Sync user to Bubble so backend knows tutorial is complete
                do {
                    try await dataController.apiService.updateUser(userId: user.id, fields: [
                        "has_completed_app_tutorial": true
                    ])
                    user.needsSync = false
                    try modelContext.save()
                    print("[TUTORIAL_LAUNCHER] Tutorial completion synced to Bubble")
                } catch {
                    print("[TUTORIAL_LAUNCHER] Warning: Failed to sync tutorial completion to Bubble: \(error)")
                    // Non-fatal - will sync later
                }
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
