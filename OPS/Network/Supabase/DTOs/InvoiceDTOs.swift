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
    let invoiceNumber: String?
    let subject: String?
    let status: String?
    let subtotal: Double?
    let taxRate: Double?
    let taxAmount: Double?
    let total: Double?
    let amountPaid: Double?
    let balanceDue: Double?
    let dueDate: String?
    let sentAt: String?
    let paidAt: String?
    let notes: String?
    let createdAt: String?
    let updatedAt: String?
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
        case subject
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
        case lineItems      = "line_items"
        case payments
    }

    func toModel() -> Invoice {
        let inv = Invoice(
            id: id,
            companyId: companyId,
            invoiceNumber: invoiceNumber ?? "",
            status: InvoiceStatus(rawValue: status ?? "") ?? .draft,
            taxRate: taxRate ?? 0,
            createdAt: createdAt.flatMap { SupabaseDate.parse($0) } ?? Date(),
            updatedAt: updatedAt.flatMap { SupabaseDate.parse($0) } ?? Date()
        )
        inv.subtotal = subtotal ?? 0
        inv.taxAmount = taxAmount ?? 0
        inv.total = total ?? 0
        inv.amountPaid = amountPaid ?? 0
        inv.balanceDue = balanceDue ?? 0
        inv.title = subject
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
    let invoiceId: String?
    let productId: String?
    let name: String?
    let description: String?
    let quantity: Double?
    let unitPrice: Double?
    let unit: String?
    let type: String?
    let lineTotal: Double?
    let sortOrder: Int?
    let parentLineItemId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case invoiceId  = "invoice_id"
        case productId  = "product_id"
        case name
        case description
        case quantity
        case unitPrice  = "unit_price"
        case unit
        case type
        case lineTotal  = "line_total"
        case sortOrder  = "sort_order"
        case parentLineItemId = "parent_line_item_id"
    }

    func toModel() -> InvoiceLineItem {
        let qty = quantity ?? 0
        let price = unitPrice ?? 0
        let item = InvoiceLineItem(
            id: id,
            invoiceId: invoiceId ?? "",
            name: name ?? "",
            type: type.flatMap { LineItemType(rawValue: $0) } ?? .labor,
            quantity: qty,
            unitPrice: price,
            displayOrder: sortOrder ?? 0
        )
        item.lineTotal = lineTotal ?? (qty * price)
        item.unit = unit
        item.itemDescription = description
        item.parentLineItemId = parentLineItemId
        return item
    }
}

struct PaymentDTO: Codable, Identifiable {
    let id: String
    let invoiceId: String?
    let companyId: String?
    let clientId: String?
    let amount: Double?
    let paymentMethod: String?
    let reference: String?
    let notes: String?
    let isVoid: Bool?
    let paymentDate: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case invoiceId      = "invoice_id"
        case companyId      = "company_id"
        case clientId       = "client_id"
        case amount
        case paymentMethod  = "payment_method"
        case reference
        case notes
        case isVoid         = "is_void"
        case paymentDate    = "payment_date"
        case createdAt      = "created_at"
    }

    func toModel() -> Payment {
        let pay = Payment(
            id: id,
            invoiceId: invoiceId ?? "",
            companyId: companyId ?? "",
            amount: amount ?? 0,
            method: paymentMethod.flatMap { PaymentMethod(rawValue: $0) } ?? .other,
            paidAt: paymentDate.flatMap { SupabaseDate.parse($0) } ?? Date(),
            createdAt: createdAt.flatMap { SupabaseDate.parse($0) } ?? Date()
        )
        pay.notes = notes
        return pay
    }
}

struct CreatePaymentDTO: Codable {
    let invoiceId: String
    let companyId: String
    let clientId: String
    let amount: Double
    let paymentMethod: String
    let reference: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case invoiceId      = "invoice_id"
        case companyId      = "company_id"
        case clientId       = "client_id"
        case amount
        case paymentMethod  = "payment_method"
        case reference
        case notes
    }
}
