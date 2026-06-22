//
//  CatalogStockUnitEventDTOs.swift
//  OPS
//
//  Wire types for the append-only `catalog_stock_unit_events` ledger.
//  `CatalogStockUnitEventDTO` decodes the inbound mirror; `CreateCatalogStockUnitEventDTO`
//  is the insert shape (no `created_by` — the server defaults it via
//  `private.get_current_user_id()`; no `id` is required by the table but we
//  supply one so the local mirror id matches the server row).
//

import Foundation

struct CatalogStockUnitEventDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let catalogStockUnitId: String
    let catalogVariantId: String
    let relatedCatalogStockUnitId: String?
    let eventType: String
    let fromStatus: String?
    let toStatus: String?
    let quantityDelta: Double?
    let remainingLengthDelta: Double?
    let marker: String?
    let notes: String?
    let createdBy: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyId                   = "company_id"
        case catalogStockUnitId          = "catalog_stock_unit_id"
        case catalogVariantId            = "catalog_variant_id"
        case relatedCatalogStockUnitId   = "related_catalog_stock_unit_id"
        case eventType                   = "event_type"
        case fromStatus                  = "from_status"
        case toStatus                    = "to_status"
        case quantityDelta               = "quantity_delta"
        case remainingLengthDelta        = "remaining_length_delta"
        case marker
        case notes
        case createdBy                   = "created_by"
        case createdAt                   = "created_at"
    }

    func toModel() -> CatalogStockUnitEvent {
        CatalogStockUnitEvent(
            id: id,
            companyId: companyId,
            catalogStockUnitId: catalogStockUnitId,
            catalogVariantId: catalogVariantId,
            relatedCatalogStockUnitId: relatedCatalogStockUnitId,
            eventType: CatalogStockUnitLifecycleEventType(rawValue: eventType) ?? .adjust,
            fromStatus: fromStatus.flatMap { CatalogStockUnitStatus(rawValue: $0) },
            toStatus: toStatus.flatMap { CatalogStockUnitStatus(rawValue: $0) },
            quantityDelta: quantityDelta,
            remainingLengthDelta: remainingLengthDelta,
            marker: marker,
            notes: notes,
            createdBy: createdBy,
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
    }
}

struct CreateCatalogStockUnitEventDTO: Codable {
    let id: String
    let companyId: String
    let catalogStockUnitId: String
    let catalogVariantId: String
    let relatedCatalogStockUnitId: String?
    let eventType: CatalogStockUnitLifecycleEventType
    let fromStatus: CatalogStockUnitStatus?
    let toStatus: CatalogStockUnitStatus?
    let quantityDelta: Double?
    let remainingLengthDelta: Double?
    /// Free-form provenance metadata persisted to the `payload` jsonb column.
    /// Omitted when nil so the server default (`'{}'`) applies.
    let payload: [String: String]?
    let marker: String?
    let notes: String?

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
        payload: [String: String]? = nil,
        marker: String? = nil,
        notes: String? = nil
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
        self.payload = payload
        self.marker = marker
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case companyId                   = "company_id"
        case catalogStockUnitId          = "catalog_stock_unit_id"
        case catalogVariantId            = "catalog_variant_id"
        case relatedCatalogStockUnitId   = "related_catalog_stock_unit_id"
        case eventType                   = "event_type"
        case fromStatus                  = "from_status"
        case toStatus                    = "to_status"
        case quantityDelta               = "quantity_delta"
        case remainingLengthDelta        = "remaining_length_delta"
        case payload
        case marker
        case notes
    }

    /// Explicit encode so nil optionals are OMITTED rather than sent as JSON
    /// `null`. Critical for `payload`: the column is NOT NULL with a `'{}'`
    /// default, so an explicit `null` would violate the constraint — omitting it
    /// lets the server default apply. The nullable columns are simply left unset.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(companyId, forKey: .companyId)
        try c.encode(catalogStockUnitId, forKey: .catalogStockUnitId)
        try c.encode(catalogVariantId, forKey: .catalogVariantId)
        try c.encode(eventType, forKey: .eventType)
        try c.encodeIfPresent(relatedCatalogStockUnitId, forKey: .relatedCatalogStockUnitId)
        try c.encodeIfPresent(fromStatus, forKey: .fromStatus)
        try c.encodeIfPresent(toStatus, forKey: .toStatus)
        try c.encodeIfPresent(quantityDelta, forKey: .quantityDelta)
        try c.encodeIfPresent(remainingLengthDelta, forKey: .remainingLengthDelta)
        try c.encodeIfPresent(payload, forKey: .payload)
        try c.encodeIfPresent(marker, forKey: .marker)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}
