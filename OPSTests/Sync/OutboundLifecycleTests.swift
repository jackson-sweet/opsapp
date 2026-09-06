import SwiftData
import XCTest
@testable import OPS

@MainActor
final class OutboundLifecycleTests: XCTestCase {
    func testContainerOwnerOutlivesAwaitedFailureAndKeepsRetryEvidence() async throws {
        var container: ModelContainer? = try makeContainer()
        weak var weakContainer = container
        let context = try XCTUnwrap(container).mainContext
        let operation = try makeOperation(in: context)
        let started = expectation(description: "request suspended")
        let gate = OutboundLifecycleGate()
        let processor = OutboundProcessor(repositoryPush: { _, _, _, _ in
            started.fulfill()
            await gate.wait()
            throw URLError(.notConnectedToInternet)
        })
        let work = Task { try await processor.executeOperation(operation, context: context) }
        await fulfillment(of: [started], timeout: 2)
        container = nil // Reproduce the preceding fixture releasing its owner.
        let retained = try XCTUnwrap(weakContainer, "The driver must own its container across the request")
        await gate.release()
        do { try await work.value; XCTFail("Expected the simulated network failure") }
        catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertEqual(operation.status, "pending")
        XCTAssertEqual(operation.retryCount, 1)
        XCTAssertNotNil(operation.lastError)
        withExtendedLifetime(retained) {}
    }

    func testInvalidationDuringAwaitDoesNotCompleteOrChargeRetry() async throws {
        for shouldFail in [false, true] {
            let container = try makeContainer()
            let operation = try makeOperation(in: container.mainContext)
            let originalPayload = operation.payload
            let started = expectation(description: "request suspended")
            let gate = OutboundLifecycleGate()
            let processor = OutboundProcessor(repositoryPush: { _, _, _, _ in
                started.fulfill()
                await gate.wait()
                if shouldFail { throw URLError(.notConnectedToInternet) }
            })
            let work = Task { try await processor.executeOperation(operation, context: container.mainContext) }
            await fulfillment(of: [started], timeout: 2)
            processor.invalidate() // SyncEngine does this synchronously before logout/reconfigure.
            await gate.release()
            do { try await work.value; XCTFail("Old session continuation must stop") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(operation.status, "inProgress", "Interrupted claim stays durable for recovery")
            XCTAssertEqual(operation.retryCount, 0)
            XCTAssertNil(operation.completedAt)
            XCTAssertNil(operation.lastError)
            XCTAssertEqual(operation.payload, originalPayload)
        }
    }

    func testAccountChangeDuringAwaitStopsOldAcknowledgment() async throws {
        let defaults = UserDefaults.standard
        let keys = ["currentUserId", "currentUserCompanyId"]
        let old = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, old) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        for changedKey in keys {
            defaults.set("original-user", forKey: keys[0])
            defaults.set("original-company", forKey: keys[1])
            let container = try makeContainer()
            let operation = try makeOperation(in: container.mainContext)
            let started = expectation(description: "request suspended")
            let gate = OutboundLifecycleGate()
            let processor = OutboundProcessor(repositoryPush: { _, _, _, _ in
                started.fulfill()
                await gate.wait()
            })
            let work = Task { try await processor.executeOperation(operation, context: container.mainContext) }
            await fulfillment(of: [started], timeout: 2)
            defaults.set("replacement-identity", forKey: changedKey)
            await gate.release()
            do { try await work.value; XCTFail("Replacement account cannot acknowledge old work") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(operation.status, "inProgress")
            XCTAssertNil(operation.completedAt)
            XCTAssertEqual(operation.retryCount, 0)
        }
    }

    func testCancellationDuringAwaitKeepsClaimForRecovery() async throws {
        let container = try makeContainer()
        let operation = try makeOperation(in: container.mainContext)
        let started = expectation(description: "request suspended")
        let gate = OutboundLifecycleGate()
        let processor = OutboundProcessor(repositoryPush: { _, _, _, _ in
            started.fulfill()
            await gate.wait()
            throw URLError(.cancelled)
        })
        let work = Task { try await processor.executeOperation(operation, context: container.mainContext) }
        await fulfillment(of: [started], timeout: 2)
        work.cancel()
        await gate.release()
        do { try await work.value; XCTFail("Cancelled request must stop") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(operation.status, "inProgress")
        XCTAssertNil(operation.lastError)
        XCTAssertEqual(operation.retryCount, 0)
    }

    func testInvalidationBeforeSyntheticStoreResetNeverTouchesDestroyedOperation() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let operation = try makeOperation(in: context)
        let started = expectation(description: "request suspended")
        let gate = OutboundLifecycleGate()
        let processor = OutboundProcessor(repositoryPush: { _, _, _, _ in
            started.fulfill()
            await gate.wait()
            throw URLError(.notConnectedToInternet)
        })
        let work = Task { try await processor.executeOperation(operation, context: context) }
        await fulfillment(of: [started], timeout: 2)
        processor.invalidate()
        container.deleteAllData() // This container holds only this synthetic fixture.
        await gate.release()
        do { try await work.value; XCTFail("Reset must stop the old continuation") }
        catch { XCTAssertTrue(error is CancellationError) }
        // Awaiting CancellationError is the proof: the continuation and its
        // claim-release defer survived without touching the destroyed model.
        // deleteAllData also removes this container's stores, so constructing
        // another context here would itself trap, independently of the driver.
    }

    func testActorDrainCannotAcknowledgeAfterSessionInvalidationAndResume() async throws {
        for shouldFail in [false, true] {
            let container = try makeContainer()
            _ = try makeOperation(in: container.mainContext)
            let actor = await Task.detached { DataActor(modelContainer: container) }.value
            let started = expectation(description: "actor request suspended")
            let gate = OutboundLifecycleGate()
            await actor.setOutboundPushForTesting { _, _, _, _ in
                started.fulfill()
                await gate.wait()
                if shouldFail { throw URLError(.notConnectedToInternet) }
            }
            let work = Task { await actor.processPendingOperations() }
            await fulfillment(of: [started], timeout: 2)
            // These are synchronous, including from MainActor before its logout wipe.
            actor.invalidateOutboundWork()
            actor.resumeOutboundWork()
            await gate.release()
            _ = await work.value
            let fresh = ModelContext(container)
            let row = try XCTUnwrap(fresh.fetch(FetchDescriptor<SyncOperation>()).first)
            XCTAssertEqual(row.status, "inProgress", "A new session never authorizes an old callback")
            XCTAssertNil(row.completedAt)
            XCTAssertEqual(row.retryCount, 0)
        }
    }

    func testActorDrainCompletesCurrentSession() async throws {
        let container = try makeContainer()
        _ = try makeOperation(in: container.mainContext)
        let actor = await Task.detached { DataActor(modelContainer: container) }.value
        await actor.setOutboundPushForTesting { _, _, _, _ in }
        _ = await actor.processPendingOperations()
        let fresh = ModelContext(container)
        let row = try XCTUnwrap(fresh.fetch(FetchDescriptor<SyncOperation>()).first)
        XCTAssertEqual(row.status, "completed", "Claim refresh must preserve a valid registered operation")
        XCTAssertNotNil(row.completedAt)
        XCTAssertEqual(row.retryCount, 0)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: SyncOperation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func makeOperation(in context: ModelContext) throws -> SyncOperation {
        let operation = SyncOperation(entityType: "client", entityId: UUID().uuidString.lowercased(),
            operationType: "create", payload: Data("{}".utf8), changedFields: ["name"])
        context.insert(operation)
        try context.save()
        return operation
    }
}

private actor OutboundLifecycleGate {
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
