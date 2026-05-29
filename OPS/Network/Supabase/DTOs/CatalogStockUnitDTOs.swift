//
//  CatalogStockUnitDTOs.swift
//  OPS
//

import Foundation

struct CatalogStockUnitDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let catalogVariantId: String
    let unitKind: String
    let label: String?
    let lotCode: String?
    let widthValue: Double?
    let widthUnit: String?
    let originalLengthValue: Double?
    let remainingLengthValue: Double?
    let lengthUnit: String?
    let quantityValue: Double
    let location: String?
    let status: String
    let sourceOrderItemId: String?
    let notes: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId              = "company_id"
        case catalogVariantId       = "catalog_variant_id"
        case unitKind               = "unit_kind"
        case label
        case lotCode                = "lot_code"
        case widthValue             = "width_value"
        case widthUnit              = "width_unit"
        case originalLengthValue    = "original_length_value"
        case remainingLengthValue   = "remaining_length_value"
        case lengthUnit             = "length_unit"
        case quantityValue          = "quantity_value"
        case location
        case status
        case sourceOrderItemId      = "source_order_item_id"
        case notes
        case createdAt              = "created_at"
        case updatedAt              = "updated_at"
        case deletedAt              = "deleted_at"
    }

    func toModel() -> CatalogStockUnit {
        let model = CatalogStockUnit(
            id: id,
            companyId: companyId,
            catalogVariantId: catalogVariantId,
            unitKind: CatalogStockUnitKind(rawValue: unitKind) ?? .each,
            label: label,
            lotCode: lotCode,
            widthValue: widthValue,
            widthUnit: widthUnit,
            originalLengthValue: originalLengthValue,
            remainingLengthValue: remainingLengthValue,
            lengthUnit: lengthUnit,
            quantityValue: quantityValue,
            location: location,
            status: CatalogStockUnitStatus(rawValue: status) ?? .full,
            sourceOrderItemId: sourceOrderItemId,
            notes: notes,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
        model.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return model
    }
}

struct CreateCatalogStockUnitDTO: Codable {
    let id: String
    let companyId: String
    let catalogVariantId: String
    let unitKind: CatalogStockUnitKind
    let label: String?
    let lotCode: String?
    let widthValue: Double?
    let widthUnit: String?
    let originalLengthValue: Double?
    let remainingLengthValue: Double?
    let lengthUnit: String?
    let quantityValue: Double
    let location: String?
    let status: CatalogStockUnitStatus
    let sourceOrderItemId: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId              = "company_id"
        case catalogVariantId       = "catalog_variant_id"
        case unitKind               = "unit_kind"
        case label
        case lotCode                = "lot_code"
        case widthValue             = "width_value"
        case widthUnit              = "width_unit"
        case originalLengthValue    = "original_length_value"
        case remainingLengthValue   = "remaining_length_value"
        case lengthUnit             = "length_unit"
        case quantityValue          = "quantity_value"
        case location
        case status
        case sourceOrderItemId      = "source_order_item_id"
        case notes
    }
}

struct UpdateCatalogStockUnitDTO: Codable {
    var unitKind: CatalogStockUnitKind?
    var label: String?
    var lotCode: String?
    var widthValue: Double?
    var widthUnit: String?
    var originalLengthValue: Double?
    var remainingLengthValue: Double?
    var lengthUnit: String?
    var quantityValue: Double?
    var location: String?
    var status: CatalogStockUnitStatus?
    var sourceOrderItemId: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case unitKind               = "unit_kind"
        case label
        case lotCode                = "lot_code"
        case widthValue             = "width_value"
        case widthUnit              = "width_unit"
        case originalLengthValue    = "original_length_value"
        case remainingLengthValue   = "remaining_length_value"
        case lengthUnit             = "length_unit"
        case quantityValue          = "quantity_value"
        case location
        case status
        case sourceOrderItemId      = "source_order_item_id"
        case notes
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(unitKind, forKey: .unitKind)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(lotCode, forKey: .lotCode)
        try c.encodeIfPresent(widthValue, forKey: .widthValue)
        try c.encodeIfPresent(widthUnit, forKey: .widthUnit)
        try c.encodeIfPresent(originalLengthValue, forKey: .originalLengthValue)
        try c.encodeIfPresent(remainingLengthValue, forKey: .remainingLengthValue)
        try c.encodeIfPresent(lengthUnit, forKey: .lengthUnit)
        try c.encodeIfPresent(quantityValue, forKey: .quantityValue)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(sourceOrderItemId, forKey: .sourceOrderItemId)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}
