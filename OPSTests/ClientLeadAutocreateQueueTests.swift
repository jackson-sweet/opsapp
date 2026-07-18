//
//  ClientLeadAutocreateQueueTests.swift
//  OPSTests
//


import XCTest
@testable import OPS

@MainActor
final class ClientLeadAutocreateQueueTests: XCTestCase {
    private enum TestError: Error {
        case offline
    }

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ClientLeadAutocreateQueueTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFailedDeliveryRemainsQueuedAndDuplicateEnqueueCollapses() async {
        var attempts = 0
        let queue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in
                attempts += 1
                throw TestError.offline
            }
        )
        let client = makeClient(id: "CLIENT-1")

        queue.enqueue(client, companyId: "company-1")
        queue.enqueue(client, companyId: "company-1")

        XCTAssertEqual(queue.pendingCount, 1)

        await queue.drain()

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertTrue(queue.contains(clientId: "client-1"))
    }

    func testQueuedDeliverySurvivesQueueRecreation() {
        let firstQueue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in throw TestError.offline }
        )
        firstQueue.enqueue(makeClient(id: "client-2"), companyId: "company-1")

        let reloadedQueue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in throw TestError.offline }
        )

        XCTAssertEqual(reloadedQueue.pendingCount, 1)
        XCTAssertTrue(reloadedQueue.contains(clientId: "CLIENT-2"))
    }

    func testRecoveredDeliveryClearsQueuedClientAndPublishesRefresh() async {
        let refresh = expectation(description: "lead refresh published")
        let observer = NotificationCenter.default.addObserver(
            forName: .opsLeadsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            refresh.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let queue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in
                ClientLeadAutocreateDelivery(
                    opportunityId: "opportunity-1",
                    opportunityDTO: nil,
                    createdNow: false
                )
            }
        )
        queue.enqueue(makeClient(id: "client-3"), companyId: "company-1")

        await queue.drain()

        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertFalse(queue.contains(clientId: "client-3"))
        await fulfillment(of: [refresh], timeout: 1)
    }

    func testCompanyChangeDuringDeliveryKeepsReceiptForCorrectScope() async {
        var activeCompanyId = "company-1"
        var switchCompanyDuringAttempt = true
        let queue = ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            activeCompanyId: { activeCompanyId },
            attempt: { _ in
                if switchCompanyDuringAttempt {
                    activeCompanyId = "company-2"
                }
                return ClientLeadAutocreateDelivery(
                    opportunityId: "opportunity-1",
                    opportunityDTO: nil,
                    createdNow: true
                )
            }
        )
        queue.enqueue(makeClient(id: "client-4"), companyId: "company-1")

        await queue.drain()

        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertTrue(queue.contains(clientId: "client-4"))

        switchCompanyDuringAttempt = false
        activeCompanyId = "company-1"
        await queue.drain()

        XCTAssertEqual(queue.pendingCount, 0)
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
}
