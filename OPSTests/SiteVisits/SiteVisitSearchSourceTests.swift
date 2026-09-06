import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitSearchSourceTests: XCTestCase {
    func test_localClientsAreAvailableBeforeAnyRemoteResponse() async throws {
        let schema = Schema([Client.self, SubClient.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        context.insert(Client(id: "local", name: "Synthetic local", companyId: "company"))
        context.insert(Client(id: "foreign", name: "Synthetic foreign", companyId: "other-company"))
        try context.save()
        let gate = SearchGate()
        defer { gate.cancelAll() }
        let source = SiteVisitSearchSource(search: { _, query in try await gate.search(query) })
        source.loadLocalClients(context: context, companyId: "company")
        XCTAssertEqual(source.clients.map(\.id), ["local"])
        let pending = Task { await source.refresh(query: "local", companyId: "company", userId: "actor") }
        await gate.waitForRequest("local")
        XCTAssertEqual(source.clients.map(\.id), ["local"])
        gate.finish("local", rows: [])
        await pending.value
    }

    func test_lateSearchCannotOverwriteNewestQueryOrCrossAccountResults() async throws {
        let gate = SearchGate()
        defer { gate.cancelAll() }
        let source = SiteVisitSearchSource(search: { _, query in try await gate.search(query) })
        let old = Task { await source.refresh(query: "old", companyId: "company", userId: "actor") }
        await gate.waitForRequest("old")
        let new = Task { await source.refresh(query: "new", companyId: "company", userId: "other-actor") }
        await gate.waitForRequest("new")
        gate.finish("new", rows: [try dto(id: "new-result", company: "company")])
        await new.value
        gate.finish("old", rows: [try dto(id: "old-result", company: "company")])
        await old.value
        XCTAssertEqual(source.leads.map(\.id), ["new-result"])
    }

    private func dto(id: String, company: String) throws -> OpportunityDTO {
        let row: [String: Any] = ["id": id, "company_id": company, "contact_name": "Synthetic customer",
            "stage": "new_lead", "stage_entered_at": "2026-09-06T12:00:00Z", "assignment_version": 0,
            "created_at": "2026-09-06T12:00:00Z", "updated_at": "2026-09-06T12:00:00Z"]
        return try JSONDecoder().decode(OpportunityDTO.self, from: JSONSerialization.data(withJSONObject: row))
    }

    @MainActor
    private final class SearchGate {
        private var requests: [String: CheckedContinuation<[OpportunityDTO], Error>] = [:]
        private var registrations: [String: XCTestExpectation] = [:]
        private var cancelledQueries = Set<String>()
        func search(_ query: String) async throws -> [OpportunityDTO] {
            try Task.checkCancellation()
            guard !cancelledQueries.contains(query) else { throw CancellationError() }
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    requests[query] = continuation
                    registrations.removeValue(forKey: query)?.fulfill()
                }
            } onCancel: {
                Task { @MainActor in self.cancel(query) }
            }
        }
        func waitForRequest(_ query: String) async {
            if requests[query] != nil { return }
            let registered = XCTestExpectation(description: "Search registered: \(query)")
            registrations[query] = registered
            let result = await XCTWaiter.fulfillment(of: [registered], timeout: 5)
            if result != .completed { cancel(query) }
            XCTAssertEqual(result, .completed, "The request must be registered before delivering its response")
        }
        func finish(_ query: String, rows: [OpportunityDTO]) {
            requests.removeValue(forKey: query)?.resume(returning: rows)
        }
        private func cancel(_ query: String) {
            cancelledQueries.insert(query)
            requests.removeValue(forKey: query)?.resume(throwing: CancellationError())
            registrations.removeValue(forKey: query)?.fulfill()
        }
        func cancelAll() {
            for query in Set(requests.keys).union(registrations.keys) { cancel(query) }
        }
    }
}
