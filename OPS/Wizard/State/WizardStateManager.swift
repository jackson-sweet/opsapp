//
//  WizardStateManager.swift
//  OPS
//
//  Central state machine for the wizard system.
//  Manages active wizard state, step progression, and analytics.
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class WizardStateManager: ObservableObject {

    // Required: nonisolated init so @StateObject can construct this
    // in a non-@MainActor View struct. All actual work happens on MainActor.
    nonisolated init() {}

    // MARK: - Published Properties

    /// Whether a wizard is currently active
    @Published var isActive: Bool = false

    /// The currently active wizard definition
    @Published var activeWizard: (any WizardDefinitionProtocol)?

    /// Current step index within the active wizard
    @Published var currentStepIndex: Int = 0

    /// Current instruction text
    @Published var currentInstruction: String = ""

    /// Current description text
    @Published var currentDescription: String?

    /// Whether the instruction bar is in "paused" state (user navigated away)
    @Published var isPaused: Bool = false

    /// Whether to show the wizard banner
    @Published var showBanner: Bool = false

    /// The wizard definition for the pending banner
    @Published var pendingBannerWizard: (any WizardDefinitionProtocol)?

    /// Whether to show the prompt overlay
    @Published var showPromptOverlay: Bool = false

    /// Whether the wizard system is enabled (master toggle)
    @Published var isEnabled: Bool = true

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var userId: String?
    private var userRole: UserRole?
    private var stepStartTime: Date?
    private var wizardStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    private var stepObserver: AnyCancellable?

    // MARK: - Analytics

    let analytics = WizardAnalyticsService.shared

    // MARK: - Computed Properties

    var currentStep: WizardStepDefinition? {
        guard let wizard = activeWizard,
              currentStepIndex < wizard.steps.count else { return nil }
        return wizard.steps[currentStepIndex]
    }

    var totalSteps: Int {
        activeWizard?.totalSteps ?? 0
    }

    var progressFraction: CGFloat {
        guard totalSteps > 0 else { return 0 }
        return CGFloat(currentStepIndex) / CGFloat(totalSteps)
    }

    // MARK: - Configuration

    func configure(modelContext: ModelContext, userId: String, userRole: UserRole) {
        self.modelContext = modelContext
        self.userId = userId
        self.userRole = userRole
        self.isEnabled = !UserDefaults.standard.bool(forKey: "wizard_system_disabled")
    }

    // MARK: - State Persistence

    /// Fetch or create WizardState for a given wizard ID
    func wizardState(for wizardId: String) -> WizardState? {
        guard let modelContext, let userId else { return nil }

        let descriptor = FetchDescriptor<WizardState>(
            predicate: #Predicate { $0.wizardId == wizardId && $0.userId == userId }
        )
        let results = (try? modelContext.fetch(descriptor)) ?? []
        if let existing = results.first {
            return existing
        }

        let newState = WizardState(wizardId: wizardId, userId: userId)
        modelContext.insert(newState)
        try? modelContext.save()
        return newState
    }

    /// Fetch all wizard states for the current user
    func allWizardStates() -> [WizardState] {
        guard let modelContext, let userId else { return [] }
        let descriptor = FetchDescriptor<WizardState>(
            predicate: #Predicate { $0.userId == userId }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Banner & Prompt Flow

    /// Show the banner for a wizard (called by WizardTriggerService)
    func showBanner(for wizard: any WizardDefinitionProtocol) {
        guard isEnabled, !isActive else { return }

        // Check if this wizard should be shown
        if let state = wizardState(for: wizard.wizardId), state.doNotShow {
            return
        }

        pendingBannerWizard = wizard
        showBanner = true

        analytics.recordEvent(
            event: "wizard_banner_shown",
            wizardId: wizard.wizardId,
            sessionId: wizardState(for: wizard.wizardId)?.currentSessionId ?? UUID().uuidString,
            userId: userId,
            userRole: userRole?.rawValue,
            triggerType: wizard.triggerType.rawValue
        )
    }

    /// User tapped the banner
    func bannerTapped() {
        guard let wizard = pendingBannerWizard else { return }

        showBanner = false

        analytics.recordEvent(
            event: "wizard_banner_tapped",
            wizardId: wizard.wizardId,
            sessionId: wizardState(for: wizard.wizardId)?.currentSessionId ?? UUID().uuidString,
            userId: userId,
            userRole: userRole?.rawValue
        )

        showPromptOverlay = true

        analytics.recordEvent(
            event: "wizard_prompt_shown",
            wizardId: wizard.wizardId,
            sessionId: wizardState(for: wizard.wizardId)?.currentSessionId ?? UUID().uuidString,
            userId: userId,
            userRole: userRole?.rawValue
        )
    }

    /// User dismissed the banner without tapping (implicit "Maybe Later")
    func bannerDismissed() {
        guard let wizard = pendingBannerWizard else { return }

        analytics.recordEvent(
            event: "wizard_dismissed",
            wizardId: wizard.wizardId,
            sessionId: wizardState(for: wizard.wizardId)?.currentSessionId ?? UUID().uuidString,
            userId: userId,
            userRole: userRole?.rawValue
        )

        showBanner = false
        pendingBannerWizard = nil
    }

    /// User chose "Start Guide" from the prompt overlay
    func startWizard(doNotShowAgain: Bool) {
        guard let wizard = pendingBannerWizard else { return }
        guard let state = wizardState(for: wizard.wizardId) else { return }

        if doNotShowAgain {
            state.doNotShow = true
        }

        let isRestart = state.status == .completed
        state.start()
        try? modelContext?.save()

        activeWizard = wizard
        currentStepIndex = state.currentStepIndex
        isActive = true
        isPaused = false
        showPromptOverlay = false
        pendingBannerWizard = nil
        stepStartTime = Date()
        wizardStartTime = Date()

        updateInstructionForCurrentStep()
        observeStepCompletion()

        analytics.recordEvent(
            event: "wizard_started",
            wizardId: wizard.wizardId,
            sessionId: state.currentSessionId,
            userId: userId,
            userRole: userRole?.rawValue,
            stepIndex: currentStepIndex,
            totalSteps: totalSteps,
            isRestart: isRestart
        )
    }

    /// Start a wizard directly (from Settings, bypassing banner/prompt)
    func startWizardDirectly(_ wizard: any WizardDefinitionProtocol, isRestart: Bool = false) {
        guard let state = wizardState(for: wizard.wizardId) else { return }

        if isRestart {
            state.restart()
        } else {
            state.start()
        }
        try? modelContext?.save()

        activeWizard = wizard
        currentStepIndex = state.currentStepIndex
        isActive = true
        isPaused = false
        showPromptOverlay = false
        pendingBannerWizard = nil
        stepStartTime = Date()
        wizardStartTime = Date()

        updateInstructionForCurrentStep()
        observeStepCompletion()

        analytics.recordEvent(
            event: isRestart ? "wizard_restarted" : "wizard_started",
            wizardId: wizard.wizardId,
            sessionId: state.currentSessionId,
            userId: userId,
            userRole: userRole?.rawValue,
            stepIndex: currentStepIndex,
            totalSteps: totalSteps,
            isRestart: isRestart
        )
    }

    /// User chose "Maybe Later" from the prompt overlay
    func dismissWizard(doNotShowAgain: Bool) {
        guard let wizard = pendingBannerWizard else { return }
        guard let state = wizardState(for: wizard.wizardId) else { return }

        if doNotShowAgain {
            state.doNotShow = true
            state.status = .dismissed
            state.needsSync = true
            try? modelContext?.save()

            analytics.recordEvent(
                event: "wizard_do_not_show",
                wizardId: wizard.wizardId,
                sessionId: state.currentSessionId,
                userId: userId,
                userRole: userRole?.rawValue
            )
        }

        analytics.recordEvent(
            event: "wizard_dismissed",
            wizardId: wizard.wizardId,
            sessionId: state.currentSessionId,
            userId: userId,
            userRole: userRole?.rawValue
        )

        showPromptOverlay = false
        pendingBannerWizard = nil
    }

    // MARK: - Step Progression

    /// Advance to the next step (called when user completes the current step)
    func completeCurrentStep() {
        guard let wizard = activeWizard,
              let state = wizardState(for: wizard.wizardId) else { return }

        // Record duration for this step
        let stepDuration = stepStartTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
        state.addDuration(stepDuration)

        analytics.recordEvent(
            event: "wizard_step_completed",
            wizardId: wizard.wizardId,
            sessionId: state.currentSessionId,
            userId: userId,
            userRole: userRole?.rawValue,
            stepIndex: currentStepIndex,
            stepId: currentStep?.id,
            totalSteps: totalSteps,
            durationMs: stepDuration
        )

        // Check if this was the last step
        if currentStepIndex >= totalSteps - 1 {
            completeWizard()
            return
        }

        state.advanceStep(totalSteps: totalSteps)
        currentStepIndex = state.currentStepIndex
        stepStartTime = Date()
        try? modelContext?.save()

        updateInstructionForCurrentStep()
        observeStepCompletion()

        TutorialHaptics.lightTap()
    }

    /// Skip the current step
    func skipCurrentStep() {
        guard let wizard = activeWizard,
              let state = wizardState(for: wizard.wizardId) else { return }

        analytics.recordEvent(
            event: "wizard_step_skipped",
            wizardId: wizard.wizardId,
            sessionId: state.currentSessionId,
            userId: userId,
            userRole: userRole?.rawValue,
            stepIndex: currentStepIndex,
            stepId: currentStep?.id,
            totalSteps: totalSteps
        )

        if currentStepIndex >= totalSteps - 1 {
            completeWizard()
            return
        }

        state.recordSkip(totalSteps: totalSteps)
        currentStepIndex = state.currentStepIndex
        stepStartTime = Date()
        try? modelContext?.save()

        updateInstructionForCurrentStep()
        observeStepCompletion()

        TutorialHaptics.lightTap()
    }

    /// Exit the wizard (saves progress)
    func exitWizard() {
        guard let wizard = activeWizard,
              let state = wizardState(for: wizard.wizardId) else { return }

        let stepDuration = stepStartTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
        state.addDuration(stepDuration)
        state.lastActiveAt = Date()
        try? modelContext?.save()

        analytics.recordEvent(
            event: "wizard_abandoned",
            wizardId: wizard.wizardId,
            sessionId: state.currentSessionId,
            userId: userId,
            userRole: userRole?.rawValue,
            stepIndex: currentStepIndex,
            totalSteps: totalSteps,
            durationMs: state.totalDurationMs,
            stepsSkipped: state.stepsSkipped
        )

        deactivate()
    }

    /// Complete the wizard
    private func completeWizard() {
        guard let wizard = activeWizard,
              let state = wizardState(for: wizard.wizardId) else { return }

        state.markCompleted()
        try? modelContext?.save()

        analytics.recordEvent(
            event: "wizard_completed",
            wizardId: wizard.wizardId,
            sessionId: state.currentSessionId,
            userId: userId,
            userRole: userRole?.rawValue,
            totalSteps: totalSteps,
            durationMs: state.totalDurationMs,
            stepsSkipped: state.stepsSkipped
        )

        TutorialHaptics.success()
        deactivate()
    }

    /// Deactivate the wizard UI without changing persistence
    private func deactivate() {
        stepObserver?.cancel()
        stepObserver = nil
        isActive = false
        activeWizard = nil
        currentInstruction = ""
        currentDescription = nil
        isPaused = false
    }

    // MARK: - Private Helpers

    private func updateInstructionForCurrentStep() {
        guard let step = currentStep else { return }
        currentInstruction = step.instruction
        currentDescription = step.description
    }

    /// Observe NotificationCenter for the current step's completion trigger
    private func observeStepCompletion() {
        stepObserver?.cancel()
        stepObserver = nil

        guard let step = currentStep,
              let notificationName = step.completionNotification else { return }

        stepObserver = NotificationCenter.default
            .publisher(for: Notification.Name(notificationName))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.completeCurrentStep()
            }
    }

    // MARK: - Developer Tools

    /// Reset all wizard states (for developer testing)
    func resetAllStates() {
        guard let modelContext, let userId else { return }
        let descriptor = FetchDescriptor<WizardState>(
            predicate: #Predicate { $0.userId == userId }
        )
        if let states = try? modelContext.fetch(descriptor) {
            for state in states {
                modelContext.delete(state)
            }
            try? modelContext.save()
        }
        deactivate()
    }

    /// Reset a single wizard's state
    func resetState(for wizardId: String) {
        if let state = wizardState(for: wizardId) {
            modelContext?.delete(state)
            try? modelContext?.save()
        }
        if activeWizard?.wizardId == wizardId {
            deactivate()
        }
    }

    /// Force trigger a wizard's banner (bypasses trigger conditions)
    func forceTrigger(wizard: any WizardDefinitionProtocol) {
        showBanner(for: wizard)
    }

    /// Jump to a specific step (debug only, no state validation)
    func jumpToStep(_ index: Int) {
        guard let wizard = activeWizard,
              let state = wizardState(for: wizard.wizardId),
              index >= 0, index < totalSteps else { return }

        state.currentStepIndex = index
        state.status = .inProgress
        state.lastActiveAt = Date()
        try? modelContext?.save()

        currentStepIndex = index
        stepStartTime = Date()
        updateInstructionForCurrentStep()
        observeStepCompletion()
    }

    /// Toggle master enable/disable
    func toggleEnabled() {
        isEnabled.toggle()
        UserDefaults.standard.set(!isEnabled, forKey: "wizard_system_disabled")
        if !isEnabled {
            deactivate()
            showBanner = false
            showPromptOverlay = false
        }
    }
}
