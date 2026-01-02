//
//  TutorialCreatorFlowWrapper.swift
//  OPS
//
//  Tutorial flow wrapper for company creator flow.
//  Displays the full app UI at native size with tutorial overlays.
//  Injects tutorialMode=true into the environment for demo data filtering.
//

import SwiftUI
import SwiftData

/// Wrapper view for the Company Creator tutorial flow
/// Shows full-screen app content with spotlight overlay and floating tooltip
struct TutorialCreatorFlowWrapper: View {
    @ObservedObject var stateManager: TutorialStateManager
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    /// Callback when tutorial completes
    let onComplete: () -> Void

    /// Frame tracking for spotlight cutouts
    @State private var fabFrame: CGRect = .zero
    @State private var projectCardFrame: CGRect = .zero

    /// Sheet presentation
    @State private var showProjectForm: Bool = false
    @State private var showTaskForm: Bool = false

    var body: some View {
        ZStack {
            // Layer 1: Full-screen app content
            contentForCurrentPhase
                .environment(\.tutorialMode, true)
                .environment(\.tutorialPhase, stateManager.currentPhase)
                .environment(\.tutorialStateManager, stateManager)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .animation(.easeInOut(duration: 0.4), value: currentTabForPhase)

            // Layer 1.5: Blocking overlay for intro phases (blocks interaction with content)
            // This overlay is BELOW the FAB, so FAB remains tappable
            if shouldShowIntroBlockingOverlay {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: shouldShowIntroBlockingOverlay)
            }

            // Layer 2: Floating Action Button overlay (captures frame for spotlight)
            if shouldShowFAB {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FloatingActionMenu()
                            .environment(\.tutorialMode, true)
                            .environment(\.tutorialPhase, stateManager.currentPhase)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            updateFABFrame(geo.frame(in: .global))
                                        }
                                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                            updateFABFrame(newFrame)
                                        }
                                }
                            )
                    }
                }
            }

            // Layer 3: Tutorial spotlight overlay (dark with cutout)
            // Note: For steps 1-2 (jobBoardIntro, fabTap), we DON'T show the spotlight
            // because the blocking overlay already provides the darkening effect
            if shouldShowSpotlight && currentCutoutFrame != .zero {
                TutorialSpotlight(
                    cutoutFrame: currentCutoutFrame,
                    showHighlight: shouldShowSpotlightHighlight
                )
                .allowsHitTesting(false)
            }

            // Layer 4: Swipe indicator (when applicable)
            if stateManager.showSwipeHint {
                TutorialSwipeIndicator(
                    direction: stateManager.swipeDirection,
                    targetFrame: currentCutoutFrame
                )
            }

            // Layer 5: Inline sheet for ProjectFormSheet (custom, stays in view hierarchy)
            // Note: TutorialInlineSheet manages its own visibility - no `if` wrapper needed
            TutorialInlineSheet(isPresented: $showProjectForm, interactiveDismissDisabled: true) {
                ProjectFormSheet(mode: .create) { project in
                    handleProjectCreated()
                }
                .environment(\.tutorialMode, true)
                .environment(\.tutorialPhase, stateManager.currentPhase)
                .environment(\.modelContext, modelContext)
                .environmentObject(dataController)
            }

            // Layer 6: Inline sheet for TaskFormSheet (custom, stays in view hierarchy)
            // Note: TutorialInlineSheet manages its own visibility - no `if` wrapper needed
            TutorialInlineSheet(isPresented: $showTaskForm, interactiveDismissDisabled: true) {
                TaskFormSheet(draftMode: .draft(nil)) { localTask in
                    // Post notification so ProjectFormSheet can add this task
                    NotificationCenter.default.post(
                        name: Notification.Name("TutorialTaskSaved"),
                        object: nil,
                        userInfo: ["task": localTask]
                    )
                    showTaskForm = false
                }
                .environment(\.tutorialMode, true)
                .environment(\.tutorialPhase, stateManager.currentPhase)
                .environment(\.modelContext, modelContext)
                .environmentObject(dataController)
            }

            // Layer 7: Collapsible tooltip at top of screen + Continue button
            VStack(spacing: 0) {
                TutorialCollapsibleTooltip(
                    text: stateManager.tooltipText,
                    description: stateManager.tooltipDescription,
                    animated: true
                )

                // Continue button (appears after auto-advance timer)
                if stateManager.showContinueButton {
                    Button {
                        stateManager.continueFromAutoAdvance()
                    } label: {
                        HStack(spacing: 8) {
                            Text("CONTINUE")
                                .font(OPSStyle.Typography.bodyBold)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        // Dark glow effect
                        .shadow(color: Color.black.opacity(0.8), radius: 20, x: 0, y: 0)
                        .shadow(color: Color.black.opacity(0.6), radius: 40, x: 0, y: 4)
                    }
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()
            }
            .animation(.easeOut(duration: 0.3), value: stateManager.showContinueButton)

            // Layer 8 (TOPMOST): Floating Done button for tutorial summary
            if shouldShowDoneButton {
                VStack {
                    Spacer()
                    Button {
                        TutorialHaptics.success()
                        stateManager.advancePhase()
                    } label: {
                        Text("DONE")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            // Dark glow effect
                            .shadow(color: Color.black.opacity(0.8), radius: 20, x: 0, y: 0)
                            .shadow(color: Color.black.opacity(0.6), radius: 40, x: 0, y: 4)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 120)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .animation(.easeOut(duration: 0.3), value: shouldShowDoneButton)
            }
        }
        .ignoresSafeArea(.keyboard)
        // Listen for FAB button tap (opens menu)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialFABTapped"))) { _ in
            if stateManager.currentPhase == .jobBoardIntro {
                stateManager.advancePhase()
            }
        }
        // Listen for "Create Project" tap in menu (opens form)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialCreateProjectTapped"))) { _ in
            if stateManager.currentPhase == .fabTap {
                stateManager.advancePhase()
            }
            showProjectForm = true
        }
        // Listen for client selected in project form
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialClientSelected"))) { _ in
            if stateManager.currentPhase == .projectFormClient {
                stateManager.advancePhase()
            }
        }
        // Listen for project name entered
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialProjectNameEntered"))) { _ in
            if stateManager.currentPhase == .projectFormName {
                stateManager.advancePhase()
            }
        }
        // Listen for add task tapped
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialAddTaskTapped"))) { _ in
            if stateManager.currentPhase == .projectFormAddTask {
                stateManager.advancePhase()
            }
            showTaskForm = true
        }
        // Listen for crew assigned in task form
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialCrewAssigned"))) { _ in
            if stateManager.currentPhase == .taskFormCrew {
                stateManager.advancePhase()
            }
        }
        // Listen for task type selected
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialTaskTypeSelected"))) { _ in
            if stateManager.currentPhase == .taskFormType {
                stateManager.advancePhase()
            }
        }
        // Listen for date set in task form
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialDateSet"))) { _ in
            if stateManager.currentPhase == .taskFormDate {
                stateManager.advancePhase()
            }
        }
        // Listen for task form done
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialTaskFormDone"))) { _ in
            if stateManager.currentPhase == .taskFormDone {
                stateManager.advancePhase()
            }
            showTaskForm = false
        }
        // Listen for project form complete
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialProjectFormComplete"))) { _ in
            if stateManager.currentPhase == .projectFormComplete {
                showProjectForm = false
                stateManager.advancePhase()
            }
        }
        // Listen for drag to accepted (user drags project to accepted column)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialDragToAccepted"))) { _ in
            if stateManager.currentPhase == .dragToAccepted {
                stateManager.advancePhase()
            }
        }
        // Listen for project list swipe (user swipes to close out project)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialProjectListSwipe"))) { _ in
            if stateManager.currentPhase == .projectListSwipe {
                stateManager.advancePhase()
            }
        }
        // Listen for closed projects section viewed (auto-advances after scroll + delay)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialClosedProjectsViewed"))) { _ in
            if stateManager.currentPhase == .closedProjectsScroll {
                stateManager.advancePhase()
            }
        }
        // Listen for calendar month tap (user taps "Month" toggle)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialCalendarMonthTapped"))) { _ in
            if stateManager.currentPhase == .calendarMonthPrompt {
                stateManager.advancePhase()
            }
        }
        // Note: calendarWeek and calendarMonth now use Continue button
        // instead of scroll/pinch detection to avoid double-advance issues
        // Listen for project card frame updates (for swipe indicator positioning)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialProjectCardFrame"))) { notification in
            if let frame = notification.userInfo?["frame"] as? CGRect {
                projectCardFrame = frame
            }
        }
    }

    // MARK: - Content Routing

    /// Returns the appropriate view for the current tutorial phase
    @ViewBuilder
    private var contentForCurrentPhase: some View {
        switch stateManager.currentPhase {
        case .jobBoardIntro, .fabTap, .createProjectAction,
             .projectFormClient, .projectFormName, .projectFormAddTask, .projectFormComplete,
             .taskFormCrew, .taskFormType, .taskFormDate, .taskFormDone:
            // Job Board phases (form filling)
            TutorialMainTabView(selectedTab: 1)

        case .dragToAccepted:
            // Dashboard view for dragging project to accepted
            TutorialMainTabView(selectedTab: 1)

        case .projectListStatusDemo, .projectListSwipe, .closedProjectsScroll:
            // Project list phases (viewing/interacting with list)
            TutorialMainTabView(selectedTab: 1)

        case .calendarWeek, .calendarMonthPrompt, .calendarMonth, .tutorialSummary:
            // Calendar phases (including summary to prevent view recreation)
            TutorialMainTabView(selectedTab: 2)

        case .completed:
            // Completion is handled by TutorialLauncherView, just call onComplete
            Color.clear
                .onAppear {
                    onComplete()
                }

        default:
            // Fallback to job board
            TutorialMainTabView(selectedTab: 1)
        }
    }

    // MARK: - Helpers

    /// Returns the current tab index for animation purposes
    private var currentTabForPhase: Int {
        switch stateManager.currentPhase {
        case .calendarWeek, .calendarMonthPrompt, .calendarMonth, .tutorialSummary:
            return 2  // Calendar tab
        default:
            return 1  // Job Board tab
        }
    }

    private var shouldShowFAB: Bool {
        switch stateManager.currentPhase {
        case .jobBoardIntro, .fabTap, .createProjectAction:
            return true
        default:
            return false
        }
    }

    /// Whether to show the blocking overlay during intro phases
    /// This blocks interaction with the app content, focusing user on FAB
    private var shouldShowIntroBlockingOverlay: Bool {
        switch stateManager.currentPhase {
        case .jobBoardIntro, .fabTap:
            return true
        default:
            return false
        }
    }

    private var currentCutoutFrame: CGRect {
        switch stateManager.currentPhase {
        case .jobBoardIntro, .fabTap:
            return fabFrame
        case .projectListStatusDemo, .projectListSwipe:
            return projectCardFrame
        default:
            return .zero
        }
    }

    /// Whether to show the floating done button for tutorial summary
    private var shouldShowDoneButton: Bool {
        stateManager.currentPhase == .tutorialSummary
    }

    /// Whether to show the spotlight overlay (not shown for intro phases - blocking overlay handles it)
    private var shouldShowSpotlight: Bool {
        switch stateManager.currentPhase {
        case .jobBoardIntro, .fabTap:
            // These phases use the blocking overlay instead
            return false
        default:
            return stateManager.currentPhase.requiresUserAction
        }
    }

    /// Whether to show the highlight border around the spotlight cutout
    private var shouldShowSpotlightHighlight: Bool {
        switch stateManager.currentPhase {
        case .jobBoardIntro, .fabTap, .projectListSwipe:
            // No highlight for intro phases or swipe phase (card has its own border + shimmer)
            return false
        default:
            return true
        }
    }

    /// Whether the FAB should be disabled (greyed out)
    private var isFABDisabled: Bool {
        stateManager.currentPhase == .fabTap
    }

    private func updateFABFrame(_ frame: CGRect) {
        fabFrame = frame
        if stateManager.currentPhase == .fabTap {
            stateManager.setCutout(for: frame)
        }
    }

    private func handleProjectCreated() {
        showProjectForm = false
        // Advance through project form phases
        if stateManager.currentPhase == .createProjectAction ||
           stateManager.currentPhase == .projectFormClient ||
           stateManager.currentPhase == .projectFormName ||
           stateManager.currentPhase == .projectFormComplete {
            stateManager.advancePhase()
        }
    }
}

// MARK: - Tutorial Main Tab View

/// Simplified MainTabView for tutorial that shows specific tabs
private struct TutorialMainTabView: View {
    let selectedTab: Int
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            // Tab content
            switch selectedTab {
            case 0:
                HomeView()
            case 1:
                JobBoardView()
            case 2:
                ScheduleView()
            case 3:
                SettingsView()
            default:
                JobBoardView()
            }

            // Tab bar at bottom
            VStack {
                Spacer()
                TutorialTabBar(selectedTab: selectedTab)
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }
}

// MARK: - Tutorial Tab Bar

/// Visual-only tab bar for tutorial
private struct TutorialTabBar: View {
    let selectedTab: Int
    @Environment(\.tutorialPhase) private var tutorialPhase

    private let tabs = [
        ("house.fill", "Home"),
        ("briefcase.fill", "Jobs"),
        ("calendar", "Schedule"),
        ("gearshape.fill", "Settings")
    ]

    /// Whether the tab bar should be greyed out during certain tutorial phases
    private var shouldGreyOut: Bool {
        switch tutorialPhase {
        case .dragToAccepted, .projectListStatusDemo, .projectListSwipe:
            return true
        default:
            return false
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                VStack(spacing: 4) {
                    Image(systemName: tabs[index].0)
                        .font(.system(size: 22))
                        .foregroundColor(index == selectedTab ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
        .padding(.bottom, 24)
        .opacity(shouldGreyOut ? 0.3 : 1.0)
        .allowsHitTesting(!shouldGreyOut) // Disable interaction when greyed out
        .animation(.easeInOut(duration: 0.3), value: shouldGreyOut)
        .background(
            OPSStyle.Colors.cardBackgroundDark
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: -2)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct TutorialCreatorFlowWrapper_Previews: PreviewProvider {
    static var previews: some View {
        let stateManager = TutorialStateManager(flowType: .companyCreator)

        TutorialCreatorFlowWrapper(
            stateManager: stateManager,
            onComplete: {}
        )
        .environmentObject(DataController())
        .environmentObject(AppState())
        .onAppear {
            stateManager.start()
        }
    }
}
#endif
