import Foundation

struct DecksCompanyProvisioningRequest: Encodable, Equatable {
    let firebaseUID: String
    let email: String
    let displayName: String?
    let sourceApp: String = "ops_decks"

    enum CodingKeys: String, CodingKey {
        case firebaseUID = "firebase_uid"
        case email
        case displayName = "display_name"
        case sourceApp = "source_app"
    }
}

struct DecksCompanyProvisioningResponse: Decodable, Equatable {
    let companyId: String
    let userId: String
    let role: String
    let subscriptionPlan: String

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case userId = "user_id"
        case role
        case subscriptionPlan = "subscription_plan"
    }
}
