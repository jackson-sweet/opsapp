//
//  GuidedStockUnitResolverTests.swift
//  OPSTests
//
//  TDD coverage for GuidedStockUnitResolver:
//  - spec() maps each GuidedMeasurement to the correct dimension/display/abbreviation.
//  - resolveUnitId returns an existing active unit without calling the creator.
//  - resolveUnitId creates a remote unit, inserts it locally, and returns its id
//    when no active local unit exists.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class GuidedStockUnitResolverTests: XCTestCase {

    // MARK: - Helpers

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: OPSSchemaV8.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    /// Builds a minimal CatalogUnitDTO that toModel() can convert without crashing.
    private func makeUnitDTO(
        id: String = UUID().uuidString,
        companyId: String = "c1",
        display: String = "ft",
        abbreviation: String? = "ft",
        dimension: String = "length",
        isDefault: Bool = false,
        sortOrder: Int = 0
    ) -> CatalogUnitDTO {
        CatalogUnitDTO(
            id: id,
            companyId: companyId,
            display: display,
            abbreviation: abbreviation,
            dimension: dimension,
            isDefault: isDefault,
            sortOrder: sortOrder,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            deletedAt: nil
        )
    }

    // MARK: - spec() mapping

    func test_spec_mapsMeasurementToDimension() {
        let piece  = GuidedStockUnitResolver.spec(for: .piece)
        XCTAssertEqual(piece.dimension,    "count")
        XCTAssertEqual(piece.display,      "ea")
        XCTAssertEqual(piece.abbreviation, "ea")

        let length = GuidedStockUnitResolver.spec(for: .length)
        XCTAssertEqual(length.dimension,    "length")
        XCTAssertEqual(length.display,      "ft")
        XCTAssertEqual(length.abbreviation, "ft")

        let area   = GuidedStockUnitResolver.spec(for: .area)
        XCTAssertEqual(area.dimension,    "area")
        XCTAssertEqual(area.display,      "sq ft")
        XCTAssertEqual(area.abbreviation, "sq ft")
    }

    // MARK: - resolveUnitId reuses existing active unit

    func test_resolve_reusesExistingActiveUnit() async throws {
        let context = try makeInMemoryContext()

        // Insert an active length unit.
        let existing = CatalogUnit(id: "unit-existing", companyId: "c1", display: "ft",
                                   dimension: "length", isDefault: false)
        context.insert(existing)
        try context.save()

        var creatorCallCount = 0
        let resolver = GuidedStockUnitResolver(
            companyId: "c1",
            modelContext: context,
            createUnit: { _ in
                creatorCallCount += 1
                XCTFail("Creator must not be called when an active unit already exists")
                // Provide a dummy return to satisfy the type; XCTFail already marks failure.
                throw URLError(.badServerResponse)
            }
        )

        let resolved = try await resolver.resolveUnitId(for: .length)

        XCTAssertEqual(resolved, "unit-existing", "Should return the existing active unit's id")
        XCTAssertEqual(creatorCallCount, 0, "Remote creator must not be invoked")
    }

    // MARK: - resolveUnitId creates when no active unit exists

    func test_resolve_createsWhenMissing() async throws {
        let context = try makeInMemoryContext()

        var capturedDTO: CreateCatalogUnitDTO?
        let spyReturn = makeUnitDTO(id: "unit-new", dimension: "length")

        let resolver = GuidedStockUnitResolver(
            companyId: "c1",
            modelContext: context,
            createUnit: { dto in
                capturedDTO = dto
                return spyReturn
            }
        )

        let resolved = try await resolver.resolveUnitId(for: .length)

        XCTAssertEqual(resolved, "unit-new", "Should return the created unit's id")
        XCTAssertEqual(capturedDTO?.dimension, "length", "Creator must be called with dimension 'length'")

        // Verify the unit was inserted locally.
        let descriptor = FetchDescriptor<CatalogUnit>(
            predicate: #Predicate { $0.id == "unit-new" }
        )
        let inserted = try context.fetch(descriptor)
        XCTAssertEqual(inserted.count, 1, "Created unit must be persisted locally in the model context")
    }

    // MARK: - resolveUnitId ignores soft-deleted units

    func test_resolve_ignoresSoftDeletedUnit_andCreatesNew() async throws {
        let context = try makeInMemoryContext()

        // Insert a soft-deleted length unit.
        let deleted = CatalogUnit(id: "unit-deleted", companyId: "c1", display: "ft",
                                  dimension: "length", isDefault: false)
        deleted.deletedAt = Date(timeIntervalSinceNow: -3600)
        context.insert(deleted)
        try context.save()

        let spyReturn = makeUnitDTO(id: "unit-fresh", dimension: "length")
        let resolver = GuidedStockUnitResolver(
            companyId: "c1",
            modelContext: context,
            createUnit: { _ in spyReturn }
        )

        let resolved = try await resolver.resolveUnitId(for: .length)

        XCTAssertEqual(resolved, "unit-fresh",
                       "Soft-deleted unit must not be reused; a new one must be created")
    }
}
