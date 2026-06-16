//
//  InboundChangeSignalDataActorTests.swift
//  OPSTests
//
//  Verifies that DataActor's inbound merge paths announce themselves via
//  `.inboundDataMerged` — the signal that repaints the calendar when a
//  teammate's schedule change arrives over Realtime — and that the new
//  CalendarUserEvent realtime merge writes correctly (this entity was
//  missing from the actor's syncOrder entirely, so user events never
//  synced inbound while FeatureFlags.useDataActor was on).
//

import SwiftData
import XCTest
@testable import OPS

final class InboundChangeSignalDataActorTests: XCTestCase {

    // MARK: - Harness

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            User.self,
            SyncOperation.self,
            CalendarUserEvent.self,
            ProjectVinylOrderMarker.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeTaskDTO(
        id: String,
        companyId: String = "company-1",
        projectId: String = "project-1",
        startDate: String? = "2026-06-10T00:00:00+00:00",
        endDate: String? = "2026-06-11T00:00:00+00:00"
    ) -> SupabaseProjectTaskDTO {
        SupabaseProjectTaskDTO(
            id: id,
            bubbleId: nil,
            companyId: companyId,
            projectId: projectId,
            taskTypeId: nil,
            customTitle: "Footings",
            taskNotes: nil,
            status: "scheduled",
            taskColor: nil,
            displayOrder: 0,
            teamMemberIds: nil,
            sourceLineItemId: nil,
            sourceEstimateId: nil,
            startDate: startDate,
            endDate: endDate,
            duration: 2,
            dependencyOverrides: nil,
            startTime: nil,
            endTime: nil,
            pairedFromTaskId: nil,
            scheduleLocked: nil,
            deletedAt: nil,
            createdAt: nil
        )
    }

    /// Decodes a CalendarUserEventDTO the same way the realtime path does —
    /// through SupabaseDate.makeISODecoder() — because the DTO's custom
    /// init(from:) suppresses the memberwise initializer.
    private func makeUserEventDTO(
        id: String,
        userId: String,
        title: String = "Time off",
        deletedAt: String? = nil
    ) throws -> CalendarUserEventDTO {
        let deletedAtJSON = deletedAt.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
            "id": "\(id)",
            "user_id": "\(userId)",
            "company_id": "company-1",
            "type": "time_off",
            "title": "\(title)",
            "start_date": "2026-06-15T00:00:00+00:00",
            "end_date": "2026-06-16T00:00:00+00:00",
            "all_day": true,
            "notes": null,
            "status": "approved",
            "address": null,
            "team_member_ids": null,
            "reviewed_by": null,
            "reviewed_at": null,
            "created_at": "2026-06-01T12:00:00.123456+00:00",
            "updated_at": null,
            "deleted_at": \(deletedAtJSON),
            "series_id": null
        }
        """
        return try SupabaseDate.makeISODecoder().decode(
            CalendarUserEventDTO.self,
            from: Data(json.utf8)
        )
    }

    private func expectInboundSignal(containing entityName: String) -> XCTestExpectation {
        expectation(forNotification: .inboundDataMerged, object: nil) { notification in
            guard let names = notification.userInfo?[InboundChangeSignal.entityNamesKey] as? [String] else {
                return false
            }
            return names.contains(entityName)
        }
    }

    // MARK: - Realtime task merge posts the signal

    func test_realtimeTaskMerge_postsProjectTaskSignal_andPersistsRow() async throws {
        let container = try makeInMemoryContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let signal = expectInboundSignal(containing: "ProjectTask")

        let taskId = "0a345678-90ab-cdef-0123-456789abcdef"
        await actor.handleRealtimeUpdate(.task(makeTaskDTO(id: taskId)))

        await fulfillment(of: [signal], timeout: 3.0)

        let context = ModelContext(container)
        let rows = try context.fetch(
            FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == taskId })
        )
        XCTAssertEqual(rows.count, 1, "realtime task merge must persist exactly one row")
        XCTAssertNotNil(rows.first?.startDate, "schedule dates must land from the DTO")
    }

    // MARK: - Realtime soft delete posts the signal

    func test_realtimeSoftDelete_postsProjectTaskSignal_andSetsDeletedAt() async throws {
        let container = try makeInMemoryContainer()
        let seedContext = ModelContext(container)
        let taskId = "1b345678-90ab-cdef-0123-456789abcdef"

        let task = ProjectTask(id: taskId, projectId: "project-1", taskTypeId: "", companyId: "company-1")
        task.needsSync = false
        seedContext.insert(task)
        try seedContext.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let signal = expectInboundSignal(containing: "ProjectTask")

        await actor.softDeleteFromRealtime(table: "project_tasks", id: taskId)

        await fulfillment(of: [signal], timeout: 3.0)

        let context = ModelContext(container)
        let rows = try context.fetch(
            FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == taskId })
        )
        XCTAssertNotNil(rows.first?.deletedAt, "realtime delete must soft-delete the local row")
    }

    // MARK: - Realtime user-event merge (restored entity)

    func test_realtimeUserEventMerge_insertsRow_andPostsCalendarUserEventSignal() async throws {
        let container = try makeInMemoryContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let signal = expectInboundSignal(containing: "CalendarUserEvent")

        let eventId = "2c345678-90ab-cdef-0123-456789abcdef"
        let dto = try makeUserEventDTO(id: eventId, userId: "user-1")
        await actor.handleRealtimeUpdate(.calendarUserEvent(dto))

        await fulfillment(of: [signal], timeout: 3.0)

        let context = ModelContext(container)
        let rows = try context.fetch(
            FetchDescriptor<CalendarUserEvent>(predicate: #Predicate { $0.id == eventId })
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "Time off")
        XCTAssertEqual(rows.first?.status, "approved")
    }

    func test_realtimeUserEventMerge_respectsPendingLocalEdit() async throws {
        let container = try makeInMemoryContainer()
        let seedContext = ModelContext(container)
        let eventId = "3d345678-90ab-cdef-0123-456789abcdef"

        let local = CalendarUserEvent(
            id: eventId,
            userId: "user-1",
            companyId: "company-1",
            type: .timeOff,
            title: "Local edit in flight",
            startDate: Date(),
            endDate: Date()
        )
        local.needsSync = true
        seedContext.insert(local)
        try seedContext.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let dto = try makeUserEventDTO(id: eventId, userId: "user-1", title: "Server title")
        await actor.handleRealtimeUpdate(.calendarUserEvent(dto))

        let context = ModelContext(container)
        let rows = try context.fetch(
            FetchDescriptor<CalendarUserEvent>(predicate: #Predicate { $0.id == eventId })
        )
        XCTAssertEqual(rows.first?.title, "Local edit in flight",
                       "needsSync rows must not be overwritten by inbound merges")
    }

    func test_realtimeUserEventMerge_skipsInsertOfSoftDeletedRow() async throws {
        let container = try makeInMemoryContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()

        let eventId = "4e345678-90ab-cdef-0123-456789abcdef"
        let dto = try makeUserEventDTO(
            id: eventId,
            userId: "user-1",
            deletedAt: "2026-06-08T10:00:00+00:00"
        )
        await actor.handleRealtimeUpdate(.calendarUserEvent(dto))

        let context = ModelContext(container)
        let rows = try context.fetch(
            FetchDescriptor<CalendarUserEvent>(predicate: #Predicate { $0.id == eventId })
        )
        XCTAssertTrue(rows.isEmpty, "soft-deleted server rows must never be inserted locally")
    }
}
