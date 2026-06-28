import Foundation

struct AppleIdentity: Equatable {
    let sub: String
    let email: String?
    let fullName: String?

    init(
        sub: String,
        email: String? = nil,
        fullName: String? = nil
    ) {
        self.sub = sub
        self.email = email
        self.fullName = fullName
    }
}

struct UsersRow: Equatable {
    let id: String
    let firebaseUid: String
    let companyId: String?
}

struct CompanyDraft: Equatable {
    let id: String
    let name: String
    let adminIds: [String]
    let subscriptionPlan: String

    init(
        id: String,
        name: String,
        adminIds: [String],
        subscriptionPlan: String = "decks"
    ) {
        self.id = id
        self.name = name
        self.adminIds = adminIds
        self.subscriptionPlan = subscriptionPlan
    }
}

struct UserDraft: Equatable {
    let id: String
    let firebaseUid: String
    let authId: String
    let companyId: String
    let role: String
}

struct ProvisioningPlan: Equatable {
    let createCompany: CompanyDraft?
    let createUser: UserDraft?
    let attachToCompanyId: String?
    let resolvedCompanyId: String
}

protocol ProvisioningBackend: AnyObject {
    func applyProvisioningPlan(_ plan: ProvisioningPlan) async throws
}

struct CompanyOfOneProvisioner {
    private let companyIdGenerator: () -> String
    private let userIdGenerator: () -> String

    init(
        companyIdGenerator: @escaping () -> String = { UUID().uuidString },
        userIdGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        self.companyIdGenerator = companyIdGenerator
        self.userIdGenerator = userIdGenerator
    }

    func plan(
        for identity: AppleIdentity,
        existingUser: UsersRow?
    ) -> ProvisioningPlan {
        if let companyId = existingUser?.companyId?.trimmedNonEmpty {
            return ProvisioningPlan(
                createCompany: nil,
                createUser: nil,
                attachToCompanyId: nil,
                resolvedCompanyId: companyId
            )
        }

        let companyId = companyIdGenerator()
        let companyName = Self.companyName(for: identity)

        if let existingUser {
            return ProvisioningPlan(
                createCompany: CompanyDraft(
                    id: companyId,
                    name: companyName,
                    adminIds: [existingUser.id]
                ),
                createUser: nil,
                attachToCompanyId: companyId,
                resolvedCompanyId: companyId
            )
        }

        let userId = userIdGenerator()
        return ProvisioningPlan(
            createCompany: CompanyDraft(
                id: companyId,
                name: companyName,
                adminIds: [userId]
            ),
            createUser: UserDraft(
                id: userId,
                firebaseUid: identity.sub,
                authId: identity.sub,
                companyId: companyId,
                role: "admin"
            ),
            attachToCompanyId: nil,
            resolvedCompanyId: companyId
        )
    }

    private static func companyName(for identity: AppleIdentity) -> String {
        identity.fullName?.trimmedNonEmpty ?? OPSDecksCopy.defaultCompanyName
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
