import XCTest
@testable import OPS

final class PriorityQueueSchedulingTests: XCTestCase {
    private let cal = Calendar.current
    private func d(_ y: Int, _ m: Int, _ dd: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: dd))! }

    private struct Mock: SchedulableTask {
        let id: String
        let taskTypeId: String
        var startDate: Date? = nil
        var endDate: Date? = nil
        var duration: Int = 1
        var effectiveDependencies: [TaskTypeDependency] = []
        var displayOrder: Int = 0
        var schedulingTeamMemberIds: Set<String> = ["crew"]
        var schedulingProjectId: String = "p1"
    }

    private struct Provider: ScheduleDataProvider {
        var tasks: [String: any SchedulableTask]
        var unranked: [any SchedulableTask] = []
        func tasksForProject(_ id: String) -> [any SchedulableTask] { tasks.values.filter { $0.schedulingProjectId == id } }
        func allScheduledTasksForMembers(_ m: Set<String>, from date: Date) -> [any SchedulableTask] { [] }
        func coordinatesForProject(_ id: String) -> (lat: Double, lng: Double)? { nil }
        func priorityDateForProject(_ id: String) -> Date? { nil }
        func schedulableTasks(forIds ids: [String]) -> [any SchedulableTask] { ids.compactMap { tasks[$0] } }
        func unrankedActiveSchedulableTasks() -> [any SchedulableTask] { unranked }
    }

    private func constraints() -> ScheduleConstraints {
        ScheduleConstraints(skipWeekends: false, preciseScheduling: false,
            schedulingWindow: .companyHours(open: "08:00", close: "17:00"),
            proximityRadiusKm: 15, weatherConstraints: nil)
    }

    func testPlacesIndependentTasksInPriorityOrderBackToBack() {
        let a = Mock(id: "a", taskTypeId: "ta", duration: 2, schedulingProjectId: "p1")
        let b = Mock(id: "b", taskTypeId: "tb", duration: 1, schedulingProjectId: "p2")
        let p = Provider(tasks: ["a": a, "b": b])
        let req = ScheduleRequest(mode: .taskPriorityQueue(orderedTaskIds: ["a", "b"], includeUnranked: false), anchorDate: d(2026, 4, 6), constraints: constraints())
        let plan = AutoScheduleManager.schedule(request: req, provider: p)
        XCTAssertEqual(plan.placements.count, 2)
        let pa = plan.placements.first { $0.id == "a" }!
        let pb = plan.placements.first { $0.id == "b" }!
        XCTAssertEqual(cal.startOfDay(for: pa.startDate), d(2026, 4, 6))   // Mon–Tue
        XCTAssertEqual(cal.startOfDay(for: pb.startDate), d(2026, 4, 8))   // Wed, after a's crew block
    }

    func testDependencyForcesPredecessorFirstEvenWhenRankedLower() {
        // Same project, same crew. "framing" depends on "footings".
        // User ranks framing ABOVE footings — dependency must still win.
        let footings = Mock(id: "foot", taskTypeId: "footings", duration: 1, schedulingProjectId: "p1")
        let dep = TaskTypeDependency(dependsOnTaskTypeId: "footings", overlapPercentage: 0, overlapMode: "after_end")
        let framing = Mock(id: "frame", taskTypeId: "framing", duration: 1, effectiveDependencies: [dep], schedulingProjectId: "p1")
        let p = Provider(tasks: ["foot": footings, "frame": framing])
        let req = ScheduleRequest(mode: .taskPriorityQueue(orderedTaskIds: ["frame", "foot"], includeUnranked: false), anchorDate: d(2026, 4, 6), constraints: constraints())
        let plan = AutoScheduleManager.schedule(request: req, provider: p)
        let pf = plan.placements.first { $0.id == "foot" }!
        let pframe = plan.placements.first { $0.id == "frame" }!
        XCTAssertLessThan(pf.startDate, pframe.startDate)   // footings scheduled before framing
    }

    func testIncludeUnrankedAppendsTailAfterRanked() {
        let a = Mock(id: "a", taskTypeId: "ta", duration: 1, schedulingProjectId: "p1")
        let u = Mock(id: "u", taskTypeId: "tu", duration: 1, schedulingProjectId: "p2")
        let p = Provider(tasks: ["a": a, "u": u], unranked: [u])
        let req = ScheduleRequest(mode: .taskPriorityQueue(orderedTaskIds: ["a"], includeUnranked: true), anchorDate: d(2026, 4, 6), constraints: constraints())
        let plan = AutoScheduleManager.schedule(request: req, provider: p)
        XCTAssertEqual(Set(plan.placements.map(\.id)), ["a", "u"])
    }

    func testExcludeUnrankedSchedulesOnlyRanked() {
        let a = Mock(id: "a", taskTypeId: "ta", schedulingProjectId: "p1")
        let u = Mock(id: "u", taskTypeId: "tu", schedulingProjectId: "p2")
        let p = Provider(tasks: ["a": a, "u": u], unranked: [u])
        let req = ScheduleRequest(mode: .taskPriorityQueue(orderedTaskIds: ["a"], includeUnranked: false), anchorDate: d(2026, 4, 6), constraints: constraints())
        let plan = AutoScheduleManager.schedule(request: req, provider: p)
        XCTAssertEqual(plan.placements.map(\.id), ["a"])
    }
}
