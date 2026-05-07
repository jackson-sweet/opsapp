//
//  CatalogOrderDTOs.swift
//  OPS
//

import Foundation

struct CatalogOrderDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let status: String
    let title: String?
    let supplierName: String?
    let supplierContact: String?
    let expectedDeliveryDate: String?
    let notes: String?
    let createdById: String?
    let createdAt: String
    let updatedAt: String
    let sentAt: String?
    let fulfilledAt: String?
    let cancelledAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId               = "company_id"
        case status
        case title
        case supplierName            = "supplier_name"
        case supplierContact         = "supplier_contact"
        case expectedDeliveryDate    = "expected_delivery_date"
        case notes
        case createdById             = "created_by_id"
        case createdAt               = "created_at"
        case updatedAt               = "updated_at"
        case sentAt                  = "sent_at"
        case fulfilledAt             = "fulfilled_at"
        case cancelledAt             = "cancelled_at"
        case deletedAt               = "deleted_at"
    }

    func toModel() -> CatalogOrder {
        let order = CatalogOrder(
            id: id, companyId: companyId,
            status: CatalogOrderStatus(rawValue: status) ?? .draft,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
        order.title = title
        order.supplierName = supplierName
        order.supplierContact = supplierContact
        order.expectedDeliveryDate = expectedDeliveryDate.flatMap { SupabaseDate.parseDateOnly($0) }
        order.notes = notes
        order.createdById = createdById
        order.sentAt = sentAt.flatMap { SupabaseDate.parse($0) }
        order.fulfilledAt = fulfilledAt.flatMap { SupabaseDate.parse($0) }
        order.cancelledAt = cancelledAt.flatMap { SupabaseDate.parse($0) }
        order.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return order
    }
}

struct CatalogOrderItemDTO: Codable, Identifiable {
    let id: String
    let orderId: String
    let catalogVariantId: String
    let quantityRequested: Double
    let costPerUnit: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orderId               = "order_id"
        case catalogVariantId      = "catalog_variant_id"
        case quantityRequested     = "quantity_requested"
        case costPerUnit           = "cost_per_unit"
        case notes
    }

    func toModel() -> CatalogOrderItem {
        CatalogOrderItem(
            id: id, orderId: orderId, catalogVariantId: catalogVariantId,
            quantityRequested: quantityRequested,
            costPerUnit: costPerUnit, notes: notes
        )
    }
}

struct CreateCatalogOrderDTO: Codable {
    let companyId: String
    let status: String
    let title: String?
    let supplierName: String?
    let notes: String?
    let createdById: String?

    enum CodingKeys: String, CodingKey {
        case companyId      = "company_id"
        case status
        case title
        case supplierName   = "supplier_name"
        case notes
        case createdById    = "created_by_id"
    }
}

struct CreateCatalogOrderItemDTO: Codable {
    let orderId: String
    let catalogVariantId: String
    let quantityRequested: Double
    let costPerUnit: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case orderId            = "order_id"
        case catalogVariantId   = "catalog_variant_id"
        case quantityRequested  = "quantity_requested"
        case costPerUnit        = "cost_per_unit"
        case notes
    }
}
