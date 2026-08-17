//
//  ScheduleLongPressQAHost.swift
//  OPS
//
//  DEBUG-only harness for bug 75318af9 (Schedule long-press quick actions
//  vanished). Renders the REAL calendar cards — the day CalendarEventCard and the
//  month EventBar — with an in-memory task and a permissive PermissionStore, so an
//  XCUITest can drive a real long-press and assert the quick-action context menu
//  actually opens. No auth, no network, no SwiftData store on disk.
//
//  Calendar surfaces, each independently long-pressable:
//    • FIXED  — the shipping day composition: one CalendarEventCard whose single
//               context menu carries the injected quick actions. Must show them.
//    • ONGOING— the continuation-day composition used by DayCanvasView. Must keep
//               the same actions as the first day of the task.
//    • MONTH DETAIL — the CalendarEventCard composition used inside the month
//               day-detail sheet. Must keep the same actions as week view.
//    • BUGGY  — the pre-fix composition kept as a guard: a CalendarEventCard that
//               owns its own default menu AND is wrapped in a SECOND .contextMenu.
//               Reproduces the shadow — the quick actions do NOT appear.
//    • MONTH  — the real month EventBar (single menu + .draggable). Must show them.
//    • CONTROL— a bare view with one .contextMenu. Sanity: long-press works at all.
//  Plus a DROP zone under FIXED: hold + MOVE on the fixed card must lift into a
//  native reschedule drag and land its payload there (menu/drag coexistence — the
//  drag-to-reschedule flow must survive the single-owner menu).
//

#if DEBUG
import SwiftUI
import SwiftData

struct ScheduleLongPressQAHost: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    @State private var isReady = false
    @State private var lastAction = "—"
    /// Set by the DROP zone when a reschedule payload lands — proves the card
    /// still lifts into a drag despite owning the (single) context menu.
    @State private var droppedId = "—"

    @State private var dragSession = ScheduleDragSession()

    private static let modelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: OPSSchemaV23.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create Schedule long-press QA container: \(error.localizedDescription)")
        }
    }()

    // MARK: - Fixtures

    private static let taskId = "qa_longpress_task"

    private func makeTask(in context: ModelContext) -> ProjectTask {
        if let existing = (try? context.fetch(FetchDescriptor<ProjectTask>()))?.first(where: { $0.id == Self.taskId }) {
            return existing
        }
        let project = Project(id: "qa_longpress_project", title: "FIELD PANEL INSTALL", status: .inProgress)
        project.address = "1420 Industrial Ave, Calgary"
        let task = ProjectTask(id: Self.taskId, projectId: project.id, taskTypeId: "tt", companyId: "qa_co")
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        task.startDate = start
        task.endDate = cal.date(byAdding: .day, value: 1, to: start) ?? start
        task.duration = 2
        task.project = project
        project.tasks.append(task)
        context.insert(project)
        context.insert(task)
        try? context.save()
        return task
    }

    private func payload(for task: ProjectTask) -> RescheduleDragPayload {
        RescheduleDragPayload(
            id: task.id, kind: .task, title: task.displayTitle,
            durationDays: 2, startEpoch: (task.startDate ?? Date()).timeIntervalSince1970)
    }

    private func monthSpan(for task: ProjectTask) -> WeekEventSpan {
        WeekEventSpan(
            id: "qa_span", eventId: task.id, title: "FIELD PANEL INSTALL",
            color: task.effectiveColor, startDate: task.startDate ?? Date(),
            endDate: task.startDate ?? Date(), startDayIndex: 0, endDayIndex: 0,
            row: 0, isFirstSegment: true, isLastSegment: true, isSingleDay: true,
            taskTypeDisplay: "INSTALL")
    }

    /// The injected quick actions (Push / Extend / Cascade / Reschedule / Select).
    /// Actions record into `lastAction` so the XCUITest could also assert taps land,
    /// but the test's job is only to prove the menu OPENS with these items.
    private var quickActions: ScheduleCardQuickActions {
        ScheduleCardQuickActions(
            onPush: { lastAction = "push \($0)" },
            onExtend: { lastAction = "extend \($0)" },
            onCascade: { lastAction = "cascade \($0)" },
            onReschedule: { lastAction = "reschedule" },
            onSelect: { lastAction = "select" })
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            if isReady, let task = (try? Self.modelContainer.mainContext
                .fetch(FetchDescriptor<ProjectTask>()))?.first(where: { $0.id == Self.taskId }) {
                cards(task: task)
            } else {
                Text("// SCHEDULE LONG-PRESS QA")
                    .font(OPSStyle.Typography.pageTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
        }
        .environment(dragSession)
        .modelContainer(Self.modelContainer)
        .onAppear(perform: prepare)
    }

    @ViewBuilder
    private func cards(task: ProjectTask) -> some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing5) {
                Text("LAST_ACTION::\(lastAction)")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .accessibilityIdentifier("qa_last_action")

                labeled("DROP", id: "qa_drop_zone") {
                    // Hermetic drop target for the drag-coexistence proof: the
                    // FIXED card below must long-press+move into a native drag
                    // and land its RescheduleDragPayload here. Sits ABOVE the
                    // card because a committed context menu blooms BELOW a
                    // top-anchored preview — a drop zone under the card gets
                    // occluded by menu items mid-drag. Records the payload id
                    // into a label the XCUITest reads.
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(OPSStyle.Colors.cardBackground)
                        .frame(height: 80)
                        .overlay(
                            Text(droppedId == "—" ? "DROP HERE" : "DROPPED::\(droppedId)")
                                .font(OPSStyle.Typography.bodyEmphasis)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .accessibilityIdentifier("qa_drop_result")
                        )
                        .dropDestination(for: RescheduleDragPayload.self) { payloads, _ in
                            guard let first = payloads.first else { return false }
                            droppedId = first.id
                            return true
                        }
                }

                labeled("FIXED", id: "qa_card_fixed") {
                    CalendarEventCard(
                        task: task, isFirst: true,
                        dragPayload: payload(for: task), dragSession: dragSession,
                        hostQuickActions: quickActions, onTap: {})
                }

                labeled("ONGOING", id: "qa_card_ongoing") {
                    // Mirrors the shipping continuation-day composition.
                    CalendarEventCard(
                        task: task, isFirst: false, isOngoing: true,
                        hostQuickActions: quickActions, onTap: {})
                }

                labeled("MONTH DETAIL", id: "qa_card_month_detail") {
                    // Mirrors the real card inside DayDetailsSheet.
                    CalendarEventCard(
                        task: task, isFirst: true,
                        hostQuickActions: quickActions, onTap: {})
                }

                labeled("BUGGY", id: "qa_card_buggy") {
                    // Pre-fix composition: the card owns its default menu AND a second
                    // .contextMenu is stacked on top. This is the shadow bug.
                    CalendarEventCard(
                        task: task, isFirst: true,
                        dragPayload: payload(for: task), dragSession: dragSession,
                        hostQuickActions: nil, onTap: {})
                        .contextMenu {
                            Section("Push") {
                                Button { lastAction = "push 1" } label: { Label("+1 Day", systemImage: "arrow.right") }
                                Button { lastAction = "push 7" } label: { Label("+1 Week", systemImage: "arrow.right.to.line") }
                            }
                            Section("Cascade") {
                                Button { lastAction = "cascade 1" } label: { Label("+1 Day (+ crew)", systemImage: "arrow.triangle.branch") }
                            }
                        }
                }

                labeled("MONTH", id: "qa_card_month") {
                    EventBar(
                        span: monthSpan(for: task),
                        cellHeight: OPSStyle.Layout.monthGridStandardHeightThreshold,
                        dayWidth: OPSStyle.Layout.touchTargetMin,
                        onTap: {},
                        quickActions: quickActions,
                        onOpenDayDetails: { lastAction = "details" })
                        .reschedulable(payload(for: task), session: dragSession)
                }

                labeled("CONTROL", id: "qa_card_control") {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(OPSStyle.Colors.cardBackground)
                        .frame(height: 60)
                        .overlay(Text("CONTROL").font(OPSStyle.Typography.bodyEmphasis)
                            .foregroundColor(OPSStyle.Colors.primaryText))
                        .contextMenu {
                            Button { lastAction = "push 1" } label: { Label("+1 Day", systemImage: "arrow.right") }
                            Button { lastAction = "cascade 1" } label: { Label("+1 Day (+ crew)", systemImage: "arrow.triangle.branch") }
                        }
                }
            }
            .padding(OPSStyle.Layout.spacing4)
        }
    }

    @ViewBuilder
    private func labeled<Content: View>(_ label: String, id: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            content()
                .contentShape(Rectangle())
                .accessibilityIdentifier(id)
        }
    }

    // MARK: - Session prep

    @MainActor
    private func prepare() {
        // Nested system context menus keep reporting animation activity to
        // XCTest on iOS 26.5. Disable UIKit animation only for menu assertions;
        // the drag-coexistence test opts back into native animation because its
        // preview lift is itself the behavior under test.
        if !ProcessInfo.processInfo.arguments.contains("-OPS_SCHEDULE_QA_KEEP_ANIMATIONS") {
            UIView.setAnimationsEnabled(false)
        }

        _ = makeTask(in: Self.modelContainer.mainContext)

        dataController.isAuthenticated = true
        dataController.isConnected = true
        dataController.permissionStore = permissionStore

        // Grant calendar.edit "all" so ProjectTask.canEditSchedule (which reads
        // PermissionStore.shared) returns true — the injected quick actions are
        // gated on it. "all" short-circuits before the per-user id check, so the
        // (private) currentUserId is irrelevant here.
        permissionStore.permissions = ["calendar.edit": "all"]
        permissionStore.roleName = "Owner"
        permissionStore.roleHierarchy = 100
        permissionStore.blockedByFlags = []
        permissionStore.disabledFlags = []
        permissionStore.initialized = true

        isReady = true
    }
}
#endif
