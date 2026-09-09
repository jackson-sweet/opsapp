import CoreSpotlight
import SwiftData
import XCTest
@testable import OPS

@MainActor
final class SpotlightSessionLifetimeTests: XCTestCase {
    func testRetiredAvatarContinuationCannotReadWipedClientOrSubmitIndexItem() async throws {
        let oldCompany = UserDefaults.standard.object(forKey: "currentUserCompanyId")
        UserDefaults.standard.set("spotlight-lifetime-company", forKey: "currentUserCompanyId")
        defer { restoreCompany(oldCompany) }
        let container = try makeContainer()
        let client = makeClient(in: container.mainContext)
        try container.mainContext.save()
        let avatarStarted = expectation(description: "fake avatar suspended")
        let gate = SpotlightLifetimeGate()
        var submitted: [String] = []
        let manager = SpotlightIndexManager.makeForTesting(
            avatar: { _ in avatarStarted.fulfill(); await gate.wait() },
            submit: { items in submitted.append(contentsOf: items.map(\.uniqueIdentifier)) }
        )
        let tracker = SpotlightSyncTracker(manager: manager)
        let lifetime = OutboundSessionLifetime()
        tracker.markDirty(domain: SpotlightDomain.client, id: client.id)
        let dispatch = Task {
            await tracker.dispatch(context: container.mainContext,
                isCurrent: { lifetime.snapshot() != nil })
        }
        await fulfillment(of: [avatarStarted], timeout: 3)
        lifetime.invalidate()
        container.mainContext.delete(client)
        try container.mainContext.save()
        await gate.release()
        await dispatch.value
        XCTAssertTrue(submitted.isEmpty, "Old avatar completion must not repopulate the cleared index")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Client>()), 0)
    }

    func testMarksAddedDuringSuspendedDispatchBelongToNextBatch() async throws {
        let oldCompany = UserDefaults.standard.object(forKey: "currentUserCompanyId")
        UserDefaults.standard.set("spotlight-lifetime-company", forKey: "currentUserCompanyId")
        defer { restoreCompany(oldCompany) }
        let container = try makeContainer()
        let client = makeClient(in: container.mainContext)
        try container.mainContext.save()
        let avatarStarted = expectation(description: "first batch avatar suspended")
        let gate = SpotlightLifetimeGate()
        var submittedCount = 0
        let manager = SpotlightIndexManager.makeForTesting(
            avatar: { _ in avatarStarted.fulfill(); await gate.wait() },
            submit: { items in submittedCount += items.count }
        )
        let tracker = SpotlightSyncTracker(manager: manager)
        tracker.markDirty(domain: SpotlightDomain.client, id: client.id)
        let dispatch = Task { await tracker.dispatch(context: container.mainContext) }
        await fulfillment(of: [avatarStarted], timeout: 3)
        tracker.markDirty(domain: SpotlightDomain.project, id: "next-batch-project")
        await gate.release()
        await dispatch.value
        XCTAssertEqual(submittedCount, 1, "The current batch still indexes its live client")
        XCTAssertFalse(tracker.isEmpty, "Its completion must not erase marks added during the await")
    }

    private func makeContainer() throws -> ModelContainer {
        // The head, not a version literal. These fixtures mean "the current
        // schema"; naming V26 silently pinned them to a graph whose frozen
        // models the live code no longer uses — inserting or fetching a live
        // @Model against a stale container traps inside SwiftData with an
        // uncatchable EXC_BREAKPOINT. See OPSSchemaCurrent.swift.
        let schema = Schema(OPSSchemaCurrent.models)
        return try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    private func makeClient(in context: ModelContext) -> Client {
        let client = Client(id: UUID().uuidString.lowercased(), name: "Spotlight fixture",
            companyId: "spotlight-lifetime-company")
        client.profileImageURL = "https://spotlight-fixture.invalid/\(UUID().uuidString).png"
        context.insert(client)
        return client
    }

    private func restoreCompany(_ value: Any?) {
        if let value { UserDefaults.standard.set(value, forKey: "currentUserCompanyId") }
        else { UserDefaults.standard.removeObject(forKey: "currentUserCompanyId") }
    }
}

private actor SpotlightLifetimeGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
