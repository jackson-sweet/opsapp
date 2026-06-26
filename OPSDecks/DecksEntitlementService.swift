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
