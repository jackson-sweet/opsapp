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

    func testDeleteAccountCallsBackendThenClearsStoredContextAndProviderSession() async throws {
        let existingContext = OPSDecksAccountContext(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: nil,
            companyId: "company-123",
            userId: "user-123",
            role: "admin",
            subscriptionPlan: "decks"
        )
        let receipt = DecksAccountDeletionReceipt(
            receiptId: "receipt-123",
            deletedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        let authProvider = RecordingDecksAuthProvider()
        let deletionClient = RecordingDecksAccountDeletionClient(receipt: receipt)
        let contextStore = RecordingAccountContextStore(storedContext: existingContext)
        let coordinator = OPSDecksAccountDeletionCoordinator(
            authProvider: authProvider,
            deletionClient: deletionClient,
            contextStore: contextStore
        )

        let returnedReceipt = try await coordinator.deleteCurrentAccount(
            company: AccountDeletionCompanyRow(
                id: "company-123",
                adminIds: ["user-123"],
                subscriptionPlan: "decks",
                memberCount: 1
            ),
            deckIds: ["deck-1", "deck-2"]
        )

        XCTAssertEqual(returnedReceipt, receipt)
        XCTAssertEqual(
            deletionClient.requests,
            [
                DecksAccountDeletionRequest(
                    firebaseUID: "firebase-123",
                    companyId: "company-123"
                )
            ]
        )
        XCTAssertNil(try contextStore.loadAccountContext())
        XCTAssertEqual(contextStore.clearCallCount, 1)
        XCTAssertEqual(authProvider.signOutCallCount, 1)
        XCTAssertEqual(authProvider.signInCallCount, 0)
    }

    func testDeleteAccountBlocksUpgradedCompanyWithoutSideEffects() async throws {
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
        let deletionClient = RecordingDecksAccountDeletionClient()
        let contextStore = RecordingAccountContextStore(storedContext: existingContext)
        let coordinator = OPSDecksAccountDeletionCoordinator(
            authProvider: authProvider,
            deletionClient: deletionClient,
            contextStore: contextStore
        )

        do {
            _ = try await coordinator.deleteCurrentAccount(
                company: AccountDeletionCompanyRow(
                    id: "company-123",
                    adminIds: ["user-123"],
                    subscriptionPlan: "pro",
                    memberCount: 1
                ),
                deckIds: ["deck-1"]
            )
            XCTFail("Expected upgraded OPS company deletion to be blocked.")
        } catch let error as OPSDecksAccountDeletionCoordinatorError {
            XCTAssertEqual(error, .blocked(.upgradedOPSCompany))
        }

        XCTAssertEqual(deletionClient.requests, [])
        XCTAssertEqual(try contextStore.loadAccountContext(), existingContext)
        XCTAssertEqual(contextStore.clearCallCount, 0)
        XCTAssertEqual(authProvider.signOutCallCount, 0)
    }

    func testDeleteAccountBlocksCompanySnapshotMismatchWithoutSideEffects() async throws {
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
        let deletionClient = RecordingDecksAccountDeletionClient()
        let contextStore = RecordingAccountContextStore(storedContext: existingContext)
        let coordinator = OPSDecksAccountDeletionCoordinator(
            authProvider: authProvider,
            deletionClient: deletionClient,
            contextStore: contextStore
        )

        do {
            _ = try await coordinator.deleteCurrentAccount(
                company: AccountDeletionCompanyRow(
                    id: "company-other",
                    adminIds: ["user-123"],
                    subscriptionPlan: "decks",
                    memberCount: 1
                ),
                deckIds: ["deck-1"]
            )
            XCTFail("Expected mismatched company snapshot deletion to be blocked.")
        } catch let error as OPSDecksAccountDeletionCoordinatorError {
            XCTAssertEqual(error, .companyMismatch)
        }

        XCTAssertEqual(deletionClient.requests, [])
        XCTAssertEqual(try contextStore.loadAccountContext(), existingContext)
        XCTAssertEqual(contextStore.clearCallCount, 0)
        XCTAssertEqual(authProvider.signOutCallCount, 0)
    }

    func testDeleteAccountRequiresStoredAccountContext() async throws {
        let authProvider = RecordingDecksAuthProvider()
        let deletionClient = RecordingDecksAccountDeletionClient()
        let contextStore = RecordingAccountContextStore()
        let coordinator = OPSDecksAccountDeletionCoordinator(
            authProvider: authProvider,
            deletionClient: deletionClient,
            contextStore: contextStore
        )

        do {
            _ = try await coordinator.deleteCurrentAccount(
                company: AccountDeletionCompanyRow(
                    id: "company-123",
                    adminIds: ["user-123"],
                    subscriptionPlan: "decks",
                    memberCount: 1
                ),
                deckIds: ["deck-1"]
            )
            XCTFail("Expected deletion to require a stored account context.")
        } catch let error as OPSDecksAccountDeletionCoordinatorError {
            XCTAssertEqual(error, .missingAccountContext)
        }

        XCTAssertEqual(deletionClient.requests, [])
        XCTAssertEqual(contextStore.clearCallCount, 0)
        XCTAssertEqual(authProvider.signOutCallCount, 0)
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

private final class RecordingDecksAccountDeletionClient: DecksAccountDeletionClient {
    private let receipt: DecksAccountDeletionReceipt
    private(set) var requests: [DecksAccountDeletionRequest] = []

    init(
        receipt: DecksAccountDeletionReceipt = DecksAccountDeletionReceipt(
            receiptId: "receipt-default",
            deletedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    ) {
        self.receipt = receipt
    }

    func deleteAccount(
        _ request: DecksAccountDeletionRequest
    ) async throws -> DecksAccountDeletionReceipt {
        requests.append(request)
        return receipt
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
