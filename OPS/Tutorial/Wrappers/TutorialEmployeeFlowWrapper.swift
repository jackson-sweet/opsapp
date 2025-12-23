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

    var body: some View {
        ZStack {
            // Layer 1: Full-screen app content
            contentForCurrentPhase
                .environment(\.tutorialMode, true)
                .environment(\.tutorialPhase, stateManager.currentPhase)
                .environment(\.tutorialStateManager, stateManager)

            // Layer 2: Tutorial spotlight overlay (dark with cutout)
            if stateManager.currentPhase.requiresUserAction && currentCutoutFrame != .zero {
                TutorialSpotlight(
                    cutoutFrame: currentCutoutFrame,
                    showHighlight: true
                )
                .allowsHitTesting(false)
            }

            // Layer 3: Swipe indicator (when applicable)
            if stateManager.showSwipeHint {
                TutorialSwipeIndicator(
                    direction: stateManager.swipeDirection,
                    targetFrame: currentCutoutFrame
                )
            }

            // Layer 4 (TOPMOST): Collapsible tooltip at top of screen
            VStack {
                TutorialCollapsibleTooltip(
                    text: stateManager.tooltipText,
                    description: stateManager.tooltipDescription,
                    animated: true
                )

                Spacer()
            }
        }
        .ignoresSafeArea(.keyboard)
        // Listen for project tap in tutorial mode
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialProjectTapped"))) { _ in
            if stateManager.currentPhase == .tapProject {
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
                stateManager.advancePhase()
            }
        }
    }

    // MARK: - Content Routing

    /// Returns the appropriate view for the current tutorial phase
    @ViewBuilder
    private var contentForCurrentPhase: some View {
        switch stateManager.currentPhase {
        case .homeOverview, .tapProject, .projectStarted:
            // Home view phases
            EmployeeTutorialTabView(selectedTab: 0) // Home tab

        case .longPressDetails, .addNote, .addPhoto, .completeProject:
            // Project details phases
            EmployeeTutorialTabView(selectedTab: 0)

        case .jobBoardBrowse:
            // Job board browsing
            EmployeeTutorialTabView(selectedTab: 1) // Job Board tab

        case .calendarWeek, .calendarMonthPrompt, .calendarMonth:
            // Calendar phases
            EmployeeTutorialTabView(selectedTab: 2) // Schedule tab

        case .completed:
            // Show completion view
            TutorialCompletionView(
                manager: stateManager,
                onDismiss: onComplete
            )

        default:
            // Fallback to home
            EmployeeTutorialTabView(selectedTab: 0)
        }
    }

    // MARK: - Helpers

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
