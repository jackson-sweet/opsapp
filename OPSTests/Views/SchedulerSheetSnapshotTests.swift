//
//  SchedulerSheetSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the rebuilt schedule sheet. Renders the REAL views against
//  a seeded in-memory store through a UIHostingController in a UIWindow —
//  ImageRenderer cannot resolve OPS asset colours, so this is the only harness
//  that shows what ships.
//
//  A rendering harness, not an assertion suite: it fails only if a state
//  cannot be rendered at all. Read the PNGs.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/SchedulerSheetSnapshotTests
//

#if DEBUG
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class SchedulerSheetSnapshotTests: XCTestCase {

    private let calendar = Calendar.current
    private let phone = CGSize(width: 390, height: 844)     // iPhone 15 Pro class
    private let smallPhone = CGSize(width: 375, height: 667) // iPhone SE class

    private var outDir: URL {
        // Session scratchpad — verification artifacts never land in the repo.
        let scratch = "/private/tmp/claude-501/-Users-jacksonsweet-Projects-OPS/0b4742a0-8291-4da2-a8b2-5d8e6292a741/scratchpad/schedule-sheet-proofs"
        let dir = URL(fileURLWithPath: scratch, isDirectory: true)
        if (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) == nil {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
        return dir
    }

    // MARK: - Scenarios

    /// Nothing picked yet, and the job's prerequisite is already on the
    /// calendar — so the sheet opens with a suggestion and an empty panel.
    func testEmptyStateWithSuggestionChip() throws {
        let world = try World()
        snapshot("01_empty_with_suggestion", size: phone) {
            world.sheet(start: nil, end: nil)
        }
    }

    /// A committed range that collides with another crew's job — the panel
    /// names the project, the client, the crew member, and the drive.
    func testRangeWithNamedConflictAndDistance() throws {
        let world = try World()
        snapshot("02_range_named_conflict", size: phone) {
            world.sheet(start: world.conflictStart, end: world.conflictEnd)
        }
    }

    /// A range that starts before the dependency floor: the pre-floor days sit
    /// dimmed in the grid and the panel carries the amber note. Still savable.
    func testPreFloorDimmingAndNote() throws {
        let world = try World()
        snapshot("03_pre_floor_dimming", size: phone) {
            world.sheet(start: world.preFloorStart, end: world.preFloorEnd)
        }
    }

    /// Rescheduling an already-dated task: quick-push row and the explicit
    /// UNSCHEDULE control both present.
    func testRescheduleModeShowsPushRowAndUnschedule() throws {
        let world = try World()
        snapshot("04_reschedule_mode", size: phone) {
            world.sheet(
                start: world.scheduledStart,
                end: world.scheduledEnd,
                onClearDates: {}
            )
        }
    }

    /// Half of the range picked — the footer asks for the end date.
    func testStartPickedFooterState() throws {
        let world = try World()
        snapshot("05_start_picked", size: phone) {
            world.sheet(start: world.conflictStart, end: nil)
        }
    }

    /// The long-press inspector, with its plain-language verdict in the header.
    func testLongPressDaySheet() throws {
        let world = try World()
        let context = world.dayContext()
        snapshot("06_day_sheet", size: phone) {
            SchedulerDaySheet(
                day: world.conflictStart,
                context: context,
                action: .useAsStart,
                onApply: {}
            )
        }
    }

    /// A day with the crew booked away, so the verdict names the person.
    func testLongPressDaySheetOnTimeOff() throws {
        let world = try World()
        let context = world.dayContext()
        snapshot("07_day_sheet_time_off", size: phone) {
            SchedulerDaySheet(
                day: world.timeOffDay,
                context: context,
                action: .useAsEnd,
                onApply: {}
            )
        }
    }

    /// 667pt-class fit — the day panel compresses rather than pushing the
    /// footer off screen.
    func testSmallPhoneFit() throws {
        let world = try World()
        snapshot("08_small_phone_fit", size: smallPhone) {
            world.sheet(start: world.conflictStart, end: world.conflictEnd)
        }
    }

    /// The footer in all three of its states, side by side.
    func testFooterStates() {
        let day = calendar.startOfDay(for: Date())
        let later = calendar.date(byAdding: .day, value: 3, to: day)!
        let states: [(String, SchedulerSelection)] = [
            ("09_footer_none", .none),
            ("10_footer_start", .start(day)),
            ("11_footer_range", .range(day, later))
        ]
        for (name, selection) in states {
            snapshot(name, size: CGSize(width: phone.width, height: 76)) {
                SchedulerFooterBar(selection: selection, onClear: {}, onSave: {})
                    .background(Color.black)
            }
        }
    }

    // MARK: - Seeded world

    /// One coherent little company: a deck job with framing already booked,
    /// another crew's fence job two kilometres away, and a crew member off.
    @MainActor
    private final class World {
        let container: ModelContainer
        let context: ModelContext
        let dataController: DataController

        let item: ProjectTask
        let floorDay: Date
        let conflictStart: Date
        let conflictEnd: Date
        let preFloorStart: Date
        let preFloorEnd: Date
        let scheduledStart: Date
        let scheduledEnd: Date
        let timeOffDay: Date

        private let calendar = Calendar.current

        init() throws {
            let schema = Schema([
                Project.self,
                ProjectTask.self,
                TaskType.self,
                TaskTypeReminder.self,
                TaskReminder.self,
                User.self,
                Client.self,
                SubClient.self,
                SyncOperation.self,
                CalendarUserEvent.self
            ])
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)]
            )
            context = ModelContext(container)
            dataController = DataController()
            dataController.setModelContext(context)

            // Anchor everything to a fixed Monday so the grid reads the same on
            // any day the suite runs.
            var monday = calendar.startOfDay(for: Date())
            while calendar.component(.weekday, from: monday) != 2 {
                monday = calendar.date(byAdding: .day, value: 1, to: monday)!
            }

            let marcus = User(id: "user-marcus", firstName: "Marcus", lastName: "Hale", role: .crew, companyId: "company-1")
            let dana = User(id: "user-dana", firstName: "Dana", lastName: "Reid", role: .crew, companyId: "company-1")
            let operatorUser = User(id: "user-op", firstName: "Jackson", lastName: "Sweet", role: .owner, companyId: "company-1")
            for user in [marcus, dana, operatorUser] { context.insert(user) }
            dataController.currentUser = operatorUser

            let keys = Client(id: "client-keys", name: "Faye Keys", companyId: "company-1")
            let marsh = Client(id: "client-marsh", name: "Ollie Marsh", companyId: "company-1")
            context.insert(keys)
            context.insert(marsh)

            let harbour = Project(id: "project-harbour", title: "Harbour Deck", status: .inProgress)
            harbour.companyId = "company-1"
            harbour.client = keys
            harbour.latitude = 48.4284
            harbour.longitude = -123.3656
            let cedar = Project(id: "project-cedar", title: "Cedar Ridge Fence", status: .inProgress)
            cedar.companyId = "company-1"
            cedar.client = marsh
            cedar.latitude = 48.4484
            cedar.longitude = -123.3656
            context.insert(harbour)
            context.insert(cedar)

            let framingType = TaskType(id: "type-framing", display: "Framing", color: "#9DB582", companyId: "company-1")
            let deckingType = TaskType(id: "type-decking", display: "Decking", color: "#6F94B0", companyId: "company-1")
            deckingType.dependencies = [
                TaskTypeDependency(dependsOnTaskTypeId: "type-framing", overlapPercentage: 0)
            ]
            let fenceType = TaskType(id: "type-fence", display: "Fence Panels", color: "#C4A868", companyId: "company-1")
            for type in [framingType, deckingType, fenceType] { context.insert(type) }

            // Framing runs Mon–Wed, so decking cannot legally start until Thu.
            let framing = ProjectTask(id: "task-framing", projectId: harbour.id, taskTypeId: framingType.id, companyId: "company-1")
            framing.taskType = framingType
            framing.project = harbour
            framing.startDate = monday
            framing.endDate = calendar.date(byAdding: .day, value: 2, to: monday)!
            framing.duration = 3
            framing.setTeamMemberIds([marcus.id])
            framing.teamMembers = [marcus]
            context.insert(framing)
            floorDay = calendar.date(byAdding: .day, value: 3, to: monday)!

            // Another crew job, 2.2 km away, that Marcus is already on.
            let fence = ProjectTask(id: "task-fence", projectId: cedar.id, taskTypeId: fenceType.id, companyId: "company-1")
            fence.taskType = fenceType
            fence.project = cedar
            fence.startDate = calendar.date(byAdding: .day, value: 8, to: monday)!
            fence.endDate = calendar.date(byAdding: .day, value: 9, to: monday)!
            fence.duration = 2
            fence.setTeamMemberIds([marcus.id])
            fence.teamMembers = [marcus]
            context.insert(fence)

            // Dana is off the following Thursday.
            timeOffDay = calendar.date(byAdding: .day, value: 10, to: monday)!
            let off = CalendarUserEvent(
                id: "event-dana-off",
                userId: dana.id,
                companyId: "company-1",
                type: .timeOff,
                title: "Time off",
                startDate: timeOffDay,
                endDate: timeOffDay
            )
            off.status = CalendarUserEventStatus.approved.rawValue
            context.insert(off)

            // The job being scheduled.
            item = ProjectTask(id: "task-decking", projectId: harbour.id, taskTypeId: deckingType.id, companyId: "company-1")
            item.taskType = deckingType
            item.project = harbour
            item.duration = 2
            item.setTeamMemberIds([marcus.id, dana.id])
            item.teamMembers = [marcus, dana]
            context.insert(item)

            try? context.save()

            conflictStart = calendar.date(byAdding: .day, value: 8, to: monday)!
            conflictEnd = calendar.date(byAdding: .day, value: 9, to: monday)!
            preFloorStart = calendar.date(byAdding: .day, value: 1, to: monday)!
            preFloorEnd = calendar.date(byAdding: .day, value: 4, to: monday)!
            scheduledStart = calendar.date(byAdding: .day, value: 3, to: monday)!
            scheduledEnd = calendar.date(byAdding: .day, value: 4, to: monday)!
        }

        @ViewBuilder
        func sheet(start: Date?, end: Date?, onClearDates: (() -> Void)? = nil) -> some View {
            CalendarSchedulerSheet(
                isPresented: .constant(true),
                itemType: .task(item),
                currentStartDate: start,
                currentEndDate: end,
                onScheduleUpdate: { _, _ in },
                onClearDates: onClearDates
            )
            .environmentObject(dataController)
            .modelContainer(container)
        }

        /// The same engine the sheet builds, for rendering the day inspector.
        func dayContext() -> SchedulerDayContext {
            let tasks = dataController.getScheduledTasks(
                in: calendar.date(byAdding: .month, value: -1, to: Date())!
                    ... calendar.date(byAdding: .month, value: 3, to: Date())!
            )
            var events: [SchedulerDayContext.Event] = []
            for task in tasks {
                guard let start = task.startDate else { continue }
                var names: [String: String] = [:]
                for member in task.teamMembers { names[member.id] = member.firstName }
                events.append(
                    SchedulerDayContext.Event(
                        id: task.id,
                        kind: .job,
                        title: task.project?.title ?? task.displayTitle,
                        subtitle: task.project?.effectiveClientName,
                        taskTitle: task.displayTitle,
                        projectId: task.projectId,
                        start: start,
                        end: task.endDate ?? start,
                        crewIds: Set(task.getTeamMemberIds()),
                        crewFirstNames: names,
                        latitude: task.project?.latitude,
                        longitude: task.project?.longitude
                    )
                )
            }
            events.append(
                SchedulerDayContext.Event(
                    id: "userevent:event-dana-off",
                    kind: .timeOff,
                    title: "Dana",
                    start: timeOffDay,
                    end: timeOffDay,
                    crewIds: ["user-dana"],
                    crewFirstNames: ["user-dana": "Dana"]
                )
            )
            return SchedulerDayContext(
                item: SchedulerDayContext.Item(
                    selfTaskId: item.id,
                    projectId: item.projectId,
                    crewIds: Set(item.getTeamMemberIds()),
                    latitude: item.project?.latitude,
                    longitude: item.project?.longitude,
                    dependencies: item.effectiveDependencies,
                    isScheduled: false
                ),
                events: events,
                prerequisites: [
                    SchedulerDayContext.Prerequisite(
                        taskTypeId: "type-framing",
                        title: "Framing",
                        start: calendar.date(byAdding: .day, value: -3, to: floorDay)!,
                        duration: 3
                    )
                ],
                skipsWeekends: false,
                calendar: calendar
            )
        }
    }

    // MARK: - Render harness

    private func snapshot<V: View>(_ name: String, size: CGSize, @ViewBuilder _ content: () -> V) {
        let host = UIHostingController(rootView: content())
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Let .onAppear run and the store-backed context load before capture.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        // Retire the window before the next render, or its content bleeds
        // through the following `drawHierarchy` pass.
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        guard let data = image.pngData() else {
            XCTFail("failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name) → \(outDir.path)")
    }
}
#endif
