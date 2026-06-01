//
//  GuidedStockUnitResolver.swift
//  OPS
//
//  Maps a GuidedMeasurement to a catalog_units dimension, finds an active local
//  unit for that dimension, or creates one (remote + local insert). The creator
//  closure is injectable so the class is fully testable without a live Supabase
//  connection.
//

import Foundation
import SwiftData

@MainActor
final class GuidedStockUnitResolver {

    // MARK: - Types

    typealias UnitCreator = (CreateCatalogUnitDTO) async throws -> CatalogUnitDTO

    struct UnitSpec: Equatable {
        let dimension: String
        let display: String
        let abbreviation: String
    }

    // MARK: - Mapping

    static func spec(for measurement: GuidedMeasurement) -> UnitSpec {
        switch measurement {
        case .piece:  return UnitSpec(dimension: "count",  display: "ea",    abbreviation: "ea")
        case .length: return UnitSpec(dimension: "length", display: "ft",    abbreviation: "ft")
        case .area:   return UnitSpec(dimension: "area",   display: "sq ft", abbreviation: "sq ft")
        }
    }

    // MARK: - Dependencies

    private let companyId: String
    private let modelContext: ModelContext
    private let createUnitRemote: UnitCreator

    // MARK: - Init

    init(companyId: String, modelContext: ModelContext, createUnit: UnitCreator? = nil) {
        self.companyId = companyId
        self.modelContext = modelContext
        if let createUnit {
            self.createUnitRemote = createUnit
        } else {
            let cid = companyId
            self.createUnitRemote = { dto in
                try await CatalogRepository(companyId: cid).createUnit(dto)
            }
        }
    }

    // MARK: - Resolution

    /// Returns the id of an active local unit for the measurement's dimension.
    /// If no active unit exists, one is created remotely and inserted locally.
    func resolveUnitId(for measurement: GuidedMeasurement) async throws -> String {
        let spec = Self.spec(for: measurement)
        let cid = companyId
        let dim = spec.dimension

        let descriptor = FetchDescriptor<CatalogUnit>(
            predicate: #Predicate { $0.companyId == cid && $0.dimension == dim && $0.deletedAt == nil }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        if let pick = existing.first(where: { $0.isDefault })
            ?? existing.first(where: { $0.display == spec.display })
            ?? existing.first {
            return pick.id
        }

        let dto = CreateCatalogUnitDTO(
            companyId: companyId,
            display: spec.display,
            abbreviation: spec.abbreviation,
            dimension: spec.dimension,
            isDefault: false,
            sortOrder: 0
        )
        let created = try await createUnitRemote(dto)
        let model = created.toModel()
        model.lastSyncedAt = Date()
        modelContext.insert(model)
        try? modelContext.save()
        return created.id
    }
}
