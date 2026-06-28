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
