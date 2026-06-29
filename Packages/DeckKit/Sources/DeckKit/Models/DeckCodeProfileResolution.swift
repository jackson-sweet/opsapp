import Foundation

public struct DeckSiteAddress: Codable, Equatable {
    public var addressLine1: String
    public var addressLine2: String?
    public var locality: String
    public var administrativeArea: String
    public var postalCode: String
    public var countryCode: String

    public init(
        addressLine1: String,
        addressLine2: String? = nil,
        locality: String,
        administrativeArea: String,
        postalCode: String,
        countryCode: String
    ) {
        self.addressLine1 = addressLine1
        self.addressLine2 = addressLine2
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.postalCode = postalCode
        self.countryCode = countryCode
    }
}

public struct DeckCodeProfileRequest: Codable, Equatable {
    public var siteAddress: DeckSiteAddress?
    public var jurisdictionId: String?

    public init(siteAddress: DeckSiteAddress? = nil, jurisdictionId: String? = nil) {
        self.siteAddress = siteAddress
        self.jurisdictionId = jurisdictionId
    }
}

public enum DeckCodeProfileResolutionStatus: String, Codable, Equatable {
    case notConfigured
    case available
    case unavailable
    case failed
}

public struct DeckCodeProfileResolutionToken: RawRepresentable, Codable, Equatable {
    public static let notConfigured = DeckCodeProfileResolutionToken("deck.code.profile.notConfigured")
    public static let unavailable = DeckCodeProfileResolutionToken("deck.code.profile.unavailable")
    public static let failed = DeckCodeProfileResolutionToken("deck.code.profile.failed")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct DeckCodeProfileResolution: Codable, Equatable {
    public var request: DeckCodeProfileRequest
    public var status: DeckCodeProfileResolutionStatus
    public var profile: DeckCodeProfile?
    public var reasonToken: DeckCodeProfileResolutionToken?

    public init(
        request: DeckCodeProfileRequest,
        status: DeckCodeProfileResolutionStatus,
        profile: DeckCodeProfile? = nil,
        reasonToken: DeckCodeProfileResolutionToken? = nil
    ) {
        self.request = request
        self.status = status
        self.profile = profile
        self.reasonToken = reasonToken
    }
}

public struct DeckManualCodeProfileResolver: Equatable {
    private let profilesByJurisdictionId: [String: DeckCodeProfile]

    public init(profiles: [DeckCodeProfile]) {
        var profilesByJurisdictionId: [String: DeckCodeProfile] = [:]
        for profile in profiles where profilesByJurisdictionId[profile.jurisdiction.id] == nil {
            profilesByJurisdictionId[profile.jurisdiction.id] = profile
        }
        self.profilesByJurisdictionId = profilesByJurisdictionId
    }

    public func resolve(_ request: DeckCodeProfileRequest) -> DeckCodeProfileResolution {
        guard let jurisdictionId = request.jurisdictionId, !jurisdictionId.isEmpty else {
            return DeckCodeProfileResolution(
                request: request,
                status: .notConfigured,
                reasonToken: .notConfigured
            )
        }

        guard let profile = profilesByJurisdictionId[jurisdictionId] else {
            return DeckCodeProfileResolution(
                request: request,
                status: .unavailable,
                reasonToken: .unavailable
            )
        }

        return DeckCodeProfileResolution(
            request: request,
            status: .available,
            profile: profile
        )
    }
}
