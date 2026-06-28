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

struct AccountDeletionCompanyRow: Equatable {
    let id: String
    let adminIds: [String]
    let subscriptionPlan: String
    let memberCount: Int
}

enum AccountDeletionBlockReason: Equatable {
    case upgradedOPSCompany
    case otherMembersPresent
    case userIsNotSoleAdmin
}

struct AccountDeletionPlan: Equatable {
    let softDeleteDeckIds: [String]
    let deleteCompany: Bool
    let deleteUser: Bool
    let blockedReason: AccountDeletionBlockReason?
}

struct AccountDeletionPlanner {
    func plan(
        company: AccountDeletionCompanyRow,
        userId: String,
        deckIds: [String]
    ) -> AccountDeletionPlan {
        guard company.subscriptionPlan == "decks" else {
            return blocked(.upgradedOPSCompany)
        }

        guard company.memberCount == 1 else {
            return blocked(.otherMembersPresent)
        }

        guard company.adminIds.count == 1, company.adminIds.first == userId else {
            return blocked(.userIsNotSoleAdmin)
        }

        return AccountDeletionPlan(
            softDeleteDeckIds: deckIds,
            deleteCompany: true,
            deleteUser: true,
            blockedReason: nil
        )
    }

    private func blocked(_ reason: AccountDeletionBlockReason) -> AccountDeletionPlan {
        AccountDeletionPlan(
            softDeleteDeckIds: [],
            deleteCompany: false,
            deleteUser: false,
            blockedReason: reason
        )
    }
}
