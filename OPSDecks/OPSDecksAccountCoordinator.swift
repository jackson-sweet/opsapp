import Foundation

struct OPSDecksAuthenticatedIdentity: Equatable {
    let firebaseUID: String
    let email: String
    let displayName: String?
}

protocol OPSDecksAuthProvider: AnyObject {
    func signInWithApple() async throws -> OPSDecksAuthenticatedIdentity
    func signOut() async throws
}

enum OPSDecksAccountDeletionCoordinatorError: Error, Equatable {
    case missingAccountContext
    case companyMismatch
    case blocked(AccountDeletionBlockReason)
}

final class OPSDecksAccountCoordinator {
    private let authProvider: OPSDecksAuthProvider
    private let provisioningClient: DecksCompanyProvisioningClient
    private let contextStore: OPSDecksAccountContextStore

    init(
        authProvider: OPSDecksAuthProvider,
        provisioningClient: DecksCompanyProvisioningClient,
        contextStore: OPSDecksAccountContextStore
    ) {
        self.authProvider = authProvider
        self.provisioningClient = provisioningClient
        self.contextStore = contextStore
    }

    func loadStoredAccountContext() throws -> OPSDecksAccountContext? {
        try contextStore.loadAccountContext()
    }

    func signInWithApple() async throws -> OPSDecksAccountContext {
        let identity = try await authProvider.signInWithApple()
        let response = try await provisioningClient.provisionCompany(
            DecksCompanyProvisioningRequest(
                firebaseUID: identity.firebaseUID,
                email: identity.email,
                displayName: identity.displayName
            )
        )
        let context = OPSDecksAccountContext(
            firebaseUID: identity.firebaseUID,
            email: identity.email,
            displayName: identity.displayName,
            provisioningResponse: response
        )
        try contextStore.saveAccountContext(context)
        return context
    }

    func signOut() async throws {
        try contextStore.clearAccountContext()
        try await authProvider.signOut()
    }
}

final class OPSDecksAccountDeletionCoordinator {
    private let authProvider: OPSDecksAuthProvider
    private let deletionClient: DecksAccountDeletionClient
    private let contextStore: OPSDecksAccountContextStore
    private let planner: AccountDeletionPlanner

    init(
        authProvider: OPSDecksAuthProvider,
        deletionClient: DecksAccountDeletionClient,
        contextStore: OPSDecksAccountContextStore,
        planner: AccountDeletionPlanner = AccountDeletionPlanner()
    ) {
        self.authProvider = authProvider
        self.deletionClient = deletionClient
        self.contextStore = contextStore
        self.planner = planner
    }

    func deleteCurrentAccount(
        company: AccountDeletionCompanyRow,
        deckIds: [String]
    ) async throws -> DecksAccountDeletionReceipt {
        guard let context = try contextStore.loadAccountContext() else {
            throw OPSDecksAccountDeletionCoordinatorError.missingAccountContext
        }

        guard company.id == context.companyId else {
            throw OPSDecksAccountDeletionCoordinatorError.companyMismatch
        }

        let plan = planner.plan(
            company: company,
            userId: context.userId,
            deckIds: deckIds
        )
        if let blockedReason = plan.blockedReason {
            throw OPSDecksAccountDeletionCoordinatorError.blocked(blockedReason)
        }

        let receipt = try await deletionClient.deleteAccount(
            DecksAccountDeletionRequest(
                firebaseUID: context.firebaseUID,
                companyId: context.companyId
            )
        )
        try contextStore.clearAccountContext()
        try await authProvider.signOut()
        return receipt
    }
}
