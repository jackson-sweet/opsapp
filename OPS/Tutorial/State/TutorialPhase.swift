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

    /// Drag project to Accepted column
    case dragToAccepted

    /// Status auto-progresses to In Progress
    case statusProgressionInProgress

    /// Status auto-progresses to Completed
    case statusProgressionCompleted

    /// Switch to list view, swipe to advance status
    case projectListSwipe

    /// Calendar week view intro
    case calendarWeek

    /// Prompt to tap month
    case calendarMonthPrompt

    /// Calendar month view exploration
    case calendarMonth

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
            return "TAP THE + TO CREATE YOUR FIRST PROJECT"
        case .fabTap:
            return "TAP CREATE PROJECT"
        case .createProjectAction:
            return "TAP CREATE PROJECT"
        case .projectFormClient:
            return "SELECT A CLIENT"
        case .projectFormName:
            return "NAME YOUR PROJECT"
        case .projectFormAddTask:
            return "ADD A TASK"
        case .taskFormCrew:
            return "ASSIGN YOUR CREW"
        case .taskFormType:
            return "PICK THE WORK TYPE"
        case .taskFormDate:
            return "SET THE DATE"
        case .taskFormDone:
            return "TAP DONE"
        case .projectFormComplete:
            return "TAP COMPLETE TO CREATE PROJECT"
        case .dragToAccepted:
            return "DRAG YOUR PROJECT TO ACCEPTED"
        case .statusProgressionInProgress:
            return "YOUR CREW STARTED. STATUS UPDATES AUTOMATICALLY."
        case .statusProgressionCompleted:
            return "JOB DONE. NOW CLOSE IT OUT."
        case .projectListSwipe:
            return "SWIPE TO ADVANCE STATUS"
        case .calendarWeek:
            return "YOUR WEEK AT A GLANCE. SCROLL, TAP, RESCHEDULE."
        case .calendarMonthPrompt:
            return "TAP MONTH TO SEE THE BIG PICTURE"
        case .calendarMonth:
            return "PINCH TO EXPAND. TAP A DAY TO SEE DETAILS."

        // Employee Phases
        case .homeOverview:
            return "YOUR JOBS FOR TODAY. TAP TO START."
        case .tapProject:
            return "TAP TO START PROJECT"
        case .projectStarted:
            return "PROJECT STARTED. NOW CHECK THE DETAILS."
        case .longPressDetails:
            return "LONG PRESS FOR PROJECT DETAILS"
        case .addNote:
            return "ADD A NOTE FOR YOUR CREW"
        case .addPhoto:
            return "SNAP A PHOTO OF YOUR WORK"
        case .completeProject:
            return "TAP COMPLETE WHEN YOU'RE DONE"
        case .jobBoardBrowse:
            return "SWIPE TO SEE ALL YOUR JOBS BY STATUS"

        case .completed:
            return "YOU'RE READY."
        }
    }

    // MARK: - Phase Properties

    /// Whether this phase shows a swipe hint indicator
    var showsSwipeHint: Bool {
        switch self {
        case .dragToAccepted, .projectListSwipe, .jobBoardBrowse:
            return true
        default:
            return false
        }
    }

    /// The swipe direction for phases that show a swipe hint
    var swipeDirection: TutorialSwipeDirection? {
        switch self {
        case .dragToAccepted:
            return .right
        case .projectListSwipe:
            return .left
        case .jobBoardBrowse:
            return .left
        default:
            return nil
        }
    }

    /// Whether this phase auto-advances after a delay
    var autoAdvances: Bool {
        switch self {
        case .statusProgressionInProgress, .statusProgressionCompleted:
            return true
        default:
            return false
        }
    }

    /// The delay in seconds before auto-advancing (if applicable)
    var autoAdvanceDelay: TimeInterval {
        switch self {
        case .statusProgressionInProgress:
            return 2.0
        case .statusProgressionCompleted:
            return 2.0
        default:
            return 0
        }
    }

    /// Whether this phase requires waiting for user action
    var requiresUserAction: Bool {
        switch self {
        case .notStarted, .completed, .statusProgressionInProgress, .statusProgressionCompleted:
            return false
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
            return .createProjectAction
        case .createProjectAction:
            return .projectFormClient
        case .projectFormClient:
            return .projectFormName
        case .projectFormName:
            return .projectFormAddTask
        case .projectFormAddTask:
            return .taskFormCrew
        case .taskFormCrew:
            return .taskFormType
        case .taskFormType:
            return .taskFormDate
        case .taskFormDate:
            return .taskFormDone
        case .taskFormDone:
            return .projectFormComplete
        case .projectFormComplete:
            return .dragToAccepted
        case .dragToAccepted:
            return .statusProgressionInProgress
        case .statusProgressionInProgress:
            return .statusProgressionCompleted
        case .statusProgressionCompleted:
            return .projectListSwipe
        case .projectListSwipe:
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
