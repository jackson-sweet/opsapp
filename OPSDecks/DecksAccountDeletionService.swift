import Foundation

struct DecksAccountDeletionRequest: Encodable, Equatable {
    let firebaseUID: String
    let companyId: String

    enum CodingKeys: String, CodingKey {
        case firebaseUID = "firebase_uid"
        case companyId = "company_id"
    }
}

struct DecksAccountDeletionReceipt: Decodable, Equatable {
    let receiptId: String
    let deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case receiptId = "receipt_id"
        case deletedAt = "deleted_at"
    }
}
