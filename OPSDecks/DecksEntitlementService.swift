import Foundation

enum DecksEntitlement: Equatable {
    case free(savedDeckLimit: Int)
    case pro
}

enum DeckSaveDecision: Equatable {
    case allowSave
    case requiresPro
}

struct DecksEntitlementGate {
    let entitlement: DecksEntitlement

    func decision(savedDeckCount: Int) -> DeckSaveDecision {
        switch entitlement {
        case .pro:
            return .allowSave
        case .free(let limit):
            let normalizedCount = max(savedDeckCount, 0)
            let normalizedLimit = max(limit, 0)
            return normalizedCount < normalizedLimit ? .allowSave : .requiresPro
        }
    }
}

enum DeckSubscriptionMirrorStatus: Equatable {
    case active
    case trialing
    case inGrace
    case expired
    case cancelled
    case revoked
    case unknown(String)

    var unlocksPro: Bool {
        switch self {
        case .active, .trialing, .inGrace:
            return true
        case .expired, .cancelled, .revoked, .unknown:
            return false
        }
    }
}

extension DeckSubscriptionMirrorStatus: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "active":
            self = .active
        case "trialing":
            self = .trialing
        case "in_grace":
            self = .inGrace
        case "expired":
            self = .expired
        case "cancelled":
            self = .cancelled
        case "revoked":
            self = .revoked
        default:
            self = .unknown(rawValue)
        }
    }
}

struct DeckSubscriptionMirrorRow: Decodable, Equatable {
    let companyId: String
    let revenueCatCustomerId: String
    let entitlement: String
    let productId: String
    let status: DeckSubscriptionMirrorStatus
    let store: String
    let expiresAt: Date?
    let lastEventAt: Date

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case revenueCatCustomerId = "revenuecat_customer_id"
        case entitlement
        case productId = "product_id"
        case status
        case store
        case expiresAt = "expires_at"
        case lastEventAt = "last_event_at"
    }
}

enum DecksEntitlementResolver {
    static let deckProEntitlementIdentifier = "deck_pro"
    static let freeSavedDeckLimit = 1

    static func entitlement(
        activeRevenueCatEntitlementIds: Set<String>,
        freeSavedDeckLimit: Int = Self.freeSavedDeckLimit
    ) -> DecksEntitlement {
        activeRevenueCatEntitlementIds.contains(deckProEntitlementIdentifier)
            ? .pro
            : .free(savedDeckLimit: freeSavedDeckLimit)
    }

    static func entitlement(
        subscriptionMirror row: DeckSubscriptionMirrorRow?,
        freeSavedDeckLimit: Int = Self.freeSavedDeckLimit
    ) -> DecksEntitlement {
        guard
            let row,
            row.entitlement == deckProEntitlementIdentifier,
            row.status.unlocksPro
        else {
            return .free(savedDeckLimit: freeSavedDeckLimit)
        }
        return .pro
    }
}

protocol DecksRevenueCatCustomerInfoReading: AnyObject {
    func activeEntitlementIdentifiers() async throws -> Set<String>
}

protocol DecksEntitlementProviding: AnyObject {
    func currentEntitlement() async -> DecksEntitlement
    func refreshEntitlement() async -> DecksEntitlement
}

final class DecksRevenueCatEntitlementProvider: DecksEntitlementProviding {
    private let customerInfoReader: DecksRevenueCatCustomerInfoReading
    private let freeSavedDeckLimit: Int
    private var cachedEntitlement: DecksEntitlement

    init(
        customerInfoReader: DecksRevenueCatCustomerInfoReading,
        cachedEntitlement: DecksEntitlement = .free(savedDeckLimit: DecksEntitlementResolver.freeSavedDeckLimit),
        freeSavedDeckLimit: Int = DecksEntitlementResolver.freeSavedDeckLimit
    ) {
        self.customerInfoReader = customerInfoReader
        self.cachedEntitlement = cachedEntitlement
        self.freeSavedDeckLimit = freeSavedDeckLimit
    }

    func currentEntitlement() async -> DecksEntitlement {
        cachedEntitlement
    }

    func refreshEntitlement() async -> DecksEntitlement {
        do {
            let identifiers = try await customerInfoReader.activeEntitlementIdentifiers()
            let resolved = DecksEntitlementResolver.entitlement(
                activeRevenueCatEntitlementIds: identifiers,
                freeSavedDeckLimit: freeSavedDeckLimit
            )
            cachedEntitlement = resolved
            return resolved
        } catch {
            return cachedEntitlement
        }
    }
}
