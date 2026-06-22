// OPS/OPSTests/DeckBuilder/VinylOffcutInventoryTests.swift
//
//  Covers the offcut-inventory additions to the vinyl cut engine
//  (settings-driven threshold, surfaced produced offcuts, banked-offcut reuse
//  seeding) and the gating short-circuit on `VinylOffcutInventoryService`.
//
//  The "inventory_mode flipped both ways" check the spec calls for is a runtime
//  verification against a tracked company (Canpro/Maverick) — the mode is a
//  server fetch. These unit tests cover the deterministic half: the capability
//  gate short-circuits every write to a no-op without touching the network.

import CoreGraphics
import SwiftData
import XCTest
@testable import OPS

final class VinylOffcutInventoryTests: XCTestCase {

    // MARK: - Engine: produced offcuts + threshold

    func testProducedOffcutSurfacedFromLeftoverWidth() {
        // 288 × 132 on a 72" roll → two strips (72" + 60"), 12" leftover banked.
        let surface = rectangle(id: "main", width: 288, height: 132)
        let plan = VinylCutListEngine.makePlan(surfaces: [surface], settings: zeroAllowanceSettings())

        XCTAssertFalse(plan.producedOffcuts.isEmpty, "a 12in leftover should surface as a produced offcut")
        for offcut in plan.producedOffcuts {
            XCTAssertGreaterThanOrEqual(offcut.widthInches, 6)
            XCTAssertLessThan(offcut.widthInches, 72, "a remnant is narrower than the roll it came from")
            XCTAssertGreaterThan(offcut.lengthInches, 0)
        }
    }

    func testOffcutThresholdComesFromSettings() {
        let surface = rectangle(id: "main", width: 288, height: 132)

        // Default 6" threshold: the ~12" leftover qualifies.
        let lowPlan = VinylCutListEngine.makePlan(surfaces: [surface], settings: zeroAllowanceSettings())
        XCTAssertFalse(lowPlan.producedOffcuts.isEmpty)

        // Raise the threshold above the leftover: nothing is worth banking.
        let highPlan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: zeroAllowanceSettings(offcutMinWidthInches: 60)
        )
        XCTAssertTrue(highPlan.producedOffcuts.isEmpty, "a 12in leftover must not bank under a 60in threshold")
    }

    // MARK: - Engine: banked-offcut reuse seeding

    func testOnHandOffcutSeedingReusesAcrossJobsAndCutsPurchase() {
        // One small surface that fits inside a banked offcut.
        let surface = rectangle(id: "patch", width: 120, height: 40)
        let settings = zeroAllowanceSettings()

        let withoutSeed = VinylCutListEngine.makePlan(surfaces: [surface], settings: settings)
        XCTAssertGreaterThan(withoutSeed.totalOrderedSqFt, 0, "with no banked stock the patch must be purchased")
        XCTAssertEqual(withoutSeed.totalReusedCutAreaSqFt, 0, accuracy: 0.01)

        let seed = VinylOnHandOffcut(id: "stock-1", label: "BANKED OFFCUT", widthInches: 72, lengthInches: 200)
        let withSeed = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: settings,
            availableOffcuts: [seed]
        )

        XCTAssertGreaterThan(withSeed.totalReusedCutAreaSqFt, 0, "the patch should reuse the banked offcut")
        XCTAssertLessThan(withSeed.totalOrderedSqFt, withoutSeed.totalOrderedSqFt)
        XCTAssertTrue(withSeed.producedOffcuts.isEmpty, "reusing a banked offcut must not re-bank it as new")
    }

    // MARK: - Service gating: capability off → silent no-op

    @MainActor
    func testServiceNoOpsWhenStockSchemaCapabilityOff() async throws {
        let key = "catalog.schema.catalogStockUnits"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(false, forKey: key)

        let schema = Schema(versionedSchema: OPSSchemaV10.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let service = VinylOffcutInventoryService(
            companyId: "company-1",
            userId: "user-1",
            modelContext: container.mainContext
        )

        let active = await service.isTrackingActive()
        XCTAssertFalse(active, "tracking must read inactive when the stock-unit schema is unavailable")

        let rolls = try await service.receiveRolls(
            orderItemId: "order-item-1",
            variantId: "variant-1",
            rollCount: 2,
            rollLengthFeet: 150,
            rollWidthInches: 60
        )
        XCTAssertTrue(rolls.isEmpty, "receiveRolls must no-op when gated off")

        let writtenUnits = try container.mainContext.fetchCount(FetchDescriptor<CatalogStockUnit>())
        XCTAssertEqual(writtenUnits, 0, "no stock units may be written when gated off")

        let banked = try await service.bankOffcut(
            variantId: "variant-1",
            sourceRollId: "roll-1",
            offcut: VinylProducedOffcut(id: "o-1", sourceSurfaceLabel: "MAIN", widthInches: 22, lengthInches: 120),
            projectId: nil
        )
        XCTAssertNil(banked, "bankOffcut must no-op when gated off")
    }

    // MARK: - Sync wiring regression guard

    func testActiveSyncPathCoversEveryLegacyEntityIncludingStockEvents() {
        // FeatureFlags.useDataActor defaults true, so DataActor is the live
        // inbound path. Every entity the legacy InboundProcessor pulls MUST also
        // be in DataActor.syncOrder, or it silently never syncs on the default
        // path — the exact catalogStockUnitEvent omission this guards. (DataActor
        // legitimately covers MORE: the legacy inventory_* entities.)
        let inbound = Set(InboundProcessor.syncOrder)
        let active = Set(DataActor.syncOrder)
        XCTAssertTrue(
            inbound.isSubset(of: active),
            "DataActor.syncOrder is missing entities the legacy path syncs: \(inbound.subtracting(active))"
        )
        XCTAssertTrue(active.contains(.catalogStockUnitEvent), "active path must sync the stock-unit ledger")
        XCTAssertTrue(inbound.contains(.catalogStockUnitEvent), "legacy path must sync the stock-unit ledger")
    }

    // MARK: - Helpers

    private func zeroAllowanceSettings(offcutMinWidthInches: Double = 6) -> VinylOrderSettings {
        VinylOrderSettings(
            color: "",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .lengthwise,
            offcutMinWidthInches: offcutMinWidthInches
        )
    }

    private func rectangle(
        id: String,
        label: String = "Surface",
        width: Double,
        height: Double
    ) -> VinylOrderSurfaceInput {
        VinylOrderSurfaceInput(
            id: id,
            label: label,
            levelName: nil,
            positions: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: width, y: 0),
                CGPoint(x: width, y: height),
                CGPoint(x: 0, y: height)
            ],
            scaleFactor: 1
        )
    }
}
