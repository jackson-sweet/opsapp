//
//  ProjectVinylOrderMarkerSyncTests.swift
//  OPSTests
//
//  Coverage for the `projects.vinyl_color` / `vinyl_po` marker fields:
//  DTO decode (including legacy payloads without the columns), marker
//  conversion, local application through the synced project-field writer,
//  and the outbound payload allowlists on both sync paths.
//

import SwiftData
import XCTest
import Supabase
@testable import OPS

@MainActor
final class ProjectVinylOrderMarkerSyncTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "feature.useDataActor")
        super.tearDown()
    }

    // MARK: - DTO decode

    func testProjectDTODecodesVinylColorAndPOIntoMarker() throws {
        let json = """
        {
            "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "company_id": "company-1",
            "title": "6836 Mark Ln",
            "status": "in_progress",
            "vinyl_order_status": "ordered",
            "vinyl_ordered_at": "2026-07-14T18:00:00+00:00",
            "vinyl_ordered_by": null,
            "vinyl_color": "68mil Cobblestone",
            "vinyl_po": "PO 6836 Mark Ln"
        }
        """
        let dto = try JSONDecoder().decode(
            SupabaseProjectDTO.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(dto.vinylColor, "68mil Cobblestone")
        XCTAssertEqual(dto.vinylPO, "PO 6836 Mark Ln")

        let marker = dto.toVinylOrderMarkerModel()
        XCTAssertEqual(marker.projectId, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(marker.status, .ordered)
        XCTAssertNotNil(marker.orderedAt)
        XCTAssertEqual(marker.vinylColor, "68mil Cobblestone")
        XCTAssertEqual(marker.vinylPO, "PO 6836 Mark Ln")
    }

    func testProjectDTOToleratesLegacyPayloadWithoutVinylColorAndPO() throws {
        let json = """
        {
            "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "company_id": "company-1",
            "title": "6836 Mark Ln",
            "status": "accepted",
            "vinyl_order_status": "not_ordered"
        }
        """
        let dto = try JSONDecoder().decode(
            SupabaseProjectDTO.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(dto.vinylColor)
        XCTAssertNil(dto.vinylPO)

        let marker = dto.toVinylOrderMarkerModel()
        XCTAssertEqual(marker.status, .notOrdered)
        XCTAssertNil(marker.vinylColor)
        XCTAssertNil(marker.vinylPO)
    }

    // MARK: - Local application via the synced project-field writer

    func testUpdateProjectFieldsWritesVinylColorAndPOToMarkerAndQueuesPayload() async throws {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")

        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let projectId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let project = Project(id: projectId, title: "Deck rebuild", status: .accepted)
        project.companyId = "company-1"
        context.insert(project)
        try context.save()

        let dataController = DataController()
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )

        try await dataController.updateProjectFields(
            projectId: projectId,
            fields: [
                ProjectVinylOrderFields.status: .string(ProjectVinylOrderStatus.ordered.rawValue),
                ProjectVinylOrderFields.orderedAt: .string("2026-07-16T17:00:00+00:00"),
                ProjectVinylOrderFields.orderedBy: .null,
                ProjectVinylOrderFields.color: .string("68mil Cobblestone"),
                ProjectVinylOrderFields.po: .string("PO 6836 Mark Ln")
            ]
        )

        let markers = try context.fetch(FetchDescriptor<ProjectVinylOrderMarker>())
        let marker = try XCTUnwrap(markers.first { $0.id == projectId })
        XCTAssertEqual(marker.status, .ordered)
        XCTAssertNotNil(marker.orderedAt)
        XCTAssertEqual(marker.vinylColor, "68mil Cobblestone")
        XCTAssertEqual(marker.vinylPO, "PO 6836 Mark Ln")

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let operation = try XCTUnwrap(operations.first)
        XCTAssertEqual(operation.entityType, SyncEntityType.project.rawValue)
        XCTAssertEqual(
            Set(operation.getChangedFields()),
            Set([
                ProjectVinylOrderFields.status,
                ProjectVinylOrderFields.orderedAt,
                ProjectVinylOrderFields.orderedBy,
                ProjectVinylOrderFields.color,
                ProjectVinylOrderFields.po
            ])
        )

        let payload = try JSONSerialization.jsonObject(with: operation.payload) as? [String: Any]
        XCTAssertEqual(payload?[ProjectVinylOrderFields.color] as? String, "68mil Cobblestone")
        XCTAssertEqual(payload?[ProjectVinylOrderFields.po] as? String, "PO 6836 Mark Ln")
    }

    func testUpdateProjectFieldsNullingVinylColorAndPOClearsMarker() async throws {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")

        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let projectId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        let project = Project(id: projectId, title: "Deck teardown", status: .inProgress)
        project.companyId = "company-1"
        context.insert(project)

        let marker = ProjectVinylOrderMarker(
            projectId: projectId,
            status: .ordered,
            orderedAt: Date(),
            orderedBy: nil
        )
        marker.vinylColor = "68mil Hansberry"
        marker.vinylPO = "PO 303 Stevens"
        context.insert(marker)
        try context.save()

        let dataController = DataController()
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )

        try await dataController.updateProjectFields(
            projectId: projectId,
            fields: [
                ProjectVinylOrderFields.status: .string(ProjectVinylOrderStatus.notOrdered.rawValue),
                ProjectVinylOrderFields.orderedAt: .null,
                ProjectVinylOrderFields.orderedBy: .null,
                ProjectVinylOrderFields.color: .null,
                ProjectVinylOrderFields.po: .null
            ]
        )

        XCTAssertEqual(marker.status, .notOrdered)
        XCTAssertNil(marker.orderedAt)
        XCTAssertNil(marker.vinylColor)
        XCTAssertNil(marker.vinylPO)
    }

    // MARK: - Outbound allowlists

    func testSanitizedProjectPayloadsKeepVinylColorAndPOOnBothSyncPaths() {
        let payload: [String: Any] = [
            "vinyl_order_status": "ordered",
            "vinyl_color": "68mil Hansberry",
            "vinyl_po": "PO 303 Stevens",
            "task_index": 4
        ]

        let outbound = OutboundProcessor.sanitizedProjectPayloadForSync(payload)
        XCTAssertEqual(outbound["vinyl_color"] as? String, "68mil Hansberry")
        XCTAssertEqual(outbound["vinyl_po"] as? String, "PO 303 Stevens")
        XCTAssertNil(outbound["task_index"], "Local-only keys must still be stripped")

        let viaActor = DataActor.sanitizedProjectPayloadForSync(payload)
        XCTAssertEqual(viaActor["vinyl_color"] as? String, "68mil Hansberry")
        XCTAssertEqual(viaActor["vinyl_po"] as? String, "PO 303 Stevens")
        XCTAssertNil(viaActor["task_index"], "Local-only keys must still be stripped")
    }

    // MARK: - Harness

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
            ProjectVinylOrderMarker.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
