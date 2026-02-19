//
//  InvoiceDTOs.swift
//  OPS
//
//  Data Transfer Objects for Invoice Supabase tables.
//

import Foundation

struct InvoiceDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let estimateId: String?
    let opportunityId: String?
    let projectId: String?
    let clientId: String?
    let invoiceNumber: String
    let title: String?
    let status: String
    let subtotal: Double
    let taxRate: Double?
    let taxAmount: Double?
    let total: Double
    let amountPaid: Double
    let balanceDue: Double
    let dueDate: String?
    let sentAt: String?
    let paidAt: String?
    let notes: String?
    let createdAt: String
    let updatedAt: String
    let lineItems: [InvoiceLineItemDTO]?
    let payments: [PaymentDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId      = "company_id"
        case estimateId     = "estimate_id"
        case opportunityId  = "opportunity_id"
        case projectId      = "project_id"
        case clientId       = "client_id"
        case invoiceNumber  = "invoice_number"
        case title
        case status
        case subtotal
        case taxRate        = "tax_rate"
        case taxAmount      = "tax_amount"
        case total
        case amountPaid     = "amount_paid"
        case balanceDue     = "balance_due"
        case dueDate        = "due_date"
        case sentAt         = "sent_at"
        case paidAt         = "paid_at"
        case notes
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
        case lineItems      = "invoice_line_items"
        case payments
    }

    func toModel() -> Invoice {
        let inv = Invoice(
            id: id,
            companyId: companyId,
            invoiceNumber: invoiceNumber,
            status: InvoiceStatus(rawValue: status) ?? .draft,
            taxRate: taxRate ?? 0,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
        inv.subtotal = subtotal
        inv.taxAmount = taxAmount ?? 0
        inv.total = total
        inv.amountPaid = amountPaid
        inv.balanceDue = balanceDue
        inv.title = title
        inv.estimateId = estimateId
        inv.opportunityId = opportunityId
        inv.projectId = projectId
        inv.clientId = clientId
        if let dd = dueDate { inv.dueDate = SupabaseDate.parse(dd) }
        if let sa = sentAt { inv.sentAt = SupabaseDate.parse(sa) }
        if let pa = paidAt { inv.paidAt = SupabaseDate.parse(pa) }
        return inv
    }
}

struct InvoiceLineItemDTO: Codable, Identifiable {
    let id: String
    let invoiceId: String
    let productId: String?
    let description: String
    let quantity: Double
    let unitPrice: Double
    let unit: String?
    let type: String?
    let total: Double
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case invoiceId  = "invoice_id"
        case productId  = "product_id"
        case description
        case quantity
        case unitPrice  = "unit_price"
        case unit
        case type
        case total
        case sortOrder  = "sort_order"
    }

    func toModel() -> InvoiceLineItem {
        let item = InvoiceLineItem(
            id: id,
            invoiceId: invoiceId,
            name: description,
            type: type.flatMap { LineItemType(rawValue: $0) } ?? .labor,
            quantity: quantity,
            unitPrice: unitPrice,
            displayOrder: sortOrder
        )
        item.lineTotal = total
        item.unit = unit
        return item
    }
}

struct PaymentDTO: Codable, Identifiable {
    let id: String
    let invoiceId: String
    let companyId: String
    let amount: Double
    let method: String
    let reference: String?
    let notes: String?
    let isVoid: Bool?
    let paidAt: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case invoiceId  = "invoice_id"
        case companyId  = "company_id"
        case amount
        case method
        case reference
        case notes
        case isVoid     = "is_void"
        case paidAt     = "paid_at"
        case createdAt  = "created_at"
    }

    func toModel() -> Payment {
        let pay = Payment(
            id: id,
            invoiceId: invoiceId,
            companyId: companyId,
            amount: amount,
            method: PaymentMethod(rawValue: method) ?? .other,
            paidAt: SupabaseDate.parse(paidAt) ?? Date(),
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        pay.notes = notes
        return pay
    }
}

struct CreatePaymentDTO: Codable {
    let invoiceId: String
    let companyId: String
    let amount: Double
    let method: String
    let reference: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case invoiceId  = "invoice_id"
        case companyId  = "company_id"
        case amount
        case method
        case reference
        case notes
    }
}
