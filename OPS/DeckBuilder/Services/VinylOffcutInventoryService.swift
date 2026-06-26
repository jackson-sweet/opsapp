//
//  VinylOffcutInventoryService.swift
//  OPS
//
//  Bridges the vinyl deck-builder cut flow into the modern catalog stock-unit
//  inventory.
//
//  • Phase 1 — receipt: seeds one physical roll stock unit per roll on order
//    receipt, linked back to its `catalog_order_items` line via
//    `source_order_item_id`.
//  • Phase 2 — bank: records cutting a strip from a roll — debiting the source
//    roll (full → partial), creating the banked offcut, and writing the
//    lifecycle ledger (`offcut_create` on the offcut + `adjust` on the source).
//
//  Every write is a SILENT no-op unless the company runs
//  `inventory_mode == .tracked` AND the `catalog_stock_units` schema capability
//  is present; the draft-order / project-marker behaviour is otherwise
//  unchanged. After each mutation the variant's mirrored `quantity` is
//  recomputed from the available stock units via `CatalogStockUnitAggregator`
//  + `CatalogStockQuantityPolicy` (web `/catalog` STOCK reads the variant
//  directly).
//
//  This is a DISTINCT surface from the authoritative server consumption pipeline
//  (`complete_project_task`) and never duplicates it. Ledger rows carry a
//  source marker so a future reconciliation can dedupe against task-completion
//  deductions.
//
//  Vinyl stock is measured in SQUARE FEET — matching the order's sq-ft world —
//  so widths and lengths are stored in feet (`length_unit`/`width_unit` = "ft")
//  and the aggregator mirrors the available area back to the variant quantity.
//

import Foundation
import DeckKit
import SwiftData

@MainActor
struct VinylOffcutInventoryService {
    let companyId: String
    let userId: String
    let modelContext: ModelContext

    /// Canonical stored unit for vinyl roll/offcut dimensions (see file note).
    private static let storedUnit = "ft"
    /// Ledger source markers — namespace the deck-builder surface so a future
    /// reconciliation can tell these apart from task-completion deductions.
    private static let receiptMarker = "ios_vinyl_order_receipt"
    private static let bankMarker = "ios_deck_builder_cut"

    private var stockUnitRepo: CatalogStockUnitRepository { CatalogStockUnitRepository(companyId: companyId) }
    private var eventRepo: CatalogStockUnitEventRepository { CatalogStockUnitEventRepository(companyId: companyId) }
    private var catalogRepo: CatalogRepository { CatalogRepository(companyId: companyId) }
    private var inventoryModeRepo: CompanyInventoryModeRepository { CompanyInventoryModeRepository(companyId: companyId) }

    // MARK: - Gating

    /// True only when the company tracks inventory AND the stock-unit schema is
    /// live. All writes short-circuit to a silent no-op otherwise.
    func isTrackingActive() async -> Bool {
        guard CatalogSchemaCapabilityGate.current.catalogStockUnits else { return false }
        let mode = try? await inventoryModeRepo.fetchInventoryMode()
        return mode?.isTracked == true
    }

    // MARK: - Phase 1: receive rolls into stock

    /// Creates one `roll` stock unit per physical roll received against the
    /// drafted order line. No-ops silently when tracking is inactive. Returns the
    /// created local models (empty when gated off or inputs invalid).
    @discardableResult
    func receiveRolls(
        orderItemId: String?,
        variantId: String,
        rollCount: Int,
        rollLengthFeet: Double,
        rollWidthInches: Double,
        lotCode: String? = nil,
        location: String? = nil
    ) async throws -> [CatalogStockUnit] {
        guard rollCount > 0, rollLengthFeet > 0, rollWidthInches > 0 else { return [] }
        guard await isTrackingActive() else { return [] }

        let widthFeet = rollWidthInches / 12.0
        var created: [CatalogStockUnit] = []

        for index in 0..<rollCount {
            let label = rollCount == 1 ? "ROLL" : "ROLL \(index + 1)"
            let dto = CreateCatalogStockUnitDTO(
                id: UUID().uuidString,
                companyId: companyId,
                catalogVariantId: variantId,
                unitKind: .roll,
                label: label,
                lotCode: lotCode,
                widthValue: widthFeet,
                widthUnit: Self.storedUnit,
                originalLengthValue: rollLengthFeet,
                remainingLengthValue: rollLengthFeet,
                lengthUnit: Self.storedUnit,
                quantityValue: 1,
                location: location,
                status: .full,
                sourceOrderItemId: orderItemId,
                notes: nil
            )
            let createdDTO = try await stockUnitRepo.create(dto)
            created.append(insertStockUnitMirror(createdDTO))

            // Ledger: receive event (best-effort — the stock unit is the source
            // of truth; a ledger hiccup must not strand a received roll).
            let eventDTO = CreateCatalogStockUnitEventDTO(
                companyId: companyId,
                catalogStockUnitId: createdDTO.id,
                catalogVariantId: variantId,
                eventType: .receive,
                fromStatus: nil,
                toStatus: .full,
                quantityDelta: 1,
                remainingLengthDelta: rollLengthFeet,
                payload: [
                    "source": "ios_vinyl_order",
                    "action": "receive",
                    "order_item_id": orderItemId ?? ""
                ],
                marker: Self.receiptMarker,
                notes: nil
            )
            await emitEvent(eventDTO)
        }

        try? modelContext.save()
        await remirrorVariantQuantity(variantId: variantId)
        return created
    }

    // MARK: - Phase 2: bank an offcut produced by the cut plan

    /// Records cutting `offcut` from `sourceRollId`: debits the roll's remaining
    /// length, creates the banked offcut stock unit, writes the ledger, and posts
    /// the OFFCUT BANKED rail notification. No-ops silently when tracking is
    /// inactive or the source roll is gone/exhausted. Returns the banked offcut.
    @discardableResult
    func bankOffcut(
        variantId: String,
        sourceRollId: String,
        offcut: VinylProducedOffcut,
        projectId: String?,
        notes: String? = nil
    ) async throws -> CatalogStockUnit? {
        guard offcut.lengthInches > 0, offcut.widthInches > 0 else { return nil }
        guard await isTrackingActive() else { return nil }

        let rollDescriptor = FetchDescriptor<CatalogStockUnit>(
            predicate: #Predicate { $0.id == sourceRollId }
        )
        guard let roll = try modelContext.fetch(rollDescriptor).first,
              roll.deletedAt == nil,
              roll.status != .consumed,
              roll.status != .scrapped,
              let rollRemaining = roll.remainingLengthValue,
              rollRemaining > 0 else { return nil }

        let offcutLengthFeet = offcut.lengthInches / 12.0
        let offcutWidthFeet = offcut.widthInches / 12.0
        // The roll must physically cover the full strip length — never silently
        // truncate, which would mis-size the offcut and misreport the rail
        // notification. The caller picks a roll with enough remaining; if none
        // does, banking is rejected (no-op).
        guard rollRemaining + 0.001 >= offcutLengthFeet else { return nil }
        let consumedFeet = offcutLengthFeet

        let nextRemaining = max(0, rollRemaining - consumedFeet)
        let rollFromStatus = roll.status
        let nextRollStatus: CatalogStockUnitStatus = nextRemaining <= 0 ? .consumed : .partial

        // 1) Create the offcut stock unit FIRST — its events reference it, and
        //    the anon RLS requires the row to already exist for the company.
        let offcutDTO = CreateCatalogStockUnitDTO(
            id: UUID().uuidString,
            companyId: companyId,
            catalogVariantId: variantId,
            unitKind: .offcut,
            label: "OFFCUT \(inchLabel(offcut.widthInches))",
            lotCode: roll.lotCode,
            widthValue: offcutWidthFeet,
            widthUnit: roll.widthUnit ?? Self.storedUnit,
            originalLengthValue: consumedFeet,
            remainingLengthValue: consumedFeet,
            lengthUnit: roll.lengthUnit ?? Self.storedUnit,
            quantityValue: 1,
            location: roll.location,
            status: .partial,
            sourceOrderItemId: roll.sourceOrderItemId,
            notes: notes
        )
        let createdOffcut = try await stockUnitRepo.create(offcutDTO)

        // 2) Debit the source roll. If this fails, compensate the just-created
        //    offcut so we never strand an orphan unit / inflated inventory —
        //    there is no cross-request transaction across these REST writes.
        do {
            var rollFields = UpdateCatalogStockUnitDTO()
            rollFields.remainingLengthValue = nextRemaining
            rollFields.status = nextRollStatus
            _ = try await stockUnitRepo.update(sourceRollId, fields: rollFields)
        } catch {
            try? await stockUnitRepo.softDelete(createdOffcut.id)
            throw error
        }

        // 3) Ledger (best-effort): offcut_create on the offcut + adjust on the
        //    source roll, cross-linked via related_catalog_stock_unit_id.
        let payload: [String: String] = [
            "source": "ios_deck_builder_cut",
            "action": "offcut_bank",
            "offcut_id": createdOffcut.id,
            "source_roll_id": sourceRollId,
            "project_id": projectId ?? ""
        ]
        await emitEvent(CreateCatalogStockUnitEventDTO(
            companyId: companyId,
            catalogStockUnitId: createdOffcut.id,
            catalogVariantId: variantId,
            relatedCatalogStockUnitId: sourceRollId,
            eventType: .offcutCreate,
            fromStatus: nil,
            toStatus: .partial,
            quantityDelta: 1,
            remainingLengthDelta: consumedFeet,
            payload: payload,
            marker: Self.bankMarker,
            notes: notes
        ))
        await emitEvent(CreateCatalogStockUnitEventDTO(
            companyId: companyId,
            catalogStockUnitId: sourceRollId,
            catalogVariantId: variantId,
            relatedCatalogStockUnitId: createdOffcut.id,
            eventType: .adjust,
            fromStatus: rollFromStatus,
            toStatus: nextRollStatus,
            quantityDelta: nil,
            remainingLengthDelta: -consumedFeet,
            payload: payload,
            marker: Self.bankMarker,
            notes: notes
        ))

        // 4) Update local mirrors so the UI reflects the cut immediately.
        let offcutModel = insertStockUnitMirror(createdOffcut)
        roll.remainingLengthValue = nextRemaining
        roll.status = nextRollStatus
        roll.updatedAt = Date()
        roll.lastSyncedAt = Date()
        roll.needsSync = false
        try? modelContext.save()

        // 5) Re-mirror the variant quantity from the updated stock set.
        await remirrorVariantQuantity(variantId: variantId)

        // 6) Rail notification.
        await postOffcutBankedNotification(offcut: offcut, projectId: projectId)

        return offcutModel
    }

    // MARK: - Mirror helpers

    @discardableResult
    private func insertStockUnitMirror(_ dto: CatalogStockUnitDTO) -> CatalogStockUnit {
        let model = dto.toModel()
        model.needsSync = false
        model.lastSyncedAt = Date()
        modelContext.insert(model)
        return model
    }

    private func emitEvent(_ dto: CreateCatalogStockUnitEventDTO) async {
        do {
            let created = try await eventRepo.create(dto)
            let model = created.toModel()
            model.needsSync = false
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        } catch {
            print("[VinylOffcutInventoryService] ledger emit failed (\(dto.eventType.rawValue)): \(error)")
        }
    }

    /// Recomputes `catalog_variants.quantity` from the available stock units for
    /// the variant and writes it through (server + local mirror).
    private func remirrorVariantQuantity(variantId: String) async {
        do {
            let descriptor = FetchDescriptor<CatalogStockUnit>(
                predicate: #Predicate { $0.catalogVariantId == variantId && $0.deletedAt == nil }
            )
            let units = try modelContext.fetch(descriptor)
            let aggregate = CatalogStockUnitAggregator.aggregate(units: units).byVariantId[variantId]
                ?? CatalogStockUnitVariantAggregate()
            let newQuantity = CatalogStockQuantityPolicy.quantityToMirror(aggregate)
            _ = try await catalogRepo.adjustVariantQuantity(variantId, newQuantity: newQuantity)

            let variantDescriptor = FetchDescriptor<CatalogVariant>(
                predicate: #Predicate { $0.id == variantId }
            )
            if let variant = try modelContext.fetch(variantDescriptor).first {
                variant.quantity = newQuantity
                variant.lastSyncedAt = Date()
                variant.needsSync = false
                try? modelContext.save()
            }
        } catch {
            print("[VinylOffcutInventoryService] variant quantity re-mirror failed: \(error)")
        }
    }

    private func postOffcutBankedNotification(offcut: VinylProducedOffcut, projectId: String?) async {
        guard !userId.isEmpty else { return }
        let body = "\(inchLabel(offcut.widthInches)) × \(vinylFormatFeetAndInches(offcut.lengthInches)) BANKED TO STOCK"
        try? await NotificationRepository.shared.createNotification(
            NotificationRepository.CreateNotificationDTO(
                userId: userId,
                companyId: companyId,
                type: "standard",
                title: "// OFFCUT BANKED",
                body: body,
                projectId: projectId,
                deepLinkType: "catalog_stock",
                persistent: false,
                actionUrl: "/catalog?segment=stock",
                actionLabel: "VIEW STOCK"
            )
        )
        NotificationCenter.default.post(name: .notificationReceived, object: nil)
    }

    private func inchLabel(_ inches: Double) -> String {
        let rounded = (inches * 10).rounded() / 10
        if rounded.rounded() == rounded { return "\(Int(rounded))\"" }
        return String(format: "%.1f\"", rounded)
    }
}
