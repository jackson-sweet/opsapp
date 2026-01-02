//
//  TutorialEmployeeFlowWrapper.swift
//  OPS
//
//  Tutorial flow wrapper for employee flow.
//  Displays the full app UI at native size with tutorial overlays.
//  Injects tutorialMode=true into the environment for demo data filtering.
//

import SwiftUI
import SwiftData

/// Wrapper view for the Employee tutorial flow
/// Shows full-screen app content with spotlight overlay and floating tooltip
struct TutorialEmployeeFlowWrapper: View {
    @ObservedObject var stateManager: TutorialStateManager
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    /// Callback when tutorial completes
    let onComplete: () -> Void

    /// Frame tracking for spotlight cutouts
    @State private var projectCardFrame: CGRect = .zero
    @State private var noteButtonFrame: CGRect = .zero
    @State private var photoButtonFrame: CGRect = .zero
    @State private var completeButtonFrame: CGRect = .zero

    /// Inline sheet presentation for project details
    @State private var showProjectDetails: Bool = false
    @State private var detailsProjectID: String? = nil

    var body: some View {
        ZStack {
            // Layer 1: Full-screen app content with smooth tab transitions
            // Note: The dark overlay for tapProject phase is handled within HomeContentView
            // to ensure proper z-ordering (overlay behind carousel, in front of other content)
            contentForCurrentPhase
                .id(currentTabIndex)  // Force view recreation for transition animation
                .environment(\.tutorialMode, true)
                .environment(\.tutorialPhase, stateManager.currentPhase)
                .environment(\.tutorialStateManager, stateManager)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: currentTabIndex)

            // Layer 2: Swipe indicator (when applicable)
            if stateManager.showSwipeHint {
                TutorialSwipeIndicator(
                    direction: stateManager.swipeDirection,
                    targetFrame: currentCutoutFrame
                )
            }

            // Layer 3: Inline sheet for ProjectDetailsView
            // Note: TutorialInlineSheet manages its own visibility - no `if` wrapper needed
            TutorialInlineSheet(isPresented: $showProjectDetails, interactiveDismissDisabled: true) {
                if let projectID = detailsProjectID,
                   let project = dataController.getProject(id: projectID) {
                    NavigationView {
                        ProjectDetailsView(project: project)
                    }
                    .environment(\.tutorialMode, true)
                    .environment(\.tutorialPhase, stateManager.currentPhase)
                    .environment(\.modelContext, modelContext)
                    .environmentObject(dataController)
                } else {
                    // Placeholder when no project - sheet manages visibility
                    Color.clear
                }
            }

            // Layer 4: Collapsible tooltip at top of screen + Continue button
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

            // Layer 5: Done button for tutorial summary (matches company creator flow)
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
        // Listen for project tap in tutorial mode
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialProjectTapped"))) { _ in
            if stateManager.currentPhase == .tapProject {
                stateManager.advancePhase()
            }
        }
        // Listen for details button tapped
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialDetailsTapped"))) { notification in
            if stateManager.currentPhase == .tapDetails {
                // Extract project ID and show inline sheet
                if let userInfo = notification.userInfo,
                   let projectID = userInfo["projectID"] as? String {
                    detailsProjectID = projectID
                    showProjectDetails = true
                }
                stateManager.advancePhase()
            }
        }
        // Listen for note added
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialNoteAdded"))) { _ in
            if stateManager.currentPhase == .addNote {
                stateManager.advancePhase()
            }
        }
        // Listen for photo added
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialPhotoAdded"))) { _ in
            if stateManager.currentPhase == .addPhoto {
                stateManager.advancePhase()
            }
        }
        // Listen for project completed
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialProjectCompleted"))) { _ in
            if stateManager.currentPhase == .completeProject {
                // Close the inline sheet - it handles its own animation
                showProjectDetails = false
                // Wait for sheet dismiss animation, then advance to job board
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Advance to jobBoardBrowse - the tab view will switch to job board
                    stateManager.advancePhase()
                }
            }
        }
        // Listen for calendar month tap (step 10 - user taps "Month" toggle)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialCalendarMonthTapped"))) { _ in
            if stateManager.currentPhase == .calendarMonthPrompt {
                stateManager.advancePhase()
            }
        }
        // Note: Steps 9 (calendarWeek) and 11 (calendarMonth) now use Continue button
        // instead of scroll/pinch detection to avoid double-advance issues
    }

    // MARK: - Content Routing

    /// Returns the appropriate view for the current tutorial phase
    @ViewBuilder
    private var contentForCurrentPhase: some View {
        switch stateManager.currentPhase {
        case .homeOverview, .tapProject, .projectStarted:
            // Home view phases
            EmployeeTutorialTabView(selectedTab: 0) // Home tab

        case .tapDetails, .addNote, .addPhoto, .completeProject:
            // Project details phases (after starting project)
            EmployeeTutorialTabView(selectedTab: 0)

        case .jobBoardBrowse:
            // Job board browsing
            EmployeeTutorialTabView(selectedTab: 1) // Job Board tab

        case .calendarWeek, .calendarMonthPrompt, .calendarMonth, .tutorialSummary:
            // Calendar phases (including summary to prevent view recreation)
            EmployeeTutorialTabView(selectedTab: 2) // Schedule tab

        case .completed:
            // Completion is handled by TutorialLauncherView, just call onComplete
            Color.clear
                .onAppear {
                    onComplete()
                }

        default:
            // Fallback to home
            EmployeeTutorialTabView(selectedTab: 0)
        }
    }

    // MARK: - Helpers

    /// Current tab index for animation tracking
    private var currentTabIndex: Int {
        switch stateManager.currentPhase {
        case .homeOverview, .tapProject, .projectStarted, .tapDetails, .addNote, .addPhoto, .completeProject:
            return 0
        case .jobBoardBrowse:
            return 1
        case .calendarWeek, .calendarMonthPrompt, .calendarMonth, .tutorialSummary:
            return 2
        case .completed:
            return 3
        default:
            return 0
        }
    }

    /// Whether to show the floating Done button for tutorial summary
    private var shouldShowDoneButton: Bool {
        stateManager.currentPhase == .tutorialSummary
    }

    /// Current cutout frame based on phase (used for swipe indicators)
    private var currentCutoutFrame: CGRect {
        switch stateManager.currentPhase {
        case .jobBoardBrowse:
            return projectCardFrame
        default:
            return .zero
        }
    }
}

// MARK: - Employee Tutorial Tab View

/// Simplified tab view for employee tutorial
private struct EmployeeTutorialTabView: View {
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
                HomeView()
            }

            // Tab bar at bottom
            VStack {
                Spacer()
                EmployeeTutorialTabBar(selectedTab: selectedTab)
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }
}

// MARK: - Employee Tutorial Tab Bar

/// Visual-only tab bar for employee tutorial
private struct EmployeeTutorialTabBar: View {
    let selectedTab: Int

    private let tabs = [
        ("house.fill", "Home"),
        ("briefcase.fill", "Jobs"),
        ("calendar", "Schedule"),
        ("gearshape.fill", "Settings")
    ]

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
        .padding(.bottom, 24) // Safe area
        .background(
            OPSStyle.Colors.cardBackgroundDark
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: -2)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct TutorialEmployeeFlowWrapper_Previews: PreviewProvider {
    static var previews: some View {
        let stateManager = TutorialStateManager(flowType: .employee)

        TutorialEmployeeFlowWrapper(
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
