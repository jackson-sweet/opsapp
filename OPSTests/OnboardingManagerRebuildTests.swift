//
//  OnboardingManagerRebuildTests.swift
//  OPSTests
//
//  Task 2.4 — coverage for the hardened OnboardingManager: createCompanyViaRPC
//  (NO_USER_ROW → sync-user → retry; typed-error mapping) and the offline
//  completion queue (markOnboardingCompleteOrQueue + shouldShowOnboarding gating).
//
//  The RPC boundary is exercised through the injectable `createCompanyRPC` seam and
//  the sync-user / ACK boundary through an OnboardingServiceProtocol stub, so no
//  network or live Supabase client is touched.
//

import XCTest
import Supabase
@testable import OPS

@MainActor
final class OnboardingManagerRebuildTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearOnboardingDefaults()
        UserDefaults.standard.removeObject(forKey: OnboardingStorageKeys.completionPending)
    }

    override func tearDown() {
        clearOnboardingDefaults()
        UserDefaults.standard.removeObject(forKey: OnboardingStorageKeys.completionPending)
        super.tearDown()
    }

    // MARK: - Counting sync-user stub

    /// OnboardingService stub that counts sync-user invocations and lets a test
    /// force the completion ACK to succeed or fail.
    private final class CountingOnboardingService: OnboardingServiceProtocol {
        private(set) var syncUserCallCount = 0
        var completionError: Error?

        func syncUser(email: String, firstName: String?, lastName: String?, photoURL: String?) async throws -> SyncUserResponse {
            syncUserCallCount += 1
            return SyncUserResponse(
                user: .init(
                    id: "supabase-user-id",
                    firstName: firstName ?? "",
                    lastName: lastName ?? "",
                    email: email,
                    companyId: nil,
                    userType: nil,
                    role: nil,
                    isActive: true
                ),
                company: nil
            )
        }

        func markOnboardingComplete(userId: String) async throws {
            if let completionError { throw completionError }
        }
    }

    private func makeManager(
        service: OnboardingServiceProtocol,
        rpc: @escaping OnboardingManager.CreateCompanyRPCInvoking
    ) -> OnboardingManager {
        let manager = OnboardingManager(
            dataController: DataController(),
            onboardingService: service,
            createCompanyRPC: rpc
        )
        manager.state.userData.userId = "supabase-user-id"
        manager.state.userData.email = "owner@example.com"
        manager.state.userData.firstName = "Jack"
        manager.state.userData.lastName = "Ops"
        manager.state.companyData.name = "Acme Field Services"
        return manager
    }

    private func postgrestError(_ token: String) -> PostgrestError {
        PostgrestError(code: "P0001", message: token)
    }

    private func successResult() -> OnboardingManager.CreateCompanyRPCResult {
        OnboardingManager.CreateCompanyRPCResult(
            companyId: "company-uuid-123",
            companyCode: "ABCD2345",
            alreadyExisted: false
        )
    }

    // MARK: - createCompanyViaRPC: NO_USER_ROW → sync-user → retry → success

    func testCreateCompanyViaRPCRetriesAfterSyncUserOnNoUserRow() async throws {
        let service = CountingOnboardingService()
        var rpcCallCount = 0

        let manager = makeManager(service: service) { _, _, _, _, _ in
            rpcCallCount += 1
            if rpcCallCount == 1 {
                throw self.postgrestError("NO_USER_ROW")
            }
            return self.successResult()
        }

        let code = try await manager.createCompanyViaRPC()

        XCTAssertEqual(code, "ABCD2345")
        XCTAssertEqual(rpcCallCount, 2, "RPC should be retried exactly once after sync-user")
        XCTAssertEqual(service.syncUserCallCount, 1, "sync-user should be re-run exactly once on NO_USER_ROW")
        // DB-truth code/id persisted to state for the CrewCode screen.
        XCTAssertEqual(manager.state.companyData.companyId, "company-uuid-123")
        XCTAssertEqual(manager.state.companyData.companyCode, "ABCD2345")
        XCTAssertEqual(manager.state.profileCompanyPhase, .success)
        XCTAssertTrue(manager.state.hasExistingCompany)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "company_id"), "company-uuid-123")
    }

    func testCreateCompanyViaRPCSurfacesUserRowMissingWhenRetryStillFails() async {
        let service = CountingOnboardingService()
        var rpcCallCount = 0

        let manager = makeManager(service: service) { _, _, _, _, _ in
            rpcCallCount += 1
            throw self.postgrestError("NO_USER_ROW")
        }

        do {
            _ = try await manager.createCompanyViaRPC()
            XCTFail("Expected userRowMissing after retry still fails")
        } catch let error as OnboardingManager.CreateCompanyError {
            guard case .userRowMissing = error else {
                return XCTFail("Expected .userRowMissing, got \(error)")
            }
            XCTAssertEqual(rpcCallCount, 2, "RPC tried once, then retried once")
            XCTAssertEqual(service.syncUserCallCount, 1)
            XCTAssertEqual(manager.state.profileCompanyPhase, .form, "phase reset on failure")
        } catch {
            XCTFail("Expected CreateCompanyError, got \(error)")
        }
    }

    // MARK: - createCompanyViaRPC: typed-error mapping (no retry path)

    func testCreateCompanyViaRPCMapsAlreadyInCompany() async {
        let service = CountingOnboardingService()
        let manager = makeManager(service: service) { _, _, _, _, _ in
            throw self.postgrestError("ALREADY_IN_COMPANY")
        }

        do {
            _ = try await manager.createCompanyViaRPC()
            XCTFail("Expected alreadyInCompany")
        } catch let error as OnboardingManager.CreateCompanyError {
            guard case .alreadyInCompany = error else {
                return XCTFail("Expected .alreadyInCompany, got \(error)")
            }
            XCTAssertEqual(service.syncUserCallCount, 0, "no sync-user re-run for non NO_USER_ROW tokens")
        } catch {
            XCTFail("Expected CreateCompanyError, got \(error)")
        }
    }

    func testCreateCompanyViaRPCMapsInvalidNameFromServer() async {
        // A non-empty local name that the server rejects (e.g. whitespace-only on
        // the server contract) must still map to .invalidName.
        let service = CountingOnboardingService()
        let manager = makeManager(service: service) { _, _, _, _, _ in
            throw self.postgrestError("INVALID_NAME")
        }

        do {
            _ = try await manager.createCompanyViaRPC()
            XCTFail("Expected invalidName")
        } catch let error as OnboardingManager.CreateCompanyError {
            guard case .invalidName = error else {
                return XCTFail("Expected .invalidName, got \(error)")
            }
        } catch {
            XCTFail("Expected CreateCompanyError, got \(error)")
        }
    }

    func testCreateCompanyViaRPCMapsUnknownTokenToGeneric() async {
        let service = CountingOnboardingService()
        let manager = makeManager(service: service) { _, _, _, _, _ in
            throw self.postgrestError("CODE_GENERATION_EXHAUSTED")
        }

        do {
            _ = try await manager.createCompanyViaRPC()
            XCTFail("Expected generic")
        } catch let error as OnboardingManager.CreateCompanyError {
            guard case .generic(let message) = error else {
                return XCTFail("Expected .generic, got \(error)")
            }
            XCTAssertTrue(message.contains("CODE_GENERATION_EXHAUSTED"))
        } catch {
            XCTFail("Expected CreateCompanyError, got \(error)")
        }
    }

    func testCreateCompanyViaRPCRejectsEmptyNameBeforeRPC() async {
        let service = CountingOnboardingService()
        var rpcCallCount = 0
        let manager = makeManager(service: service) { _, _, _, _, _ in
            rpcCallCount += 1
            return self.successResult()
        }
        manager.state.companyData.name = "   " // whitespace only

        do {
            _ = try await manager.createCompanyViaRPC()
            XCTFail("Expected invalidName for blank company name")
        } catch let error as OnboardingManager.CreateCompanyError {
            guard case .invalidName = error else {
                return XCTFail("Expected .invalidName, got \(error)")
            }
            XCTAssertEqual(rpcCallCount, 0, "blank name short-circuits before the RPC")
        } catch {
            XCTFail("Expected CreateCompanyError, got \(error)")
        }
    }

    // MARK: - markOnboardingCompleteOrQueue

    func testMarkOnboardingCompleteOrQueueReturnsAcknowledgedOnSuccess() async {
        let service = CountingOnboardingService() // completionError == nil → success
        let manager = OnboardingManager(dataController: DataController(), onboardingService: service)
        manager.state.userData.userId = "supabase-user-id"
        manager.state.companyData.companyId = "company-id"

        let outcome = await manager.markOnboardingCompleteOrQueue(callCompletion: false)

        XCTAssertEqual(outcome, .acknowledged)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: OnboardingStorageKeys.completionPending))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "onboarding_completed"))
    }

    func testMarkOnboardingCompleteOrQueueQueuesOnAckFailure() async {
        let service = CountingOnboardingService()
        service.completionError = OnboardingServiceError.serverError("ack down")
        let manager = OnboardingManager(dataController: DataController(), onboardingService: service)
        manager.state.userData.userId = "supabase-user-id"
        manager.state.companyData.companyId = "company-id"

        let outcome = await manager.markOnboardingCompleteOrQueue(callCompletion: false)

        XCTAssertEqual(outcome, .queued)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: OnboardingStorageKeys.completionPending),
                      "completion pending flag set so the sweep retries the ACK")
        // User is still admitted locally so the CompletionGate lets them in.
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "onboarding_completed"))
        XCTAssertNil(manager.state.resumeBoundary)
    }

    // MARK: - shouldShowOnboarding treats queued completion as complete

    func testShouldShowOnboardingSkipsWhenCompletionQueued() {
        UserDefaults.standard.set(true, forKey: OnboardingStorageKeys.completionPending)

        let dataController = DataController()
        let user = User(
            id: "queued-user-id",
            firstName: "Jack",
            lastName: "Ops",
            role: .owner,
            companyId: "company-id"
        )
        user.userType = .company
        // Crucially, the server ACK never landed, so this stays false — the queue
        // flag alone must be enough to skip re-onboarding.
        user.hasCompletedAppOnboarding = false
        dataController.currentUser = user
        dataController.isAuthenticated = true

        let (shouldShow, manager) = OnboardingManager.shouldShowOnboarding(dataController: dataController)

        XCTAssertFalse(shouldShow, "queued completion must not re-onboard the user")
        XCTAssertNil(manager)
    }

    func testShouldShowOnboardingStillShowsWhenPendingButNoCompany() {
        // Pending flag without an identity (no company) must NOT skip — a half-set
        // flag can't strand a user with no company in the app.
        UserDefaults.standard.set(true, forKey: OnboardingStorageKeys.completionPending)

        let dataController = DataController()
        let user = User(
            id: "pending-no-company",
            firstName: "Jack",
            lastName: "Ops",
            role: .unassigned,
            companyId: ""
        )
        user.userType = .company
        user.hasCompletedAppOnboarding = false
        dataController.currentUser = user
        dataController.isAuthenticated = true

        let (shouldShow, _) = OnboardingManager.shouldShowOnboarding(dataController: dataController)

        XCTAssertTrue(shouldShow, "pending flag without a company must not skip onboarding")
    }
}
