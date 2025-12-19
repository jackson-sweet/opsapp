//
//  TutorialEmployeeFlowWrapper.swift
//  OPS
//
//  Tutorial flow wrapper for employee flow.
//  Wraps the Home tab with tutorial overlay, tooltip, and swipe indicators.
//  Injects tutorialMode=true into the environment for demo data filtering.
//

import SwiftUI
import SwiftData

/// Wrapper view for the Employee tutorial flow
/// Manages the home view with tutorial overlays and phase progression
struct TutorialEmployeeFlowWrapper: View {
    @ObservedObject var stateManager: TutorialStateManager
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    /// Callback when tutorial completes
    let onComplete: () -> Void

    /// Frame tracking for cutout positions
    /// Note: Frame captures will be wired when Phase 6 adds .tutorialTarget() modifiers
    /// to the actual UI elements (project cards, action buttons in ProjectDetailsView)
    @State private var projectCardFrame: CGRect = .zero
    @State private var noteButtonFrame: CGRect = .zero
    @State private var photoButtonFrame: CGRect = .zero
    @State private var completeButtonFrame: CGRect = .zero

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
        case .homeOverview, .tapProject, .projectStarted:
            // Home view phases
            homeContent

        case .longPressDetails, .addNote, .addPhoto, .completeProject:
            // Project details phases - shown as sheet over home
            homeContent

        case .jobBoardBrowse:
            // Job board browsing
            jobBoardContent

        case .calendarWeek, .calendarMonthPrompt, .calendarMonth:
            // Calendar phases (shared with creator flow)
            calendarContent

        case .completed:
            // Show completion view
            TutorialCompletionView(
                manager: stateManager,
                onDismiss: onComplete
            )

        default:
            // Fallback to home
            homeContent
        }
    }

    // MARK: - Phase-Specific Views

    /// Home view with today's projects
    @ViewBuilder
    private var homeContent: some View {
        HomeView()
    }

    /// Job board view for browsing all jobs
    @ViewBuilder
    private var jobBoardContent: some View {
        JobBoardDashboard()
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
        case .homeOverview, .tapProject:
            return projectCardFrame
        case .longPressDetails:
            return projectCardFrame
        case .addNote:
            return noteButtonFrame
        case .addPhoto:
            return photoButtonFrame
        case .completeProject:
            return completeButtonFrame
        case .jobBoardBrowse:
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
struct TutorialEmployeeFlowWrapper_Previews: PreviewProvider {
    static var previews: some View {
        let stateManager = TutorialStateManager(flowType: .employee)

        TutorialEmployeeFlowWrapper(
            stateManager: stateManager,
            onComplete: {}
        )
        .onAppear {
            stateManager.start()
        }
    }
}
#endif
