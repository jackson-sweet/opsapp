//
//  OpportunityAssignmentMigrationTests.swift
//  OPSTests
//
//  Proves the exact V15 Opportunity shape migrates through the full plan to
//  the current schema (V18) without a store wipe, defaulting the assignment
//  concurrency snapshot to zero and the chase/summary columns to nil.
//

import SwiftData
import XCTest
@testable import OPS

final class OpportunityAssignmentMigrationTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opportunity-assignment-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("ops.store")
    }

    override func tearDownWithError() throws {
        if let directory = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testV15OpportunityMigratesToCurrentWithZeroAssignmentVersion() throws {
        try autoreleasepool {
            let schema = Schema(versionedSchema: OPSSchemaV15.self)
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)

            let legacy = OPSSchemaLegacyOpportunityV15.Opportunity(
                id: "lead-v15",
                companyId: "company-1",
                contactName: "Jason Zavarella",
                stage: .quoted,
                stageEnteredAt: Date(timeIntervalSince1970: 1_000),
                createdAt: Date(timeIntervalSince1970: 900),
                updatedAt: Date(timeIntervalSince1970: 1_100)
            )
            legacy.title = "Framing renovation"
            legacy.assignedTo = "user-jason"
            legacy.estimatedValue = 42_000
            context.insert(legacy)
            try context.save()
        }

        let schema = Schema(versionedSchema: OPSSchemaV18.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: OPSMigrationPlan.self,
            configurations: configuration
        )
        let context = ModelContext(container)

        let leads = try context.fetch(FetchDescriptor<Opportunity>())
        let lead = try XCTUnwrap(leads.first)
        XCTAssertEqual(leads.count, 1)
        XCTAssertEqual(lead.id, "lead-v15")
        XCTAssertEqual(lead.title, "Framing renovation")
        XCTAssertEqual(lead.assignedTo, "user-jason")
        XCTAssertEqual(lead.estimatedValue, 42_000)
        XCTAssertEqual(lead.assignmentVersion, 0)
        XCTAssertNil(lead.handledAt)
        XCTAssertNil(lead.aiSummary)
        XCTAssertNil(lead.aiSummaryUpdatedAt)

        lead.assignmentVersion = 3
        try context.save()
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Opportunity>()).first?.assignmentVersion,
            3
        )
    }
}
