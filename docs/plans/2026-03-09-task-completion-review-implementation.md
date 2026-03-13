# Task Completion Review Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Tinder-style swipe card stack for reviewing active tasks (due today or past-due) and marking them complete, cancelled, or rescheduled.

**Architecture:** Reuses the existing SwipeDirection gesture mechanics with a configurable label system. New task-specific card, bio sheet, and reschedule sheet. Entry points in AppHeader (next to payment review) and FAB (new review section). Permission-based filtering: full-access users see all tasks, others see only assigned.

**Tech Stack:** SwiftUI, SwiftData, OPSStyle design system, SchedulingEngine for cascade pushes, CalendarSchedulerSheet for manual reschedule.

**Design doc:** `docs/plans/2026-03-09-task-completion-review-design.md`

---

### Task 1: Make SwipeDirection labels configurable

Currently `SwipeDirection` has hardcoded payment-review labels (CLOSED, SEND REMINDER, etc.). We need task-review labels (COMPLETE, RESCHEDULE, CANCEL) too.

**Files:**
- Modify: `OPS/Views/Review/SwipeDirection.swift`
- Modify: `OPS/Views/Review/SwipeStampOverlay.swift`

**Step 1: Add SwipeActionConfig struct and update SwipeDirection**

In `SwipeDirection.swift`, add a config struct and keep existing properties as defaults:

```swift
/// Configurable labels/icons/colors for swipe directions.
/// Pass to stamp overlay and hint pills to customize per-context.
struct SwipeActionConfig {
    let label: String
    let icon: String
    let color: Color

    // Payment review defaults
    static func paymentConfig(for direction: SwipeDirection) -> SwipeActionConfig {
        SwipeActionConfig(label: direction.label, icon: direction.icon, color: direction.color)
    }

    // Task review configs
    static func taskConfig(for direction: SwipeDirection) -> SwipeActionConfig {
        switch direction {
        case .right:
            return SwipeActionConfig(label: "COMPLETE", icon: "checkmark.circle.fill", color: OPSStyle.Colors.successStatus)
        case .left:
            return SwipeActionConfig(label: "SKIP", icon: "arrow.right.circle", color: OPSStyle.Colors.tertiaryText)
        case .up:
            return SwipeActionConfig(label: "RESCHEDULE", icon: "calendar.badge.clock", color: OPSStyle.Colors.primaryAccent)
        case .down:
            return SwipeActionConfig(label: "CANCEL", icon: "xmark.circle.fill", color: OPSStyle.Colors.errorStatus)
        }
    }
}
```

Leave the existing `SwipeDirection` enum properties unchanged (they serve as payment review defaults).

**Step 2: Update SwipeStampOverlay to accept optional config**

In `SwipeStampOverlay.swift`, add an optional `actionConfig` parameter:

```swift
struct SwipeStampOverlay: View {
    let direction: SwipeDirection
    let progress: CGFloat
    var actionConfig: SwipeActionConfig? = nil

    private var displayLabel: String { actionConfig?.label ?? direction.label }
    private var displayIcon: String { actionConfig?.icon ?? direction.icon }
    private var displayColor: Color { actionConfig?.color ?? direction.color }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(displayColor.opacity(0.2 * Double(progress)))

            VStack(spacing: 8) {
                Image(systemName: displayIcon)
                    .font(.system(size: 48, weight: .bold))
                Text(displayLabel)
                    .font(OPSStyle.Typography.headingBold)
                    .tracking(1.2)
            }
            .foregroundColor(displayColor)
            .opacity(Double(progress))
            .rotationEffect(.degrees(direction.stampRotation))
        }
        .allowsHitTesting(false)
    }
}
```

**Step 3: Verify existing payment review still works**

`ProjectReviewCardStack` passes no `actionConfig` to `SwipeStampOverlay`, so it falls back to `direction.label`/etc. — no change needed.

**Step 4: Build**

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add OPS/Views/Review/SwipeDirection.swift OPS/Views/Review/SwipeStampOverlay.swift
git commit -m "feat: make swipe direction labels configurable for task review"
```

---

### Task 2: Create TaskSwipeCardView

Photo-forward card for tasks, matching the payment review card design.

**Files:**
- Create: `OPS/Views/Review/TaskSwipeCardView.swift`
- Reference: `OPS/Views/Review/SwipeCardView.swift` (follow same pattern)

**Step 1: Create the task card view**

Create `OPS/Views/Review/TaskSwipeCardView.swift`:

```swift
//
//  TaskSwipeCardView.swift
//  OPS
//

import SwiftUI

struct TaskSwipeCardView: View {
    let task: ProjectTask
    let onTap: () -> Void

    @State private var heroImage: UIImage?
    @State private var isLoadingImage = true

    private var scheduledDaysAgo: Int {
        guard let startDate = task.startDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
    }

    private var dateBadgeText: String {
        if scheduledDaysAgo == 0 { return "TODAY" }
        return "\(scheduledDaysAgo) DAY\(scheduledDaysAgo == 1 ? "" : "S") AGO"
    }

    private var dateBadgeColor: Color {
        scheduledDaysAgo >= 7 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.warningStatus
    }

    private var taskColorValue: Color {
        if let hex = task.taskColor, !hex.isEmpty {
            return Color(hex: hex)
        }
        return task.status.color
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background: most recent project photo or fallback
            projectPhoto

            // Bottom gradient overlay for text readability
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                startPoint: .center,
                endPoint: .bottom
            )

            // Task color stripe at top
            VStack {
                taskColorValue
                    .frame(height: 4)
                Spacer()
            }

            // Task info overlay
            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                // Date badge
                Text(dateBadgeText)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(dateBadgeColor))

                // Task name
                Text(task.displayTitle.uppercased())
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                    .lineLimit(2)

                // Project name
                if let projectTitle = task.project?.title {
                    Text(projectTitle.uppercased())
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                // Client name
                if let clientName = task.project?.effectiveClientName, !clientName.isEmpty {
                    Text(clientName.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onAppear { loadHeroImage() }
    }

    // MARK: - Photo

    @ViewBuilder
    private var projectPhoto: some View {
        if let image = heroImage {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else if isLoadingImage {
            ZStack {
                taskGradientFallback
                ProgressView()
                    .tint(.white)
            }
        } else {
            taskGradientFallback
        }
    }

    private var taskGradientFallback: some View {
        LinearGradient(
            colors: [
                taskColorValue.opacity(0.4),
                OPSStyle.Colors.cardBackgroundDark
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }

    // MARK: - Image Loading (from parent project)

    private func loadHeroImage() {
        guard let project = task.project else {
            isLoadingImage = false
            return
        }

        let photos = project.getProjectImages()
        guard let lastPhoto = photos.last else {
            isLoadingImage = false
            return
        }

        let cacheKey = lastPhoto.hasPrefix("//") ? "https:" + lastPhoto : lastPhoto

        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            heroImage = cached
            isLoadingImage = false
            return
        }

        if let loadedImage = ImageFileManager.shared.loadImage(localID: lastPhoto) {
            ImageCache.shared.set(loadedImage, forKey: cacheKey)
            heroImage = loadedImage
            isLoadingImage = false
            return
        }

        guard let url = URL(string: cacheKey) else {
            isLoadingImage = false
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = UIImage(data: data) {
                    ImageCache.shared.set(img, forKey: cacheKey)
                    await MainActor.run {
                        heroImage = img
                        isLoadingImage = false
                    }
                } else {
                    await MainActor.run { isLoadingImage = false }
                }
            } catch {
                await MainActor.run { isLoadingImage = false }
            }
        }
    }
}
```

**Step 2: Build and verify**

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add OPS/Views/Review/TaskSwipeCardView.swift
git commit -m "feat: add TaskSwipeCardView for task completion review"
```

---

### Task 3: Create TaskReviewCardStack

Card stack with 4-direction gestures using task-specific labels. Mirrors `ProjectReviewCardStack` but uses `TaskSwipeCardView` and task-specific action configs.

**Files:**
- Create: `OPS/Views/Review/TaskReviewCardStack.swift`
- Reference: `OPS/Views/Review/ProjectReviewCardStack.swift` (same gesture logic)

**Step 1: Create the task card stack**

Create `OPS/Views/Review/TaskReviewCardStack.swift`:

```swift
//
//  TaskReviewCardStack.swift
//  OPS
//

import SwiftUI

struct TaskReviewCardStack: View {
    let tasks: [ProjectTask]
    let hasCalendarAccess: Bool
    let onSwipe: (ProjectTask, SwipeDirection) -> Void
    let onTapCard: (ProjectTask) -> Void

    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var dragDirection: SwipeDirection? = nil
    @State private var hasTriggeredThresholdHaptic: Bool = false

    private let swipeThreshold: CGFloat = 120
    private let maxVisibleCards: Int = 3

    private func actionConfig(for direction: SwipeDirection) -> SwipeActionConfig {
        SwipeActionConfig.taskConfig(for: direction)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(visibleIndices.reversed().enumerated()), id: \.element) { _, index in
                    let relativeIndex = index - currentIndex

                    ZStack {
                        TaskSwipeCardView(
                            task: tasks[index],
                            onTap: { onTapCard(tasks[index]) }
                        )

                        if index == currentIndex, let direction = dragDirection {
                            SwipeStampOverlay(
                                direction: direction,
                                progress: swipeProgress,
                                actionConfig: actionConfig(for: direction)
                            )
                        }
                    }
                    .frame(
                        width: geometry.size.width - 32,
                        height: min(geometry.size.height - 20, 500)
                    )
                    .scaleEffect(scale(for: relativeIndex))
                    .offset(y: yOffset(for: relativeIndex))
                    .offset(index == currentIndex ? dragOffset : .zero)
                    .rotationEffect(index == currentIndex ? dragRotation : .zero)
                    .zIndex(Double(tasks.count - index))
                    .allowsHitTesting(index == currentIndex)
                    .gesture(index == currentIndex ? dragGesture : nil)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Visible Cards

    private var visibleIndices: [Int] {
        let end = min(currentIndex + maxVisibleCards, tasks.count)
        guard currentIndex < end else { return [] }
        return Array(currentIndex..<end)
    }

    // MARK: - Card Positioning

    private func scale(for relativeIndex: Int) -> CGFloat {
        1.0 - CGFloat(relativeIndex) * 0.05
    }

    private func yOffset(for relativeIndex: Int) -> CGFloat {
        CGFloat(relativeIndex) * 12
    }

    private var dragRotation: Angle {
        .degrees(Double(dragOffset.width) / 20)
    }

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

                let magnitude = max(abs(value.translation.width), abs(value.translation.height))
                if magnitude >= swipeThreshold && !hasTriggeredThresholdHaptic {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    hasTriggeredThresholdHaptic = true
                } else if magnitude < swipeThreshold {
                    hasTriggeredThresholdHaptic = false
                }
            }
            .onEnded { value in
                hasTriggeredThresholdHaptic = false
                let translation = value.translation
                let direction = computeDirection(from: translation)
                let magnitude = max(abs(translation.width), abs(translation.height))

                if magnitude > swipeThreshold, let dir = direction {
                    // Block up swipe without calendar access
                    if dir == .up && !hasCalendarAccess {
                        withAnimation(.spring()) {
                            dragOffset = .zero
                            dragDirection = nil
                        }
                        return
                    }

                    commitSwipe(dir)
                } else {
                    withAnimation(.spring()) {
                        dragOffset = .zero
                        dragDirection = nil
                    }
                }
            }
    }

    private func commitSwipe(_ direction: SwipeDirection) {
        let flyAway = flyAwayOffset(for: direction)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.easeIn(duration: 0.25)) {
            dragOffset = flyAway
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let task = tasks[currentIndex]
            currentIndex += 1
            dragOffset = .zero
            dragDirection = nil
            onSwipe(task, direction)
        }
    }

    // MARK: - Direction Detection

    private func computeDirection(from translation: CGSize) -> SwipeDirection? {
        let absW = abs(translation.width)
        let absH = abs(translation.height)
        guard max(absW, absH) > 20 else { return nil }

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

**Step 2: Build and commit**

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Review/TaskReviewCardStack.swift
git commit -m "feat: add TaskReviewCardStack with 4-direction gestures"
```

---

### Task 4: Create TaskBioSheet

Expanded detail view shown on card tap. Shows task info, photo carousel, team, notes, link to TaskDetailsView.

**Files:**
- Create: `OPS/Views/Review/TaskBioSheet.swift`
- Reference: `OPS/Views/Review/ProjectBioSheet.swift` (same layout concept)

**Step 1: Create the task bio sheet**

Create `OPS/Views/Review/TaskBioSheet.swift`:

```swift
//
//  TaskBioSheet.swift
//  OPS
//

import SwiftUI

struct TaskBioSheet: View {
    let task: ProjectTask
    let onDismiss: () -> Void

    @EnvironmentObject private var dataController: DataController
    @State private var navigateToDetails: Bool = false

    private var taskColorValue: Color {
        if let hex = task.taskColor, !hex.isEmpty {
            return Color(hex: hex)
        }
        return task.status.color
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Photo carousel
                    photoCarousel

                    // Task header
                    taskHeader
                        .padding(.horizontal, 16)

                    // Project info
                    projectInfoSection
                        .padding(.horizontal, 16)

                    // Schedule info
                    scheduleSection
                        .padding(.horizontal, 16)

                    // Team members
                    if !task.teamMembers.isEmpty {
                        teamSection
                            .padding(.horizontal, 16)
                    }

                    // Notes
                    if let notes = task.taskNotes, !notes.isEmpty {
                        notesSection(notes)
                            .padding(.horizontal, 16)
                    }

                    // View full details button
                    viewDetailsButton
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                }
            }
            .background(OPSStyle.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .navigationDestination(isPresented: $navigateToDetails) {
                if let project = task.project {
                    TaskDetailsView(task: task, project: project)
                        .environmentObject(dataController)
                }
            }
        }
    }

    // MARK: - Photo Carousel

    private var photoCarousel: some View {
        Group {
            if let project = task.project {
                let photos = project.getProjectImages()
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos.reversed(), id: \.self) { photoId in
                                PhotoThumbnail(photoIdentifier: photoId, size: CGSize(width: 200, height: 200))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 200)
                }
            }
        }
    }

    // MARK: - Task Header

    private var taskHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Task color bar + status
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(taskColorValue)
                    .frame(width: 4, height: 24)

                Text(task.displayTitle.uppercased())
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Text(task.status.displayName.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(task.status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(task.status.color.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Project Info

    private var projectInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: OPSStyle.Icons.project, title: "PROJECT")

            VStack(alignment: .leading, spacing: 4) {
                if let project = task.project {
                    Text(project.title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(project.effectiveClientName.uppercased())
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "calendar", title: "SCHEDULE")

            VStack(alignment: .leading, spacing: 8) {
                if let startDate = task.startDate {
                    HStack {
                        Text("SCHEDULED")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                        Text(startDate.formatted(date: .abbreviated, time: .omitted))
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }

                HStack {
                    Text("DURATION")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer()
                    Text("\(task.duration) DAY\(task.duration == 1 ? "" : "S")")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Team

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "person.2", title: "TEAM")

            HStack(spacing: -8) {
                ForEach(task.teamMembers.prefix(6), id: \.id) { member in
                    UserAvatar(user: member, size: 36)
                        .overlay(Circle().stroke(OPSStyle.Colors.background, lineWidth: 2))
                }
                if task.teamMembers.count > 6 {
                    Text("+\(task.teamMembers.count - 6)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(width: 36, height: 36)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(OPSStyle.Colors.background, lineWidth: 2))
                }
            }
        }
    }

    // MARK: - Notes

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "note.text", title: "NOTES")

            Text(notes)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }

    // MARK: - View Details Button

    private var viewDetailsButton: some View {
        Button(action: { navigateToDetails = true }) {
            HStack {
                Text("VIEW FULL DETAILS")
                    .font(OPSStyle.Typography.captionBold)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text(title)
                .font(OPSStyle.Typography.captionBold)
        }
        .foregroundColor(OPSStyle.Colors.secondaryText)
    }
}
```

**Step 2: Build and commit**

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Review/TaskBioSheet.swift
git commit -m "feat: add TaskBioSheet for task completion review"
```

---

### Task 5: Create TaskRescheduleSheet

Action sheet shown on up-swipe with push buttons (+1D, +2D, +3D, +1W with cascade) and a RESCHEDULE button that opens CalendarSchedulerSheet.

**Files:**
- Create: `OPS/Views/Review/TaskRescheduleSheet.swift`
- Reference: `OPS/Views/Calendar Tab/DayCanvasView.swift` (bulk action bar push logic)
- Reference: `OPS/Utilities/SchedulingEngine.swift` (calculateCascade, pushByDays)
- Reference: `OPS/Views/Components/Scheduling/CalendarSchedulerSheet.swift`
- Reference: `OPS/Views/Components/Scheduling/CascadePreviewSheet.swift`

**Step 1: Create the reschedule sheet**

Create `OPS/Views/Review/TaskRescheduleSheet.swift`:

```swift
//
//  TaskRescheduleSheet.swift
//  OPS
//

import SwiftUI

struct TaskRescheduleSheet: View {
    let task: ProjectTask
    let onRescheduled: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var dataController: DataController
    @State private var showScheduler: Bool = false
    @State private var showCascadePreview: Bool = false
    @State private var pendingCascadeResult: CascadeResult? = nil
    @State private var pendingNewStart: Date? = nil
    @State private var pendingNewEnd: Date? = nil
    @AppStorage("showCascadePreview") private var cascadePreviewEnabled: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Title
            Text("RESCHEDULE TASK")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.top, 16)

            // Task name
            Text(task.displayTitle.uppercased())
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.top, 4)

            // Current date
            if let startDate = task.startDate {
                Text("Currently: \(startDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.top, 4)
            }

            // Push options
            VStack(spacing: 12) {
                Text("PUSH")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                HStack(spacing: 12) {
                    pushButton(label: "+1D", days: 1)
                    pushButton(label: "+2D", days: 2)
                    pushButton(label: "+3D", days: 3)
                    pushButton(label: "+1W", days: 7)
                }
            }
            .padding(.top, 24)

            // Manual reschedule
            Button(action: { showScheduler = true }) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .medium))
                    Text("RESCHEDULE")
                        .font(OPSStyle.Typography.captionBold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(OPSStyle.Colors.primaryAccent)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            // Cancel
            Button(action: onDismiss) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .sheet(isPresented: $showScheduler) {
            CalendarSchedulerSheet(
                isPresented: $showScheduler,
                itemType: .task,
                currentStartDate: task.startDate,
                currentEndDate: task.endDate,
                onScheduleUpdate: { newStart, newEnd in
                    applyReschedule(newStart: newStart, newEnd: newEnd)
                },
                preselectedTeamMemberIds: Set(task.getTeamMemberIds())
            )
        }
        .sheet(isPresented: $showCascadePreview) {
            if let result = pendingCascadeResult,
               let newStart = pendingNewStart,
               let newEnd = pendingNewEnd {
                CascadePreviewSheet(
                    isPresented: $showCascadePreview,
                    primaryTaskTitle: task.displayTitle,
                    oldStartDate: task.startDate,
                    oldEndDate: task.endDate,
                    newStartDate: newStart,
                    newEndDate: newEnd,
                    cascadeResult: result,
                    onConfirm: {
                        executePushWithCascade(newStart: newStart, newEnd: newEnd, cascade: result)
                    }
                )
            }
        }
    }

    // MARK: - Push Button

    private func pushButton(label: String, days: Int) -> some View {
        Button(action: { handlePush(days: days) }) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 56, height: 44)
                .background(OPSStyle.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
    }

    // MARK: - Push Logic

    private func handlePush(days: Int) {
        let newDates = SchedulingEngine.pushByDays(task: task, days: days)

        // Check for cascade
        if let project = task.project {
            let projectTasks = project.tasks?.filter { $0.deletedAt == nil } ?? []
            let cascadeResult = SchedulingEngine.calculateCascade(
                pushedTaskId: task.id,
                newStartDate: newDates.newStart,
                newEndDate: newDates.newEnd,
                allProjectTasks: projectTasks
            )

            if !cascadeResult.changes.isEmpty && cascadePreviewEnabled {
                pendingCascadeResult = cascadeResult
                pendingNewStart = newDates.newStart
                pendingNewEnd = newDates.newEnd
                showCascadePreview = true
                return
            }

            if !cascadeResult.changes.isEmpty {
                executePushWithCascade(newStart: newDates.newStart, newEnd: newDates.newEnd, cascade: cascadeResult)
                return
            }
        }

        // Simple push — no cascade needed
        applyReschedule(newStart: newDates.newStart, newEnd: newDates.newEnd)
    }

    private func executePushWithCascade(newStart: Date, newEnd: Date, cascade: CascadeResult) {
        // Apply primary task
        task.startDate = newStart
        task.endDate = newEnd
        task.needsSync = true

        // Apply cascade changes
        if let project = task.project {
            let projectTasks = project.tasks?.filter { $0.deletedAt == nil } ?? []
            for change in cascade.changes {
                if let affectedTask = projectTasks.first(where: { $0.id == change.id }) {
                    affectedTask.startDate = change.newStartDate
                    affectedTask.endDate = change.newEndDate
                    affectedTask.needsSync = true
                }
            }
        }

        onRescheduled()
    }

    private func applyReschedule(newStart: Date, newEnd: Date) {
        task.startDate = newStart
        task.endDate = newEnd
        task.needsSync = true
        onRescheduled()
    }
}
```

**Step 2: Build and commit**

Note: `CascadePreviewSheet` may have a slightly different init signature. Read the actual file before implementing:

```bash
# Check CascadePreviewSheet init signature
head -50 "OPS/Views/Components/Scheduling/CascadePreviewSheet.swift"
```

Adjust the `CascadePreviewSheet(...)` call to match the actual init. If the init doesn't match, adapt accordingly — the key is to show the cascade preview before confirming.

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Review/TaskRescheduleSheet.swift
git commit -m "feat: add TaskRescheduleSheet with push cascade support"
```

---

### Task 6: Create TaskCompletionReviewView

Full-screen review view. Mirrors `ProjectPaymentReviewView` structure but for tasks.

**Files:**
- Create: `OPS/Views/Review/TaskCompletionReviewView.swift`

**Step 1: Create the main review view**

Create `OPS/Views/Review/TaskCompletionReviewView.swift`:

```swift
//
//  TaskCompletionReviewView.swift
//  OPS
//

import SwiftUI
import SwiftData

struct TaskCompletionReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var permissionStore: PermissionStore

    let tasks: [ProjectTask]

    @State private var reviewedCount: Int = 0
    @State private var showBio: Bool = false
    @State private var selectedTask: ProjectTask? = nil
    @State private var showCancelConfirmation: Bool = false
    @State private var pendingCancelTask: ProjectTask? = nil
    @State private var showRescheduleSheet: Bool = false
    @State private var pendingRescheduleTask: ProjectTask? = nil
    @State private var showAllDone: Bool = false
    @State private var celebrationScale: CGFloat = 0
    @State private var celebrationOpacity: Double = 0

    private var hasCalendarAccess: Bool {
        permissionStore.can("calendar.edit")
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 8)

                if tasks.isEmpty {
                    noTasksView
                } else if showAllDone {
                    allDoneView
                } else {
                    directionHints
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    TaskReviewCardStack(
                        tasks: tasks,
                        hasCalendarAccess: hasCalendarAccess,
                        onSwipe: handleSwipe,
                        onTapCard: { task in
                            selectedTask = task
                            showBio = true
                        }
                    )

                    Spacer()

                    Text("\(reviewedCount) OF \(tasks.count) REVIEWED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showBio) {
            if let task = selectedTask {
                TaskBioSheet(
                    task: task,
                    onDismiss: { showBio = false }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showRescheduleSheet) {
            if let task = pendingRescheduleTask {
                TaskRescheduleSheet(
                    task: task,
                    onRescheduled: {
                        showRescheduleSheet = false
                        pendingRescheduleTask = nil
                        reviewedCount += 1
                        checkCompletion()
                    },
                    onDismiss: {
                        showRescheduleSheet = false
                        pendingRescheduleTask = nil
                        // Treat as skip — don't increment
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .alert("Cancel Task?", isPresented: $showCancelConfirmation) {
            Button("Keep Active", role: .cancel) {
                pendingCancelTask = nil
                reviewedCount += 1
                checkCompletion()
            }
            Button("Cancel Task", role: .destructive) {
                if let task = pendingCancelTask {
                    executeCancelTask(task)
                    pendingCancelTask = nil
                }
            }
        } message: {
            Text("This will cancel the task. You can reactivate it later if needed.")
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
                Text("TASK REVIEW")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("\(tasks.count) TASK\(tasks.count == 1 ? "" : "S")")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Direction Hints

    private var directionHints: some View {
        HStack(spacing: 12) {
            hintPill(icon: "arrow.left", label: "SKIP", color: OPSStyle.Colors.tertiaryText)
            hintPill(icon: "arrow.right", label: "COMPLETE", color: OPSStyle.Colors.successStatus)
            if hasCalendarAccess {
                hintPill(icon: "arrow.up", label: "RESCHEDULE", color: OPSStyle.Colors.primaryAccent)
            }
            hintPill(icon: "arrow.down", label: "CANCEL", color: OPSStyle.Colors.errorStatus)
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

    // MARK: - No Tasks

    private var noTasksView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundColor(OPSStyle.Colors.successStatus)

            Text("NO TASKS TO REVIEW")
                .font(.custom("Mohave-Bold", size: 24))
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("All tasks are up to date")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Spacer()

            Button(action: { dismiss() }) {
                Text("DISMISS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - All Done

    private var allDoneView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(OPSStyle.Colors.successStatus)
                .scaleEffect(celebrationScale)

            Text("ALL DONE")
                .font(.custom("Mohave-Bold", size: 28))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .opacity(celebrationOpacity)

            Text("All tasks reviewed")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .opacity(celebrationOpacity)

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
            .opacity(celebrationOpacity)
        }
        .onAppear {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                celebrationScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                celebrationOpacity = 1.0
            }
        }
    }

    // MARK: - Swipe Handlers

    private func handleSwipe(_ task: ProjectTask, _ direction: SwipeDirection) {
        reviewedCount += 1

        switch direction {
        case .right:
            executeComplete(task)
        case .left:
            break // Skip
        case .up:
            // Don't increment — reschedule sheet handles it
            reviewedCount -= 1
            pendingRescheduleTask = task
            showRescheduleSheet = true
        case .down:
            // Don't increment — confirmation handles it
            reviewedCount -= 1
            pendingCancelTask = task
            showCancelConfirmation = true
        }

        checkCompletion()
    }

    private func executeComplete(_ task: ProjectTask) {
        guard task.modelContext != nil else { return }
        task.status = .completed
        task.needsSync = true
    }

    private func executeCancelTask(_ task: ProjectTask) {
        guard task.modelContext != nil else { return }
        task.status = .cancelled
        task.needsSync = true
        reviewedCount += 1
        checkCompletion()
    }

    private func checkCompletion() {
        if reviewedCount >= tasks.count {
            withAnimation(.spring().delay(0.3)) {
                showAllDone = true
            }
        }
    }
}
```

**Step 2: Build and commit**

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Review/TaskCompletionReviewView.swift
git commit -m "feat: add TaskCompletionReviewView full-screen review"
```

---

### Task 7: Add task review button to AppHeader

Add the task review button next to the payment review button in the Job Board header.

**Files:**
- Modify: `OPS/Views/Components/Common/AppHeader.swift`

**Step 1: Add parameters**

Add these parameters next to the existing `onPaymentReviewTapped`:

```swift
var onTaskReviewTapped: (() -> Void)? = nil
var taskReviewBadgeCount: Int = 0
```

**Step 2: Add button before payment review button**

In the `if headerType == .jobBoard` block, add the task review button BEFORE the payment review button:

```swift
// Task review button
if let onTaskReviewTapped = onTaskReviewTapped {
    Button(action: onTaskReviewTapped) {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "checklist")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 44, height: 44)
                .background(OPSStyle.Colors.cardBackground)
                .clipShape(Circle())

            if taskReviewBadgeCount > 0 {
                Text("\(taskReviewBadgeCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(OPSStyle.Colors.errorStatus)
                    .clipShape(Capsule())
                    .offset(x: 6, y: -4)
            }
        }
    }
    .buttonStyle(PlainButtonStyle())
}
```

**Step 3: Build and commit**

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Components/Common/AppHeader.swift
git commit -m "feat: add task review button to AppHeader"
```

---

### Task 8: Wire up in JobBoardView

Compute reviewable tasks and connect to the task review sheet.

**Files:**
- Modify: `OPS/Views/JobBoard/JobBoardView.swift`

**Step 1: Add state variables**

Add next to existing payment review state:

```swift
// Task review state
@State private var showTaskReview: Bool = false
@State private var reviewableTasks: [ProjectTask] = []
@State private var reviewableTaskCount: Int = 0
```

**Step 2: Add computeReviewableTasks function**

Add next to existing `computeReviewProjects()`:

```swift
private func computeReviewableTasks() {
    let calendar = Calendar.current
    let endOfToday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())

    let allTasks: [ProjectTask]
    if PermissionStore.shared.hasFullAccess("tasks.view") {
        allTasks = dataController.getAllTasks()
    } else if let userId = dataController.currentUser?.id {
        allTasks = dataController.getAllTasks().filter { task in
            task.getTeamMemberIds().contains(userId)
        }
    } else {
        allTasks = []
    }

    reviewableTasks = allTasks.filter { task in
        task.status == .active
            && task.deletedAt == nil
            && task.startDate != nil
            && task.startDate! < endOfToday
    }
    .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

    reviewableTaskCount = reviewableTasks.count
}
```

Note: Check that `dataController.getAllTasks()` exists. If not, use the appropriate method — read `DataController.swift` to find the correct method name for fetching all tasks.

**Step 3: Update AppHeader call**

Add the task review params:

```swift
AppHeader(
    headerType: .jobBoard,
    onPaymentReviewTapped: (permissionStore.can("projects.edit") || permissionStore.hasFullAccess("projects.view")) ? {
        computeReviewProjects()
        showPaymentReview = true
    } : nil,
    paymentReviewBadgeCount: overdueCount,
    onTaskReviewTapped: {
        computeReviewableTasks()
        showTaskReview = true
    },
    taskReviewBadgeCount: reviewableTaskCount
)
```

**Step 4: Add .task to compute on appear**

Add after the existing `.task { computeReviewProjects() }`:

```swift
.task {
    computeReviewableTasks()
}
```

**Step 5: Add sheet**

Add after the existing `.sheet(isPresented: $showPaymentReview)`:

```swift
.sheet(isPresented: $showTaskReview) {
    TaskCompletionReviewView(tasks: reviewableTasks)
        .environmentObject(appState)
        .environmentObject(permissionStore)
}
```

**Step 6: Build and commit**

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/JobBoard/JobBoardView.swift
git commit -m "feat: wire task review into JobBoardView with AppHeader button"
```

---

### Task 9: Add review section to FloatingActionMenu

Add a "REVIEW" section below the existing creation groups with both task review and payment review entries.

**Files:**
- Modify: `OPS/Views/Components/FloatingActionMenu.swift`

**Step 1: Add state variables**

Add to the existing `@State` properties in `FloatingActionMenu`:

```swift
@State private var showTaskReview: Bool = false
@State private var showPaymentReview: Bool = false
```

**Step 2: Add REVIEW group to menuGroups**

After the last `FABMenuGroup` (scheduling), add:

```swift
FABMenuGroup(id: "review", title: "REVIEW", items: [
    FABMenuItem(
        id: "task-review",
        icon: "checklist",
        label: "Task Review",
        permission: nil,
        disabledInTutorial: true,
        action: {
            showCreateMenu = false
            showTaskReview = true
        }
    ),
    FABMenuItem(
        id: "payment-review",
        icon: "rectangle.stack.fill",
        label: "Payment Review",
        permission: "projects.edit",
        disabledInTutorial: true,
        action: {
            showCreateMenu = false
            showPaymentReview = true
        }
    ),
]),
```

**Step 3: Add sheets**

Add `.sheet` modifiers to the FAB view body (after existing sheets):

```swift
.sheet(isPresented: $showTaskReview) {
    TaskCompletionReviewView(tasks: computeFABReviewableTasks())
        .environmentObject(appState)
        .environmentObject(PermissionStore.shared)
}
.sheet(isPresented: $showPaymentReview) {
    ProjectPaymentReviewView(
        overdueProjects: computeFABOverdueProjects(),
        completedProjects: computeFABCompletedProjects()
    )
    .environmentObject(appState)
    .environmentObject(PermissionStore.shared)
}
```

**Step 4: Add compute functions**

Add private helper functions to `FloatingActionMenu`:

```swift
private func computeFABReviewableTasks() -> [ProjectTask] {
    let calendar = Calendar.current
    let endOfToday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())

    let allTasks: [ProjectTask]
    if PermissionStore.shared.hasFullAccess("tasks.view") {
        allTasks = dataController.getAllTasks()
    } else if let userId = dataController.currentUser?.id {
        allTasks = dataController.getAllTasks().filter { task in
            task.getTeamMemberIds().contains(userId)
        }
    } else {
        allTasks = []
    }

    return allTasks.filter { task in
        task.status == .active
            && task.deletedAt == nil
            && task.startDate != nil
            && task.startDate! < endOfToday
    }
    .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
}

private func computeFABOverdueProjects() -> [Project] {
    let allProjects = dataController.getProjects()
    let threshold: Int
    if let companyId = dataController.currentUser?.companyId,
       let company = dataController.getCompany(id: companyId) {
        threshold = company.overdueReviewThresholdDays
    } else {
        threshold = 14
    }
    return OverdueProjectDetector.overdueProjects(from: allProjects, thresholdDays: threshold)
}

private func computeFABCompletedProjects() -> [Project] {
    return dataController.getProjects().filter { $0.status == .completed }
}
```

Note: Check that `dataController.getAllTasks()` exists. Read `DataController.swift` to find the correct method name.

**Step 5: Build and commit**

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Components/FloatingActionMenu.swift
git commit -m "feat: add review section to FAB with task and payment review"
```

---

### Task 10: Final build verification

**Files:** None (verification only)

**Step 1: Full build**

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

**Step 2: Verify all new files exist**

```bash
ls -la OPS/Views/Review/Task*.swift
```

Expected: `TaskSwipeCardView.swift`, `TaskReviewCardStack.swift`, `TaskCompletionReviewView.swift`, `TaskBioSheet.swift`, `TaskRescheduleSheet.swift`

**Step 3: Verify git status is clean**

```bash
git status
```

All new files should be committed across Tasks 1-9.
