//
//  TutorialCreatorFlowWrapper.swift
//  OPS
//
//  Tutorial flow wrapper for company creator flow.
//  Wraps the JobBoard tab with tutorial overlay, tooltip, and swipe indicators.
//  Injects tutorialMode=true into the environment for demo data filtering.
//

import SwiftUI
import SwiftData

/// Wrapper view for the Company Creator tutorial flow
/// Manages the job board view with tutorial overlays and phase progression
struct TutorialCreatorFlowWrapper: View {
    @ObservedObject var stateManager: TutorialStateManager
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    /// Callback when tutorial completes
    let onComplete: () -> Void

    /// Frame tracking for cutout positions
    /// Note: Additional frame captures (createProjectMenuItemFrame, projectCardFrame) will be wired
    /// when Phase 6 adds .tutorialTarget() modifiers to the actual UI elements
    @State private var fabFrame: CGRect = .zero
    @State private var createProjectMenuItemFrame: CGRect = .zero
    @State private var projectCardFrame: CGRect = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main content area (scaled)
                TutorialContainerView {
                    contentForCurrentPhase
                        .environment(\.tutorialMode, true)
                        .environment(\.tutorialPhase, stateManager.currentPhase)
                        .environment(\.tutorialStateManager, stateManager)
                }

                // Tutorial overlay with cutout
                if stateManager.currentPhase.requiresUserAction {
                    TutorialSpotlight(
                        cutoutFrame: currentCutoutFrame,
                        showHighlight: true
                    )
                }

                // Swipe indicator (when applicable)
                if stateManager.showSwipeHint {
                    swipeIndicatorOverlay
                }

                // Tooltip at bottom
                VStack {
                    Spacer()

                    TutorialTooltipCard(
                        text: stateManager.tooltipText,
                        animated: true
                    )
                    .padding(.bottom, 40)
                }
            }
        }
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Content Routing

    /// Returns the appropriate view for the current tutorial phase
    @ViewBuilder
    private var contentForCurrentPhase: some View {
        switch stateManager.currentPhase {
        case .jobBoardIntro, .fabTap, .createProjectAction,
             .dragToAccepted, .statusProgressionInProgress, .statusProgressionCompleted:
            // Job Board Dashboard phases
            jobBoardContent

        case .projectFormClient, .projectFormName, .projectFormAddTask, .projectFormComplete:
            // Project form phases - shown as sheet over job board
            jobBoardContent

        case .taskFormCrew, .taskFormType, .taskFormDate, .taskFormDone:
            // Task form phases - shown as sheet over job board
            jobBoardContent

        case .projectListSwipe:
            // List view for swipe action
            projectListContent

        case .calendarWeek, .calendarMonthPrompt, .calendarMonth:
            // Calendar phases
            calendarContent

        case .completed:
            // Show completion view
            TutorialCompletionView(
                manager: stateManager,
                onDismiss: onComplete
            )

        default:
            // Fallback to job board
            jobBoardContent
        }
    }

    // MARK: - Phase-Specific Views

    /// Job board view with FAB
    @ViewBuilder
    private var jobBoardContent: some View {
        ZStack {
            JobBoardDashboard()

            // Capture FAB frame for cutout using existing PreferenceKeys utilities
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingActionMenu()
                        .tutorialTargetFrame()
                        .padding(.trailing, 20)
                        .padding(.bottom, 100)
                }
            }
        }
        .onTutorialTargetFrameChange { frame in
            if stateManager.currentPhase == .jobBoardIntro ||
               stateManager.currentPhase == .fabTap {
                fabFrame = frame
                stateManager.setCutout(for: frame)
            }
        }
    }

    /// Project list view for swipe demonstration - state bindings for required parameters
    @State private var projectListSearchText: String = ""
    @State private var projectListShowingFilters: Bool = false
    @State private var projectListShowingFilterSheet: Bool = false

    @ViewBuilder
    private var projectListContent: some View {
        // Use JobBoardProjectListView filtered to demo projects
        JobBoardProjectListView(
            searchText: projectListSearchText,
            showingFilters: $projectListShowingFilters,
            showingFilterSheet: $projectListShowingFilterSheet
        )
    }

    /// Calendar view
    @ViewBuilder
    private var calendarContent: some View {
        // Schedule view (calendar tab)
        ScheduleView()
    }

    // MARK: - Overlay Components

    /// Current cutout frame based on phase
    private var currentCutoutFrame: CGRect {
        switch stateManager.currentPhase {
        case .jobBoardIntro, .fabTap:
            return fabFrame
        case .createProjectAction:
            return createProjectMenuItemFrame
        case .dragToAccepted, .statusProgressionInProgress, .statusProgressionCompleted:
            return projectCardFrame
        case .projectListSwipe:
            return projectCardFrame
        default:
            return .zero // No cutout (full access)
        }
    }

    /// Swipe indicator overlay positioned near the target
    @ViewBuilder
    private var swipeIndicatorOverlay: some View {
        TutorialSwipeIndicator(
            direction: stateManager.swipeDirection,
            targetFrame: currentCutoutFrame
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
        .onAppear {
            stateManager.start()
        }
    }
}
#endif
