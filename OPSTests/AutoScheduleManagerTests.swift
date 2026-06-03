import XCTest
@testable import OPS

// MARK: - Test Helpers

/// Lightweight SchedulableTask for testing — no SwiftData dependency
private struct MockTask: SchedulableTask {
    let id: String
    let taskTypeId: String
    let startDate: Date?
    let endDate: Date?
    let duration: Int
    let effectiveDependencies: [TaskTypeDependency]
    let displayOrder: Int
    let schedulingTeamMemberIds: Set<String>
    let schedulingProjectId: String

    init(
        id: String,
        taskTypeId: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        duration: Int = 1,
        dependencies: [TaskTypeDependency] = [],
        displayOrder: Int = 0,
        teamMemberIds: Set<String> = [],
        projectId: String = "project-1"
    ) {
        self.id = id
        self.taskTypeId = taskTypeId
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.effectiveDependencies = dependencies
        self.displayOrder = displayOrder
        self.schedulingTeamMemberIds = teamMemberIds
        self.schedulingProjectId = projectId
    }
}

/// Provides pre-built task data to AutoScheduleManager without needing DataController
private struct MockScheduleDataProvider: ScheduleDataProvider {
    let allTasks: [any SchedulableTask]
    let projectCoordinates: [String: (lat: Double, lng: Double)]
    let projectPriorities: [String: Date] // projectId -> priority date (won date or fallback)
    var schedulableTasksById: [String: any SchedulableTask] = [:]
    var unranked: [any SchedulableTask] = []

    func tasksForProject(_ projectId: String) -> [any SchedulableTask] {
        allTasks.filter { $0.schedulingProjectId == projectId }
    }

    func allScheduledTasksForMembers(_ memberIds: Set<String>, from date: Date) -> [any SchedulableTask] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: date)
        return allTasks.filter { task in
            guard let taskStart = task.startDate else { return false }
            let taskEnd = task.endDate ?? taskStart
            guard calendar.startOfDay(for: taskEnd) >= startDay else { return false }
            return !task.schedulingTeamMemberIds.isDisjoint(with: memberIds)
        }
    }

    func coordinatesForProject(_ projectId: String) -> (lat: Double, lng: Double)? {
        projectCoordinates[projectId]
    }

    func priorityDateForProject(_ projectId: String) -> Date? {
        projectPriorities[projectId]
    }

    func schedulableTasks(forIds ids: [String]) -> [any SchedulableTask] {
        ids.compactMap { schedulableTasksById[$0] }
    }

    func unrankedActiveSchedulableTasks() -> [any SchedulableTask] { unranked }
}

// MARK: - Tests

final class AutoScheduleManagerTests: XCTestCase {

    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - A: Team Availability

    func testA1_SkipsBookedDays() {
        // Jake booked Mon-Wed on another task
        let monday = date(2026, 4, 6) // Monday
        let wednesday = date(2026, 4, 8)
        let thursday = date(2026, 4, 9)

        let existingTask = MockTask(
            id: "existing-1", taskTypeId: "type-a",
            startDate: monday, endDate: wednesday, duration: 3,
            teamMemberIds: ["jake"], projectId: "project-other"
        )

        let newTask = MockTask(
            id: "new-1", taskTypeId: "type-b", duration: 1,
            teamMemberIds: ["jake"], projectId: "project-1"
        )

        let provider = MockScheduleDataProvider(
            allTasks: [existingTask],
            projectCoordinates: [:],
            projectPriorities: [:]
        )

        let constraints = ScheduleConstraints(
            skipWeekends: false, preciseScheduling: false,
            schedulingWindow: .companyHours(open: "08:00", close: "17:00"),
            proximityRadiusKm: 15.0, weatherConstraints: nil
        )

        let request = ScheduleRequest(
            mode: .single(task: newTask, teamMemberIds: ["jake"]),
            anchorDate: monday,
            constraints: constraints
        )

        let plan = AutoScheduleManager.schedule(request: request, provider: provider)

        XCTAssertEqual(plan.placements.count, 1)
        XCTAssertEqual(calendar.startOfDay(for: plan.placements[0].startDate), thursday)
    }

    func testA2_BothMembersMustBeFree() {
        // Jake free Mon-Fri, Maria booked Mon-Tue
        let monday = date(2026, 4, 6)
        let tuesday = date(2026, 4, 7)
        let wednesday = date(2026, 4, 8)

        let mariaTask = MockTask(
            id: "existing-1", taskTypeId: "type-a",
            startDate: monday, endDate: tuesday, duration: 2,
            teamMemberIds: ["maria"], projectId: "project-other"
        )

        let newTask = MockTask(
            id: "new-1", taskTypeId: "type-b", duration: 1,
            teamMemberIds: ["jake", "maria"], projectId: "project-1"
        )

        let provider = MockScheduleDataProvider(
            allTasks: [mariaTask],
            projectCoordinates: [:],
            projectPriorities: [:]
        )

        let constraints = ScheduleConstraints(
            skipWeekends: false, preciseScheduling: false,
            schedulingWindow: .companyHours(open: "08:00", close: "17:00"),
            proximityRadiusKm: 15.0, weatherConstraints: nil
        )

        let request = ScheduleRequest(
            mode: .single(task: newTask, teamMemberIds: ["jake", "maria"]),
            anchorDate: monday,
            constraints: constraints
        )

        let plan = AutoScheduleManager.schedule(request: request, provider: provider)

        XCTAssertEqual(plan.placements.count, 1)
        XCTAssertEqual(calendar.startOfDay(for: plan.placements[0].startDate), wednesday)
    }

    func testA3_ContiguousBlock() {
        // 3-day task, Jake free Mon, booked Tue, free Wed-Fri
        let monday = date(2026, 4, 6)
        let tuesday = date(2026, 4, 7)
        let wednesday = date(2026, 4, 8)
        let friday = date(2026, 4, 10)

        let jakeTask = MockTask(
            id: "existing-1", taskTypeId: "type-a",
            startDate: tuesday, endDate: tuesday, duration: 1,
            teamMemberIds: ["jake"], projectId: "project-other"
        )

        let newTask = MockTask(
            id: "new-1", taskTypeId: "type-b", duration: 3,
            teamMemberIds: ["jake"], projectId: "project-1"
        )

        let provider = MockScheduleDataProvider(
            allTasks: [jakeTask],
            projectCoordinates: [:],
            projectPriorities: [:]
        )

        let constraints = ScheduleConstraints(
            skipWeekends: false, preciseScheduling: false,
            schedulingWindow: .companyHours(open: "08:00", close: "17:00"),
            proximityRadiusKm: 15.0, weatherConstraints: nil
        )

        let request = ScheduleRequest(
            mode: .single(task: newTask, teamMemberIds: ["jake"]),
            anchorDate: monday,
            constraints: constraints
        )

        let plan = AutoScheduleManager.schedule(request: request, provider: provider)

        XCTAssertEqual(plan.placements.count, 1)
        // Can't fit 3 days starting Mon (Mon ok, Tue blocked, broken block)
        // Must start Wed for contiguous Wed-Fri
        XCTAssertEqual(calendar.startOfDay(for: plan.placements[0].startDate), wednesday)
        XCTAssertEqual(calendar.startOfDay(for: plan.placements[0].endDate), friday)
    }

    func testA6_NoCrewAssigned_WarnsInMetadata() {
        let monday = date(2026, 4, 6)

        let newTask = MockTask(
            id: "new-1", taskTypeId: "type-b", duration: 1,
            teamMemberIds: [], projectId: "project-1"
        )

        let provider = MockScheduleDataProvider(
            allTasks: [],
            projectCoordinates: [:],
            projectPriorities: [:]
        )

        let constraints = ScheduleConstraints(
            skipWeekends: false, preciseScheduling: false,
            schedulingWindow: .companyHours(open: "08:00", close: "17:00"),
            proximityRadiusKm: 15.0, weatherConstraints: nil
        )

        let request = ScheduleRequest(
            mode: .single(task: newTask, teamMemberIds: []),
            anchorDate: monday,
            constraints: constraints
        )

        let plan = AutoScheduleManager.schedule(request: request, provider: provider)

        // Should still schedule (no availability to check)
        XCTAssertEqual(plan.placements.count, 1)
        XCTAssertEqual(calendar.startOfDay(for: plan.placements[0].startDate), monday)
        // Should warn about no crew
        XCTAssertTrue(plan.conflicts.contains { $0.type == .noCrewAssigned })
    }

    // MARK: - B: Dependencies

    func testB1_DependencyRespected() {
        // Task B depends on Task A (0% overlap). A ends Friday.
        let monday = date(2026, 4, 6)
        let friday = date(2026, 4, 10)
        let nextMonday = date(2026, 4, 13)

        let taskA = MockTask(
            id: "task-a", taskTypeId: "type-a",
            startDate: monday, endDate: friday, duration: 5,
            teamMemberIds: ["jake"], projectId: "project-1"
        )

        let dep = TaskTypeDependency(
            dependsOnTaskTypeId: "type-a",
            overlapPercentage: 0
        )

        let taskB = MockTask(
            id: "task-b", taskTypeId: "type-b", duration: 1,
            dependencies: [dep],
            teamMemberIds: ["jake"], projectId: "project-1"
        )

        let provider = MockScheduleDataProvider(
            allTasks: [taskA],
            projectCoordinates: [:],
            projectPriorities: [:]
        )

        let constraints = ScheduleConstraints(
            skipWeekends: true, preciseScheduling: false,
            schedulingWindow: .companyHours(open: "08:00", close: "17:00"),
            proximityRadiusKm: 15.0, weatherConstraints: nil
        )

        let request = ScheduleRequest(
            mode: .single(task: taskB, teamMemberIds: ["jake"]),
            anchorDate: monday,
            constraints: constraints
        )

        let plan = AutoScheduleManager.schedule(request: request, provider: provider)

        XCTAssertEqual(plan.placements.count, 1)
        // A ends Friday, 0% overlap → B starts next day. With skip weekends → Monday
        XCTAssertEqual(calendar.startOfDay(for: plan.placements[0].startDate), nextMonday)
    }

    // MARK: - G: Edge Cases

    func testG1_ZeroDurationTreatedAsOneDay() {
        let monday = date(2026, 4, 6)

        let newTask = MockTask(
            id: "new-1", taskTypeId: "type-b", duration: 0,
            teamMemberIds: ["jake"], projectId: "project-1"
        )

        let provider = MockScheduleDataProvider(
            allTasks: [],
            projectCoordinates: [:],
            projectPriorities: [:]
        )

        let constraints = ScheduleConstraints(
            skipWeekends: false, preciseScheduling: false,
            schedulingWindow: .companyHours(open: "08:00", close: "17:00"),
            proximityRadiusKm: 15.0, weatherConstraints: nil
        )

        let request = ScheduleRequest(
            mode: .single(task: newTask, teamMemberIds: ["jake"]),
            anchorDate: monday,
            constraints: constraints
        )

        let plan = AutoScheduleManager.schedule(request: request, provider: provider)

        XCTAssertEqual(plan.placements.count, 1)
        // Start and end should be same day (1-day minimum)
        XCTAssertEqual(
            calendar.startOfDay(for: plan.placements[0].startDate),
            calendar.startOfDay(for: plan.placements[0].endDate)
        )
    }

    func testG2_PastAnchorClampedToToday() {
        let pastDate = date(2020, 1, 1)
        let today = calendar.startOfDay(for: Date())

        let newTask = MockTask(
            id: "new-1", taskTypeId: "type-b", duration: 1,
            teamMemberIds: [], projectId: "project-1"
        )

        let provider = MockScheduleDataProvider(
            allTasks: [],
            projectCoordinates: [:],
            projectPriorities: [:]
        )

        let constraints = ScheduleConstraints(
            skipWeekends: false, preciseScheduling: false,
            schedulingWindow: .companyHours(open: "08:00", close: "17:00"),
            proximityRadiusKm: 15.0, weatherConstraints: nil
        )

        let request = ScheduleRequest(
            mode: .single(task: newTask, teamMemberIds: []),
            anchorDate: pastDate,
            constraints: constraints
        )

        let plan = AutoScheduleManager.schedule(request: request, provider: provider)

        XCTAssertEqual(plan.placements.count, 1)
        XCTAssertGreaterThanOrEqual(
            calendar.startOfDay(for: plan.placements[0].startDate),
            today
        )
    }

    func testG7_EmptyBatchReturnsEmptyPlan() {
        let provider = MockScheduleDataProvider(
            allTasks: [],
            projectCoordinates: [:],
            projectPriorities: [:]
        )

        let constraints = ScheduleConstraints(
            skipWeekends: false, preciseScheduling: false,
            schedulingWindow: .companyHours(open: "08:00", close: "17:00"),
            proximityRadiusKm: 15.0, weatherConstraints: nil
        )

        let request = ScheduleRequest(
            mode: .projectBatch(projectId: "project-1"),
            anchorDate: Date(),
            constraints: constraints
        )

        let plan = AutoScheduleManager.schedule(request: request, provider: provider)

        XCTAssertTrue(plan.placements.isEmpty)
        XCTAssertTrue(plan.conflicts.isEmpty)
    }
}
