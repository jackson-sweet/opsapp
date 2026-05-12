import Foundation

struct PaymentMilestoneDTO: Codable, Identifiable {
    let id: String
    let estimateId: String
    let name: String
    let type: String
    let value: Double
    let amount: Double
    let sortOrder: Int
    let invoiceId: String?
    let paidAt: String?
    let expectedDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case estimateId   = "estimate_id"
        case name
        case type
        case value
        case amount
        case sortOrder    = "sort_order"
        case invoiceId    = "invoice_id"
        case paidAt       = "paid_at"
        case expectedDate = "expected_date"
    }
}

struct CreatePaymentMilestoneDTO: Codable {
    let estimateId: String
    let name: String
    let type: String
    let value: Double
    let amount: Double
    let sortOrder: Int
    let expectedDate: String?

    enum CodingKeys: String, CodingKey {
        case estimateId   = "estimate_id"
        case name, type, value, amount
        case sortOrder    = "sort_order"
        case expectedDate = "expected_date"
    }
}
