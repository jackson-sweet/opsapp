import XCTest
@testable import OPS

final class ProjectTaskDuplicationTests: XCTestCase {
    private let sourceId = "11111111-2222-3333-4444-555555555555"
    private let duplicateId = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testDuplicateCopiesTaskDefinitionAndResetsOperationalState() throws {
        let dependency = TaskTypeDependency(
            dependsOnTaskTypeId: "prep-type",
            overlapPercentage: 25,
            overlapMode: "percentage"
        )
        let source = makeSource()
        source.setDependencyOverrides([dependency])

        let dto = try ProjectTaskDuplication.makeDTO(
            from: source,
            id: duplicateId,
            createdAt: createdAt,
            displayOrder: 9
        )

        XCTAssertEqual(dto.id, duplicateId.lowercased())
        XCTAssertEqual(dto.companyId, "company-1")
        XCTAssertEqual(dto.projectId, "project-1")
        XCTAssertEqual(dto.taskTypeId, "install-type")
        XCTAssertEqual(dto.customTitle, "North elevation")
        XCTAssertEqual(dto.taskNotes, "Protect the finished fascia.")
        XCTAssertEqual(dto.status, TaskStatus.active.rawValue)
        XCTAssertEqual(dto.taskColor, "#93A17C")
        XCTAssertEqual(dto.displayOrder, 9)
        XCTAssertEqual(dto.teamMemberIds, ["crew-1", "crew-2"])
        XCTAssertEqual(dto.duration, 4)
        XCTAssertEqual(dto.dependencyOverrides, [dependency])
        XCTAssertNil(dto.sourceLineItemId)
        XCTAssertNil(dto.sourceEstimateId)
        XCTAssertNil(dto.startDate)
        XCTAssertNil(dto.endDate)
        XCTAssertNil(dto.startTime)
        XCTAssertNil(dto.endTime)
        XCTAssertNil(dto.pairedFromTaskId)
        XCTAssertEqual(dto.scheduleLocked, false)
        XCTAssertNil(dto.deletedAt)
        XCTAssertEqual(dto.createdAt, "2023-11-14T22:13:20Z")
    }

    func testDuplicateGeneratesFreshCanonicalIds() throws {
        let source = makeSource()

        let first = try ProjectTaskDuplication.makeDTO(
            from: source,
            createdAt: createdAt,
            displayOrder: 9
        )
        let second = try ProjectTaskDuplication.makeDTO(
            from: source,
            createdAt: createdAt,
            displayOrder: 10
        )

        XCTAssertNotEqual(first.id, source.id)
        XCTAssertNotEqual(second.id, source.id)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.id, first.id.lowercased())
        XCTAssertEqual(second.id, second.id.lowercased())
    }

    func testDuplicatePreservesExplicitEmptyDependencyOverride() throws {
        let source = makeSource()
        source.dependencyOverridesJSON = "[]"

        let dto = try ProjectTaskDuplication.makeDTO(
            from: source,
            id: duplicateId,
            createdAt: createdAt,
            displayOrder: 9
        )

        XCTAssertEqual(dto.dependencyOverrides, [])
        XCTAssertEqual(dto.toModel().dependencyOverridesJSON, "[]")
    }

    func testDuplicateRejectsCorruptDependencyOverrideInsteadOfChangingScheduleBehavior() {
        let source = makeSource()
        source.dependencyOverridesJSON = "{not-json"

        XCTAssertThrowsError(
            try ProjectTaskDuplication.makeDTO(
                from: source,
                id: duplicateId,
                createdAt: createdAt,
                displayOrder: 9
            )
        ) { error in
            XCTAssertEqual(error as? ProjectTaskDuplicationError, .invalidDependencyOverrides)
        }
    }

    func testDuplicatePermissionRequiresFullTaskCreateAccessAndLiveSource() {
        XCTAssertTrue(
            ProjectTaskDuplication.canDuplicate(
                canCreateTasks: true,
                isMentionOnly: false,
                sourceDeletedAt: nil
            )
        )
        XCTAssertFalse(
            ProjectTaskDuplication.canDuplicate(
                canCreateTasks: false,
                isMentionOnly: false,
                sourceDeletedAt: nil
            )
        )
        XCTAssertFalse(
            ProjectTaskDuplication.canDuplicate(
                canCreateTasks: true,
                isMentionOnly: true,
                sourceDeletedAt: nil
            )
        )
        XCTAssertFalse(
            ProjectTaskDuplication.canDuplicate(
                canCreateTasks: true,
                isMentionOnly: false,
                sourceDeletedAt: .distantPast
            )
        )
    }

    func testQueuedCreatePayloadCarriesDependencyOverrideAndCreationMetadata() throws {
        let source = makeSource()
        source.dependencyOverridesJSON = "[]"
        let dto = try ProjectTaskDuplication.makeDTO(
            from: source,
            id: duplicateId,
            createdAt: createdAt,
            displayOrder: 9
        )

        let fields = try DataController.projectTaskCreateFields(for: dto)

        XCTAssertEqual(fields["created_at"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(fields["schedule_locked"] as? Bool, false)
        XCTAssertEqual((fields["dependency_overrides"] as? [Any])?.count, 0)
        XCTAssertNil(fields["start_date"])
        XCTAssertNil(fields["source_line_item_id"])
        XCTAssertNil(fields["paired_from_task_id"])
    }

    private func makeSource() -> ProjectTask {
        let source = ProjectTask(
            id: sourceId,
            projectId: "project-1",
            taskTypeId: "install-type",
            companyId: "company-1",
            status: .completed,
            taskColor: "#93A17C"
        )
        source.customTitle = "North elevation"
        source.taskNotes = "Protect the finished fascia."
        source.displayOrder = 3
        source.setTeamMemberIds(["CREW-1", "CREW-2"])
        source.startDate = Date(timeIntervalSince1970: 1_710_000_000)
        source.endDate = Date(timeIntervalSince1970: 1_710_259_200)
        source.duration = 4
        source.sourceLineItemId = "line-item-1"
        source.sourceEstimateId = "estimate-1"
        source.pairedFromTaskId = "paired-task-1"
        source.scheduleLocked = true
        return source
    }
}
