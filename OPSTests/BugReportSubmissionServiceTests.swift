//
//  BugReportSubmissionServiceTests.swift
//  OPSTests
//
//  Bug 956823c9: accepting a report is a durable local operation. Network
//  delivery happens afterward and must never hold the report sheet open.
//

import XCTest
import UIKit
@testable import OPS

@MainActor
final class BugReportSubmissionServiceTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testOnlineAcceptanceReturnsAfterDurableEnqueueWhileTransportIsSuspended() async throws {
        let queue = makeQueue()
        let transport = SuspendedBugReportTransport()
        let service = BugReportSubmissionService(
            offlineQueue: queue,
            backgroundWorkEnabled: true,
            onlineSubmitter: transport.submit
        )

        try service.acceptReport(
            payload: payload(),
            screenshot: nil,
            shouldAttemptSync: true
        )

        let accepted = try XCTUnwrap(try queue.loadQueue().first)
        XCTAssertEqual(accepted.id, "11111111-1111-1111-1111-111111111111")

        await transport.waitUntilStarted()
        XCTAssertEqual(try queue.loadQueue().map(\.id), [accepted.id])

        transport.resume()
        await waitForQueueToDrain(queue)
        XCTAssertTrue(try queue.loadQueue().isEmpty)
    }

    func testFailedDrainRetainsTheCompleteReportForRetryAfterRelaunch() async throws {
        let firstQueue = makeQueue()
        let service = BugReportSubmissionService(
            offlineQueue: firstQueue,
            backgroundWorkEnabled: false,
            onlineSubmitter: { _, _, _ in throw TestFailure.transport }
        )

        try service.acceptReport(
            payload: payload(),
            screenshot: nil,
            shouldAttemptSync: false
        )
        await service.drainQueuedReports()

        let reloaded = try makeQueue().loadQueue()
        let retained = try XCTUnwrap(reloaded.first)
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(
            retained.payload.consoleLogs,
            [["level": .string("error"), "message": .string("request failed")]]
        )
        XCTAssertEqual(
            retained.payload.breadcrumbs,
            [["label": .string("Home"), "type": .string("screenView")]]
        )
        XCTAssertEqual(
            retained.payload.networkLog,
            [["status": .int(503), "url": .string("/rest/v1/bug_reports")]]
        )
        XCTAssertEqual(
            retained.payload.stateSnapshot,
            ["pendingSyncCount": .int(3), "isConnected": .bool(true)]
        )
    }

    func testSuccessfulDrainUsesStableClientIDAndClearsTheDurableQueue() async throws {
        let queue = makeQueue()
        let transport = RecordingBugReportTransport()
        let service = BugReportSubmissionService(
            offlineQueue: queue,
            backgroundWorkEnabled: false,
            onlineSubmitter: transport.submit
        )

        try service.acceptReport(
            payload: payload(),
            screenshot: nil,
            shouldAttemptSync: false
        )
        await service.drainQueuedReports()

        let delivered = try XCTUnwrap(transport.received.first)
        XCTAssertEqual(delivered.id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(
            delivered.consoleLogs,
            .array([["level": .string("error"), "message": .string("request failed")]])
        )
        XCTAssertEqual(
            delivered.stateSnapshot,
            .dictionary(["pendingSyncCount": .int(3), "isConnected": .bool(true)])
        )
        XCTAssertTrue(try queue.loadQueue().isEmpty)
    }

    func testDrainRetainsReportWhenItsPersistedScreenshotIsUnavailable() async throws {
        let queue = makeQueue()
        let item = try queue.enqueue(payload: payload(), screenshot: screenshot())
        let screenshotURL = try XCTUnwrap(queue.screenshotURL(for: item))
        try FileManager.default.removeItem(at: screenshotURL)

        let transport = RecordingBugReportTransport()
        let service = BugReportSubmissionService(
            offlineQueue: queue,
            backgroundWorkEnabled: false,
            onlineSubmitter: transport.submit
        )

        await service.drainQueuedReports()

        XCTAssertTrue(transport.received.isEmpty)
        XCTAssertEqual(try queue.loadQueue().map(\.id), [item.id])
    }

    func testFailedDeliveryRetainsScreenshotAndRetriesWithTheSameID() async throws {
        let queue = makeQueue()
        let item = try queue.enqueue(payload: payload(), screenshot: screenshot())
        let screenshotURL = try XCTUnwrap(queue.screenshotURL(for: item))
        let transport = FailOnceBugReportTransport()
        let service = BugReportSubmissionService(
            offlineQueue: queue,
            backgroundWorkEnabled: false,
            onlineSubmitter: transport.submit
        )

        await service.drainQueuedReports()

        XCTAssertEqual(try queue.loadQueue().map(\.id), [item.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotURL.path))

        await service.drainQueuedReports()

        XCTAssertEqual(transport.received.map(\.id), [item.id, item.id])
        XCTAssertTrue(try queue.loadQueue().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: screenshotURL.path))
    }

    func testAcceptanceFailsWhenScreenshotCannotBePersisted() throws {
        let screenshotPath = directory
            .appendingPathComponent("11111111-1111-1111-1111-111111111111.jpg")
        try FileManager.default.createDirectory(
            at: screenshotPath,
            withIntermediateDirectories: true
        )
        let queue = makeQueue()

        XCTAssertThrowsError(
            try queue.enqueue(payload: payload(), screenshot: screenshot())
        ) { error in
            XCTAssertEqual(error as? BugReportError, .failedToCreateReport)
        }
        XCTAssertTrue(try queue.loadQueue().isEmpty)
    }

    func testLegacyQueueWithoutDiagnosticFieldsStillLoads() throws {
        let queue = makeQueue()
        try queue.enqueue(payload: payload(), screenshot: nil)
        let queueFile = directory.appendingPathComponent("queue.json")
        let data = try Data(contentsOf: queueFile)
        var rows = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )
        var legacyPayload = try XCTUnwrap(rows[0]["payload"] as? [String: Any])
        legacyPayload.removeValue(forKey: "consoleLogs")
        legacyPayload.removeValue(forKey: "breadcrumbs")
        legacyPayload.removeValue(forKey: "networkLog")
        legacyPayload.removeValue(forKey: "stateSnapshot")
        rows[0]["payload"] = legacyPayload
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
            .write(to: queueFile, options: .atomic)

        let reloaded = try makeQueue().loadQueue()

        let retained = try XCTUnwrap(reloaded.first)
        XCTAssertNil(retained.payload.consoleLogs)
        XCTAssertNil(retained.payload.breadcrumbs)
        XCTAssertNil(retained.payload.networkLog)
        XCTAssertNil(retained.payload.stateSnapshot)
    }

    func testAcceptanceFailsWhenTheQueueCannotBePersisted() throws {
        let blockedURL = directory.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockedURL)
        let queue = BugReportOfflineQueue(
            directoryURL: blockedURL,
            idProvider: { "11111111-1111-1111-1111-111111111111" }
        )

        XCTAssertThrowsError(try queue.enqueue(payload: payload(), screenshot: nil)) { error in
            XCTAssertEqual(error as? BugReportError, .failedToCreateReport)
        }
    }

    // MARK: - Fixtures

    private func makeQueue() -> BugReportOfflineQueue {
        BugReportOfflineQueue(
            directoryURL: directory,
            idProvider: { "11111111-1111-1111-1111-111111111111" },
            dateProvider: { Date(timeIntervalSince1970: 1_786_000_000) }
        )
    }

    private func payload() -> BugReportPayload {
        BugReportPayload(
            companyId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            reporterId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            description: "Save this report locally first",
            category: "bug",
            platform: "ios",
            appVersion: "3.0.5",
            buildNumber: "3.0.5",
            osName: "iOS",
            osVersion: "26.5.2",
            deviceModel: "iPhone17,1",
            screenName: "Home",
            networkType: "wifi",
            batteryLevel: 0.72,
            freeDiskMb: 4_096,
            freeRamMb: 768,
            consoleLogs: [[
                "level": .string("error"),
                "message": .string("request failed")
            ]],
            breadcrumbs: [[
                "label": .string("Home"),
                "type": .string("screenView")
            ]],
            networkLog: [[
                "status": .int(503),
                "url": .string("/rest/v1/bug_reports")
            ]],
            stateSnapshot: [
                "pendingSyncCount": .int(3),
                "isConnected": .bool(true)
            ],
            reporterName: "Jackson Sweet",
            reporterEmail: "jackson@example.com"
        )
    }

    private func screenshot() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    private func waitForQueueToDrain(_ queue: BugReportOfflineQueue) async {
        for _ in 0..<200 {
            if (try? queue.loadQueue().isEmpty) == true { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class SuspendedBugReportTransport {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var submitWaiter: CheckedContinuation<Void, Never>?

    func submit(_ dto: BugReportInsertDTO, _ screenshot: UIImage?, _ companyId: String) async throws {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { submitWaiter = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func resume() {
        submitWaiter?.resume()
        submitWaiter = nil
    }
}

@MainActor
private final class RecordingBugReportTransport {
    private(set) var received: [BugReportInsertDTO] = []

    func submit(_ dto: BugReportInsertDTO, _ screenshot: UIImage?, _ companyId: String) async throws {
        received.append(dto)
    }
}

@MainActor
private final class FailOnceBugReportTransport {
    private(set) var received: [BugReportInsertDTO] = []

    func submit(_ dto: BugReportInsertDTO, _ screenshot: UIImage?, _ companyId: String) async throws {
        received.append(dto)
        if received.count == 1 {
            throw TestFailure.transport
        }
    }
}

private enum TestFailure: Error {
    case transport
}
