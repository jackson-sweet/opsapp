//
//  SchedulerDayContextTests.swift
//  OPSTests
//
//  Coverage for the schedule sheet's availability engine: the ranged
//  user-event fetch that feeds it, the per-day signals it emits, the
//  dependency floor, conflict review, proximity, and the plain-language
//  day interpretation shown in the long-press inspector.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class SchedulerDayContextTests: XCTestCase {

    private let calendar = Calendar.current

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    // MARK: - Task 1 — Ranged user-event fetch

    func testGetUserEventsInRangeReturnsOnlyApprovedOrUnmanagedNonDeletedOverlaps() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let dataController = DataController()
        dataController.setModelContext(context)

        let user = User(id: "user-1", firstName: "Marcus", lastName: "Hale", role: .crew, companyId: "company-1")
        context.insert(user)
        dataController.currentUser = user

        let approved = makeEvent(id: "approved", start: day(2026, 8, 10), end: day(2026, 8, 12))
        approved.status = CalendarUserEventStatus.approved.rawValue

        let unmanaged = makeEvent(id: "unmanaged", start: day(2026, 8, 11), end: day(2026, 8, 11))
        unmanaged.status = CalendarUserEventStatus.none.rawValue

        let denied = makeEvent(id: "denied", start: day(2026, 8, 10), end: day(2026, 8, 12))
        denied.status = CalendarUserEventStatus.denied.rawValue

        let pending = makeEvent(id: "pending", start: day(2026, 8, 10), end: day(2026, 8, 12))
        pending.status = CalendarUserEventStatus.pending.rawValue

        let deleted = makeEvent(id: "deleted", start: day(2026, 8, 10), end: day(2026, 8, 12))
        deleted.status = CalendarUserEventStatus.approved.rawValue
        deleted.deletedAt = Date()

        let otherCompany = makeEvent(id: "other-company", start: day(2026, 8, 10), end: day(2026, 8, 12))
        otherCompany.companyId = "company-2"
        otherCompany.status = CalendarUserEventStatus.approved.rawValue

        let outOfRange = makeEvent(id: "out-of-range", start: day(2026, 9, 20), end: day(2026, 9, 21))
        outOfRange.status = CalendarUserEventStatus.approved.rawValue

        for event in [approved, unmanaged, denied, pending, deleted, otherCompany, outOfRange] {
            context.insert(event)
        }

        let fetched = dataController.getUserEvents(in: day(2026, 8, 1)...day(2026, 8, 31))

        XCTAssertEqual(Set(fetched.map(\.id)), ["approved", "unmanaged"])
    }

    // MARK: - Task 2 — Dependency floor

    func testFloorComesFromTheLatestScheduledPrerequisiteOnly() {
        let context = makeContext(
            item: item(dependencies: [dependency(on: "framing"), dependency(on: "electrical")]),
            prerequisites: [
                .init(taskTypeId: "framing", title: "Framing", start: day(2026, 8, 10), duration: 3),
                .init(taskTypeId: "electrical", title: "Electrical", start: day(2026, 8, 17), duration: 2)
            ]
        )

        // Electrical runs 17–18, so the first legal day is the 19th, and the
        // note must name the prerequisite that actually set the floor.
        XCTAssertEqual(context.dependencyFloor, day(2026, 8, 19))
        XCTAssertEqual(context.floorPrerequisiteTitle, "Electrical")
    }

    func testUnscheduledPrerequisitesProduceNoFloorAndNoDimmedDays() {
        let context = makeContext(
            item: item(dependencies: [dependency(on: "framing")]),
            prerequisites: []
        )

        XCTAssertNil(context.dependencyFloor)
        XCTAssertNil(context.suggestion)
        for offset in -10...10 {
            let probe = calendar.date(byAdding: .day, value: offset, to: day(2026, 8, 15))!
            XCTAssertFalse(context.signals(for: probe).isPreFloor, "offset \(offset) must not dim")
        }
    }

    func testDaysBeforeTheFloorDimButRemainSelectable() {
        let context = makeContext(
            item: item(dependencies: [dependency(on: "framing")]),
            prerequisites: [
                .init(taskTypeId: "framing", title: "Framing", start: day(2026, 8, 10), duration: 3)
            ]
        )

        XCTAssertTrue(context.signals(for: day(2026, 8, 12)).isPreFloor)
        XCTAssertFalse(context.signals(for: day(2026, 8, 13)).isPreFloor)

        // Selecting into the dim zone is a note, never a block.
        let review = context.rangeReview(start: day(2026, 8, 11), end: day(2026, 8, 14))
        XCTAssertEqual(review.floorViolation, day(2026, 8, 13))
        XCTAssertTrue(SchedulerSelection.range(day(2026, 8, 11), day(2026, 8, 14)).isCommittable)
    }

    func testDependencyFloorMatchesAutoScheduleManager() {
        let dependencies = [dependency(on: "framing")]
        let prerequisiteStart = day(2026, 8, 10)

        let context = makeContext(
            item: item(dependencies: dependencies),
            prerequisites: [
                .init(taskTypeId: "framing", title: "Framing", start: prerequisiteStart, duration: 3)
            ]
        )

        let engineFloor = AutoScheduleManager.calculateDependencyFloor(
            for: FloorProbeTask(id: "item", taskTypeId: "decking", dependencies: dependencies),
            allProjectTasks: [
                FloorProbeTask(
                    id: "framing-1",
                    taskTypeId: "framing",
                    startDate: prerequisiteStart,
                    duration: 3
                )
            ],
            anchor: .distantPast,
            skipWeekends: false
        )

        XCTAssertEqual(context.dependencyFloor, calendar.startOfDay(for: engineFloor))
    }

    // MARK: - Task 2 — Day signals

    func testTimeOffTouchingTheCrewMarksTheDayAndNamesThePerson() {
        let context = makeContext(
            item: item(crewIds: ["marcus"]),
            events: [
                timeOffEvent(id: "off-1", start: day(2026, 8, 12), end: day(2026, 8, 12), crew: ["marcus": "Marcus"])
            ]
        )

        let signals = context.signals(for: day(2026, 8, 12))
        XCTAssertTrue(signals.crewTimeOff)
        XCTAssertFalse(signals.crewBusy)
        XCTAssertEqual(context.interpretation(for: day(2026, 8, 12)), "MARCUS OFF")
    }

    func testTimeOffForSomebodyElseIsDensityNotAnAbsence() {
        let context = makeContext(
            item: item(crewIds: ["marcus"]),
            events: [
                timeOffEvent(id: "off-1", start: day(2026, 8, 12), end: day(2026, 8, 12), crew: ["dana": "Dana"])
            ]
        )

        let signals = context.signals(for: day(2026, 8, 12))
        XCTAssertFalse(signals.crewTimeOff)
        XCTAssertEqual(signals.otherCount, 1)
    }

    func testTheTaskBeingRescheduledNeverCountsAgainstItself() {
        let context = makeContext(
            item: item(selfTaskId: "task-self", projectId: "project-1", crewIds: ["marcus"]),
            events: [
                jobEvent(
                    id: "task-self",
                    start: day(2026, 8, 12),
                    end: day(2026, 8, 12),
                    projectId: "project-1",
                    crew: ["marcus": "Marcus"]
                )
            ]
        )

        XCTAssertEqual(context.signals(for: day(2026, 8, 12)), SchedulerDayContext.DaySignals())
        XCTAssertTrue(context.events(on: day(2026, 8, 12)).relevant.isEmpty)
        XCTAssertEqual(context.rangeReview(start: day(2026, 8, 12), end: day(2026, 8, 12)).conflictCount, 0)
        XCTAssertEqual(context.interpretation(for: day(2026, 8, 12)), "CREW CLEAR")
    }

    func testAMultiDayJobLandsOnEveryDayItSpansExactlyOnce() {
        let context = makeContext(
            item: item(crewIds: ["marcus"]),
            events: [
                jobEvent(
                    id: "job-1",
                    start: day(2026, 8, 10),
                    end: day(2026, 8, 12),
                    crew: ["marcus": "Marcus"]
                )
            ]
        )

        for dayOfMonth in 10...12 {
            let probe = day(2026, 8, dayOfMonth)
            XCTAssertTrue(context.signals(for: probe).crewBusy, "day \(dayOfMonth)")
            XCTAssertEqual(context.events(on: probe).relevant.count, 1, "day \(dayOfMonth)")
        }
        XCTAssertFalse(context.signals(for: day(2026, 8, 13)).crewBusy)

        // The range review dedupes across the span — one job, one row.
        let review = context.rangeReview(start: day(2026, 8, 9), end: day(2026, 8, 14))
        XCTAssertEqual(review.rows.count, 1)
        XCTAssertEqual(review.conflictCount, 1)
    }

    // MARK: - Task 2 — Attribution, ordering, distance

    func testAttributionNamesOnePersonAndCountsACrew() {
        let context = makeContext(
            item: item(crewIds: ["marcus", "dana"]),
            events: [
                jobEvent(id: "solo", start: day(2026, 8, 10), end: day(2026, 8, 10), crew: ["marcus": "Marcus"]),
                jobEvent(
                    id: "pair",
                    start: day(2026, 8, 11),
                    end: day(2026, 8, 11),
                    crew: ["marcus": "Marcus", "dana": "Dana"]
                )
            ]
        )

        let solo = context.events(on: day(2026, 8, 10)).relevant[0]
        let pair = context.events(on: day(2026, 8, 11)).relevant[0]
        XCTAssertEqual(context.attribution(for: solo), "MARCUS")
        XCTAssertEqual(context.attribution(for: pair), "2 CREW")
    }

    func testRangeRowsLeadWithConflicts() {
        let context = makeContext(
            item: item(projectId: "project-1", crewIds: ["marcus"]),
            events: [
                jobEvent(
                    id: "same-project",
                    start: day(2026, 8, 10),
                    end: day(2026, 8, 10),
                    projectId: "project-1"
                ),
                jobEvent(
                    id: "crew-clash",
                    start: day(2026, 8, 12),
                    end: day(2026, 8, 12),
                    crew: ["marcus": "Marcus"]
                )
            ]
        )

        let review = context.rangeReview(start: day(2026, 8, 9), end: day(2026, 8, 13))
        XCTAssertEqual(review.rows.map(\.id), ["crew-clash", "same-project"])
        XCTAssertEqual(review.conflictCount, 1)
    }

    func testDistanceReadsCloseInTenthsAndFarInWholeKilometres() {
        XCTAssertEqual(SchedulerDayContext.distanceLabel(2.14), "2.1 KM")
        XCTAssertEqual(SchedulerDayContext.distanceLabel(11.6), "12 KM")

        let context = makeContext(
            item: item(latitude: 48.4284, longitude: -123.3656),
            events: [
                jobEvent(id: "no-coords", start: day(2026, 8, 10), end: day(2026, 8, 10))
            ]
        )
        let event = context.events.first { $0.id == "no-coords" }!
        XCTAssertNil(context.distanceKM(to: event))
        XCTAssertNil(context.distanceLabel(to: event))
    }

    func testDistanceIsMeasuredBetweenTheTwoJobSites() {
        let context = makeContext(
            item: item(latitude: 48.4284, longitude: -123.3656),
            events: [
                jobEvent(
                    id: "nearby",
                    start: day(2026, 8, 10),
                    end: day(2026, 8, 10),
                    latitude: 48.4484,
                    longitude: -123.3656
                )
            ]
        )
        let event = context.events.first { $0.id == "nearby" }!
        let km = try? XCTUnwrap(context.distanceKM(to: event))
        XCTAssertEqual(km ?? 0, 2.2, accuracy: 0.2)
        XCTAssertEqual(context.distanceLabel(to: event), "2.2 KM")
    }

    func testDistanceIsSuppressedForWorkOnTheSameSite() {
        let context = makeContext(
            item: item(projectId: "project-1", latitude: 48.4284, longitude: -123.3656),
            events: [
                jobEvent(
                    id: "same-site",
                    start: day(2026, 8, 10),
                    end: day(2026, 8, 10),
                    projectId: "project-1",
                    latitude: 48.4284,
                    longitude: -123.3656
                )
            ]
        )
        let event = context.events.first { $0.id == "same-site" }!
        XCTAssertNil(context.distanceLabel(to: event), "0.0 KM to your own site is noise, not data")
    }

    // MARK: - Task 2 — Interpretation priority

    func testInterpretationLeadsWithTimeOffThenCrewAndStopsAtTwoClauses() {
        let context = makeContext(
            item: item(projectId: "project-1", crewIds: ["marcus", "dana"], dependencies: [dependency(on: "framing")]),
            events: [
                timeOffEvent(id: "off", start: day(2026, 8, 11), end: day(2026, 8, 11), crew: ["marcus": "Marcus"]),
                jobEvent(
                    id: "busy",
                    title: "Harbour Deck",
                    start: day(2026, 8, 11),
                    end: day(2026, 8, 11),
                    crew: ["dana": "Dana"]
                ),
                jobEvent(
                    id: "same-project",
                    start: day(2026, 8, 11),
                    end: day(2026, 8, 11),
                    projectId: "project-1",
                    taskTitle: "Railings"
                )
            ],
            prerequisites: [
                .init(taskTypeId: "framing", title: "Framing", start: day(2026, 8, 20), duration: 2)
            ]
        )

        // Time off wins, crew-busy second, and the floor note + same-project
        // clause are dropped rather than making a third and fourth clause.
        XCTAssertEqual(
            context.interpretation(for: day(2026, 8, 11)),
            "MARCUS OFF · DANA ON HARBOUR DECK"
        )
    }

    func testInterpretationFallsThroughToTheFloorNoteThenTheProject() {
        let floorOnly = makeContext(
            item: item(dependencies: [dependency(on: "framing")]),
            prerequisites: [
                .init(taskTypeId: "framing", title: "Framing", start: day(2026, 8, 20), duration: 2)
            ]
        )
        XCTAssertEqual(
            floorOnly.interpretation(for: day(2026, 8, 11)),
            "BEFORE FRAMING ENDS · AUG 22"
        )

        let projectOnly = makeContext(
            item: item(projectId: "project-1", crewIds: ["marcus"]),
            events: [
                jobEvent(
                    id: "same-project",
                    start: day(2026, 8, 11),
                    end: day(2026, 8, 11),
                    projectId: "project-1",
                    taskTitle: "Railings"
                )
            ]
        )
        XCTAssertEqual(
            projectOnly.interpretation(for: day(2026, 8, 11)),
            "RAILINGS · THIS PROJECT"
        )
    }

    func testInterpretationCountsACrewWhenMoreThanOnePersonIsBusy() {
        let context = makeContext(
            item: item(crewIds: ["marcus", "dana"]),
            events: [
                jobEvent(id: "a", start: day(2026, 8, 11), end: day(2026, 8, 11), crew: ["marcus": "Marcus"]),
                jobEvent(id: "b", start: day(2026, 8, 11), end: day(2026, 8, 11), crew: ["dana": "Dana"])
            ]
        )
        XCTAssertEqual(context.interpretation(for: day(2026, 8, 11)), "2 CREW ON OTHER JOBS")
    }

    func testInterpretationWithoutCrewContextReportsTheDayNotAvailability() {
        let context = makeContext(item: item(crewIds: []))
        XCTAssertEqual(context.interpretation(for: day(2026, 8, 11)), "NO JOBS")
    }

    // MARK: - Task 2 — Suggestion

    func testSuggestionOnlyAppearsForAnUnscheduledItemWithAFloor() {
        let unscheduled = makeContext(
            item: item(dependencies: [dependency(on: "framing")], isScheduled: false),
            prerequisites: [
                .init(taskTypeId: "framing", title: "Framing", start: day(2026, 8, 10), duration: 3)
            ]
        )
        XCTAssertEqual(unscheduled.suggestion, day(2026, 8, 13))

        let scheduled = makeContext(
            item: item(dependencies: [dependency(on: "framing")], isScheduled: true),
            prerequisites: [
                .init(taskTypeId: "framing", title: "Framing", start: day(2026, 8, 10), duration: 3)
            ]
        )
        XCTAssertNil(scheduled.suggestion)
    }

    func testSuggestionStepsOverTheWeekendWhenTheCompanySkipsWeekends() {
        // Anchor the prerequisite so its floor lands on a Saturday, whatever
        // the calendar does — the rule under test is the weekend step, not a
        // hardcoded date.
        var saturday = day(2026, 8, 1)
        while calendar.component(.weekday, from: saturday) != 7 {
            saturday = calendar.date(byAdding: .day, value: 1, to: saturday)!
        }
        let prerequisiteStart = calendar.date(byAdding: .day, value: -1, to: saturday)!
        let monday = calendar.date(byAdding: .day, value: 2, to: saturday)!

        let prerequisites: [SchedulerDayContext.Prerequisite] = [
            .init(taskTypeId: "framing", title: "Framing", start: prerequisiteStart, duration: 1)
        ]

        let skipping = makeContext(
            item: item(dependencies: [dependency(on: "framing")], isScheduled: false),
            prerequisites: prerequisites,
            skipsWeekends: true
        )
        XCTAssertEqual(skipping.suggestion, monday)

        let notSkipping = makeContext(
            item: item(dependencies: [dependency(on: "framing")], isScheduled: false),
            prerequisites: prerequisites,
            skipsWeekends: false
        )
        XCTAssertEqual(notSkipping.suggestion, saturday)
    }

    // MARK: - Fixtures

    private func makeContext(
        item: SchedulerDayContext.Item,
        events: [SchedulerDayContext.Event] = [],
        prerequisites: [SchedulerDayContext.Prerequisite] = [],
        skipsWeekends: Bool = false
    ) -> SchedulerDayContext {
        SchedulerDayContext(
            item: item,
            events: events,
            prerequisites: prerequisites,
            skipsWeekends: skipsWeekends,
            calendar: calendar
        )
    }

    private func item(
        selfTaskId: String? = nil,
        projectId: String? = nil,
        crewIds: Set<String> = [],
        latitude: Double? = nil,
        longitude: Double? = nil,
        dependencies: [TaskTypeDependency] = [],
        isScheduled: Bool = false
    ) -> SchedulerDayContext.Item {
        SchedulerDayContext.Item(
            selfTaskId: selfTaskId,
            projectId: projectId,
            crewIds: crewIds,
            latitude: latitude,
            longitude: longitude,
            dependencies: dependencies,
            isScheduled: isScheduled
        )
    }

    /// Finish-to-start: zero overlap means the dependent starts the day after
    /// its predecessor's last day.
    private func dependency(on taskTypeId: String) -> TaskTypeDependency {
        TaskTypeDependency(dependsOnTaskTypeId: taskTypeId, overlapPercentage: 0)
    }

    private func jobEvent(
        id: String,
        title: String = "Harbour Deck",
        start: Date,
        end: Date,
        projectId: String? = nil,
        taskTitle: String? = nil,
        crew: [String: String] = [:],
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> SchedulerDayContext.Event {
        SchedulerDayContext.Event(
            id: id,
            kind: .job,
            title: title,
            subtitle: "Faye Keys",
            taskTitle: taskTitle,
            projectId: projectId,
            start: start,
            end: end,
            crewIds: Set(crew.keys),
            crewFirstNames: crew,
            latitude: latitude,
            longitude: longitude
        )
    }

    private func timeOffEvent(
        id: String,
        start: Date,
        end: Date,
        crew: [String: String]
    ) -> SchedulerDayContext.Event {
        SchedulerDayContext.Event(
            id: id,
            kind: .timeOff,
            title: crew.values.first ?? "Crew",
            start: start,
            end: end,
            crewIds: Set(crew.keys),
            crewFirstNames: crew
        )
    }

    /// Minimal `SchedulableTask` used only to pin our floor against the
    /// auto-scheduler's own implementation.
    private struct FloorProbeTask: SchedulableTask {
        let id: String
        let taskTypeId: String
        var startDate: Date?
        var endDate: Date?
        var duration: Int = 1
        var effectiveDependencies: [TaskTypeDependency] = []
        var displayOrder: Int = 0
        var schedulingTeamMemberIds: Set<String> = []
        var schedulingProjectId: String = "project-1"

        init(
            id: String,
            taskTypeId: String,
            startDate: Date? = nil,
            duration: Int = 1,
            dependencies: [TaskTypeDependency] = []
        ) {
            self.id = id
            self.taskTypeId = taskTypeId
            self.startDate = startDate
            self.duration = duration
            self.effectiveDependencies = dependencies
        }
    }

    private func makeEvent(
        id: String,
        start: Date,
        end: Date,
        type: CalendarUserEventType = .timeOff,
        userId: String = "user-1",
        teamMemberIds: [String]? = nil
    ) -> CalendarUserEvent {
        CalendarUserEvent(
            id: id,
            userId: userId,
            companyId: "company-1",
            type: type,
            title: "Time off",
            startDate: start,
            endDate: end,
            teamMemberIds: teamMemberIds
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
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
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
