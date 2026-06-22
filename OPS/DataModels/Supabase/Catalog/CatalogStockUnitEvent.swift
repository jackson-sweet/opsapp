//
//  CatalogStockUnitEvent.swift
//  OPS
//
//  Local mirror of the `catalog_stock_unit_events` ledger — the append-only
//  parentage/lifecycle trail behind every stock unit (receive, consume,
//  offcut_create, adjust, scrap, …). Rows are immutable: the table has no
//  `updated_at`/`deleted_at` column, so this model carries `createdAt` only and
//  is synced inbound-fetch-only, keyed off `created_at`. Writes go straight to
//  Supabase via `CatalogStockUnitEventRepository`; the inbound sync mirrors the
//  ledger so offcut provenance resolves locally once its parent stock units are
//  present (sync priority 13, after stock units/variants).
//

import Foundation
import SwiftData

@Model
final class CatalogStockUnitEvent: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var catalogStockUnitId: String
    var catalogVariantId: String
    /// The other unit involved in the event — e.g. the source roll for an
    /// `offcut_create`, or the offcut for the matching source `adjust`.
    var relatedCatalogStockUnitId: String?
    var eventType: CatalogStockUnitLifecycleEventType
    var fromStatus: CatalogStockUnitStatus?
    var toStatus: CatalogStockUnitStatus?
    var quantityDelta: Double?
    var remainingLengthDelta: Double?
    /// Idempotency / provenance marker (e.g. the deck-builder cut key) used to
    /// guard against double-emitting the same lifecycle event.
    var marker: String?
    var notes: String?
    /// Server-resolved actor (`private.get_current_user_id()` default). The
    /// client never sets this on write; it arrives on the inbound mirror.
    var createdBy: String?
    var createdAt: Date

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        companyId: String,
        catalogStockUnitId: String,
        catalogVariantId: String,
        relatedCatalogStockUnitId: String? = nil,
        eventType: CatalogStockUnitLifecycleEventType,
        fromStatus: CatalogStockUnitStatus? = nil,
        toStatus: CatalogStockUnitStatus? = nil,
        quantityDelta: Double? = nil,
        remainingLengthDelta: Double? = nil,
        marker: String? = nil,
        notes: String? = nil,
        createdBy: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.catalogStockUnitId = catalogStockUnitId
        self.catalogVariantId = catalogVariantId
        self.relatedCatalogStockUnitId = relatedCatalogStockUnitId
        self.eventType = eventType
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.quantityDelta = quantityDelta
        self.remainingLengthDelta = remainingLengthDelta
        self.marker = marker
        self.notes = notes
        self.createdBy = createdBy
        self.createdAt = createdAt
    }
}
