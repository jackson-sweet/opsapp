//
//  EstimateAcceptanceIntegrationTests.swift
//  OPSTests
//

import SwiftData
import XCTest
@testable import OPS

final class EstimateAcceptanceIntegrationTests: XCTestCase {

    func testAcceptEstimateToJobResponseDecodesLiveRPCShape() throws {
        let payload = """
        {
          "ok": true,
          "estimate_id": "estimate-1",
          "project_id": "project-1",
          "actor_user_id": "user-1",
          "company_id": "company-1",
          "idempotency_key": "estimate-acceptance:company-1:estimate-1:key-1",
          "idempotent_replay": false,
          "project_task_result": {
            "project_id": "project-1",
            "task_ids": ["task-1", "task-2"]
          },
          "booking_projection_result": {
            "inventory_mode": "tracked",
            "demand_ids": ["demand-1"],
            "warnings": [
              {
                "code": "missing_catalog_mapping",
                "message": "Mapping needed"
              }
            ],
            "overruns": [
              {
                "demand_key": "estimate:estimate-1:line:line-2:product_material:mat-1:variant:variant-1",
                "line_item_id": "line-2",
                "product_id": "product-2",
                "catalog_variant_id": "variant-1",
                "required_quantity": 12.5,
                "available_quantity_at_booking": 4.0,
                "projected_overrun_quantity": 8.5,
                "availability_basis": "effective_available_quantity"
              }
            ],
            "missing_mappings": [
              {
                "dedupe_key": "product:line-1",
                "product_id": "product-1",
                "line_item_id": "line-1",
                "product_name": "Rail package"
              }
            ]
          },
          "mapping_notification_result": {
            "notification_persistence_performed": true,
            "dedupe_keys": ["product:line-1"],
            "recipient_count": 2,
            "inserted_notification_count": 2,
            "updated_notification_count": 0
          },
          "inventory_mode": "tracked",
          "warnings": [
            {
              "code": "missing_catalog_mapping",
              "message": "Mapping needed"
            }
          ],
          "overruns": [
            {
              "demand_key": "estimate:estimate-1:line:line-2:product_material:mat-1:variant:variant-1",
              "line_item_id": "line-2",
              "product_id": "product-2",
              "catalog_variant_id": "variant-1",
              "required_quantity": 12.5,
              "available_quantity_at_booking": 4.0,
              "projected_overrun_quantity": 8.5,
              "availability_basis": "effective_available_quantity"
            }
          ],
          "missing_mappings": [
            {
              "dedupe_key": "product:line-1",
              "product_id": "product-1",
              "line_item_id": "line-1",
              "product_name": "Rail package"
            }
          ],
          "demand_ids": ["demand-1"],
          "accepted_at": "2026-05-28T12:00:00Z"
        }
        """

        let dto = try JSONDecoder().decode(
            AcceptEstimateToJobResponseDTO.self,
            from: Data(payload.utf8)
        )

        XCTAssertTrue(dto.ok)
        XCTAssertEqual(dto.estimateId, "estimate-1")
        XCTAssertEqual(dto.projectId, "project-1")
        XCTAssertEqual(dto.inventoryMode, "tracked")
        XCTAssertEqual(dto.projectTaskResult?.taskIds, ["task-1", "task-2"])
        XCTAssertEqual(dto.mappingNotificationResult?.dedupeKeys, ["product:line-1"])
        XCTAssertEqual(dto.missingMappings.first?.dedupeKey, "product:line-1")
        XCTAssertEqual(dto.overruns.first?.demandKey, "estimate:estimate-1:line:line-2:product_material:mat-1:variant:variant-1")
        XCTAssertEqual(dto.overruns.first?.lineItemId, "line-2")
        XCTAssertEqual(dto.overruns.first?.productId, "product-2")
        XCTAssertEqual(dto.overruns.first?.catalogVariantId, "variant-1")
        XCTAssertEqual(dto.overruns.first?.requiredQuantity, 12.5)
        XCTAssertEqual(dto.overruns.first?.availableQuantityAtBooking, 4.0)
        XCTAssertEqual(dto.overruns.first?.projectedOverrunQuantity, 8.5)
        XCTAssertEqual(dto.overruns.first?.availabilityBasis, "effective_available_quantity")
    }

    func testIdempotencyStoreReusesKeyPerEstimateAndCompany() {
        let defaultsName = "EstimateAcceptanceIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let store = EstimateAcceptanceIdempotencyStore(
            userDefaults: defaults,
            namespace: "test"
        )

        let first = store.idempotencyKey(companyId: "company-1", estimateId: "estimate-1")
        let second = store.idempotencyKey(companyId: "company-1", estimateId: "estimate-1")
        let third = store.idempotencyKey(companyId: "company-1", estimateId: "estimate-2")
        let fourth = store.idempotencyKey(companyId: "company-2", estimateId: "estimate-1")

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, third)
        XCTAssertNotEqual(first, fourth)
        XCTAssertTrue(first.hasPrefix("estimate-acceptance:company-1:estimate-1:"))
    }

    @MainActor
    func testMarkApprovedUsesAcceptanceRPCAndPublishesApprovalState() async throws {
        let defaultsName = "EstimateAcceptanceIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let client = RecordingEstimateAcceptanceClient(
            response: .accepted(
                estimateId: "estimate-1",
                projectId: "project-1",
                missingMappingCount: 1
            )
        )
        let viewModel = EstimateViewModel(
            acceptanceClientFactory: { _ in client },
            acceptanceIdempotencyStore: EstimateAcceptanceIdempotencyStore(
                userDefaults: defaults,
                namespace: "test"
            )
        )
        let container = try ModelContainer(
            for: Estimate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let estimate = Estimate(
            id: "estimate-1",
            companyId: "company-1",
            estimateNumber: "EST-1",
            status: .viewed
        )
        context.insert(estimate)
        try context.save()

        viewModel.setup(companyId: "company-1", modelContext: context)
        await viewModel.markApproved(estimate)

        XCTAssertEqual(client.calls.count, 1)
        XCTAssertEqual(client.calls.first?.estimateId, "estimate-1")
        XCTAssertTrue(client.calls.first?.idempotencyKey.hasPrefix("estimate-acceptance:company-1:estimate-1:") == true)
        XCTAssertEqual(estimate.status, .approved)
        XCTAssertEqual(estimate.projectId, "project-1")
        XCTAssertEqual(
            viewModel.approvalState(for: "estimate-1"),
            .accepted(
                projectId: "project-1",
                inventoryMode: "tracked",
                warningCount: 1,
                missingMappingCount: 1,
                overrunCount: 0,
                overrunDetails: [],
                idempotentReplay: false
            )
        )
    }

    @MainActor
    func testMarkApprovedPublishesOverrunDetailsSeparatelyFromWarningsAndMappings() async throws {
        let defaultsName = "EstimateAcceptanceIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let overrun = AcceptEstimateOverrunDTO(
            demandKey: "estimate:estimate-2:line:line-9:product_material:mat-9:variant:variant-9",
            lineItemId: "line-9",
            productId: "product-9",
            catalogVariantId: "variant-9",
            requiredQuantity: 18,
            availableQuantityAtBooking: 6,
            projectedOverrunQuantity: 12,
            availabilityBasis: "effective_available_quantity"
        )
        let client = RecordingEstimateAcceptanceClient(
            response: .accepted(
                estimateId: "estimate-2",
                projectId: "project-2",
                missingMappingCount: 0,
                warnings: [],
                overruns: [overrun]
            )
        )
        let viewModel = EstimateViewModel(
            acceptanceClientFactory: { _ in client },
            acceptanceIdempotencyStore: EstimateAcceptanceIdempotencyStore(
                userDefaults: defaults,
                namespace: "test"
            )
        )
        let container = try ModelContainer(
            for: Estimate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let estimate = Estimate(
            id: "estimate-2",
            companyId: "company-1",
            estimateNumber: "EST-2",
            status: .sent
        )
        context.insert(estimate)
        try context.save()

        viewModel.setup(companyId: "company-1", modelContext: context)
        await viewModel.markApproved(estimate)

        XCTAssertEqual(
            viewModel.approvalState(for: "estimate-2"),
            .accepted(
                projectId: "project-2",
                inventoryMode: "tracked",
                warningCount: 0,
                missingMappingCount: 0,
                overrunCount: 1,
                overrunDetails: [
                    EstimateAcceptanceOverrunDetail(
                        demandKey: overrun.demandKey,
                        catalogVariantId: "variant-9",
                        requiredQuantity: 18,
                        availableQuantityAtBooking: 6,
                        projectedOverrunQuantity: 12,
                        availabilityBasis: "effective_available_quantity"
                    )
                ],
                idempotentReplay: false
            )
        )
    }

    func testCatalogSetupNotificationRoutingParsesMissingMappingActionURL() {
        let route = CatalogSetupNotificationRoute.route(
            type: "catalog_mapping_needed",
            deepLinkType: "catalogSetup",
            actionUrl: "ops://catalog/setup?missingMapping=product%3Aline-1",
            actionLabel: "FIX MAPPING",
            dedupeKey: nil
        )

        XCTAssertEqual(route?.missingMappingKey, "product:line-1")
        XCTAssertEqual(route?.actionLabel, "FIX MAPPING")
        XCTAssertEqual(route?.notificationName, Notification.Name("OpenCatalogSetup"))
    }
}

private final class RecordingEstimateAcceptanceClient: EstimateAcceptanceClient {
    struct Call: Equatable {
        let estimateId: String
        let idempotencyKey: String
    }

    private(set) var calls: [Call] = []
    private let response: AcceptEstimateToJobResponseDTO

    init(response: AcceptEstimateToJobResponseDTO) {
        self.response = response
    }

    func acceptEstimateToJob(
        estimateId: String,
        idempotencyKey: String
    ) async throws -> AcceptEstimateToJobResponseDTO {
        calls.append(Call(estimateId: estimateId, idempotencyKey: idempotencyKey))
        return response
    }
}

private extension AcceptEstimateToJobResponseDTO {
    static func accepted(
        estimateId: String,
        projectId: String,
        missingMappingCount: Int,
        warnings: [AcceptEstimateWarningDTO]? = nil,
        overruns: [AcceptEstimateOverrunDTO] = []
    ) -> AcceptEstimateToJobResponseDTO {
        AcceptEstimateToJobResponseDTO(
            ok: true,
            estimateId: estimateId,
            projectId: projectId,
            actorUserId: "user-1",
            companyId: "company-1",
            idempotencyKey: "estimate-acceptance:company-1:\(estimateId):key-1",
            idempotentReplay: false,
            projectTaskResult: AcceptEstimateProjectTaskResultDTO(projectId: projectId, taskIds: ["task-1"]),
            bookingProjectionResult: nil,
            mappingNotificationResult: nil,
            inventoryMode: "tracked",
            warnings: warnings ?? [
                AcceptEstimateWarningDTO(code: "missing_catalog_mapping", message: "Mapping needed")
            ],
            overruns: overruns,
            missingMappings: (0..<missingMappingCount).map { index in
                AcceptEstimateMissingMappingDTO(
                    dedupeKey: "product:line-\(index)",
                    productId: "product-\(index)",
                    lineItemId: "line-\(index)",
                    productName: "Rail package",
                    lineName: nil
                )
            },
            demandIds: [],
            acceptedAt: "2026-05-28T12:00:00Z"
        )
    }
}
