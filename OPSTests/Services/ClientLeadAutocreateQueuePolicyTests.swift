//
//  ClientLeadAutocreateQueuePolicyTests.swift
//  OPSTests
//
//  SYNC RECOVERY (spec §3) — the retry-policy state machine for the durable
//  client → lead delivery queue. Proves the additive Codable shape, the
//  park/backoff drain policy, the recovery-screen API, and the site-visit
//  draft/visit binding on delivery.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class ClientLeadAutocreateQueuePolicyTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ClientLeadAutocreateQueuePolicyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Codable (additive)

    /// The shipped v1 shape (no retry-state keys) MUST still decode — both as a
    /// bare object and through the queue's real reload path — with every new
    /// field nil. This is the guard against a schema change silently dropping a
    /// user's queued work on the update that introduces the retry policy.
    func testV1ShapeJSONDecodesWithNilRetryState() throws {
        let v1JSON = """
        {
          "clientId": "client-1",
          "companyId": "company-1",
          "name": "West Shore Decks",
          "email": "office@example.com",
          "phoneNumber": "250-555-0199",
          "address": "12 Bay St",
          "notes": "Contact import",
          "createdAt": 742305600
        }
        """

        let decoded = try JSONDecoder().decode(
            PendingClientLeadAutocreate.self,
            from: Data(v1JSON.utf8)
        )
        XCTAssertEqual(decoded.clientId, "client-1")
        XCTAssertEqual(decoded.companyId, "company-1")
        XCTAssertNil(decoded.attempts)
        XCTAssertNil(decoded.lastAttemptAt)
        XCTAssertNil(decoded.lastError)
        XCTAssertNil(decoded.parkedAt)
        XCTAssertEqual(decoded.effectiveAttempts, 0)
        XCTAssertFalse(decoded.isParked)

        // The real reload path decodes an ARRAY out of UserDefaults.
        let v1ArrayJSON = "[\(v1JSON)]"
        defaults.set(Data(v1ArrayJSON.utf8), forKey: "pending")
        let queue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in throw TestError.transient }
        )
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertTrue(queue.parkedRequests.isEmpty)
        XCTAssertEqual(queue.activeRequests.count, 1)
    }

    /// The new retry state must survive a JSON round-trip — the proof that the
    /// synthesized Codable keeps the `var` fields in its `CodingKeys` (a defaulted
    /// `let` would be silently dropped and never persist).
    func testRetryStateRoundTripsThroughJSON() throws {
        var request = PendingClientLeadAutocreate(client: makeClient(id: "client-9"), companyId: "company-1")
        request.attempts = 3
        request.lastAttemptAt = Date(timeIntervalSince1970: 1_000_000)
        request.lastError = "boom"
        request.parkedAt = Date(timeIntervalSince1970: 2_000_000)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(PendingClientLeadAutocreate.self, from: data)

        XCTAssertEqual(decoded.attempts, 3)
        XCTAssertEqual(decoded.effectiveAttempts, 3)
        XCTAssertEqual(decoded.lastError, "boom")
        XCTAssertEqual(decoded.lastAttemptAt, Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(decoded.parkedAt, Date(timeIntervalSince1970: 2_000_000))
        XCTAssertTrue(decoded.isParked)
    }

    // MARK: - Backoff formula

    /// Exact schedule: 60s base doubling per attempt, capped at 900s (15 min).
    func testBackoffIntervalSchedule() {
        XCTAssertEqual(ClientLeadAutocreateQueue.backoffInterval(attempts: 0), 60)
        XCTAssertEqual(ClientLeadAutocreateQueue.backoffInterval(attempts: 1), 120)
        XCTAssertEqual(ClientLeadAutocreateQueue.backoffInterval(attempts: 2), 240)
        XCTAssertEqual(ClientLeadAutocreateQueue.backoffInterval(attempts: 3), 480)
        XCTAssertEqual(ClientLeadAutocreateQueue.backoffInterval(attempts: 4), 900)
        XCTAssertEqual(ClientLeadAutocreateQueue.backoffInterval(attempts: 5), 900)
        XCTAssertEqual(ClientLeadAutocreateQueue.backoffInterval(attempts: 12), 900)
    }

    // MARK: - Drain policy

    /// A permanent rejection parks immediately and is never auto-retried — a
    /// second drain must not touch it. This is the fix for the outage's
    /// infinite-400 loop.
    func testPermanentErrorParksAndIsSkippedByLaterDrains() async {
        var attemptCount = 0
        let queue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in
                attemptCount += 1
                throw TestError.permanent
            }
        )
        queue.enqueue(makeClient(id: "client-1"), companyId: "company-1")

        await queue.drain()

        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(queue.parkedRequests.count, 1)
        XCTAssertTrue(queue.activeRequests.isEmpty)
        XCTAssertNotNil(queue.parkedRequests.first?.parkedAt)
        XCTAssertNotNil(queue.parkedRequests.first?.lastError)

        // Parked → excluded from every subsequent automatic drain.
        await queue.drain()
        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(queue.parkedRequests.count, 1)
    }

    /// A transient failure increments attempts, stamps the backoff clock, and the
    /// request stays out of the drain until its exponential window elapses.
    func testTransientErrorIncrementsAttemptsAndRespectsBackoffWindow() async {
        var attemptCount = 0
        let origin = Date(timeIntervalSince1970: 1_000_000)
        var currentNow = origin
        let queue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in
                attemptCount += 1
                throw URLError(.notConnectedToInternet)   // classifier → .transient
            }
        )
        queue.now = { currentNow }
        queue.enqueue(makeClient(id: "client-1"), companyId: "company-1")

        // First drain — never attempted before → eligible; fails transiently.
        await queue.drain()
        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(queue.activeRequests.first?.attempts, 1)
        XCTAssertTrue(queue.parkedRequests.isEmpty)

        // +60s is still inside the 120s window for attempts == 1 → skipped.
        currentNow = origin.addingTimeInterval(60)
        await queue.drain()
        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(queue.activeRequests.first?.attempts, 1)

        // +120s → window elapsed → re-attempts; attempts advances to 2.
        currentNow = origin.addingTimeInterval(120)
        await queue.drain()
        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(queue.activeRequests.first?.attempts, 2)
    }

    // MARK: - Recovery-screen API

    /// User Retry clears the park + retry state and re-delivers on the next drain.
    func testRetryParkedClearsStateAndRedelivers() async {
        var attemptCount = 0
        var shouldFail = true
        let queue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in
                attemptCount += 1
                if shouldFail { throw TestError.permanent }
                return ClientLeadAutocreateDelivery(
                    opportunityId: "opp-1",
                    opportunityDTO: nil,
                    createdNow: true
                )
            }
        )
        queue.enqueue(makeClient(id: "client-1"), companyId: "company-1")

        await queue.drain()
        XCTAssertEqual(queue.parkedRequests.count, 1)

        shouldFail = false
        queue.retryParked(clientId: "CLIENT-1")   // case-insensitive match

        // Clearing is synchronous — the park is gone the instant retry is tapped.
        XCTAssertTrue(queue.parkedRequests.isEmpty)
        XCTAssertEqual(queue.activeRequests.count, 1)
        XCTAssertNil(queue.activeRequests.first?.parkedAt)
        XCTAssertNil(queue.activeRequests.first?.attempts)
        XCTAssertNil(queue.activeRequests.first?.lastError)

        await queue.drain()
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(attemptCount, 2)
    }

    /// RETRY ALL unparks every parked request and re-delivers them.
    func testUnparkAllClearsAllParkedAndRedelivers() async {
        var shouldFail = true
        let queue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in
                if shouldFail { throw TestError.permanent }
                return ClientLeadAutocreateDelivery(
                    opportunityId: "opp",
                    opportunityDTO: nil,
                    createdNow: false
                )
            }
        )
        queue.enqueue(makeClient(id: "client-a"), companyId: "company-1")
        queue.enqueue(makeClient(id: "client-b"), companyId: "company-1")

        await queue.drain()
        XCTAssertEqual(queue.parkedRequests.count, 2)

        shouldFail = false
        queue.unparkAll()
        XCTAssertTrue(queue.parkedRequests.isEmpty)

        await queue.drain()
        XCTAssertEqual(queue.pendingCount, 0)
    }

    /// Discard drops a request entirely and the removal survives a reload.
    func testRemoveRequestDiscardsAndPersists() {
        let queue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in throw TestError.permanent }
        )
        queue.enqueue(makeClient(id: "client-1"), companyId: "company-1")
        XCTAssertEqual(queue.pendingCount, 1)

        queue.removeRequest(clientId: "CLIENT-1")   // case-insensitive
        XCTAssertEqual(queue.pendingCount, 0)

        let reloaded = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in throw TestError.permanent }
        )
        XCTAssertEqual(reloaded.pendingCount, 0)
    }

    // MARK: - Site-visit binding on delivery

    /// A successful delivery binds every unbound site-visit identity draft (and
    /// its visit) for that client to the delivered lead, and signals open capture
    /// UI per bound visit. Closes RC4 (the one-shot site-visit lead create).
    func testDeliveryBindsSiteVisitDraftAndVisit() async throws {
        let container = try makeBindingContainer()
        let context = ModelContext(container)

        let visit = SiteVisit(id: "visit-1", companyId: "company-1")
        context.insert(visit)
        let draft = SiteVisitIdentityDraft(
            siteVisitId: "visit-1",
            companyId: "company-1",
            clientId: "CLIENT-1"   // uppercase → exercises case-insensitive match
        )
        context.insert(draft)
        try context.save()

        let bound = expectation(description: "SiteVisitLeadBound posted for visit-1")
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("SiteVisitLeadBound"),
            object: nil,
            queue: nil
        ) { note in
            if note.userInfo?["siteVisitId"] as? String == "visit-1" { bound.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let queue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in
                ClientLeadAutocreateDelivery(
                    opportunityId: "opp-77",
                    opportunityDTO: nil,
                    createdNow: true
                )
            }
        )
        queue.configure(modelContext: context, activeCompanyId: { "company-1" })
        queue.enqueue(makeClient(id: "client-1"), companyId: "company-1")

        await queue.drain()

        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(draft.opportunityId, "opp-77")
        XCTAssertNotNil(draft.lastCommittedAt)
        XCTAssertEqual(visit.opportunityId, "opp-77")
        await fulfillment(of: [bound], timeout: 1)
    }

    // MARK: - Fixtures

    private enum TestError: LocalizedError {
        /// Classifies transient via URLError semantics (offline).
        case transient
        /// Classifies permanent — the message carries an unambiguous integrity
        /// phrase the shared classifier maps to `.permanent`.
        case permanent

        var errorDescription: String? {
            switch self {
            case .transient:
                return "The Internet connection appears to be offline."
            case .permanent:
                return "new row for relation \"opportunities\" violates check constraint \"opportunities_source_check\""
            }
        }
    }

    private func makeClient(id: String) -> Client {
        Client(
            id: id,
            name: "West Shore Decks",
            email: "office@example.com",
            phoneNumber: "250-555-0199",
            address: "12 Bay St",
            companyId: "company-1",
            notes: "Contact import"
        )
    }

    private func makeBindingContainer() throws -> ModelContainer {
        let schema = Schema([
            Opportunity.self,
            SiteVisit.self,
            SiteVisitIdentityDraft.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
