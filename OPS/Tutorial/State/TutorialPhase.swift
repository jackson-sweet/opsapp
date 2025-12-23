//
//  TutorialPhase.swift
//  OPS
//
//  Defines the phases of the interactive tutorial and their associated tooltip text.
//  Each phase represents a step in either the Company Creator or Employee flow.
//

import SwiftUI

// MARK: - Tutorial Flow Type

/// The two tutorial flows based on user type
enum TutorialFlowType: String, CaseIterable {
    case companyCreator  // ~30 sec flow for admin/office users
    case employee        // ~20 sec flow for field crew
}

// MARK: - Tutorial Swipe Direction

/// Direction for swipe hint animations in the tutorial
enum TutorialSwipeDirection: String, CaseIterable {
    case left
    case right
    case up
    case down

    /// The angle for the shimmer animation
    var angle: Angle {
        switch self {
        case .left: return .degrees(180)
        case .right: return .degrees(0)
        case .up: return .degrees(-90)
        case .down: return .degrees(90)
        }
    }

    /// The offset for the indicator animation
    var offset: CGSize {
        switch self {
        case .left: return CGSize(width: -20, height: 0)
        case .right: return CGSize(width: 20, height: 0)
        case .up: return CGSize(width: 0, height: -20)
        case .down: return CGSize(width: 0, height: 20)
        }
    }
}

// MARK: - Tutorial Phase

/// All phases of the interactive tutorial
enum TutorialPhase: Int, CaseIterable, Identifiable {
    // Not started
    case notStarted = 0

    // MARK: - Company Creator Phases

    /// Job Board intro - highlights FAB
    case jobBoardIntro

    /// User taps FAB
    case fabTap

    /// User selects "Create Project" from menu
    case createProjectAction

    /// Project form - select client
    case projectFormClient

    /// Project form - enter project name
    case projectFormName

    /// Project form - add task button
    case projectFormAddTask

    /// Task form - assign crew
    case taskFormCrew

    /// Task form - select task type
    case taskFormType

    /// Task form - set date
    case taskFormDate

    /// Task form - tap done
    case taskFormDone

    /// Project form - tap complete/save
    case projectFormComplete

    /// Drag project to accepted status
    case dragToAccepted

    /// View project list and watch status animate
    case projectListStatusDemo

    /// Swipe to close out the project
    case projectListSwipe

    /// Scroll to see closed projects section
    case closedProjectsScroll

    /// Calendar week view intro
    case calendarWeek

    /// Prompt to tap month
    case calendarMonthPrompt

    /// Calendar month view exploration
    case calendarMonth

    /// Final summary before completion
    case tutorialSummary

    // MARK: - Employee Phases

    /// Home view overview
    case homeOverview

    /// Tap on assigned project
    case tapProject

    /// Project is now started
    case projectStarted

    /// Long press for project details
    case longPressDetails

    /// Add a note
    case addNote

    /// Add a photo
    case addPhoto

    /// Complete the project
    case completeProject

    /// Browse job board
    case jobBoardBrowse

    // MARK: - Completion

    /// Tutorial complete
    case completed

    // MARK: - Identifiable

    var id: Int { rawValue }

    // MARK: - Tooltip Text

    /// The instruction text shown to the user during this phase
    var tooltipText: String {
        switch self {
        case .notStarted:
            return ""

        // Company Creator Phases
        case .jobBoardIntro:
            return "TAP THE + BUTTON"
        case .fabTap:
            return "TAP \"CREATE PROJECT\""
        case .createProjectAction:
            return "TAP \"CREATE PROJECT\""  // Unused - phase is skipped
        case .projectFormClient:
            return "SELECT A CLIENT"
        case .projectFormName:
            return "ENTER A PROJECT NAME"
        case .projectFormAddTask:
            return "NOW ADD A TASK"
        case .taskFormCrew:
            return "ASSIGN A CREW MEMBER"
        case .taskFormType:
            return "SELECT A TASK TYPE"
        case .taskFormDate:
            return "SET THE DATE"
        case .taskFormDone:
            return "TAP \"DONE\""
        case .projectFormComplete:
            return "TAP \"CREATE\""
        case .dragToAccepted:
            return "PRESS AND HOLD, THEN DRAG RIGHT"
        case .projectListStatusDemo:
            return "WATCH THE STATUS UPDATE"
        case .projectListSwipe:
            return "SWIPE THE CARD RIGHT TO CLOSE"
        case .closedProjectsScroll:
            return "COMPLETE. SCROLL DOWN TO FIND IT."
        case .calendarWeek:
            return "THIS IS YOUR WEEK VIEW"
        case .calendarMonthPrompt:
            return "TAP \"MONTH\""
        case .calendarMonth:
            return "PINCH OUTWARD TO EXPAND"
        case .tutorialSummary:
            return "THAT'S THE BASICS."

        // Employee Phases
        case .homeOverview:
            return "THESE ARE YOUR JOBS FOR TODAY"
        case .tapProject:
            return "TAP \"START\" TO BEGIN"
        case .projectStarted:
            return "JOB STARTED."
        case .longPressDetails:
            return "PRESS AND HOLD FOR DETAILS"
        case .addNote:
            return "TAP TO ADD A NOTE"
        case .addPhoto:
            return "TAP TO TAKE A PHOTO"
        case .completeProject:
            return "TAP \"COMPLETE\" WHEN DONE"
        case .jobBoardBrowse:
            return "SWIPE LEFT OR RIGHT"

        case .completed:
            return "YOU'RE READY."
        }
    }

    /// Optional description text shown below the main tooltip text
    var tooltipDescription: String? {
        switch self {
        // Company Creator Phases
        case .jobBoardIntro:
            return "This is where you create projects, tasks, clients, and more."
        case .fabTap:
            return "This starts a new job."
        case .projectFormClient:
            return "These are sample clients. Pick any one—this is just for practice."
        case .projectFormName:
            return "Type anything. Try \"Test Project\" or make one up."
        case .projectFormAddTask:
            return "Tasks are the individual pieces of work—like \"Install outlets\" or \"Paint bedroom.\""
        case .taskFormType:
            return "Pick any one for now. Types help you organize different kinds of work."
        case .taskFormCrew:
            return "These are sample crew members. People you assign will see this on their schedule."
        case .taskFormDate:
            return "Pick any date. This is when the task should be done."
        case .taskFormDone:
            return "This saves the task to your project."
        case .projectFormComplete:
            return "Your project is ready. This saves it to your job board."
        case .dragToAccepted:
            return "Drag it to the \"Accepted\" column. This is how you move jobs between stages."
        case .projectListStatusDemo:
            return "As your crew starts work and completes tasks, the status updates automatically. You see their progress here."
        case .projectListSwipe:
            return "Swipe right to advance status, left to go back. In this case, you're closing the job—paid out and filed."
        case .closedProjectsScroll:
            return "Finished jobs move to the bottom so active work stays on top."
        case .calendarWeek:
            return "Your scheduled tasks appear by day. Swipe left or right to see other weeks."
        case .calendarMonthPrompt:
            return "Switch to month view to see the bigger picture."
        case .calendarMonth:
            return "This shows more detail for each day. Pinch inward to shrink it back."
        case .tutorialSummary:
            return "You now know how to create projects, assign your crew, track progress, and check your schedule."

        // Employee Phases
        case .homeOverview:
            return "Each card is a job. Tap one to see options."
        case .tapProject:
            return "This tells your crew lead you're working on it."
        case .projectStarted:
            return "Your crew lead can see you've started."
        case .longPressDetails:
            return "This opens everything about the job—address, notes, photos, client info."
        case .addNote:
            return "Type anything—like \"Waiting on parts\" or \"Finished early.\" Your crew lead will see it."
        case .addPhoto:
            return "Photos save directly to this job, not your camera roll."
        case .completeProject:
            return "This marks the job finished. Your crew lead will see it's complete."
        case .jobBoardBrowse:
            return "Jobs are grouped by status: To Do, In Progress, Complete."

        default:
            return nil
        }
    }

    // MARK: - Phase Properties

    /// Whether this phase shows a swipe hint indicator overlay
    /// Note: .projectListSwipe now uses in-card shimmer instead of overlay
    var showsSwipeHint: Bool {
        switch self {
        case .jobBoardBrowse:
            return true
        default:
            return false
        }
    }

    /// The swipe direction for phases that show a swipe hint
    var swipeDirection: TutorialSwipeDirection? {
        switch self {
        case .projectListSwipe:
            return .right  // Swipe right to close/complete project
        case .jobBoardBrowse:
            return .left
        default:
            return nil
        }
    }

    /// Whether this phase auto-advances after a delay
    var autoAdvances: Bool {
        switch self {
        case .homeOverview,  // Intro phase for employee flow
             .projectListStatusDemo,  // Status animation auto-advances
             .closedProjectsScroll,  // Scroll animation auto-advances
             .projectStarted, // After starting project
             .jobBoardBrowse, // Swipe hints - auto-advance after showing
             .longPressDetails: // Long press hint - auto-advance
            return true
        default:
            return false
        }
    }

    /// The delay in seconds before auto-advancing (if applicable)
    var autoAdvanceDelay: TimeInterval {
        switch self {
        case .homeOverview:
            return 1.5 // Brief pause to see UI
        case .projectStarted:
            return 1.5
        case .projectListStatusDemo:
            return 4.0 // Time for status animation (accepted → in progress → completed)
        case .closedProjectsScroll:
            return 3.0 // Time to scroll and highlight
        case .jobBoardBrowse:
            return 2.0 // Show swipe hint, then advance
        case .longPressDetails:
            return 2.0 // Show long press hint, then advance
        default:
            return 0
        }
    }

    /// Whether this phase requires waiting for user action
    var requiresUserAction: Bool {
        switch self {
        case .notStarted, .completed,
             .projectListStatusDemo, .closedProjectsScroll,
             .homeOverview, .projectStarted,
             .jobBoardBrowse, .longPressDetails:
            return false
        case .projectListSwipe, .calendarWeek, .calendarMonth, .tutorialSummary:
            // These phases require user interaction (swipe, scroll, pinch, or button tap)
            return true
        default:
            return true
        }
    }

    // MARK: - Flow Navigation

    /// Returns the next phase based on the current flow type
    func next(for flowType: TutorialFlowType) -> TutorialPhase? {
        switch flowType {
        case .companyCreator:
            return nextCompanyPhase
        case .employee:
            return nextEmployeePhase
        }
    }

    /// The next phase in the Company Creator flow
    private var nextCompanyPhase: TutorialPhase? {
        switch self {
        case .notStarted:
            return .jobBoardIntro
        case .jobBoardIntro:
            return .fabTap
        case .fabTap:
            return .projectFormClient  // Skip createProjectAction - redundant step
        case .projectFormClient:
            return .projectFormName
        case .projectFormName:
            return .projectFormAddTask
        case .projectFormAddTask:
            return .taskFormType
        case .taskFormType:
            return .taskFormCrew
        case .taskFormCrew:
            return .taskFormDate
        case .taskFormDate:
            return .taskFormDone
        case .taskFormDone:
            return .projectFormComplete
        case .projectFormComplete:
            return .dragToAccepted  // User drags project to accepted
        case .dragToAccepted:
            return .projectListStatusDemo  // Show status animation
        case .projectListStatusDemo:
            return .projectListSwipe  // User swipes to close out
        case .projectListSwipe:
            return .closedProjectsScroll  // Show closed projects section
        case .closedProjectsScroll:
            return .calendarWeek  // Switch to calendar
        case .calendarWeek:
            return .calendarMonthPrompt
        case .calendarMonthPrompt:
            return .calendarMonth
        case .calendarMonth:
            return .tutorialSummary  // Final summary before completion
        case .tutorialSummary:
            return .completed
        default:
            return nil
        }
    }

    /// The next phase in the Employee flow
    private var nextEmployeePhase: TutorialPhase? {
        switch self {
        case .notStarted:
            return .homeOverview
        case .homeOverview:
            return .tapProject
        case .tapProject:
            return .projectStarted
        case .projectStarted:
            return .longPressDetails
        case .longPressDetails:
            return .addNote
        case .addNote:
            return .addPhoto
        case .addPhoto:
            return .completeProject
        case .completeProject:
            return .jobBoardBrowse
        case .jobBoardBrowse:
            return .calendarWeek
        case .calendarWeek:
            return .calendarMonthPrompt
        case .calendarMonthPrompt:
            return .calendarMonth
        case .calendarMonth:
            return .completed
        default:
            return nil
        }
    }

    // MARK: - First Phase

    /// The starting phase for a given flow type
    static func firstPhase(for flowType: TutorialFlowType) -> TutorialPhase {
        switch flowType {
        case .companyCreator:
            return .jobBoardIntro
        case .employee:
            return .homeOverview
        }
    }
}
