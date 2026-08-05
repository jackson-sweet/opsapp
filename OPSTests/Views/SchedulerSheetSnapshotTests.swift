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
    /// UNSCHEDULE control both present. The task carries its own saved dates,
    /// because that — not the picker's prefill — is what earns the push row.
    func testRescheduleModeShowsPushRowAndUnschedule() throws {
        let world = try World()
        world.item.startDate = world.scheduledStart
        world.item.endDate = world.scheduledEnd
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

    /// The busiest legal 667pt stack: rescheduling a dated task while the
    /// quick-push row carries the cascade toggle and the identity row carries
    /// UNSCHEDULE. The toggle is proven through the dependents branch — a
    /// same-project task that depends on this one — because that count rides
    /// project-scoped queries only. (The crew-ripple branch reads
    /// `DataController.currentUser`, which the app host's async
    /// `checkExistingAuth` can rewrite mid-render; dating this task after the
    /// fence job keeps that branch at zero either way, so the badge is a
    /// deterministic 1.) The month grid compresses to its floor; nav and
    /// footer must both survive on screen.
    func testSmallPhoneWorstCaseReschedule() throws {
        let world = try World()

        let railingsType = TaskType(id: "type-railings", display: "Railings", color: "#8B8778", companyId: "company-1")
        railingsType.dependencies = [
            TaskTypeDependency(dependsOnTaskTypeId: "type-decking", overlapPercentage: 0)
        ]
        world.context.insert(railingsType)
        let railings = ProjectTask(id: "task-railings", projectId: "project-harbour", taskTypeId: railingsType.id, companyId: "company-1")
        railings.taskType = railingsType
        world.context.insert(railings)
        try? world.context.save()

        // Monday + 15/16 — after every seeded job, so only the dependent counts.
        let start = calendar.date(byAdding: .day, value: 7, to: world.conflictStart)!
        let end = calendar.date(byAdding: .day, value: 8, to: world.conflictStart)!
        world.item.startDate = start
        world.item.endDate = end
        snapshot("12_small_phone_worst", size: smallPhone) {
            world.sheet(start: start, end: end, onClearDates: {})
        }
    }

    /// A range that runs across a week boundary. The interior leaves each cap
    /// at exactly the cap's own fill and eases to the quiet floor about a day
    /// in, so there is no seam to find; everything deeper than that stays
    /// calm. Caps are not solid white — the whole fill runs inside the narrow
    /// band between `schedulerSpanCapOpacity` and `schedulerSpanQuietOpacity`,
    /// and the hairline outline above it is the brightest thing in the
    /// selection. That outline closes only at the two caps, staying open where
    /// the rows wrap.
    func testMultiWeekRangeGradientAndOutline() throws {
        let world = try World()
        let start = world.preFloorStart
        let end = calendar.date(byAdding: .day, value: 10, to: start)!
        snapshot("13_span_gradient_wrap", size: phone) {
            world.sheet(start: start, end: end)
        }
    }

    /// Dates picked on a task that was never saved. The quick-push row must be
    /// ABSENT — there is nothing on the calendar to push yet.
    func testDraftShellHidesTheQuickPushRow() throws {
        let world = try World()
        snapshot("14_draft_no_push_row", size: phone) {
            world.draftShellSheet(start: world.scheduledStart, end: world.scheduledEnd)
        }
    }

    /// The same dates on a task that genuinely is on the calendar: the
    /// quick-push row is present. Read 14 and 15 as a pair.
    func testScheduledTaskShowsTheQuickPushRow() throws {
        let world = try World()
        world.item.startDate = world.scheduledStart
        world.item.endDate = world.scheduledEnd
        snapshot("15_scheduled_push_row", size: phone) {
            world.sheet(start: world.scheduledStart, end: world.scheduledEnd)
        }
    }

    /// A task with no prerequisite at all. The proposal comes from the crew's
    /// own calendar instead, and the chip says exactly that.
    func testCrewClearSuggestionChip() throws {
        let world = try World()
        snapshot("16_crew_clear_suggestion", size: phone) {
            world.sheet(for: world.independent, start: nil, end: nil)
        }
    }

    /// The two short spans, each on its own clean week row — the cases the
    /// curve is judged on. A sheet holds one selection at a time, so they are
    /// two frames rather than one.
    ///
    /// 17: three days. The lone interior belongs to both caps at once, so it
    /// leaves each seam at the cap's own fill and eases only to the midpoint of
    /// the fill range dead centre — the loudest the curve ever gets, and
    /// correct.
    /// 18: five days. Only the cap-adjacent days glow; the day between them
    /// sits flat on the quiet floor. Read as a pair with 13, where the same
    /// shape holds at both ends of an eleven-day range.
    func testShortSpanGradients() throws {
        let world = try World()

        // Both ranges open on the dependency floor or later and clear every
        // seeded job, so nothing dims and no signal bar crowds the read. Each
        // one also lands inside a single week row: the point is how a cap and
        // its neighbour meet, and a wrap is not what is on trial here.
        let shortStart = world.floorDay
        let shortEnd = calendar.date(byAdding: .day, value: 2, to: shortStart)!
        snapshot("17_short_span_gradient", size: phone) {
            world.sheet(start: shortStart, end: shortEnd)
        }

        let fiveStart = calendar.date(byAdding: .day, value: 10, to: world.floorDay)!
        let fiveEnd = calendar.date(byAdding: .day, value: 4, to: fiveStart)!
        snapshot("18_five_day_gradient", size: phone) {
            world.sheet(start: fiveStart, end: fiveEnd)
        }
    }

    /// The same empty state as 01, on a job whose project has a measured deck
    /// and whose company has already finished three comparable ones. The chip
    /// gains a third clause — "~2 DAYS" — read off those jobs, and one tap now
    /// picks the whole span instead of only a start, so SAVE is live
    /// immediately. Read 01 and 19 as a pair: nothing else about the sheet
    /// moves, and 16 stays date-only because fence work has no such history.
    func testLengthSuggestionChip() throws {
        let world = try World()
        world.stageComparableDeckHistory()
        snapshot("19_length_suggestion_chip", size: phone) {
            world.sheet(start: nil, end: nil)
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
        /// A task with a real crew but nothing upstream to wait on — the state
        /// that earns a CREW CLEAR proposal rather than an AFTER-prerequisite
        /// one. Deliberately left undated so the suggestion chip appears.
        let independent: ProjectTask
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
                CalendarUserEvent.self,
                DeckDesign.self
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

            // Fence panels on the same site: a dependency-free task type, so
            // nothing constrains it but Dana's own calendar.
            independent = ProjectTask(id: "task-fence-harbour", projectId: harbour.id, taskTypeId: fenceType.id, companyId: "company-1")
            independent.taskType = fenceType
            independent.project = harbour
            independent.duration = 1
            independent.setTeamMemberIds([dana.id])
            independent.teamMembers = [dana]
            context.insert(independent)

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
            sheet(for: item, start: start, end: end, onClearDates: onClearDates)
        }

        @ViewBuilder
        func sheet(
            for task: ProjectTask,
            start: Date?,
            end: Date?,
            onClearDates: (() -> Void)? = nil
        ) -> some View {
            CalendarSchedulerSheet(
                isPresented: .constant(true),
                itemType: .task(task),
                currentStartDate: start,
                currentEndDate: end,
                onScheduleUpdate: { _, _ in },
                onClearDates: onClearDates
            )
            .environmentObject(dataController)
            .modelContainer(container)
        }

        /// Exactly what TaskFormSheet hands the scheduler before a task has
        /// ever been saved: a freshly constructed shell carrying no dates of
        /// its own, alongside the form's in-flight picks.
        @ViewBuilder
        func draftShellSheet(start: Date?, end: Date?) -> some View {
            sheet(
                for: ProjectTask(
                    id: UUID().uuidString.lowercased(),
                    projectId: "project-harbour",
                    taskTypeId: "type-decking",
                    companyId: "company-1",
                    status: .active
                ),
                start: start,
                end: end
            )
        }

        /// A measured deck on the job's own project, plus three finished
        /// decking jobs on decks of a comparable size — the history the
        /// duration suggestion reads.
        ///
        /// Staged on request rather than in `init` so every other state keeps
        /// its date-only chip and 01 / 19 read as a before-and-after pair. The
        /// comps sit six months back: genuinely finished work, and far enough
        /// behind the month the grid opens on that no existing state picks up a
        /// signal from them.
        func stageComparableDeckHistory() {
            stageDeck(id: "design-harbour", projectId: "project-harbour", areaSqFt: 400)

            // 380 / 420 / 440 sqft against a 400 sqft deck: all inside the
            // 1.3× band, days 2 / 2 / 3, so the middle job is two days.
            let comps: [(title: String, areaSqFt: Double, dayCount: Int)] = [
                (title: "Ferndale Deck", areaSqFt: 380, dayCount: 2),
                (title: "Quadra Deck", areaSqFt: 420, dayCount: 2),
                (title: "Sooke Deck", areaSqFt: 440, dayCount: 3)
            ]

            let today = calendar.startOfDay(for: Date())
            for (index, comp) in comps.enumerated() {
                let projectId = "project-comp-\(index)"
                let project = Project(id: projectId, title: comp.title, status: .completed)
                project.companyId = "company-1"
                context.insert(project)

                stageDeck(id: "design-comp-\(index)", projectId: projectId, areaSqFt: comp.areaSqFt)

                let end = calendar.date(byAdding: .day, value: -180 + index * 7, to: today)!
                let job = ProjectTask(
                    id: "task-comp-\(index)",
                    projectId: projectId,
                    taskTypeId: "type-decking",
                    companyId: "company-1",
                    status: .completed
                )
                job.project = project
                job.startDate = calendar.date(byAdding: .day, value: -(comp.dayCount - 1), to: end)!
                job.endDate = end
                job.duration = comp.dayCount
                context.insert(job)
            }

            try? context.save()
        }

        /// One rectangular deck at a known real-world size, serialized the way
        /// the builder saves one: a canvas point per inch, so 240 × 240 is
        /// 20' × 20' — 400 sqft.
        private func stageDeck(id: String, projectId: String, areaSqFt: Double) {
            let width = 240.0
            let depth = areaSqFt * 144.0 / width
            let corners: [CGPoint] = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: width, y: 0),
                CGPoint(x: width, y: depth),
                CGPoint(x: 0, y: depth)
            ]

            var drawing = DeckDrawingData()
            drawing.scaleFactor = 1
            drawing.vertices = corners.enumerated().map { index, point in
                DeckVertex(id: "\(id)-v\(index)", position: point)
            }
            drawing.edges = corners.indices.map { index in
                DeckEdge(
                    id: "\(id)-e\(index)",
                    startVertexId: "\(id)-v\(index)",
                    endVertexId: "\(id)-v\((index + 1) % corners.count)"
                )
            }

            let design = DeckDesign(
                id: id,
                companyId: "company-1",
                projectId: projectId,
                title: "Deck",
                drawingDataJSON: drawing.toJSON()
            )
            design.updatedAt = Date()
            context.insert(design)
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
        // A UIWindow inherits the device safe-area insets whatever its frame —
        // ignoring safe area keeps content at its natural origin instead of
        // displaced down and bottom-clipped (the 76pt footer canvases lost
        // their buttons to it; same correction as DaySheetRowSnapshotTests).
        let host = UIHostingController(rootView: content().ignoresSafeArea())
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
