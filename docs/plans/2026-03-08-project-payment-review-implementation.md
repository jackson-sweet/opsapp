# Project Payment Review (Tinder Swipe) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Tinder-style card stack for reviewing completed projects overdue for payment, with directional swipe actions and push notifications.

**Architecture:** Hybrid approach — local SwiftData detection computes the overdue queue on-the-fly, SwiftUI card stack with 4-directional drag gestures, backend push notifications via OneSignal/Supabase for reliable delivery.

**Tech Stack:** SwiftUI, SwiftData, MapKit (existing), OneSignal (existing), Supabase edge functions (notifications)

**Design Doc:** `docs/plans/2026-03-08-project-payment-review-design.md`

---

## Phase 1: Data Layer

### Task 1: Add `completedAt` field to Project model

**Files:**
- Modify: `OPS/DataModels/Project.swift:20-22`

**Step 1:** Add `completedAt` property after `endDate` (line 20), before `status` (line 22):

```swift
var completedAt: Date?
```

**Step 2:** Find where project status is set to `.completed` in the codebase. In `AppState.swift` around the completion flow (lines 66-81) and anywhere `project.status = .completed` is assigned — add:

```swift
project.completedAt = Date()
```

Also ensure that if a project is moved BACK from `.completed` (e.g., reopened), `completedAt` is cleared:

```swift
project.completedAt = nil
```

**Step 3:** Check Bubble sync — if `completedAt` needs a BubbleFields constant, add it to `BubbleFields.swift`. Check if Bubble has a corresponding field or if this is local-only for now.

---

### Task 2: Add company settings fields for review threshold

**Files:**
- Modify: `OPS/DataModels/Company.swift:60-87`

**Step 1:** Add new settings fields in the Company model settings section (after line 87):

```swift
// Project Payment Review settings
var overdueReviewThresholdDays: Int = 14
var overdueReminderFrequencyDays: Int = 7
var matchInvoicePaymentTerms: Bool = false
```

---

### Task 3: Add `writtenOff` case to InvoiceStatus

**Files:**
- Modify: `OPS/DataModels/Enums/FinancialEnums.swift:30-49`

**Step 1:** Add new case to `InvoiceStatus` enum after `void`:

```swift
case writtenOff = "written_off"
```

**Step 2:** Add display name in `displayName` property:

```swift
case .writtenOff: return "Written Off"
```

**Step 3:** Update any `switch` statements on `InvoiceStatus` that need the new case.

---

### Task 4: Add `projectPaymentReview` notification category

**Files:**
- Modify: `OPS/Utilities/NotificationManager.swift:17-26` (enum)
- Modify: `OPS/Utilities/NotificationManager.swift:111-201` (setup method)

**Step 1:** Add new case to NotificationCategory enum (after line 25):

```swift
case projectPaymentReview = "PROJECT_PAYMENT_REVIEW_NOTIFICATION"
```

**Step 2:** Add category setup in `setupNotificationCategories()` method (after project completion category, ~line 181):

```swift
let reviewAction = UNNotificationAction(
    identifier: "REVIEW_PROJECTS",
    title: "Review Now",
    options: [.foreground]
)
let paymentReviewCategory = UNNotificationCategory(
    identifier: NotificationCategory.projectPaymentReview.rawValue,
    actions: [reviewAction],
    intentIdentifiers: [],
    options: []
)
```

Add `paymentReviewCategory` to the categories set passed to `setNotificationCategories()`.

---

## Phase 2: Overdue Detection

### Task 5: Create OverdueProjectDetector utility

**Files:**
- Create: `OPS/Utilities/OverdueProjectDetector.swift`

**Step 1:** Create the detector that computes the overdue queue:

```swift
import SwiftData
import Foundation

/// Computes the list of projects that are completed but overdue for payment review.
/// No persistence — recomputed on demand from SwiftData.
struct OverdueProjectDetector {

    /// Returns projects that have been in `.completed` status longer than the threshold.
    static func overdueProjects(
        from projects: [Project],
        thresholdDays: Int = 14
    ) -> [Project] {
        let now = Date()
        let calendar = Calendar.current

        return projects
            .filter { $0.status == .completed }
            .filter { project in
                guard let completedAt = project.completedAt else {
                    // No completedAt — use endDate as fallback, or include if no date at all
                    if let endDate = project.endDate {
                        let daysSince = calendar.dateComponents([.day], from: endDate, to: now).day ?? 0
                        return daysSince >= thresholdDays
                    }
                    return true // No date info — include for safety
                }
                let daysSince = calendar.dateComponents([.day], from: completedAt, to: now).day ?? 0
                return daysSince >= thresholdDays
            }
            .sorted { ($0.completedAt ?? $0.endDate ?? .distantPast) < ($1.completedAt ?? $1.endDate ?? .distantPast) }
    }

    /// Number of days since project was completed
    static func daysSinceCompleted(_ project: Project) -> Int {
        let referenceDate = project.completedAt ?? project.endDate ?? Date()
        return Calendar.current.dateComponents([.day], from: referenceDate, to: Date()).day ?? 0
    }
}
```

---

## Phase 3: Swipe Card UI

### Task 6: Create SwipeCardView (individual Tinder card)

**Files:**
- Create: `OPS/Views/Components/Review/SwipeCardView.swift`

**Step 1:** Build the photo-forward card face:

```swift
import SwiftUI

/// A single Tinder-style card showing a project's most recent photo,
/// name, client, completion date, and optional accounting info.
struct SwipeCardView: View {
    let project: Project
    let daysSinceCompleted: Int
    let showFinancialInfo: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background: most recent project photo or fallback
            projectPhoto

            // Bottom gradient overlay
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                startPoint: .center,
                endPoint: .bottom
            )

            // Project info overlay
            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                // Days overdue badge
                Text("\(daysSinceCompleted) DAYS AGO")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(daysSinceCompleted > 30
                            ? OPSStyle.Colors.errorStatus
                            : OPSStyle.Colors.warningStatus)
                    )

                // Project name
                Text(project.title.uppercased())
                    .font(.custom("Mohave-SemiBold", size: 28))
                    .foregroundColor(.white)
                    .lineLimit(2)

                // Client name
                Text(project.effectiveClientName.uppercased())
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(.white.opacity(0.7))

                // Financial info (if permitted)
                if showFinancialInfo {
                    financialSummary
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Photo

    @ViewBuilder
    private var projectPhoto: some View {
        // Use project's most recent photo if available
        // Check project.images or however photos are stored
        // Fallback to a gradient background with project status color
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: project.status.color).opacity(0.3),
                        OPSStyle.Colors.cardBackgroundDark
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            )
        // TODO: Replace with actual project photo loading
        // AsyncImage or cached image from project's photo gallery
    }

    // MARK: - Financial Summary

    @ViewBuilder
    private var financialSummary: some View {
        HStack(spacing: 16) {
            // TODO: Pull from linked invoices
            VStack(alignment: .leading, spacing: 2) {
                Text("TOTAL")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(.white.opacity(0.5))
                Text("$0.00")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("OWING")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(.white.opacity(0.5))
                Text("$0.00")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }
        }
        .padding(.top, 4)
    }
}
```

**Note:** The photo loading and financial data will need to be wired to actual data sources. Mark with TODO for now and implement when integrating with the full data layer.

---

### Task 7: Create SwipeStampOverlay (directional action indicators)

**Files:**
- Create: `OPS/Views/Components/Review/SwipeStampOverlay.swift`

**Step 1:** Build the stamp overlays that appear during drag:

```swift
import SwiftUI

/// Stamp overlay that appears as user drags a card in a direction.
/// Opacity scales with drag distance for progressive reveal.
struct SwipeStampOverlay: View {
    let direction: SwipeDirection
    let progress: CGFloat // 0.0 to 1.0

    var body: some View {
        ZStack {
            // Tinted background
            RoundedRectangle(cornerRadius: 16)
                .fill(direction.color.opacity(0.15 * progress))

            // Stamp label
            VStack(spacing: 8) {
                Image(systemName: direction.icon)
                    .font(.system(size: 44, weight: .bold))
                Text(direction.label)
                    .font(.custom("Mohave-Bold", size: 24))
            }
            .foregroundColor(direction.color)
            .opacity(Double(progress))
            .rotationEffect(.degrees(direction.stampRotation))
            .padding(direction.stampAlignment == .leading ? .leading : .trailing, 30)
        }
    }
}

/// Swipe directions with associated metadata
enum SwipeDirection {
    case right   // Close (paid)
    case left    // Skip
    case up      // Send reminder
    case down    // Write off

    var label: String {
        switch self {
        case .right: return "CLOSED"
        case .left:  return "SKIP"
        case .up:    return "SEND REMINDER"
        case .down:  return "CLOSE & MARK BAD DEBT"
        }
    }

    var icon: String {
        switch self {
        case .right: return "checkmark.circle.fill"
        case .left:  return "arrow.right.circle"
        case .up:    return "bell.fill"
        case .down:  return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .right: return OPSStyle.Colors.successStatus
        case .left:  return OPSStyle.Colors.tertiaryText
        case .up:    return OPSStyle.Colors.primaryAccent
        case .down:  return OPSStyle.Colors.errorStatus
        }
    }

    var stampRotation: Double {
        switch self {
        case .right: return -15
        case .left:  return 15
        case .up:    return 0
        case .down:  return 0
        }
    }

    var stampAlignment: HorizontalAlignment {
        switch self {
        case .right: return .leading
        case .left:  return .trailing
        case .up, .down: return .center
        }
    }
}
```

---

### Task 8: Create ProjectBioView (expanded card detail — the "bio")

**Files:**
- Create: `OPS/Views/Components/Review/ProjectBioView.swift`

**Step 1:** Build the Tinder-bio-style expanded project detail:

```swift
import SwiftUI

/// Expanded "bio" view shown when tapping a swipe card.
/// Shows photo carousel, team, notes, timeline, invoice status.
struct ProjectBioView: View {
    let project: Project
    let showFinancialInfo: Bool
    let onViewFullProject: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Photo carousel
                photoCarousel

                VStack(alignment: .leading, spacing: 20) {
                    // Project header
                    headerSection

                    Divider().background(OPSStyle.Colors.cardBorder)

                    // Team members
                    teamSection

                    Divider().background(OPSStyle.Colors.cardBorder)

                    // Recent notes
                    notesSection

                    // Financial info
                    if showFinancialInfo {
                        Divider().background(OPSStyle.Colors.cardBorder)
                        financialSection
                    }

                    // View full project button
                    Button(action: onViewFullProject) {
                        Text("VIEW FULL PROJECT")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OPSStyle.Colors.primaryAccent.opacity(0.12))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Sections

    @ViewBuilder
    private var photoCarousel: some View {
        // Horizontal scroll of project photos
        // TODO: Wire to actual project photo data
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(width: 280, height: 200)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        )
                }
            }
        }
        .frame(height: 200)
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title.uppercased())
                .font(.custom("Mohave-SemiBold", size: 28))
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text(project.effectiveClientName.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack(spacing: 12) {
                if let completedAt = project.completedAt {
                    Label {
                        Text("Completed \(completedAt.formatted(date: .abbreviated, time: .omitted))")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Text("\(OverdueProjectDetector.daysSinceCompleted(project)) days ago")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEAM")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Avatar row of team members
            // TODO: Wire to project.teamMembers
            HStack(spacing: -8) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(OPSStyle.Colors.cardBackground)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        )
                        .overlay(Circle().stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: 2))
                }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT NOTES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Last 3 notes
            // TODO: Wire to project notes
            Text("No recent notes")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    @ViewBuilder
    private var financialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INVOICING")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // TODO: Wire to linked invoices
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("$0.00")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("OWING")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("$0.00")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("STATUS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("—")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
    }
}
```

---

### Task 9: Create ProjectReviewCardStack (the draggable card stack)

**Files:**
- Create: `OPS/Views/Components/Review/ProjectReviewCardStack.swift`

**Step 1:** Build the Tinder-style stacked cards with 4-directional drag:

```swift
import SwiftUI

/// Tinder-style card stack with 4-directional swipe.
/// Shows 3 cards with depth/scale stacking. Top card is draggable.
struct ProjectReviewCardStack: View {
    let projects: [Project]
    let hasFinancialAccess: Bool
    let onSwipe: (Project, SwipeDirection) -> Void
    let onTapCard: (Project) -> Void

    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var dragDirection: SwipeDirection? = nil

    private let swipeThreshold: CGFloat = 120
    private let maxVisibleCards: Int = 3

    var body: some View {
        ZStack {
            ForEach(visibleIndices.reversed(), id: \.self) { index in
                let relativeIndex = index - currentIndex
                let project = projects[index]

                ZStack {
                    SwipeCardView(
                        project: project,
                        daysSinceCompleted: OverdueProjectDetector.daysSinceCompleted(project),
                        showFinancialInfo: hasFinancialAccess,
                        onTap: { onTapCard(project) }
                    )

                    // Stamp overlay (top card only)
                    if index == currentIndex, let direction = dragDirection {
                        SwipeStampOverlay(
                            direction: direction,
                            progress: swipeProgress
                        )
                    }
                }
                .frame(height: 480)
                .padding(.horizontal, 16)
                .scaleEffect(scale(for: relativeIndex))
                .offset(y: yOffset(for: relativeIndex))
                .offset(index == currentIndex ? dragOffset : .zero)
                .rotationEffect(index == currentIndex ? dragRotation : .zero)
                .zIndex(Double(projects.count - index))
                .gesture(index == currentIndex ? dragGesture : nil)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
            }
        }
    }

    // MARK: - Visible Cards

    private var visibleIndices: [Int] {
        let end = min(currentIndex + maxVisibleCards, projects.count)
        guard currentIndex < end else { return [] }
        return Array(currentIndex..<end)
    }

    // MARK: - Card Positioning

    private func scale(for relativeIndex: Int) -> CGFloat {
        1.0 - CGFloat(relativeIndex) * 0.05
    }

    private func yOffset(for relativeIndex: Int) -> CGFloat {
        CGFloat(relativeIndex) * 10
    }

    private var dragRotation: Angle {
        .degrees(Double(dragOffset.width) / 20)
    }

    // MARK: - Swipe Progress

    private var swipeProgress: CGFloat {
        let maxDrag = max(abs(dragOffset.width), abs(dragOffset.height))
        return min(maxDrag / swipeThreshold, 1.0)
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                dragDirection = computeDirection(from: value.translation)
            }
            .onEnded { value in
                let translation = value.translation
                let direction = computeDirection(from: translation)
                let magnitude = max(abs(translation.width), abs(translation.height))

                if magnitude > swipeThreshold, let dir = direction {
                    // Check permission for up/down
                    if (dir == .up || dir == .down) && !hasFinancialAccess {
                        // Snap back — no permission
                        withAnimation(.spring()) {
                            dragOffset = .zero
                            dragDirection = nil
                        }
                        return
                    }

                    // Commit swipe
                    let flyAway = flyAwayOffset(for: dir)
                    withAnimation(.easeIn(duration: 0.25)) {
                        dragOffset = flyAway
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onSwipe(projects[currentIndex], dir)
                        currentIndex += 1
                        dragOffset = .zero
                        dragDirection = nil
                    }
                } else {
                    // Snap back
                    withAnimation(.spring()) {
                        dragOffset = .zero
                        dragDirection = nil
                    }
                }
            }
    }

    // MARK: - Direction Detection

    private func computeDirection(from translation: CGSize) -> SwipeDirection? {
        let absW = abs(translation.width)
        let absH = abs(translation.height)

        if absW > absH {
            return translation.width > 0 ? .right : .left
        } else {
            return translation.height < 0 ? .up : .down
        }
    }

    private func flyAwayOffset(for direction: SwipeDirection) -> CGSize {
        switch direction {
        case .right: return CGSize(width: 500, height: 0)
        case .left:  return CGSize(width: -500, height: 0)
        case .up:    return CGSize(width: 0, height: -700)
        case .down:  return CGSize(width: 0, height: 700)
        }
    }
}
```

---

### Task 10: Create ProjectPaymentReviewView (full review screen)

**Files:**
- Create: `OPS/Views/Review/ProjectPaymentReviewView.swift`

**Step 1:** Build the full-screen review view with header, card stack, direction hints, and empty state:

```swift
import SwiftUI
import SwiftData

/// Full-screen Tinder-style project payment review.
/// Presented as a sheet from the Job Board header.
struct ProjectPaymentReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var permissionStore: PermissionStore

    let overdueProjects: [Project]

    @State private var reviewedCount: Int = 0
    @State private var showBio: Bool = false
    @State private var selectedProject: Project? = nil
    @State private var showWriteOffConfirmation: Bool = false
    @State private var pendingWriteOffProject: Project? = nil
    @State private var showAllCaughtUp: Bool = false

    private var hasFinancialAccess: Bool {
        permissionStore.can("finances.view")
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                if overdueProjects.isEmpty || showAllCaughtUp {
                    allCaughtUpView
                } else {
                    // Direction hints
                    directionHints
                        .padding(.top, 8)

                    // Card stack
                    ProjectReviewCardStack(
                        projects: overdueProjects,
                        hasFinancialAccess: hasFinancialAccess,
                        onSwipe: handleSwipe,
                        onTapCard: { project in
                            selectedProject = project
                            showBio = true
                        }
                    )
                    .padding(.top, 8)

                    Spacer()

                    // Counter
                    Text("\(reviewedCount) OF \(overdueProjects.count) REVIEWED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.bottom, 16)
                }
            }
        }
        .sheet(isPresented: $showBio) {
            if let project = selectedProject {
                ProjectBioView(
                    project: project,
                    showFinancialInfo: hasFinancialAccess,
                    onViewFullProject: {
                        showBio = false
                        // TODO: Navigate to ProjectDetailsView
                    },
                    onDismiss: { showBio = false }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .alert("Write Off as Bad Debt?", isPresented: $showWriteOffConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingWriteOffProject = nil
            }
            Button("Write Off & Close", role: .destructive) {
                if let project = pendingWriteOffProject {
                    executeWriteOff(project)
                }
            }
        } message: {
            Text("This will close the project and write off the outstanding balance. This action cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("PAYMENT REVIEW")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("\(overdueProjects.count) OVERDUE")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            // Placeholder for symmetry
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Direction Hints

    private var directionHints: some View {
        HStack(spacing: 16) {
            hintPill(icon: "arrow.left", label: "SKIP", color: OPSStyle.Colors.tertiaryText)
            hintPill(icon: "arrow.right", label: "CLOSE", color: OPSStyle.Colors.successStatus)
            if hasFinancialAccess {
                hintPill(icon: "arrow.up", label: "REMIND", color: OPSStyle.Colors.primaryAccent)
                hintPill(icon: "arrow.down", label: "WRITE OFF", color: OPSStyle.Colors.errorStatus)
            }
        }
        .padding(.horizontal, 16)
    }

    private func hintPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - All Caught Up

    private var allCaughtUpView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(OPSStyle.Colors.successStatus)
            Text("ALL CAUGHT UP")
                .font(.custom("Mohave-Bold", size: 28))
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("No projects need payment review")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()

            Button(action: { dismiss() }) {
                Text("DONE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Swipe Handlers

    private func handleSwipe(_ project: Project, _ direction: SwipeDirection) {
        reviewedCount += 1

        switch direction {
        case .right:
            executeClose(project)
        case .left:
            // Skip — no action, just move to next card
            break
        case .up:
            executeSendReminder(project)
        case .down:
            pendingWriteOffProject = project
            showWriteOffConfirmation = true
        }

        // Check if all reviewed
        if reviewedCount >= overdueProjects.count {
            withAnimation(.spring().delay(0.3)) {
                showAllCaughtUp = true
            }
        }
    }

    private func executeClose(_ project: Project) {
        project.status = .closed
        project.needsSync = true
        // TODO: Mark linked invoices as paid if financial access
    }

    private func executeSendReminder(_ project: Project) {
        // TODO: Create note "Invoice reminder sent" on project
        // TODO: Trigger notification/email to client (future)
    }

    private func executeWriteOff(_ project: Project) {
        project.status = .closed
        project.needsSync = true
        // TODO: Mark linked invoices as writtenOff
        // TODO: Create note "Marked as bad debt" on project
        pendingWriteOffProject = nil
    }
}
```

---

## Phase 4: Integration

### Task 11: Add review button to Job Board header

**Files:**
- Modify: `OPS/Views/JobBoard/JobBoardView.swift:82-139`

**Step 1:** Add state variables for the review sheet and overdue count:

```swift
@State private var showPaymentReview: Bool = false
@State private var overdueProjects: [Project] = []
```

**Step 2:** Add a review button in the header row (near the filter button, around line 104). The button should:
- Show `rectangle.stack.fill` icon
- Display a red badge with overdue count
- Be hidden when count is 0
- Trigger `.sheet(isPresented: $showPaymentReview)`

```swift
// Payment review button — only when overdue projects exist
if !overdueProjects.isEmpty,
   permissionStore.can("projects.manage") || permissionStore.hasFullAccess() {
    Button(action: { showPaymentReview = true }) {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 18))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 44, height: 44)

            // Badge
            Text("\(overdueProjects.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(OPSStyle.Colors.errorStatus)
                .clipShape(Capsule())
                .offset(x: 4, y: -2)
        }
    }
}
```

**Step 3:** Add the sheet modifier and an `.onAppear` / `.task` to compute overdue projects:

```swift
.sheet(isPresented: $showPaymentReview) {
    ProjectPaymentReviewView(overdueProjects: overdueProjects)
        .environmentObject(appState)
        .environmentObject(permissionStore)
}
.task {
    let company = appState.currentCompany
    let threshold = company?.overdueReviewThresholdDays ?? 14
    overdueProjects = OverdueProjectDetector.overdueProjects(
        from: allProjects, // however projects are accessed in this view
        thresholdDays: threshold
    )
}
```

---

### Task 12: Add Settings UI for Project Review

**Files:**
- Find and modify: The company settings view (search for where `preciseSchedulingEnabled` or `skipWeekendsInAutoSchedule` is displayed in a settings form)

**Step 1:** Add a new "PROJECT REVIEW" section to the company settings view:

```swift
// MARK: - Project Review Section

Section {
    // Overdue threshold stepper
    Stepper(value: $company.overdueReviewThresholdDays, in: 7...90) {
        HStack {
            Text("OVERDUE THRESHOLD")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            Text("\(company.overdueReviewThresholdDays) DAYS")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    // Reminder frequency stepper
    Stepper(value: $company.overdueReminderFrequencyDays, in: 1...30) {
        HStack {
            Text("REMINDER FREQUENCY")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            Text("EVERY \(company.overdueReminderFrequencyDays) DAYS")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    // Match invoice payment terms toggle
    HStack {
        Toggle(isOn: .constant(false)) {
            HStack {
                Text("MATCH INVOICE TERMS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(hasFinancialAccess
                        ? OPSStyle.Colors.primaryText
                        : OPSStyle.Colors.tertiaryText)
                if !hasFinancialAccess {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .disabled(!hasFinancialAccess)
    }
} header: {
    Text("PROJECT REVIEW")
        .font(OPSStyle.Typography.captionBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)
}
```

---

### Task 13: Set `completedAt` during status transitions

**Files:**
- Search for all places where `project.status = .completed` is set
- Key locations: `AppState.swift`, any status swipe handlers in `UniversalJobBoardCard.swift`, `DataController.swift`

**Step 1:** At every location where a project transitions TO `.completed`:

```swift
project.completedAt = Date()
```

**Step 2:** At every location where a project transitions AWAY from `.completed` (reopened):

```swift
project.completedAt = nil
```

---

## Phase 5: Notifications (Backend + Local)

### Task 14: Add local notification scheduling for overdue reviews

**Files:**
- Modify: `OPS/Utilities/NotificationManager.swift`

**Step 1:** Add a method to schedule a payment review notification:

```swift
func schedulePaymentReviewNotification(overdueCount: Int, afterDays: Int = 0) {
    let content = UNMutableNotificationContent()
    content.title = "Payment Review Needed"
    content.body = "\(overdueCount) project\(overdueCount == 1 ? "" : "s") overdue for payment"
    content.categoryIdentifier = NotificationCategory.projectPaymentReview.rawValue
    content.sound = .default
    content.userInfo = ["type": "projectPaymentReview"]

    let trigger: UNNotificationTrigger
    if afterDays > 0 {
        let date = Calendar.current.date(byAdding: .day, value: afterDays, to: Date()) ?? Date()
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
        trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    } else {
        trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    }

    let request = UNNotificationRequest(
        identifier: "payment-review-\(UUID().uuidString)",
        content: content,
        trigger: trigger
    )

    UNUserNotificationCenter.current().add(request)
}
```

**Step 2:** Add a method to check and schedule on app launch (call from AppState or app delegate):

```swift
func checkAndSchedulePaymentReviewNotifications(
    overdueCount: Int,
    reminderFrequencyDays: Int
) {
    guard overdueCount > 0 else { return }

    // Check if we've already notified recently
    let lastNotifiedKey = "lastPaymentReviewNotification"
    let lastNotified = UserDefaults.standard.object(forKey: lastNotifiedKey) as? Date

    if let last = lastNotified {
        let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        guard daysSince >= reminderFrequencyDays else { return }
    }

    schedulePaymentReviewNotification(overdueCount: overdueCount)
    UserDefaults.standard.set(Date(), forKey: lastNotifiedKey)
}
```

---

### Task 15: Handle notification deep link to review screen

**Files:**
- Modify: `OPS/Utilities/NotificationManager.swift` (or wherever notification tap handling lives)
- Modify: `OPS/AppState.swift`

**Step 1:** Add a published property to AppState for deep linking:

```swift
@Published var showPaymentReview: Bool = false
```

**Step 2:** In the notification response handler (where `userNotificationCenter(_:didReceive:)` is implemented), add a case for the payment review category:

```swift
case NotificationCategory.projectPaymentReview.rawValue:
    DispatchQueue.main.async {
        appState.showPaymentReview = true
    }
```

**Step 3:** In JobBoardView, observe `appState.showPaymentReview` and present the sheet when true.

---

### Task 16: Add overdue check on app launch

**Files:**
- Modify: `OPS/AppState.swift` or app initialization flow

**Step 1:** After projects are loaded on app launch, compute overdue count and schedule notifications if needed:

```swift
func checkOverdueProjects() {
    guard let company = currentCompany else { return }
    let threshold = company.overdueReviewThresholdDays
    let frequency = company.overdueReminderFrequencyDays

    // Fetch all completed projects (from SwiftData context)
    let overdueCount = OverdueProjectDetector.overdueProjects(
        from: allCompanyProjects,
        thresholdDays: threshold
    ).count

    NotificationManager.shared.checkAndSchedulePaymentReviewNotifications(
        overdueCount: overdueCount,
        reminderFrequencyDays: frequency
    )
}
```

Call this after initial sync completes.

---

## Phase 6: Polish & Edge Cases

### Task 17: Add haptic feedback and animations

**Files:**
- Modify: `OPS/Views/Components/Review/ProjectReviewCardStack.swift`
- Modify: `OPS/Views/Review/ProjectPaymentReviewView.swift`

**Step 1:** Ensure haptics fire at the right moments:
- Light haptic when drag crosses threshold (direction commits)
- Medium haptic on swipe release (action executes)
- Success haptic on "ALL CAUGHT UP" celebration

**Step 2:** Add spring animations to the "ALL CAUGHT UP" state:
- Checkmark scales up from 0
- Text fades in with slight delay
- "DONE" button slides up from bottom

---

### Task 18: Handle edge cases

**Files:**
- Modify: Various files from above

**Edge cases to handle:**
1. **Project deleted while in review** — Check project still exists before applying swipe action
2. **Network offline** — Swipe actions work locally (needsSync = true), sync when back online
3. **Write-off cancelled via alert** — Card should not advance; user confirmed with "Cancel"
4. **Only 1 or 2 projects** — Card stack still works with fewer than 3 visible cards
5. **No photos** — Fallback gradient background on card (already handled in SwipeCardView)
6. **Concurrent sessions** — If two admins review simultaneously, second will see already-closed projects; handle gracefully (show "already closed" toast and auto-skip)

---

## Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| 1. Data Layer | 1-4 | Model fields, enum cases, notification category |
| 2. Detection | 5 | OverdueProjectDetector utility |
| 3. Swipe UI | 6-10 | Card, stamp, bio, stack, full review screen |
| 4. Integration | 11-13 | Job Board button, settings, status transition hooks |
| 5. Notifications | 14-16 | Local scheduling, deep links, app launch check |
| 6. Polish | 17-18 | Haptics, animations, edge cases |

**Total: 18 tasks across 6 phases**
