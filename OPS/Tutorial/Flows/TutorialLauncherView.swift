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
    @Environment(\.modelContext) private var modelContext

    /// Callback when tutorial completes or is dismissed
    let onComplete: () -> Void

    /// Determines which flow to show based on user role
    let flowType: TutorialFlowType

    /// State manager for the tutorial
    @StateObject private var stateManager: TutorialStateManager

    /// Loading state for demo data seeding
    @State private var isSeeding = true

    /// Error state
    @State private var seedingError: String?

    /// Demo data manager
    @State private var demoDataManager: TutorialDemoDataManager?

    /// Completion state
    @State private var showingCompletion = false

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

            if isSeeding {
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
        .onAppear {
            setupAndSeedDemoData()
        }
        .onDisappear {
            // Cleanup if view disappears unexpectedly
            cleanupDemoDataIfNeeded()
        }
    }

    // MARK: - Views

    /// Loading view while seeding demo data
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.5)

            Text("SETTING UP YOUR TRAINING...")
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

            Text("SETUP FAILED")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text(error)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Skip Tutorial") {
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

        case .employee:
            TutorialEmployeeFlowWrapper(
                stateManager: stateManager,
                onComplete: handleFlowComplete
            )
            .environmentObject(dataController)
            .environmentObject(appState)
        }
    }

    // MARK: - Demo Data Management

    /// Seeds demo data and starts the tutorial
    private func setupAndSeedDemoData() {
        Task { @MainActor in
            do {
                print("[TUTORIAL_LAUNCHER] Starting demo data seeding...")

                // Create demo data manager
                let manager = TutorialDemoDataManager(context: modelContext)
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
            }

            // Cleanup demo data
            await cleanupDemoData()

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
