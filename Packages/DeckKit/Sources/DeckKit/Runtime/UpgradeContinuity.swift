public struct CompanyOriginInfo: Equatable, Sendable {
    public let id: String
    public let subscriptionPlan: String

    public init(
        id: String,
        subscriptionPlan: String
    ) {
        self.id = id
        self.subscriptionPlan = subscriptionPlan
    }
}

public enum UpgradeConversionBlockReason: Equatable, Sendable {
    case notDeckOnlyCompany
    case invalidTargetSubscriptionPlan
}

public struct CompanyConversionPlan: Equatable, Sendable {
    public let companyId: String
    public let currentSubscriptionPlan: String
    public let targetSubscriptionPlan: String?
    public let preservesCompany: Bool
    public let preservesDeckDesigns: Bool
    public let shouldConvert: Bool
    public let blockedReason: UpgradeConversionBlockReason?

    public init(
        companyId: String,
        currentSubscriptionPlan: String,
        targetSubscriptionPlan: String?,
        preservesCompany: Bool,
        preservesDeckDesigns: Bool,
        shouldConvert: Bool,
        blockedReason: UpgradeConversionBlockReason?
    ) {
        self.companyId = companyId
        self.currentSubscriptionPlan = currentSubscriptionPlan
        self.targetSubscriptionPlan = targetSubscriptionPlan
        self.preservesCompany = preservesCompany
        self.preservesDeckDesigns = preservesDeckDesigns
        self.shouldConvert = shouldConvert
        self.blockedReason = blockedReason
    }
}

public enum UpgradeContinuity {
    public static let deckOnlySubscriptionPlan = "decks"

    public static func opsAppShouldRouteToUpgrade(for company: CompanyOriginInfo) -> Bool {
        company.subscriptionPlan == deckOnlySubscriptionPlan
    }

    public static func opsCompanyConversion(
        from company: CompanyOriginInfo,
        targetSubscriptionPlan: String
    ) -> CompanyConversionPlan {
        if company.subscriptionPlan != deckOnlySubscriptionPlan {
            return blockedPlan(
                company: company,
                reason: .notDeckOnlyCompany
            )
        }

        if targetSubscriptionPlan == deckOnlySubscriptionPlan {
            return blockedPlan(
                company: company,
                reason: .invalidTargetSubscriptionPlan
            )
        }

        return CompanyConversionPlan(
            companyId: company.id,
            currentSubscriptionPlan: company.subscriptionPlan,
            targetSubscriptionPlan: targetSubscriptionPlan,
            preservesCompany: true,
            preservesDeckDesigns: true,
            shouldConvert: true,
            blockedReason: nil
        )
    }

    private static func blockedPlan(
        company: CompanyOriginInfo,
        reason: UpgradeConversionBlockReason
    ) -> CompanyConversionPlan {
        CompanyConversionPlan(
            companyId: company.id,
            currentSubscriptionPlan: company.subscriptionPlan,
            targetSubscriptionPlan: nil,
            preservesCompany: true,
            preservesDeckDesigns: true,
            shouldConvert: false,
            blockedReason: reason
        )
    }
}
