# COMPONENT INVENTORY

All new components needed for the tutorial system.

---

## 1. ENVIRONMENT & STATE

### TutorialEnvironment.swift
**Path:** `OPS/Tutorial/Environment/TutorialEnvironment.swift`

**Purpose:** Define environment keys for tutorial mode

```swift
import SwiftUI

struct TutorialModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

struct TutorialPhaseKey: EnvironmentKey {
    static let defaultValue: TutorialPhase? = nil
}

extension EnvironmentValues {
    var tutorialMode: Bool {
        get { self[TutorialModeKey.self] }
        set { self[TutorialModeKey.self] = newValue }
    }

    var tutorialPhase: TutorialPhase? {
        get { self[TutorialPhaseKey.self] }
        set { self[TutorialPhaseKey.self] = newValue }
    }
}
```

---

### TutorialStateManager.swift
**Path:** `OPS/Tutorial/State/TutorialStateManager.swift`

**Purpose:** Central state management for tutorial flow

**Properties:**
- `currentPhase: TutorialPhase` - Current step
- `isActive: Bool` - Whether tutorial is running
- `showSwipeHint: Bool` - Show swipe indicator
- `swipeDirection: SwipeDirection` - Direction for swipe hint
- `currentCutout: CGRect` - Frame for overlay cutout
- `tooltipText: String` - Current instruction text
- `startTime: Date?` - When tutorial started
- `completionTime: TimeInterval?` - How long it took

**Methods:**
- `start()` - Begin tutorial, start timer
- `advancePhase()` - Move to next step
- `complete()` - End tutorial, calculate time
- `setCutout(for:)` - Update overlay cutout position

---

### TutorialPhase.swift
**Path:** `OPS/Tutorial/State/TutorialPhase.swift`

**Purpose:** Enum defining all tutorial steps with tooltip text

**Cases:** (see `02_ARCHITECTURE_PLAN.md` for full list)

---

## 2. VIEW COMPONENTS

### TutorialRootView.swift
**Path:** `OPS/Tutorial/Views/TutorialRootView.swift`

**Purpose:** Root container that orchestrates the entire tutorial

**Properties:**
- `@StateObject tutorialManager: TutorialStateManager`
- `@StateObject demoDataManager: TutorialDemoDataManager`
- `flowType: TutorialFlowType`
- `onComplete: () -> Void`

**Structure:**
```swift
var body: some View {
    ZStack {
        // Current flow view based on phase
        currentFlowView

        // Tooltip at bottom
        VStack {
            Spacer()
            TutorialTooltipView(text: tutorialManager.tooltipText)
                .padding(.bottom, 50)
        }

        // Completion overlay
        if tutorialManager.currentPhase == .completed {
            TutorialCompletionView(manager: tutorialManager, onDismiss: onComplete)
        }
    }
    .onAppear {
        Task {
            try await demoDataManager.seedAllDemoData()
            tutorialManager.start()
        }
    }
    .onDisappear {
        Task {
            try await demoDataManager.cleanupAllDemoData()
        }
    }
}
```

---

### TutorialContainerView.swift
**Path:** `OPS/Tutorial/Views/TutorialContainerView.swift`

**Purpose:** 80% scaled container with proper touch mapping

**Properties:**
- `content: () -> Content` (generic)
- `scale: CGFloat = 0.8`

**Implementation:**
```swift
struct TutorialContainerView<Content: View>: View {
    let content: Content
    let scale: CGFloat

    init(scale: CGFloat = 0.8, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.scale = scale
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .scaleEffect(scale)
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height * 0.7
                )
                .clipped()
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height * 0.35
                )
        }
    }
}
```

---

### TutorialOverlayView.swift
**Path:** `OPS/Tutorial/Views/TutorialOverlayView.swift`

**Purpose:** Dark overlay with interactive cutout

**Properties:**
- `cutoutFrame: CGRect` - Area to reveal
- `cornerRadius: CGFloat = 12`

**Implementation:**
```swift
struct TutorialOverlayView: View {
    let cutoutFrame: CGRect
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Color.black.opacity(0.6)
                .compositingGroup()
                .mask(
                    ZStack {
                        Rectangle()

                        // Cutout
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .frame(width: cutoutFrame.width + 16, height: cutoutFrame.height + 16)
                            .position(x: cutoutFrame.midX, y: cutoutFrame.midY)
                            .blendMode(.destinationOut)
                    }
                )
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.3), value: cutoutFrame)
    }
}
```

---

### TutorialSwipeIndicator.swift
**Path:** `OPS/Tutorial/Views/TutorialSwipeIndicator.swift`

**Purpose:** Slide-to-unlock style shimmer animation

**Properties:**
- `direction: SwipeDirection`
- `targetFrame: CGRect` - Where to show the indicator

**Implementation:**
```swift
struct TutorialSwipeIndicator: View {
    let direction: SwipeDirection
    let targetFrame: CGRect

    @State private var shimmerOffset: CGFloat = -100

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Arrow indicators
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: arrowIcon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .position(x: targetFrame.midX, y: targetFrame.midY)

                // Shimmer gradient
                LinearGradient(
                    colors: [.clear, .white.opacity(0.4), .clear],
                    startPoint: gradientStart,
                    endPoint: gradientEnd
                )
                .frame(width: shimmerWidth, height: shimmerHeight)
                .position(x: shimmerX, y: targetFrame.midY)
                .mask(
                    RoundedRectangle(cornerRadius: 8)
                        .frame(width: targetFrame.width, height: targetFrame.height)
                        .position(x: targetFrame.midX, y: targetFrame.midY)
                )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                shimmerOffset = 200
            }
        }
    }

    private var arrowIcon: String {
        switch direction {
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        }
    }

    // ... gradient helpers based on direction
}
```

---

### TutorialTooltipView.swift
**Path:** `OPS/Tutorial/Views/TutorialTooltipView.swift`

**Purpose:** TypewriterText tooltip at bottom of screen

**Properties:**
- `text: String`

**Implementation:**
```swift
struct TutorialTooltipView: View {
    let text: String

    @State private var currentText: String = ""

    var body: some View {
        VStack {
            if !text.isEmpty {
                TypewriterText(
                    text,
                    font: OPSStyle.Typography.bodyBold,
                    color: OPSStyle.Colors.primaryText,
                    typingSpeed: 40
                )
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            }
        }
        .frame(height: 80)
        .onChange(of: text) { _, newText in
            currentText = ""
            // TypewriterText handles the animation
        }
    }
}
```

---

### TutorialCompletionView.swift
**Path:** `OPS/Tutorial/Views/TutorialCompletionView.swift`

**Purpose:** Final screen showing completion message and time

**Properties:**
- `@ObservedObject manager: TutorialStateManager`
- `onDismiss: () -> Void`

**Implementation:**
```swift
struct TutorialCompletionView: View {
    @ObservedObject var manager: TutorialStateManager
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Completion message
                if manager.showTimeInCompletion {
                    TypewriterText(
                        "DONE IN \(manager.formattedTime). NOW WE'RE TALKING.",
                        font: OPSStyle.Typography.title,
                        typingSpeed: 25
                    )
                } else {
                    TypewriterText(
                        "DONE. LET'S GET TO WORK.",
                        font: OPSStyle.Typography.title,
                        typingSpeed: 25
                    )
                }

                Spacer()

                // CTA Button
                Button(action: {
                    TutorialHaptics.success()
                    onDismiss()
                }) {
                    Text("LET'S GO")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.white)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .transition(.opacity)
    }
}
```

---

## 3. FLOW ORCHESTRATORS

### CompanyTutorialFlow.swift
**Path:** `OPS/Tutorial/Flows/CompanyTutorialFlow.swift`

**Purpose:** Orchestrate company creator tutorial steps

**Properties:**
- `@ObservedObject tutorialManager: TutorialStateManager`
- `@ObservedObject demoDataManager: TutorialDemoDataManager`

**Responsibilities:**
- Render correct view for each phase
- Handle phase transitions
- Manage cutout positions
- Handle swipe indicator visibility

---

### EmployeeTutorialFlow.swift
**Path:** `OPS/Tutorial/Flows/EmployeeTutorialFlow.swift`

**Purpose:** Orchestrate employee tutorial steps

**Properties:**
- `@ObservedObject tutorialManager: TutorialStateManager`
- `@ObservedObject demoDataManager: TutorialDemoDataManager`
- `currentUserId: String` - To assign user to demo tasks

**Responsibilities:**
- Same as CompanyTutorialFlow
- Plus: Assign current user to demo tasks on start

---

## 4. DATA MANAGERS

### TutorialDemoDataManager.swift
**Path:** `OPS/Tutorial/Data/TutorialDemoDataManager.swift`

**Purpose:** Seed and cleanup demo data

**Methods:**
- `seedAllDemoData()` - Create all Top Gun entities
- `cleanupAllDemoData()` - Delete all DEMO_ prefixed entities
- `assignCurrentUserToTasks(userId:)` - For employee flow

See `03_DEMO_DATA_IMPLEMENTATION.md` for full implementation.

---

## 5. UTILITY COMPONENTS

### TutorialHaptics.swift
**Path:** `OPS/Tutorial/Utilities/TutorialHaptics.swift`

**Purpose:** Centralized haptic feedback

```swift
struct TutorialHaptics {
    static func lightTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func mediumImpact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
```

---

### PreferenceKeys.swift
**Path:** `OPS/Tutorial/Utilities/PreferenceKeys.swift`

**Purpose:** Capture element frames for overlay cutouts

```swift
struct TargetFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension View {
    func tutorialTarget(id: String, phase: TutorialPhase) -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: TargetFramePreferenceKey.self,
                        value: geometry.frame(in: .global)
                    )
            }
        )
    }
}
```

---

## 6. COMPLETE FILE LIST

| File | Purpose | Priority |
|------|---------|----------|
| `TutorialEnvironment.swift` | Environment keys | P0 |
| `TutorialPhase.swift` | Phase enum | P0 |
| `TutorialStateManager.swift` | State management | P0 |
| `TutorialContainerView.swift` | 80% scaled container | P0 |
| `TutorialOverlayView.swift` | Dark overlay with cutout | P0 |
| `TutorialSwipeIndicator.swift` | Shimmer animation | P1 |
| `TutorialTooltipView.swift` | TypewriterText tooltip | P0 |
| `TutorialCompletionView.swift` | Completion screen | P1 |
| `TutorialRootView.swift` | Root orchestrator | P0 |
| `CompanyTutorialFlow.swift` | Company flow logic | P1 |
| `EmployeeTutorialFlow.swift` | Employee flow logic | P1 |
| `TutorialDemoDataManager.swift` | Data seeding | P0 |
| `DemoIDs.swift` | ID constants | P0 |
| `DemoTeamMembers.swift` | Team member data | P0 |
| `DemoClients.swift` | Client data | P0 |
| `DemoTaskTypes.swift` | Task type data | P0 |
| `DemoProjects.swift` | Project data | P0 |
| `TutorialHaptics.swift` | Haptic helper | P2 |
| `PreferenceKeys.swift` | Frame capture | P1 |

**P0** = Must have for MVP
**P1** = Required but can iterate
**P2** = Nice to have, can defer
