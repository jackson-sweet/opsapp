# Guided Tour - Technical Specification

**Status**: Planning Phase
**Created**: January 23, 2025
**Updated**: November 24, 2025

---

## Overview

Technical architecture and implementation details for the guided tour system.

---

## Architecture

### Component Structure
```
TourManager (Singleton)
├── TourCoordinator (Manages tour lifecycle)
├── TourStepProvider (Provides step content)
├── TourOverlayView (UI presentation)
├── TourStorage (Persistence)
└── TourAnalytics (Event tracking)
```

### State Management
- Use `@Observable` or `@StateObject` for reactive UI
- Store tour progress in UserDefaults
- No Bubble sync (local-only preference)

---

## Data Models

### Tour
```swift
struct Tour: Identifiable {
    let id: String
    let name: String
    let targetRole: UserRole
    let steps: [TourStep]
    let estimatedDuration: TimeInterval
    let recoveryStrategy: TourRecoveryStrategy
}
```

### TourStep (Intent/Action Pattern)
```swift
/// Each step is composed of one or more intents that execute in sequence
struct TourStep: Identifiable {
    let id: String
    let intents: [TourIntent]
    let canSkip: Bool
    let tags: Set<TourTag>
}

/// Intents define WHAT happens, separated from HOW
enum TourIntent {
    // Navigation
    case navigate(to: TourTarget)

    // UI Highlighting
    case highlight(target: TourTarget, padding: CGFloat = 8)

    // Content Display
    case showMessage(title: String, body: String)
    case showTooltip(message: String, position: TooltipPosition)

    // Gesture Demonstrations
    case demonstrateGesture(GestureAnimation)

    // User Interaction
    case awaitTap(onTarget: TourTarget?)  // nil = anywhere
    case awaitNextButton

    // Timing
    case delay(seconds: TimeInterval)
}

/// Gesture animations for demonstration steps
enum GestureAnimation {
    case swipeLeft
    case swipeRight
    case tap
    case longPress(duration: TimeInterval)
    case pinch(direction: PinchDirection)

    enum PinchDirection {
        case `in`, out
    }
}

/// Tooltip positioning relative to target
enum TooltipPosition {
    case above, below, leading, trailing, automatic
}
```

### TourTarget
```swift
enum TourTarget {
    case viewIdentifier(String)  // View with .accessibilityIdentifier()
    case tabBarItem(TabItem)
    case coordinates(CGRect)     // Fallback for dynamic elements
    case fullScreen              // No spotlight, full overlay
}
```

### TourState
```swift
struct TourState {
    var currentTourId: String?
    var currentStepIndex: Int
    var isActive: Bool
    var completedTours: Set<String>
    var lastShownDate: Date?
}
```

### TourTag
```swift
/// Tags for filtering and organizing tour steps
enum TourTag: String, CaseIterable {
    // User roles
    case officeRole, fieldRole, adminRole

    // Screens
    case home, jobBoard, calendar, settings

    // Features
    case navigation, gestures, statusUpdates
    case projectManagement, taskManagement

    // Tour phase
    case onboarding
}
```

---

## Type Guards

Centralized validation functions for tour logic. Keep in `TourGuards.swift`.

```swift
// MARK: - Tour Display Guards

/// Should we show the onboarding tour for this user?
func shouldShowOnboardingTour(user: User?, completedTours: Set<String>) -> Bool {
    guard let user = user else { return false }

    let tourId = tourIdForRole(user.role)
    return !completedTours.contains(tourId)
}

/// Get the appropriate tour ID for a user role
func tourIdForRole(_ role: UserRole) -> String {
    switch role {
    case .admin, .officeCrew:
        return "office_onboarding"
    case .fieldCrew:
        return "field_onboarding"
    }
}

// MARK: - Skip Guards

/// Can user skip without confirmation dialog?
func canSkipWithoutConfirmation(currentStep: Int, totalSteps: Int) -> Bool {
    let progressPercent = Double(currentStep) / Double(totalSteps)
    return progressPercent < 0.5  // No confirmation if less than 50% complete
}

// MARK: - Step Guards

/// Is this a gesture demonstration step?
func isGestureStep(_ step: TourStep) -> Bool {
    step.intents.contains { intent in
        if case .demonstrateGesture = intent { return true }
        return false
    }
}

/// Does this step require navigation?
func requiresNavigation(_ step: TourStep) -> Bool {
    step.intents.contains { intent in
        if case .navigate = intent { return true }
        return false
    }
}

// MARK: - Target Guards

/// Can we locate this target in the current view hierarchy?
func canLocateTarget(_ target: TourTarget, in viewHierarchy: UIView?) -> Bool {
    guard let view = viewHierarchy else { return false }

    switch target {
    case .viewIdentifier(let id):
        return view.accessibilityIdentifier == id ||
               view.subviews.contains { canLocateTarget(target, in: $0) }
    case .tabBarItem:
        return true  // Tab bar always accessible
    case .coordinates:
        return true  // Coordinates always valid
    case .fullScreen:
        return true
    }
}
```

---

## Error Recovery Strategy

Handle edge cases gracefully without crashing or confusing users.

```swift
struct TourRecoveryStrategy {
    /// Steps that are safe to restart from (e.g., after each screen transition)
    let checkpointSteps: Set<Int>

    /// How to handle different failure types
    let fallbackBehavior: TourFallback

    /// Max retries before giving up
    let maxRetries: Int

    static let `default` = TourRecoveryStrategy(
        checkpointSteps: [0, 3, 6, 9],  // After each major section
        fallbackBehavior: .skipToNextCheckpoint,
        maxRetries: 2
    )
}

enum TourFallback {
    /// Skip the problematic step and continue
    case skipStep

    /// Jump to next checkpoint step
    case skipToNextCheckpoint

    /// End tour gracefully with message
    case endTourGracefully(message: String)

    /// Restart from beginning
    case restartTour
}

/// Errors that can occur during tour execution
enum TourError: Error {
    case targetNotFound(TourTarget)
    case navigationFailed(to: TourTarget)
    case gestureAnimationFailed
    case unexpectedState(String)
    case userCancelled

    var recoveryAction: TourFallback {
        switch self {
        case .targetNotFound:
            return .skipStep
        case .navigationFailed:
            return .skipToNextCheckpoint
        case .gestureAnimationFailed:
            return .skipStep
        case .unexpectedState:
            return .endTourGracefully(message: "Tour ended unexpectedly. You can restart from Settings → Help.")
        case .userCancelled:
            return .endTourGracefully(message: "")
        }
    }
}
```

### Recovery Flow
```swift
// In TourCoordinator
func executeStep(_ step: TourStep) async {
    var retries = 0

    while retries < recoveryStrategy.maxRetries {
        do {
            try await performStepIntents(step.intents)
            return  // Success
        } catch let error as TourError {
            retries += 1

            if retries >= recoveryStrategy.maxRetries {
                handleRecovery(error.recoveryAction)
                return
            }

            // Brief delay before retry
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }
}

func handleRecovery(_ fallback: TourFallback) {
    switch fallback {
    case .skipStep:
        advanceToNextStep()
    case .skipToNextCheckpoint:
        advanceToNextCheckpoint()
    case .endTourGracefully(let message):
        endTour(withMessage: message)
    case .restartTour:
        restartFromBeginning()
    }
}
```

---

## UI Components (Atomic Design)

### Atoms (Smallest units)

```swift
/// Single progress dot
struct TourProgressDot: View {
    let isActive: Bool
    let isCompleted: Bool
}

/// Standard tour button
struct TourButton: View {
    let title: String
    let style: TourButtonStyle  // .primary, .secondary, .skip
    let action: () -> Void
}

/// Spotlight mask shape
struct SpotlightMask: Shape {
    let targetFrame: CGRect
    let padding: CGFloat
    let cornerRadius: CGFloat
}
```

### Molecules (Composed atoms)

```swift
/// Tooltip with title, message, and action buttons
struct TourTooltip: View {
    let title: String?
    let message: String
    let position: TooltipPosition
    let showNextButton: Bool
    let showSkipButton: Bool
    let onNext: () -> Void
    let onSkip: () -> Void
}

/// Row of progress dots
struct TourProgressIndicator: View {
    let totalSteps: Int
    let currentStep: Int
}

/// Animated hand for gesture demonstrations
struct GestureAnimationView: View {
    let gesture: GestureAnimation
    let isAnimating: Bool
}
```

### Organisms (Complete sections)

```swift
/// Complete tour step view with spotlight + tooltip
struct TourStepView: View {
    let step: TourStep
    let targetFrame: CGRect?
    let currentStepIndex: Int
    let totalSteps: Int
    let onNext: () -> Void
    let onSkip: () -> Void
}

/// Full-screen welcome overlay
struct TourWelcomeSheet: View {
    let tourName: String
    let estimatedDuration: TimeInterval
    let onStart: () -> Void
    let onSkip: () -> Void
}

/// Completion celebration screen
struct TourCompletionSheet: View {
    let tourName: String
    let onDismiss: () -> Void
}
```

---

## Analytics Events

Track tour engagement for improvement (Priority 3 - implement after core functionality).

```swift
enum TourAnalyticsEvent {
    // Lifecycle
    case tourStarted(tourId: String, userRole: UserRole)
    case tourCompleted(tourId: String, duration: TimeInterval)
    case tourSkipped(tourId: String, atStep: Int, totalSteps: Int)
    case tourAbandoned(tourId: String, atStep: Int, reason: AbandonReason)

    // Step engagement
    case stepViewed(tourId: String, stepIndex: Int, stepId: String)
    case stepSkipped(tourId: String, stepIndex: Int)

    // Gesture demonstrations
    case gestureDemo(gestureType: String, watched: Bool)

    // Errors
    case tourError(tourId: String, error: String, recovered: Bool)
}

enum AbandonReason: String {
    case userSkipped
    case appBackgrounded
    case navigationInterrupted
    case error
}

/// Single handler for all tour analytics
class TourAnalytics {
    static let shared = TourAnalytics()

    func track(_ event: TourAnalyticsEvent) {
        // Log locally
        print("[TourAnalytics] \(event)")

        // Future: send to analytics service
    }
}
```

---

## Persistence

### UserDefaults Keys
```swift
enum TourStorageKeys {
    static let hasCompletedTour = "tour_completed_"
    static let currentTourProgress = "tour_progress"
    static let tourLastDismissedDate = "tour_dismissed_date"
    static let neverShowTours = "tour_never_show"
}
```

### Storage Schema
```json
{
  "completedTours": ["office_onboarding", "field_onboarding"],
  "currentProgress": {
    "tourId": "office_onboarding",
    "stepIndex": 3
  },
  "preferences": {
    "neverShowAgain": false,
    "lastDismissed": "2025-01-23T10:30:00Z"
  }
}
```

---

## Integration Points

### App Launch
```swift
// In OPSApp.swift or main ContentView
.onAppear {
    if shouldShowOnboardingTour(user: currentUser, completedTours: tourStorage.completedTours) {
        tourManager.startTour(tourIdForRole(currentUser.role))
    }
}
```

### Settings Integration
```swift
// In SettingsView → Help section
Button("Take Tour Again") {
    tourManager.startTour(tourIdForRole(currentUser.role), force: true)
}
```

---

## Animation & Transitions

### Overlay Appearance
- Fade in: 0.3s ease-out
- Spotlight move: 0.4s ease-in-out
- Tooltip slide: 0.25s ease-out

### Step Transitions
- Crossfade between tooltips: 0.2s
- Spotlight move to new target: 0.4s
- Smooth, not jarring

### Tactical Principles
- Minimal animation
- Purposeful movement only
- No spinners or loading states

---

## Accessibility

### VoiceOver Support
- Announce tour step content
- Clear focus order (tooltip → next button → skip button)
- Dismiss with escape gesture

### Dynamic Type
- Respect user font size preferences
- Adjust tooltip size accordingly
- Minimum readable size for field use

### Touch Targets
- Next button: Minimum 56x56pt
- Skip button: Minimum 44x44pt
- Ensure usable with gloves

---

## Performance Considerations

### Memory
- Lazy load tour content
- Release overlay when not in use
- Minimal impact on app performance

### Battery
- No continuous animations
- Use static overlays where possible
- Efficient rendering

---

## Testing Strategy

### Unit Tests
- Tour state management
- Step progression logic
- Type guards
- Error recovery paths
- Intent execution

### UI Tests
- Tour appearance and dismissal
- Step navigation
- Skip functionality
- Gesture animation display

### Manual Testing
- Test on all user roles
- Verify in bright sunlight
- Test with gloves
- Verify on older devices
- Test error recovery scenarios

---

## Resolved Technical Questions

1. **Spotlight Implementation**: SwiftUI overlay with `.mask()` - simpler, native approach
2. **Target Identification**: `.accessibilityIdentifier()` on target views, coordinates as fallback
3. **Animation Library**: Built-in SwiftUI animations - no external dependencies
4. **State Restoration**: No resume after backgrounding (tours are short, restart is fine)
5. **Localization**: English only for v1, structure supports future localization

---

## Dependencies

### Existing Components
- OPSStyle system (colors, typography, layout)
- Existing navigation structure

### New Components Needed
- TourManager
- TourCoordinator
- TourOverlayView (organism)
- TourTooltip (molecule)
- TourProgressIndicator (molecule)
- GestureAnimationView (molecule)
- TourButton (atom)
- SpotlightMask (atom)
- TourGuards (utilities)
- TourAnalytics (utilities)

---

## Implementation Phases

### Phase 1: Foundation (Priority 1)
- Tour data models with Intent/Action pattern
- Type guards
- State management
- Persistence layer
- Error recovery strategy

### Phase 2: UI Components (Priority 1)
- Atoms: TourButton, SpotlightMask, TourProgressDot
- Molecules: TourTooltip, TourProgressIndicator, GestureAnimationView
- Organisms: TourStepView, TourWelcomeSheet, TourCompletionSheet

### Phase 3: Content & Logic (Priority 1)
- Tour step definitions (Office and Field tours)
- TourCoordinator implementation
- Integration with app flow
- Mock data for field tour

### Phase 4: Polish & Testing (Priority 2)
- Animations
- Accessibility
- Error recovery testing
- User testing

### Phase 5: Analytics (Priority 3)
- TourAnalytics implementation
- Event tracking integration
- Dashboard/reporting (future)

---

## Notes

- Prioritize simplicity and maintainability
- Follow OPS code patterns and conventions
- Use SwiftData defensive patterns
- Extensive logging for debugging
- Two tours only: Office/Admin and Field Crew
- No over-engineering for hypothetical future needs
