import XCTest
@testable import OPSDecks

final class OPSDecksAccountCoordinatorTests: XCTestCase {
    func testSignInWithAppleProvisionsDeckCompanyAndStoresContext() async throws {
        let authProvider = RecordingDecksAuthProvider(
            signInResponse: OPSDecksAuthenticatedIdentity(
                firebaseUID: "firebase-123",
                email: "deck@example.com",
                displayName: "Deck Operator"
            )
        )
        let provisioningClient = RecordingDecksCompanyProvisioningClient(
            response: DecksCompanyProvisioningResponse(
                companyId: "company-123",
                userId: "user-123",
                role: "admin",
                subscriptionPlan: "decks"
            )
        )
        let contextStore = RecordingAccountContextStore()
        let coordinator = OPSDecksAccountCoordinator(
            authProvider: authProvider,
            provisioningClient: provisioningClient,
            contextStore: contextStore
        )

        let context = try await coordinator.signInWithApple()

        let expectedContext = OPSDecksAccountContext(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: "Deck Operator",
            companyId: "company-123",
            userId: "user-123",
            role: "admin",
            subscriptionPlan: "decks"
        )
        XCTAssertEqual(authProvider.signInCallCount, 1)
        XCTAssertEqual(
            provisioningClient.requests,
            [
                DecksCompanyProvisioningRequest(
                    firebaseUID: "firebase-123",
                    email: "deck@example.com",
                    displayName: "Deck Operator"
                )
            ]
        )
        XCTAssertEqual(context, expectedContext)
        XCTAssertEqual(contextStore.savedContexts, [expectedContext])
        XCTAssertEqual(try contextStore.loadAccountContext(), expectedContext)
    }

    func testLoadStoredAccountContextDoesNotStartSignInOrProvisioning() throws {
        let existingContext = OPSDecksAccountContext(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: nil,
            companyId: "company-123",
            userId: "user-123",
            role: "admin",
            subscriptionPlan: "decks"
        )
        let authProvider = RecordingDecksAuthProvider()
        let provisioningClient = RecordingDecksCompanyProvisioningClient()
        let contextStore = RecordingAccountContextStore(storedContext: existingContext)
        let coordinator = OPSDecksAccountCoordinator(
            authProvider: authProvider,
            provisioningClient: provisioningClient,
            contextStore: contextStore
        )

        XCTAssertEqual(try coordinator.loadStoredAccountContext(), existingContext)
        XCTAssertEqual(authProvider.signInCallCount, 0)
        XCTAssertEqual(provisioningClient.requests, [])
    }

    func testSignOutClearsStoredContextAndProviderSession() async throws {
        let existingContext = OPSDecksAccountContext(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: nil,
            companyId: "company-123",
            userId: "user-123",
            role: "admin",
            subscriptionPlan: "decks"
        )
        let authProvider = RecordingDecksAuthProvider()
        let provisioningClient = RecordingDecksCompanyProvisioningClient()
        let contextStore = RecordingAccountContextStore(storedContext: existingContext)
        let coordinator = OPSDecksAccountCoordinator(
            authProvider: authProvider,
            provisioningClient: provisioningClient,
            contextStore: contextStore
        )

        try await coordinator.signOut()

        XCTAssertNil(try contextStore.loadAccountContext())
        XCTAssertEqual(contextStore.clearCallCount, 1)
        XCTAssertEqual(authProvider.signOutCallCount, 1)
        XCTAssertEqual(authProvider.signInCallCount, 0)
    }
}

private final class RecordingDecksAuthProvider: OPSDecksAuthProvider {
    private let signInResponse: OPSDecksAuthenticatedIdentity
    private(set) var signInCallCount = 0
    private(set) var signOutCallCount = 0

    init(
        signInResponse: OPSDecksAuthenticatedIdentity = OPSDecksAuthenticatedIdentity(
            firebaseUID: "firebase-default",
            email: "deck@example.com",
            displayName: nil
        )
    ) {
        self.signInResponse = signInResponse
    }

    func signInWithApple() async throws -> OPSDecksAuthenticatedIdentity {
        signInCallCount += 1
        return signInResponse
    }

    func signOut() async throws {
        signOutCallCount += 1
    }
}

private final class RecordingDecksCompanyProvisioningClient: DecksCompanyProvisioningClient {
    private let response: DecksCompanyProvisioningResponse
    private(set) var requests: [DecksCompanyProvisioningRequest] = []

    init(
        response: DecksCompanyProvisioningResponse = DecksCompanyProvisioningResponse(
            companyId: "company-default",
            userId: "user-default",
            role: "admin",
            subscriptionPlan: "decks"
        )
    ) {
        self.response = response
    }

    func provisionCompany(
        _ request: DecksCompanyProvisioningRequest
    ) async throws -> DecksCompanyProvisioningResponse {
        requests.append(request)
        return response
    }
}

private final class RecordingAccountContextStore: OPSDecksAccountContextStore {
    private var storedContext: OPSDecksAccountContext?
    private(set) var savedContexts: [OPSDecksAccountContext] = []
    private(set) var clearCallCount = 0

    init(storedContext: OPSDecksAccountContext? = nil) {
        self.storedContext = storedContext
    }

    func loadAccountContext() throws -> OPSDecksAccountContext? {
        storedContext
    }

    func saveAccountContext(_ context: OPSDecksAccountContext) throws {
        savedContexts.append(context)
        storedContext = context
    }

    func clearAccountContext() throws {
        clearCallCount += 1
        storedContext = nil
    }
}
