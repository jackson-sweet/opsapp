import SwiftData
import XCTest
@testable import OPS

@MainActor
final class PhotoPrefetchLifetimeTests: XCTestCase {
    func testQueuedPrefetchRetainsContainerBeforeStartingAndAcrossSnapshotWait() async throws {
        var container: ModelContainer? = try makeContainer()
        weak var retainedContainer = container
        let context = try XCTUnwrap(container).mainContext
        let service = PhotoPrefetchService.isolatedForTesting()
        let entered = expectation(description: "prefetch snapshot held")
        let gate = SyncExecutionTestGate()
        let parent = SyncExecutionScope()
        let task = try SyncExecutionContext.$scope.withValue(parent) {
            try XCTUnwrap(service.startPrefetchForTesting(context: context, connectivity: ConnectivityManager()) {
                entered.fulfill()
                await gate.wait()
            })
        }
        defer { service.cancelPrefetch() }
        container = nil // Release before the queued worker even starts.
        parent.close() // Normal parent completion must not poison independent prefetch.
        XCTAssertNotNil(retainedContainer)
        XCTAssertTrue(service.isPrefetching, "Scheduling claims ownership synchronously")
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertNotNil(retainedContainer, "The profiler/snapshot suspension retains the store owner")
        await gate.release()
        await task.value
        XCTAssertNotNil(service.lastRunAt, "The actual SwiftData snapshot completed")
        XCTAssertFalse(service.isPrefetching)
    }

    func testCancelledOlderPrefetchCannotClearReplacementOwnership() async throws {
        let container = try makeContainer()
        let service = PhotoPrefetchService.isolatedForTesting()
        let firstEntered = expectation(description: "old snapshot held")
        let nextEntered = expectation(description: "replacement snapshot held")
        let firstGate = SyncExecutionTestGate()
        let nextGate = SyncExecutionTestGate()
        let first = try XCTUnwrap(service.startPrefetchForTesting(context: container.mainContext, connectivity: ConnectivityManager()) {
            firstEntered.fulfill()
            await firstGate.wait()
        })
        defer { service.cancelPrefetch() }
        await fulfillment(of: [firstEntered], timeout: 3)
        service.cancelPrefetch()
        XCTAssertFalse(service.isPrefetching)
        let next = try XCTUnwrap(service.startPrefetchForTesting(context: container.mainContext, connectivity: ConnectivityManager()) {
            nextEntered.fulfill()
            await nextGate.wait()
        })
        await fulfillment(of: [nextEntered], timeout: 3)
        await firstGate.release()
        await first.value
        XCTAssertTrue(service.isPrefetching, "Obsolete completion cannot clear the new task's slot")
        XCTAssertNil(service.lastRunAt, "Cancelled work must not announce completion")
        await nextGate.release()
        await next.value
        XCTAssertFalse(service.isPrefetching)
        XCTAssertNotNil(service.lastRunAt)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(OPSSchemaCurrent.models)
        return try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }
}
