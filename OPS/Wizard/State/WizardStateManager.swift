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

    /// Stores the project ID opened during deep navigation (documentation wizard).
    /// Used by CONTINUE GUIDE to reopen the same project instead of fetching most recent.
    var deepNavProjectId: String?

    /// Whether to show the wizard banner
    @Published var showBanner: Bool = false

    /// The wizard definition for the pending banner
    @Published var pendingBannerWizard: (any WizardDefinitionProtocol)?

    /// Whether to show the prompt overlay
    @Published var showPromptOverlay: Bool = false

    /// Whether the wizard system is enabled (master toggle)
    @Published var isEnabled: Bool = true

    /// Briefly set on wizard completion to show a celebration toast
    @Published var completedWizardId: String?

    /// True during step transitions — collapses the instruction bar so the tab bar is visible
    @Published var isStepTransitioning: Bool = false

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var userId: String?
    private var userRole: UserRole?
    private var stepStartTime: Date?
    private var wizardStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    private var stepObserver: AnyCancellable?
    private var backgroundObserver: Any?

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
        self.isEnabled = UserDefaults.standard.object(forKey: "wizard_system_enabled") as? Bool ?? true

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveCurrentState()
            }
        }
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

    // MARK: - Global Cooldown Keys

    private static let cooldownUntilKey = "wizard_global_cooldown_until"
    private static let notNowCountKey = "wizard_global_not_now_count"

    /// Check if wizards are in a global cooldown period
    var isInGlobalCooldown: Bool {
        guard let cooldownUntil = UserDefaults.standard.object(forKey: Self.cooldownUntilKey) as? Date else {
            return false
        }
        return Date() < cooldownUntil
    }

    /// Set a global cooldown — no wizard banners for the given duration
    private func setGlobalCooldown(hours: Int) {
        let until = Calendar.current.date(byAdding: .hour, value: hours, to: Date()) ?? Date()
        UserDefaults.standard.set(until, forKey: Self.cooldownUntilKey)
        // Reset not-now count when a cooldown starts
        UserDefaults.standard.set(0, forKey: Self.notNowCountKey)
    }

    /// Increment the global "not now" counter and apply 24hr cooldown if threshold reached
    private func incrementNotNowCount() {
        let count = UserDefaults.standard.integer(forKey: Self.notNowCountKey) + 1
        UserDefaults.standard.set(count, forKey: Self.notNowCountKey)
        if count >= 2 {
            setGlobalCooldown(hours: 24)
        }
    }

    // MARK: - Banner Actions

    /// User tapped "Launch" on the banner — start the wizard directly
    func bannerLaunchTapped() {
        guard let wizard = pendingBannerWizard else { return }

        withAnimation(OPSStyle.Animation.spring) {
            showBanner = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.pendingBannerWizard = nil
        }

        analytics.recordEvent(
            event: "wizard_banner_launch",
            wizardId: wizard.wizardId,
            sessionId: wizardState(for: wizard.wizardId)?.currentSessionId ?? UUID().uuidString,
            userId: userId,
            userRole: userRole?.rawValue
        )

        // Reset not-now count on a successful launch
        UserDefaults.standard.set(0, forKey: Self.notNowCountKey)

        startWizardFromBanner(wizard)
    }

    /// User tapped "Not Now" on the banner — dismiss and track count
    func bannerNotNowTapped() {
        guard let wizard = pendingBannerWizard else { return }

        analytics.recordEvent(
            event: "wizard_banner_not_now",
            wizardId: wizard.wizardId,
            sessionId: wizardState(for: wizard.wizardId)?.currentSessionId ?? UUID().uuidString,
            userId: userId,
            userRole: userRole?.rawValue
        )

        withAnimation(OPSStyle.Animation.spring) {
            showBanner = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.pendingBannerWizard = nil
        }

        incrementNotNowCount()
    }

    /// User tapped "Never" on the banner — disable this wizard + 48hr global cooldown
    func bannerNeverTapped() {
        guard let wizard = pendingBannerWizard else { return }

        analytics.recordEvent(
            event: "wizard_banner_never",
            wizardId: wizard.wizardId,
            sessionId: wizardState(for: wizard.wizardId)?.currentSessionId ?? UUID().uuidString,
            userId: userId,
            userRole: userRole?.rawValue
        )

        // Mark this wizard as "do not show"
        if let state = wizardState(for: wizard.wizardId) {
            state.doNotShow = true
            state.status = .dismissed
            state.needsSync = true
            try? modelContext?.save()
        }

        withAnimation(OPSStyle.Animation.spring) {
            showBanner = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.pendingBannerWizard = nil
        }

        setGlobalCooldown(hours: 48)
    }

    /// Legacy: User dismissed the banner (backward compat — maps to Not Now)
    func bannerDismissed() {
        bannerNotNowTapped()
    }

    /// Legacy: User tapped the banner (backward compat — maps to Launch)
    func bannerTapped() {
        bannerLaunchTapped()
    }

    /// Start wizard from banner (takes wizard directly — avoids pendingBannerWizard race)
    func startWizardFromBanner(_ wizard: any WizardDefinitionProtocol) {
        guard let state = wizardState(for: wizard.wizardId) else { return }

        let isRestart = state.status == .completed
        state.start()
        try? modelContext?.save()

        activeWizard = wizard
        currentStepIndex = state.currentStepIndex
        isActive = true
        isPaused = false
        withAnimation(OPSStyle.Animation.standard) {
            showPromptOverlay = false
        }
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

        // Auto-navigate to the first step's target screen, then deep-navigate if needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.navigateToCurrentStep()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.requestDeepNavigation()
            }
        }
    }

    /// Legacy: User chose "Start Guide" from the prompt overlay
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
        withAnimation(OPSStyle.Animation.standard) {
            showPromptOverlay = false
        }
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

        // Auto-navigate to the first step's target screen, then deep-navigate if needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.navigateToCurrentStep()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.requestDeepNavigation()
            }
        }
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
        withAnimation(OPSStyle.Animation.standard) {
            showPromptOverlay = false
        }
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

        // Auto-navigate to the first step's target screen, then deep-navigate if needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.navigateToCurrentStep()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.requestDeepNavigation()
            }
        }
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

        withAnimation(OPSStyle.Animation.standard) {
            showPromptOverlay = false
        }
        // Clear reference after animation completes to avoid flicker
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.pendingBannerWizard = nil
        }
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

        // Notify targets to scroll into view
        if let stepId = currentStep?.id {
            NotificationCenter.default.post(
                name: Notification.Name("WizardStepChanged"),
                object: nil,
                userInfo: ["stepId": stepId]
            )

            // Allow views to re-evaluate prerequisites for the new step
            NotificationCenter.default.post(
                name: Notification.Name("WizardEvaluatePrerequisites"),
                object: nil,
                userInfo: ["stepId": stepId]
            )
        }

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

        // Notify targets of the new step (matches completeCurrentStep behavior)
        if let stepId = currentStep?.id {
            NotificationCenter.default.post(
                name: Notification.Name("WizardStepChanged"),
                object: nil,
                userInfo: ["stepId": stepId]
            )

            NotificationCenter.default.post(
                name: Notification.Name("WizardEvaluatePrerequisites"),
                object: nil,
                userInfo: ["stepId": stepId]
            )
        }

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

        // Show completion toast before deactivating
        let wizardId = wizard.wizardId
        completedWizardId = wizardId
        deactivate()

        // Auto-dismiss celebration after 4 seconds — the previous 2s was too
        // quick for a proper "nice, you finished it" moment and blew past
        // users who were in the middle of closing a sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            if self?.completedWizardId == wizardId {
                self?.completedWizardId = nil
            }
        }
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
        deepNavProjectId = nil
    }

    // MARK: - Navigation

    /// Navigate the user to the screen relevant to the current wizard step.
    /// Posts a notification that MainTabView and other containers listen for.
    /// Also posts section-level navigation for views that have sub-sections (e.g., Job Board).
    func navigateToCurrentStep() {
        guard let step = currentStep,
              let targetScreen = step.targetScreen else { return }

        // Map targetScreen identifiers to tab names
        let tabTarget = Self.tabTarget(for: targetScreen)

        NotificationCenter.default.post(
            name: Notification.Name("WizardNavigateToTarget"),
            object: nil,
            userInfo: [
                "targetScreen": targetScreen,
                "tabTarget": tabTarget ?? ""
            ]
        )

        // Post section-level navigation for Job Board wizard steps
        if let sectionTarget = Self.sectionTarget(for: targetScreen) {
            NotificationCenter.default.post(
                name: Notification.Name("WizardNavigateToSection"),
                object: nil,
                userInfo: ["section": sectionTarget]
            )
        }
    }

    /// Maps a wizard step's targetScreen to the Job Board section to navigate to.
    /// Returns the section raw value appropriate for the user's role, or nil if no section switch needed.
    static func sectionTarget(for targetScreen: String) -> String? {
        switch targetScreen {
        case "JobBoard":
            // Job Board steps need to land on a projects section.
            // Return role-appropriate section — caller reads the raw value.
            let hasManageSections = PermissionStore.shared.can("job_board.manage_sections")
            return hasManageSections ? "PROJECTS" : "MY PROJECTS"
        default:
            return nil
        }
    }

    /// Request deep navigation for wizards that need more than a tab switch.
    func requestDeepNavigation() {
        guard let wizard = activeWizard else { return }
        switch wizard.wizardId {
        case "documentation":
            NotificationCenter.default.post(
                name: Notification.Name("WizardOpenMostRecentProject"),
                object: nil
            )
        case "team_management":
            // Deep-navigate into Settings → Manage Team (bypasses Organization screen)
            NotificationCenter.default.post(
                name: Notification.Name("WizardOpenManageTeam"),
                object: nil
            )
        case "settings_security":
            // Deep-navigate into the correct Settings sub-screen for the current step
            guard let targetScreen = currentStep?.targetScreen else { break }
            switch targetScreen {
            case "SecuritySettings":
                NotificationCenter.default.post(
                    name: Notification.Name("WizardOpenSecuritySettings"),
                    object: nil
                )
            case "NotificationSettings":
                NotificationCenter.default.post(
                    name: Notification.Name("WizardOpenNotificationSettings"),
                    object: nil
                )
            default:
                break // "Settings" targetScreen needs no deep nav — user is on SettingsView
            }
        case "permissions_roles":
            // Deep-navigate into Settings → Permissions
            NotificationCenter.default.post(
                name: Notification.Name("WizardOpenPermissions"),
                object: nil
            )
        case "payment_review":
            // Deep-navigate into the PaymentReview sheet from JobBoard.
            // Only needed for steps 2+ (steps targeting "PaymentReview" screen).
            guard let targetScreen = currentStep?.targetScreen,
                  targetScreen == "PaymentReview" else { break }
            NotificationCenter.default.post(
                name: Notification.Name("OpenPaymentReview"),
                object: nil
            )
        default:
            break
        }
    }

    /// Maps a wizard step's targetScreen to the tab that contains it.
    static func tabTarget(for targetScreen: String) -> String? {
        switch targetScreen {
        // Home tab
        case "Home":
            return "Home"
        // Pipeline tab
        case "Pipeline":
            return "Pipeline"
        // Job Board tab
        case "JobBoard", "FABMenu", "ProjectForm", "ClientForm", "TaskForm":
            return "JobBoard"
        // Schedule/Calendar tab
        case "Schedule", "Calendar":
            return "Schedule"
        // Inventory tab
        case "Inventory":
            return "Inventory"
        // Settings and sub-screens
        case "Settings", "SecuritySettings", "NotificationSettings",
             "ManageTeam", "TeamInvite", "Permissions",
             "Profile", "OrganizationDetails":
            return "Settings"
        // Project details (opened from Job Board or any tab)
        case "ProjectDetails", "PhotoAnnotation",
             "TaskReview", "PaymentReview":
            return "JobBoard"
        default:
            return nil
        }
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
                guard let self, !self.isPaused else { return }
                self.completeCurrentStep()
            }
    }

    /// Check if the current step's prerequisites are met. If not and the step is skippable, auto-skip.
    /// Called after each step transition to handle data-dependent steps (e.g., "view closed" when no closed projects exist).
    func evaluateStepPrerequisites(
        closedProjectCount: Int = -1,
        swipeableProjectCount: Int = -1,
        projectPhotoCount: Int = -1,
        eligibleTeamMemberCount: Int = -1,
        scheduledTaskCount: Int = -1,
        paymentReviewCardCount: Int = -1,
        taskReviewCardCount: Int = -1,
        hasOverdueProjects: Bool = false
    ) {
        guard let step = currentStep, step.canSkip else { return }

        var shouldAutoSkip = false

        switch step.id {
        case "view_closed":
            // Auto-skip when there are no closed projects — the CLOSED button won't exist
            if closedProjectCount == 0 {
                shouldAutoSkip = true
            }
        case "swipe_status":
            // Auto-skip only when the user can't swipe at all. If they have
            // projects.edit but no project is currently in a swipe-forward
            // state, we intentionally leave the step visible so users still
            // learn that swiping changes status — they can hit SKIP to move on.
            if !PermissionStore.shared.can("projects.edit") {
                shouldAutoSkip = true
            }
        case "view_photo":
            // Auto-skip when the project has no photos — nothing to tap in the gallery
            if projectPhotoCount == 0 {
                shouldAutoSkip = true
            }
        case "assign_role":
            // Auto-skip when no team members are eligible for role change
            // (only non-current-user, non-creator members can have roles changed)
            if eligibleTeamMemberCount == 0 {
                shouldAutoSkip = true
            }
        case "enable_pin":
            // Auto-skip when a PIN is already enabled — "SET UP A PIN" is misleading.
            // hasPINEnabled is stored in UserDefaults via @AppStorage("hasPINEnabled").
            if UserDefaults.standard.bool(forKey: "hasPINEnabled") {
                shouldAutoSkip = true
            }
        case "tap_month_day", "tap_task":
            // Auto-skip when the user has no scheduled tasks on the selected day —
            // there are no task cards to tap.
            if scheduledTaskCount == 0 {
                shouldAutoSkip = true
            }
        case "view_member_overrides":
            // Auto-skip when no team members exist — empty list with nothing to tap
            if eligibleTeamMemberCount == 0 {
                shouldAutoSkip = true
            }
        case "view_on_board":
            // Auto-skip when user lacks projects.edit — swipe-to-change-status is disabled
            // so the completion notification (WizardProjectStatusChanged) can never fire.
            if !PermissionStore.shared.can("projects.edit") {
                shouldAutoSkip = true
            }
        case "task_demo_swipe_right", "task_demo_swipe_left":
            // Auto-skip when no task review cards remain — nothing to swipe.
            if taskReviewCardCount == 0 {
                shouldAutoSkip = true
            }
        case "task_demo_swipe_up":
            // Auto-skip when user lacks calendar.edit — the UP swipe (reschedule) is
            // blocked in TaskReviewCardStack and the hint pill is hidden. The user
            // cannot perform the action so the notification can never fire.
            // Also auto-skip when no cards remain.
            if !PermissionStore.shared.can("calendar.edit") || taskReviewCardCount == 0 {
                shouldAutoSkip = true
            }
        case "tap_review_completed":
            // Auto-skip when overdue projects exist — the card stack is shown
            // immediately on appear, so no intermediate screen to tap through.
            if hasOverdueProjects {
                shouldAutoSkip = true
            }
        case "payment_demo_swipe_right", "payment_demo_swipe_left",
             "payment_demo_swipe_up", "payment_demo_swipe_down":
            // Auto-skip when no cards remain in the stack — the swipe gesture
            // cannot be performed on an empty stack.
            if paymentReviewCardCount == 0 {
                shouldAutoSkip = true
            }
        default:
            break
        }

        if shouldAutoSkip {
            skipCurrentStep()
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
        UserDefaults.standard.set(isEnabled, forKey: "wizard_system_enabled")
        if !isEnabled {
            deactivate()
            showBanner = false
            showPromptOverlay = false
        }
    }

    // MARK: - Background Save

    private func saveCurrentState() {
        guard let wizard = activeWizard,
              let state = wizardState(for: wizard.wizardId) else { return }
        let stepDuration = stepStartTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
        state.addDuration(stepDuration)
        state.lastActiveAt = Date()
        try? modelContext?.save()
    }
}
