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
    @Environment(\.modelContext) private var modelContext
    @Query private var allProjects: [Project]
    @State private var draggedProject: Project? = nil
    @State private var isDragging = false
    @State private var isLongPressing = false
    @State private var dragLocation: CGPoint = .zero
    @State private var dropZone: DragZone = .center
    @State private var currentPageIndex: Int = 0
    @Namespace private var cardNamespace

    private let statuses: [Status] = [.rfq, .estimated, .accepted, .inProgress, .completed]
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
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 12)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .allowsHitTesting(!isLongPressing)

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

                if isLongPressing {
                    archiveZone(geometry: geometry)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
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
    }

    private func handleDragEnded(project: Project, geometry: GeometryProxy) {
        let zone = targetZoneForLocation(dragLocation, geometry: geometry)

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
            changeProjectStatus(project, to: .archived)
        case .center:
            cancelDrag()
        }

        draggedProject = nil
        isDragging = false
        withAnimation(.easeOut(duration: 0.2)) {
            isLongPressing = false
        }
        dragLocation = .zero
    }

    private func changeProjectStatus(_ project: Project, to newStatus: Status) {
        print("[ARCHIVE_DEBUG] 📦 Changing project '\(project.title)' status from \(project.status.rawValue) to \(newStatus.rawValue)")

        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Update local status immediately
        project.status = newStatus

        do {
            try modelContext.save()
            print("[ARCHIVE_DEBUG] ✅ Project status saved locally to \(newStatus.rawValue)")
        } catch {
            print("[ARCHIVE_DEBUG] ❌ Failed to save project status locally: \(error)")
        }

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
                }
                print("[ARCHIVE_DEBUG] ❌ Failed to sync project status to backend: \(error)")
            }
        }
    }

    private func cancelDrag() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    private func projectsForStatus(_ status: Status) -> [Project] {
        var filteredProjects = allProjects.filter { $0.status == status }

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
                        onDragEnded: onProjectDragEnded
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

    @State private var showingDetails = false
    @State private var isLongPressing = false
    @State private var touchDownTime: Date?
    @State private var touchDownLocation: CGPoint?
    @State private var dragOffset: CGSize = .zero

    private var cardGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                print("🔵 DragGesture onChanged - isLongPressing: \(isLongPressing)")

                if isLongPressing {
                    print("🟢 Long press active - calling onDragChanged")
                    if let startLocation = touchDownLocation {
                        dragOffset = CGSize(
                            width: value.location.x - startLocation.x,
                            height: value.location.y - startLocation.y
                        )
                    }
                    onDragChanged(project, value.location)
                } else {
                    if touchDownTime == nil {
                        print("📍 Touch down - starting timer")
                        touchDownTime = Date()
                        touchDownLocation = value.location
                    } else if let startTime = touchDownTime, let startLocation = touchDownLocation {
                        let timeElapsed = Date().timeIntervalSince(startTime)
                        let distance = hypot(value.location.x - startLocation.x, value.location.y - startLocation.y)

                        print("⏱️  Time: \(timeElapsed)s, Distance: \(distance)px")

                        if timeElapsed >= 0.3 && distance < 10 {
                            print("🎯 Long press threshold met - triggering")
                            triggerLongPress()
                        }
                    }
                }
            }
            .onEnded { value in
                print("🔴 DragGesture onEnded - isLongPressing: \(isLongPressing)")

                if isLongPressing {
                    print("🟠 Ending drag - calling onDragEnded")
                    onDragEnded(project)
                    dragOffset = .zero
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isLongPressing = false
                    }
                } else {
                    if let startTime = touchDownTime, let startLocation = touchDownLocation {
                        let timeElapsed = Date().timeIntervalSince(startTime)
                        let distance = hypot(value.location.x - startLocation.x, value.location.y - startLocation.y)

                        if timeElapsed < 0.3 && distance < 10 {
                            print("👆 Quick tap detected - opening details")
                            showingDetails = true
                        }
                    }
                }

                touchDownTime = nil
                touchDownLocation = nil
            }
    }

    var body: some View {
        cardContent
            .opacity(isDragged ? 0.3 : 1.0)
            .scaleEffect(isLongPressing ? 0.95 : 1.0)
            .contentShape(Rectangle())
            .simultaneousGesture(cardGesture)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isLongPressing)
            .sheet(isPresented: $showingDetails) {
                NavigationView {
                    ProjectDetailsView(project: project)
                }
            }
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
