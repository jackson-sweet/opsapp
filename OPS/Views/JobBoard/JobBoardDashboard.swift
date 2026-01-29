//
//  JobBoardDashboard.swift
//  OPS
//
//  Created by Assistant on 2025-09-26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct JobBoardDashboard: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    @Query private var allProjects: [Project]
    @State private var draggedProject: Project? = nil
    @State private var isDragging = false
    @State private var isLongPressing = false
    @State private var dragLocation: CGPoint = .zero
    @State private var dropZone: DragZone = .center
    @State private var currentPageIndex: Int = 0
    @State private var tutorialArrowOffset: CGFloat = 0
    @State private var tutorialHapticTimer: Timer?
    @State private var illuminatedArrowCount: Int = 0
    @State private var lastHapticArrowCount: Int = 0
    @State private var showingWrongDirectionHint = false
    @State private var showingStayHereToast = false
    @State private var emphasisPressHold = false
    @Namespace private var cardNamespace

    /// Whether current user is field crew
    private var isFieldCrew: Bool {
        dataController.currentUser?.role == .fieldCrew
    }

    /// Status columns to display - field crew only sees Accepted, In Progress, Completed
    private var statuses: [Status] {
        if isFieldCrew {
            return [.accepted, .inProgress, .completed]
        }
        return [.rfq, .estimated, .accepted, .inProgress, .completed]
    }
    private let columnWidth: CGFloat = 280
    private let edgeZoneWidth: CGFloat = 60

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TabView(selection: $currentPageIndex) {
                    ForEach(statuses.indices, id: \.self) { index in
                        StatusColumn(
                            status: statuses[index],
                            projects: projectsForStatus(statuses[index]),
                            draggedProject: draggedProject,
                            targetZone: targetZoneForLocation(dragLocation, geometry: geometry),
                            namespace: cardNamespace,
                            onProjectLongPress: { project in
                                handleLongPress(project: project)
                            },
                            onProjectDragChanged: { project, location in
                                handleDragChanged(project: project, location: location, geometry: geometry)
                            },
                            onProjectDragEnded: { project in
                                handleDragEnded(project: project, geometry: geometry)
                            },
                            onTapBlocked: {
                                triggerPressHoldEmphasis()
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 12)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .allowsHitTesting(!isLongPressing)
                .onChange(of: tutorialPhase) { _, newPhase in
                    // Navigate to estimated column when entering dragToAccepted phase
                    if tutorialMode && newPhase == .dragToAccepted {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            currentPageIndex = statuses.firstIndex(of: .estimated) ?? 1
                        }
                    }
                }
                .onChange(of: currentPageIndex) { _, newValue in
                    // During dragToAccepted, auto-return if user swipes away
                    let estimatedIndex = statuses.firstIndex(of: .estimated) ?? 1
                    if tutorialMode && tutorialPhase == .dragToAccepted && newValue != estimatedIndex {
                        // Show toast and return after delay
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingStayHereToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                currentPageIndex = estimatedIndex
                            }
                            // Trigger emphasis after returning
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                triggerPressHoldEmphasis()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    showingStayHereToast = false
                                }
                            }
                        }
                    }
                }

                if isLongPressing {
                    edgeZones(geometry: geometry)
                        .allowsHitTesting(false)
                        .transition(.opacity)

                    Color.clear
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    print("🚫 Overlay blocking scroll/swipe")
                                }
                        )

                    if let draggedProject = draggedProject {
                        DraggingCardOverlay(
                            project: draggedProject,
                            dragLocation: dragLocation,
                            statusColor: draggedProject.status.color,
                            dropZone: dropZone
                        )
                    }
                }

                pageIndicator

                // Archive zone - hidden for field crew
                if isLongPressing && !isFieldCrew {
                    archiveZone(geometry: geometry)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Tutorial mode: Center directional arrows overlay
                if tutorialMode && tutorialPhase == .dragToAccepted {
                    VStack {
                        Spacer()
                        tutorialCenterArrows
                        Spacer()
                            .frame(height: 200) // Position arrows above page indicator
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Tutorial mode: Wrong direction hint
                if showingWrongDirectionHint {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20, weight: .bold))
                            Text("WRONG WAY! DRAG RIGHT TOWARDS ACCEPTED")
                                .font(OPSStyle.Typography.captionBold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(OPSStyle.Colors.errorStatus)
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 180)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showingWrongDirectionHint)
                    .zIndex(999) // Ensure hint appears above other content
                }

                // Tutorial mode: Stay here toast (when user swipes away during dragToAccepted)
                if showingStayHereToast {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("STAY HERE TO COMPLETE THIS STEP")
                                .font(OPSStyle.Typography.captionBold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(OPSStyle.Colors.primaryAccent)
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        )
                        .transition(.scale.combined(with: .opacity))
                        .padding(.top, 100)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(999)
                }
            }
        }
        // Note: Completion checklist sheet is now handled globally via AppState in ContentView
        .onAppear {
            // Tutorial mode: Start on estimated column if in dragToAccepted phase
            if tutorialMode && tutorialPhase == .dragToAccepted {
                currentPageIndex = statuses.firstIndex(of: .estimated) ?? 1
            }
        }
    }

    struct ScrollOffsetPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    @ViewBuilder
    private func edgeZones(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            if canMoveToPrevious {
                leftZone(geometry: geometry)
            }

            Spacer()

            if canMoveToNext {
                rightZone(geometry: geometry)
            }
        }
    }

    @ViewBuilder
    private func leftZone(geometry: GeometryProxy) -> some View {
        let isActive = targetZoneForLocation(dragLocation, geometry: geometry) == .left
        let previousStatus = getPreviousStatus()
        let color = Color((previousStatus == .closed ? OPSStyle.Colors.secondaryText : previousStatus?.color) ?? .white)

        HStack(spacing: 0) {
            Rectangle()
                .fill(color.opacity(isActive ? 1.0 : 0.6))
                .frame(width: 6)
                .padding(.bottom, 120)
                .padding(.top, 20)

            OPSStyle.Layout.Gradients.carouselFadeLeft
                .frame(width: 74)

            Spacer()
        }
        .overlay(
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Spacer()

                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color.opacity(isActive ? 1.0 : 0.6))
                        .padding(12)

                    if let previousStatus = previousStatus {
                        Text(previousStatus.displayName.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(color.opacity(isActive ? 1.0 : 0.6))
                            .rotationEffect(.degrees(-90))
                            .padding(12)
                    }

                    Spacer()
                }
                .frame(height: 50)
                .padding(.leading, 4)

                Spacer()
            }
        )

        .frame(maxHeight: .infinity)
        .transition(.opacity)
    }

    @ViewBuilder
    private func rightZone(geometry: GeometryProxy) -> some View {
        let isActive = targetZoneForLocation(dragLocation, geometry: geometry) == .right
        let nextStatus = getNextStatus()
        let color = Color((nextStatus == .closed ? OPSStyle.Colors.secondaryText : nextStatus?.color) ?? .white)

        HStack(spacing: 0) {
            Spacer()

            OPSStyle.Layout.Gradients.carouselFadeRight
                .frame(width: 74)

            Rectangle()
                .fill(color.opacity(isActive ? 1.0 : 0.6))
                .frame(width: 6)
                .padding(.bottom, 120)
                .padding(.top, 20)
        }
        .overlay(
            HStack(spacing: 12) {
                Spacer()

                VStack(spacing: 4) {
                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color.opacity(isActive ? 1.0 : 0.6))
                        .padding(12)

                    if let nextStatus = nextStatus {
                        Text(nextStatus.displayName.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(color.opacity(isActive ? 1.0 : 0.6))
                            .rotationEffect(.degrees(-90))
                            .padding(12)
                    }

                    Spacer()
                }
                .frame(height: 50)
                .padding(.trailing, 4)
            }
        )
        .frame(maxHeight: .infinity)
        .transition(.opacity)
    }

    /// Start animated arrow offset for tutorial hint
    private func startTutorialArrowAnimation() {
        withAnimation(
            .easeInOut(duration: 0.6)
            .repeatForever(autoreverses: true)
        ) {
            tutorialArrowOffset = 8
        }
    }

    /// Start haptic nudges for tutorial hint
    private func startTutorialHaptics() {
        // Cancel any existing timer
        tutorialHapticTimer?.invalidate()

        // Create haptic timer for periodic nudges
        tutorialHapticTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            if tutorialMode && tutorialPhase == .dragToAccepted && !isLongPressing {
                TutorialHaptics.lightTap()
            }
        }
        // Fire once immediately
        TutorialHaptics.lightTap()
    }

    /// Stop haptic nudges
    private func stopTutorialHaptics() {
        tutorialHapticTimer?.invalidate()
        tutorialHapticTimer = nil
    }

    /// Trigger emphasis animation on "PRESS AND HOLD" message
    private func triggerPressHoldEmphasis() {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        // Trigger emphasis animation
        withAnimation(.easeInOut(duration: 0.15)) {
            emphasisPressHold = true
        }
        // Reset after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.3)) {
                emphasisPressHold = false
            }
        }
    }

    /// Center tutorial arrows with sequential glow effect
    /// Shows "PRESS AND HOLD" before drag, "DRAG TO ACCEPTED" during drag
    private var tutorialCenterArrows: some View {
        VStack(spacing: 12) {
            if isLongPressing {
                // During drag: show arrows pointing right
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .opacity(index < illuminatedArrowCount ? 1.0 : 0.2)
                            .scaleEffect(index < illuminatedArrowCount ? 1.2 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: illuminatedArrowCount)
                    }
                }

                Text("DRAG TO ACCEPTED LIST")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            } else {
                // Before drag: show press and hold instruction
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(emphasisPressHold ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.primaryAccent)
                    .offset(x: tutorialArrowOffset)
                    .scaleEffect(emphasisPressHold ? 1.3 : 1.0)

                Text("PRESS AND HOLD THE PROJECT CARD")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(emphasisPressHold ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.primaryAccent)
                    .scaleEffect(emphasisPressHold ? 1.1 : 1.0)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(emphasisPressHold ? OPSStyle.Colors.warningStatus : Color.clear, lineWidth: 2)
                )
        )
        .scaleEffect(emphasisPressHold ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: emphasisPressHold)
        .allowsHitTesting(false)
        .onAppear {
            startTutorialArrowAnimation()
            startTutorialHaptics()
        }
        .onDisappear {
            stopTutorialHaptics()
        }
    }

    @ViewBuilder
    private func archiveZone(geometry: GeometryProxy) -> some View {
        let isActive = targetZoneForLocation(dragLocation, geometry: geometry) == .archive

        VStack {
            Spacer()

            HStack {
                Spacer()

                HStack(spacing: 12) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color.gray.opacity(isActive ? 1.0 : 0.6))

                    Text("ARCHIVE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(Color.gray.opacity(isActive ? 1.0 : 0.6))
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(Color.gray.opacity(isActive ? 0.8 : 0.3), lineWidth: 2)
                        )
                )

                Spacer()
            }

            .padding(.bottom, 120)
        }
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    @ViewBuilder
    private var pageIndicator: some View {
        VStack {
            Spacer()

            ZStack {
                OPSStyle.Layout.Gradients.pageIndicatorFade
                    .frame(height: 180)

                HStack(spacing: 6) {
                    ForEach(statuses.indices, id: \.self) { index in
                        Rectangle()
                            .fill(currentPageIndex == index ? statuses[index].color : OPSStyle.Colors.pageIndicatorInactive)
                            .frame(width: 20, height: 2)
                    }
                    .padding(.bottom, 120)
                }
            }
        }
    }

    enum DragZone: Equatable {
        case left, right, center, archive
    }

    private func targetZoneForLocation(_ location: CGPoint, geometry: GeometryProxy?) -> DragZone {
        guard let geo = geometry else { return .center }

        let archiveZoneHeight: CGFloat = 100
        let archiveZoneWidth: CGFloat = 200

        if location.y > geo.size.height - archiveZoneHeight &&
           location.x > (geo.size.width - archiveZoneWidth) / 2 &&
           location.x < (geo.size.width + archiveZoneWidth) / 2 {
            return .archive
        } else if location.x < edgeZoneWidth {
            return .left
        } else if location.x > geo.size.width - edgeZoneWidth {
            return .right
        } else {
            return .center
        }
    }

    private func handleLongPress(project: Project) {
        draggedProject = project
        withAnimation(.easeOut(duration: 0.2)) {
            isLongPressing = true
        }
    }

    private func handleDragChanged(project: Project, location: CGPoint, geometry: GeometryProxy) {
        draggedProject = project
        isDragging = true

        let previousZone = targetZoneForLocation(dragLocation, geometry: geometry)
        dragLocation = location
        let currentZone = targetZoneForLocation(dragLocation, geometry: geometry)
        dropZone = currentZone

        if previousZone != currentZone && currentZone != .center {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }

        // Tutorial mode: Calculate illuminated arrows based on drag progress toward right
        if tutorialMode && tutorialPhase == .dragToAccepted && isLongPressing {
            let screenWidth = geometry.size.width
            let centerX = screenWidth / 2
            let rightEdge = screenWidth - edgeZoneWidth

            // Calculate progress from center to right edge (0.0 to 1.0)
            let dragX = location.x
            let progress = max(0, min(1, (dragX - centerX) / (rightEdge - centerX)))

            // Map progress to arrow count (0, 1, 2, or 3)
            let newArrowCount: Int
            if progress < 0.25 {
                newArrowCount = 0
            } else if progress < 0.5 {
                newArrowCount = 1
            } else if progress < 0.75 {
                newArrowCount = 2
            } else {
                newArrowCount = 3
            }

            // Trigger haptic when crossing threshold (increasing only)
            if newArrowCount > lastHapticArrowCount {
                let impactFeedback = UIImpactFeedbackGenerator(style: newArrowCount == 3 ? .medium : .light)
                impactFeedback.impactOccurred()
                lastHapticArrowCount = newArrowCount
            } else if newArrowCount < lastHapticArrowCount {
                // Reset haptic threshold when moving back
                lastHapticArrowCount = newArrowCount
            }

            illuminatedArrowCount = newArrowCount
        }
    }

    private func handleDragEnded(project: Project, geometry: GeometryProxy) {
        let zone = targetZoneForLocation(dragLocation, geometry: geometry)

        print("[DRAG_DEBUG] handleDragEnded called")
        print("[DRAG_DEBUG] tutorialMode=\(tutorialMode), tutorialPhase=\(String(describing: tutorialPhase))")
        print("[DRAG_DEBUG] zone=\(zone), project=\(project.title), status=\(project.status.rawValue)")

        // Tutorial mode: Only allow right drag (towards accepted)
        if tutorialMode && tutorialPhase == .dragToAccepted {
            print("[DRAG_DEBUG] ✅ In tutorial dragToAccepted branch")
            switch zone {
            case .left, .archive:
                // Wrong direction - show hint and don't change status
                print("[DRAG_DEBUG] ⛔ Wrong direction detected (zone=\(zone)), showing hint only")
                showWrongDirectionHint()
            case .right:
                print("[DRAG_DEBUG] ➡️ Right zone - will change status")
                if let nextStatus = getNextStatus() {
                    changeProjectStatus(project, to: nextStatus)
                }
            case .center:
                print("[DRAG_DEBUG] 🎯 Center zone - cancelling")
                cancelDrag()
            }
        } else {
            print("[DRAG_DEBUG] ❌ NOT in tutorial dragToAccepted branch - using normal mode")
            // Normal mode - allow any direction
            switch zone {
            case .left:
                if let previousStatus = getPreviousStatus() {
                    changeProjectStatus(project, to: previousStatus)
                }
            case .right:
                if let nextStatus = getNextStatus() {
                    changeProjectStatus(project, to: nextStatus)
                }
            case .archive:
                // Field crew cannot archive projects
                if !isFieldCrew {
                    changeProjectStatus(project, to: .archived)
                }
            case .center:
                cancelDrag()
            }
        }

        draggedProject = nil
        isDragging = false
        withAnimation(.easeOut(duration: 0.2)) {
            isLongPressing = false
        }
        dragLocation = .zero
        // Reset tutorial arrow state
        illuminatedArrowCount = 0
        lastHapticArrowCount = 0
    }

    /// Shows wrong direction hint during tutorial
    private func showWrongDirectionHint() {
        guard !showingWrongDirectionHint else { return }

        TutorialHaptics.error()
        // Notify tooltip to enter error state
        NotificationCenter.default.post(name: Notification.Name("TutorialWrongAction"), object: nil)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showingWrongDirectionHint = true
        }

        // Auto-hide after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                showingWrongDirectionHint = false
            }
        }
    }

    private func changeProjectStatus(_ project: Project, to newStatus: Status) {
        print("[ARCHIVE_DEBUG] 📦 Changing project '\(project.title)' status from \(project.status.rawValue) to \(newStatus.rawValue)")
        print("[TUTORIAL_DEBUG] tutorialMode=\(tutorialMode), tutorialPhase=\(String(describing: tutorialPhase)), currentStatus=\(project.status.rawValue), newStatus=\(newStatus.rawValue)")

        // Tutorial mode: During dragToAccepted phase, ONLY allow moving FROM estimated TO accepted
        // The user should be dragging their newly created project (at estimated) to accepted
        if tutorialMode && tutorialPhase == .dragToAccepted {
            // Must be dragging an estimated project to accepted
            guard project.status == .estimated && newStatus == .accepted else {
                print("[TUTORIAL] ⛔ Blocked: Can only move estimated→accepted during dragToAccepted. Got \(project.status.rawValue)→\(newStatus.rawValue)")
                showWrongDirectionHint()
                return
            }
        }

        // CENTRALIZED COMPLETION CHECK: If completing project, check for incomplete tasks first
        if newStatus == .completed {
            if !appState.requestProjectCompletion(project) {
                // Has incomplete tasks - checklist sheet will be shown globally
                return
            }
        }

        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Tutorial mode: notify drag to accepted
        if tutorialMode && newStatus == .accepted {
            NotificationCenter.default.post(
                name: Notification.Name("TutorialDragToAccepted"),
                object: nil
            )
        }

        // Update local status immediately
        project.status = newStatus
        project.needsSync = true  // Mark for sync

        do {
            try modelContext.save()
            print("[ARCHIVE_DEBUG] ✅ Project status saved locally to \(newStatus.rawValue)")
        } catch {
            print("[ARCHIVE_DEBUG] ❌ Failed to save project status locally: \(error)")
            return
        }

        // Check connectivity and sync accordingly
        if dataController.isConnected {
            // Sync to backend immediately
            Task {
                do {
                    try await dataController.apiService.updateProject(
                        id: project.id,
                        updates: ["status": newStatus.rawValue]
                    )
                    await MainActor.run {
                        project.needsSync = false
                        project.lastSyncedAt = Date()
                    }
                    print("[ARCHIVE_DEBUG] ✅ Project status synced to backend: \(newStatus.rawValue)")
                } catch {
                    await MainActor.run {
                        project.needsSync = true
                        // Trigger background sync to queue for later
                        dataController.syncManager?.triggerBackgroundSync()
                    }
                    print("[ARCHIVE_DEBUG] ❌ Failed to sync project status to backend: \(error)")
                }
            }
        } else {
            // Offline - queue for background sync
            print("[ARCHIVE_DEBUG] 📴 Offline - queueing status change for background sync")
            dataController.syncManager?.triggerBackgroundSync()

            // Show offline feedback
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowSuccessMessage"),
                object: nil,
                userInfo: ["message": "Saved locally. Will sync when connection improves."]
            )
        }
    }

    private func cancelDrag() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    private func projectsForStatus(_ status: Status) -> [Project] {
        var filteredProjects = allProjects.filter { $0.status == status }

        // Tutorial mode only shows demo projects
        if tutorialMode {
            filteredProjects = filteredProjects.filter { $0.id.hasPrefix("DEMO_") }
        }

        // Field crew only sees projects they're assigned to
        if let currentUser = dataController.currentUser, currentUser.role == .fieldCrew {
            filteredProjects = filteredProjects.filter { project in
                project.teamMembers.contains { user in
                    user.id == currentUser.id
                }
            }
        }

        return filteredProjects.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    private func getPreviousStatus() -> Status? {
        guard let draggedProject = draggedProject,
              let currentIndex = statuses.firstIndex(of: draggedProject.status),
              currentIndex > 0 else {
            return nil
        }
        return statuses[currentIndex - 1]
    }

    private func getNextStatus() -> Status? {
        guard let draggedProject = draggedProject,
              let currentIndex = statuses.firstIndex(of: draggedProject.status) else {
            return nil
        }

        if currentIndex < statuses.count - 1 {
            return statuses[currentIndex + 1]
        } else if draggedProject.status == .completed {
            // Field crew cannot move projects to Closed
            if isFieldCrew {
                return nil
            }
            return .closed
        }

        return nil
    }

    private var canMoveToPrevious: Bool {
        getPreviousStatus() != nil
    }

    private var canMoveToNext: Bool {
        getNextStatus() != nil
    }
}

struct StatusColumn: View {
    let status: Status
    let projects: [Project]
    let draggedProject: Project?
    let targetZone: JobBoardDashboard.DragZone
    let namespace: Namespace.ID
    let onProjectLongPress: (Project) -> Void
    let onProjectDragChanged: (Project, CGPoint) -> Void
    let onProjectDragEnded: (Project) -> Void
    var onTapBlocked: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            columnHeader
                .padding(.horizontal, 12)

            projectList
        }
        .padding(.horizontal, 6)
        .overlay(
            HStack(spacing: 0) {
                Rectangle()
                    .fill(OPSStyle.Colors.separator)
                    .frame(width: 1)

                Spacer()

                Rectangle()
                    .fill(OPSStyle.Colors.separator)
                    .frame(width: 1)
            }
            .padding(.horizontal, 4)
        )
    }

    @ViewBuilder
    private var columnHeader: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(status.color)
                .frame(width: 2, height: 12)

            Text(status.displayName.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1)

            Text("[ \(projects.count) ]")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var projectList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(projects) { project in
                    DirectionalDragCard(
                        project: project,
                        statusColor: status.color,
                        isDragged: draggedProject?.id == project.id,
                        namespace: namespace,
                        onLongPress: onProjectLongPress,
                        onDragChanged: onProjectDragChanged,
                        onDragEnded: onProjectDragEnded,
                        onTapBlocked: onTapBlocked
                    )
                    .matchedGeometryEffect(id: project.id, in: namespace)
                }

                if projects.isEmpty {
                    emptyState
                }
            }
            .padding(12)
            .padding(.bottom, 120)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: projects.count)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 28))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("No Projects")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

struct DirectionalDragCard: View {
    let project: Project
    let statusColor: Color
    let isDragged: Bool
    let namespace: Namespace.ID
    let onLongPress: (Project) -> Void
    let onDragChanged: (Project, CGPoint) -> Void
    let onDragEnded: (Project) -> Void
    var onTapBlocked: (() -> Void)? = nil

    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    @State private var tutorialHighlightPulse = false
    @State private var showingDetails = false
    @State private var isLongPressing = false
    @State private var touchDownTime: Date?
    @State private var touchDownLocation: CGPoint?
    @State private var dragOffset: CGSize = .zero

    // Drag gesture only activates after long press is triggered
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                if isLongPressing {
                    if let startLocation = touchDownLocation {
                        dragOffset = CGSize(
                            width: value.location.x - startLocation.x,
                            height: value.location.y - startLocation.y
                        )
                    }
                    onDragChanged(project, value.location)
                }
            }
            .onEnded { _ in
                if isLongPressing {
                    onDragEnded(project)
                    dragOffset = .zero
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isLongPressing = false
                    }
                }
            }
    }

    // Long press gesture to activate drag mode
    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                triggerLongPress()
            }
    }

    // Combined gesture: long press to activate, then drag
    private var combinedGesture: some Gesture {
        longPressGesture.sequenced(before: dragGesture)
    }

    var body: some View {
        cardContent
            .opacity(isDragged ? 0.3 : 1.0)
            .scaleEffect(isLongPressing ? 0.95 : 1.0)
            .contentShape(Rectangle())
            .onTapGesture {
                // Block tap during dragToAccepted tutorial phase
                if tutorialMode && tutorialPhase == .dragToAccepted {
                    onTapBlocked?()
                    return
                }
                showingDetails = true
            }
            .simultaneousGesture(combinedGesture)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isLongPressing)
            .sheet(isPresented: $showingDetails) {
                NavigationView {
                    ProjectDetailsView(project: project)
                }
                .interactiveDismissDisabled(true)
            }
    }

    /// Whether to show tutorial highlight (dragToAccepted phase)
    private var shouldShowTutorialHighlight: Bool {
        tutorialMode && tutorialPhase == .dragToAccepted
    }

    private var cardContent: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(statusColor)
                .frame(width: 4)

            cardDetails

            Spacer()
        }
        .background(OPSStyle.Colors.background)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(OPSStyle.Colors.cardBorderSubtle, lineWidth: 1)
        )
        .overlay(
            Group {
                if shouldShowTutorialHighlight {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(TutorialHighlightStyle.color, lineWidth: 2)
                        .opacity(tutorialHighlightPulse ? TutorialHighlightStyle.pulseOpacity.max : TutorialHighlightStyle.pulseOpacity.min)
                        .animation(
                            .easeInOut(duration: TutorialHighlightStyle.pulseDuration)
                            .repeatForever(autoreverses: true),
                            value: tutorialHighlightPulse
                        )
                }
            }
        )
        .onAppear {
            if shouldShowTutorialHighlight {
                tutorialHighlightPulse = true
            }
        }
        .onChange(of: tutorialPhase) { _, newPhase in
            tutorialHighlightPulse = tutorialMode && newPhase == .dragToAccepted
        }
    }

    private var cardDetails: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(project.title.uppercased())
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(project.effectiveClientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)

                leftMetadata
            }

            Spacer()

            rightMetadata
        }
        .padding(12)
    }

    private var leftMetadata: some View {
        HStack(spacing: 4) {
            if let startDate = project.startDate {
                Image(systemName: OPSStyle.Icons.calendar)
                    .font(.system(size: 10))
                Text(DateHelper.fullDateString(from: startDate))
                    .font(OPSStyle.Typography.smallCaption)
            }
        }
        .foregroundColor(OPSStyle.Colors.tertiaryText)
    }

    private var rightMetadata: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if !project.teamMembers.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: OPSStyle.Icons.personTwo)
                        .font(.system(size: 10))
                    Text("\(project.teamMembers.count)")
                        .font(OPSStyle.Typography.smallCaption)
                }
            }

            // Task-only scheduling migration: All projects use tasks
            if !project.tasks.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: OPSStyle.Icons.task)
                        .font(.system(size: 10))
                    Text("\(project.tasks.count)")
                        .font(OPSStyle.Typography.smallCaption)
                }
            }

            Spacer()

            if let startDate = project.startDate, let endDate = project.endDate {
                let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
                HStack(spacing: 4) {
                    Image(systemName: OPSStyle.Icons.clock)
                        .font(.system(size: 10))
                    Text(days == 0 ? "SAME DAY" : "\(days)d")
                        .font(OPSStyle.Typography.smallCaption)
                }
            }
        }
        .foregroundColor(OPSStyle.Colors.tertiaryText)
    }

    private func triggerLongPress() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        cancelParentScrollGestures()

        isLongPressing = true
        onLongPress(project)
    }

    private func cancelParentScrollGestures() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return
        }

        func findScrollViews(in view: UIView) {
            if let scrollView = view as? UIScrollView {
                print("🛑 Cancelling gesture on: \(type(of: scrollView))")
                scrollView.panGestureRecognizer.isEnabled = false
                scrollView.panGestureRecognizer.isEnabled = true
            }

            for subview in view.subviews {
                findScrollViews(in: subview)
            }
        }

        findScrollViews(in: window)
    }
}

struct DraggingCardOverlay: View {
    let project: Project
    let dragLocation: CGPoint
    let statusColor: Color
    let dropZone: JobBoardDashboard.DragZone

    private var dropTransition: AnyTransition {
        switch dropZone {
        case .left:
            return .asymmetric(
                insertion: .opacity,
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .right:
            return .asymmetric(
                insertion: .opacity,
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .archive:
            return .asymmetric(
                insertion: .opacity,
                removal: .move(edge: .bottom).combined(with: .opacity)
            )
        case .center:
            return .opacity
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 2)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(project.title.uppercased())
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(project.effectiveClientName)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            if let startDate = project.startDate {
                                Image(systemName: OPSStyle.Icons.calendar)
                                    .font(.system(size: 10))
                                Text(DateHelper.fullDateString(from: startDate))
                                    .font(OPSStyle.Typography.smallCaption)
                            }
                        }
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        if !project.teamMembers.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: OPSStyle.Icons.personTwo)
                                    .font(.system(size: 10))
                                Text("\(project.teamMembers.count)")
                                    .font(OPSStyle.Typography.smallCaption)
                            }
                        }

                        // Task-only scheduling migration: All projects use tasks
                        if !project.tasks.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: OPSStyle.Icons.task)
                                    .font(.system(size: 10))
                                Text("\(project.tasks.count)")
                                    .font(OPSStyle.Typography.smallCaption)
                            }
                        }

                        Spacer()

                        if let startDate = project.startDate, let endDate = project.endDate {
                            let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
                            HStack(spacing: 4) {
                                Image(systemName: OPSStyle.Icons.clock)
                                    .font(.system(size: 10))
                                Text(days == 0 ? "SAME DAY" : "\(days)d")
                                    .font(OPSStyle.Typography.smallCaption)
                            }
                        }
                    }
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(12)
            }
            .background(OPSStyle.Colors.background)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(OPSStyle.Colors.cardBorderSubtle, lineWidth: 1)
            )
            .frame(width: 256)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(0.98)
            .shadow(color: OPSStyle.Colors.shadowColor, radius: 12, x: 0, y: 4)
            .position(x: dragLocation.x, y: dragLocation.y - 120)
            .transition(dropTransition)
            .allowsHitTesting(false)
        }
    }
}
