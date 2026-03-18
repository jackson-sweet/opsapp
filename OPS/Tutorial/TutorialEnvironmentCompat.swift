// Backwards-compatibility stubs for old tutorial environment values.
// These are referenced by real views that still have old tutorial code.
// DELETE THIS FILE after Chunk 5 cleanup strips tutorial code from all real views.

import SwiftUI

// MARK: - Environment Keys (stubs)

private struct TutorialModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct TutorialPhaseKey: EnvironmentKey {
    static let defaultValue: OldTutorialPhase? = nil
}

extension EnvironmentValues {
    var tutorialMode: Bool {
        get { self[TutorialModeKey.self] }
        set { self[TutorialModeKey.self] = newValue }
    }

    var tutorialPhase: OldTutorialPhase? {
        get { self[TutorialPhaseKey.self] }
        set { self[TutorialPhaseKey.self] = newValue }
    }
}

// Minimal stub of the old TutorialPhase enum so existing views compile.
// This is NOT used by the new tutorial — it's purely for backwards compat.
// Stub for TutorialHighlightStyle referenced by UniversalJobBoardCard.
enum TutorialHighlightStyle {
    static let color = OPSStyle.Colors.primaryAccent
    static let pulseDuration: Double = 1.0
    static let lineWidth: CGFloat = 2.0
    static let pulseOpacity: (min: Double, max: Double) = (min: 0.3, max: 0.8)
}

// TutorialHaptics compat methods (.error, .lightTap, .light) are in TutorialHaptics.swift

// Stub for TutorialLauncherView referenced by OnboardingContainer.
// DELETE after Chunk 5 cleanup rewires entry points.
enum TutorialFlowType {
    case companyCreator, employee
}

struct TutorialLauncherView: View {
    var flowType: TutorialFlowType = .companyCreator
    var isPreSignup: Bool = false
    var onComplete: (() -> Void)?
    var body: some View {
        TutorialFlowView(onComplete: { onComplete?() })
    }
    static func detectFlowType(for user: User?) -> TutorialFlowType {
        return .companyCreator
    }
}

// Stub for TutorialInputHighlight used in ProjectFormSheet and TaskFormSheet.
// DELETE after Chunk 5 cleanup.
struct TutorialInputHighlight: ViewModifier {
    let isHighlighted: Bool
    var animatePulse: Bool = false
    var labelColor: Color { Color.clear }
    var borderColor: Color { Color.clear }
    func body(content: Content) -> some View {
        content
    }
}

struct TutorialPulseModifier: ViewModifier {
    var isHighlighted: Bool = false
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func tutorialHighlight(for phase: OldTutorialPhase, cornerRadius: CGFloat = 4) -> some View {
        self.modifier(TutorialInputHighlight(isHighlighted: false))
    }
    func tutorialHighlight(for phase: OldTutorialPhase, cornerRadius: CGFloat = 4, animatePulse: Bool = false) -> some View {
        self.modifier(TutorialInputHighlight(isHighlighted: false, animatePulse: animatePulse))
    }
}

enum OldTutorialPhase: Int {
    case notStarted = 0
    case jobBoardIntro = 1
    case fabTap = 2
    case createProjectAction = 3
    case projectFormClient = 4
    case projectFormName = 5
    case projectFormAddTask = 6
    case taskFormType = 7
    case taskFormCrew = 8
    case taskFormDate = 9
    case taskFormDone = 10
    case projectFormComplete = 11
    case dragToAccepted = 12
    case projectListStatusDemo = 13
    case projectListSwipe = 14
    case closedProjectsScroll = 15
    case calendarWeek = 16
    case calendarMonthPrompt = 17
    case calendarMonth = 18
    case tutorialSummary = 19
    case completed = 20
    case homeOverview = 21
    case tapProject = 22
    case projectStarted = 23
    case tapDetails = 24
    case addNote = 25
    case addPhoto = 26
    case completeProject = 27
    case jobBoardBrowse = 28
    case pipelineOverview = 29
    case estimatesOverview = 30
    case invoicesOverview = 31
}
