//
//  DaySheetCacheTests.swift
//  OPSTests
//
//  The delegate day sheet is the only lead surface that must render with no
//  signal (spec §6), and leads are repo-fetched — there is no SwiftData row to
//  fall back on. Two guarantees are locked here:
//
//   1. The snapshot is lossless. Every wire field the sheet renders survives a
//      write/read cycle byte-for-byte — including fractional-second timestamps
//      and date-only columns, which a "helpful" Date strategy would silently
//      round or reject.
//   2. A milestone pressed offline is never lost, never double-committed, and
//      never overwrites a lead someone else already moved.
//

import XCTest
@testable import OPS

@MainActor
final class DaySheetCacheTests: XCTestCase {

    private var directory: URL!

    private let userA = "11111111-1111-1111-1111-111111111111"
    private let userB = "22222222-2222-2222-2222-222222222222"
    private let companyA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private let companyB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

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

    // MARK: - Snapshot

    func test_snapshot_roundTripsEveryFieldIncludingWireTimestamps() throws {
        let cache = DaySheetCache(directory: directory)
        let savedAt = localDate(hour: 7, minute: 12)
        let dtos = [try leadDTO(id: "lead-1"), try leadDTO(id: "lead-2")]

        XCTAssertTrue(cache.save(dtos, userId: userA, companyId: companyA, savedAt: savedAt))

        let snapshot = try XCTUnwrap(cache.load(userId: userA, companyId: companyA))
        XCTAssertEqual(snapshot.savedAt, savedAt)
        XCTAssertEqual(snapshot.dtos.map(\.id), ["lead-1", "lead-2"])

        let lead = snapshot.dtos[0]
        // Timestamps stay exactly as Postgres sent them. Any lossy Date
        // strategy (ISO without fractional seconds, or a Date column that
        // cannot parse "yyyy-MM-dd") fails right here.
        XCTAssertEqual(lead.nextFollowUpAt, "2026-07-27T07:12:33.456789+00:00")
        XCTAssertEqual(
            SupabaseDate.parse(try XCTUnwrap(lead.nextFollowUpAt)),
            SupabaseDate.parse("2026-07-27T07:12:33.456789+00:00")
        )
        XCTAssertEqual(lead.stageEnteredAt, "2026-07-20T15:04:05.123456+00:00")
        XCTAssertEqual(lead.createdAt, "2026-07-18T11:00:00Z")
        XCTAssertEqual(lead.updatedAt, "2026-07-26T22:41:09.9Z")
        XCTAssertEqual(lead.handledAt, "2026-07-26T22:41:09.9Z")
        XCTAssertEqual(lead.expectedCloseDate, "2026-08-04")   // date-only column
        XCTAssertNil(lead.deletedAt)

        // Everything the row and the expanded card read.
        XCTAssertEqual(lead.stage, "quoting")
        XCTAssertEqual(lead.contactName, "Helen Vasquez")
        XCTAssertEqual(lead.contactPhone, "+15195551234")
        XCTAssertEqual(lead.address, "812 Beechwood Dr, Kitchener ON")
        XCTAssertEqual(lead.assignedTo, userA)
        XCTAssertEqual(lead.assignmentVersion, 3)
        XCTAssertEqual(lead.estimatedValue, 12_400.5)
        XCTAssertEqual(lead.latitude, 43.4516)
        XCTAssertEqual(lead.longitude, -80.4925)
        XCTAssertEqual(lead.images, ["https://cdn.example.com/a.jpg", "https://cdn.example.com/b.jpg"])
        XCTAssertEqual(lead.tags, ["referral"])
        XCTAssertEqual(lead.aiSummary, "Quote due Friday.")
    }

    func test_snapshot_isKeyedByBothOperatorAndCompany() throws {
        let cache = DaySheetCache(directory: directory)
        XCTAssertTrue(cache.save([try leadDTO(id: "lead-1")], userId: userA, companyId: companyA))

        XCTAssertNotNil(cache.load(userId: userA, companyId: companyA))
        XCTAssertNil(cache.load(userId: userB, companyId: companyA), "another operator must not read this sheet")
        XCTAssertNil(cache.load(userId: userA, companyId: companyB), "another company must not read this sheet")
    }

    func test_load_returnsNilWhenNothingWasEverSaved() {
        let cache = DaySheetCache(directory: directory)
        XCTAssertNil(cache.load(userId: userA, companyId: companyA))
    }

    func test_lastSyncLabel_isZeroPaddedTwentyFourHourLocalTime() {
        XCTAssertEqual(DaySheetCache.lastSyncLabel(localDate(hour: 7, minute: 12)), "07:12")
        XCTAssertEqual(DaySheetCache.lastSyncLabel(localDate(hour: 13, minute: 5)), "13:05")
        XCTAssertEqual(DaySheetCache.lastSyncLabel(localDate(hour: 0, minute: 0)), "00:00")
    }

    // MARK: - Milestone queue

    func test_queuedCommits_surviveRelaunch() throws {
        let first = commit(id: "00000000-0000-0000-0000-0000000000c1", leadId: "lead-1")
        let second = commit(id: "00000000-0000-0000-0000-0000000000c2", leadId: "lead-2")

        let queue = makeQueue()
        queue.enqueue(first)
        queue.enqueue(second)

        let relaunched = makeQueue()
        XCTAssertEqual(relaunched.pending.map(\.id), [first.id, second.id])
        XCTAssertEqual(relaunched.pending, [first, second])
        XCTAssertEqual(relaunched.pending(forLead: "lead-2"), [second])

        relaunched.remove(id: first.id)
        XCTAssertEqual(makeQueue().pending.map(\.id), [second.id])
    }

    func test_enqueue_isIdempotentForARepeatedRequestId() {
        let queue = makeQueue()
        let stamp = commit(id: "00000000-0000-0000-0000-0000000000c1", leadId: "lead-1")

        queue.enqueue(stamp)
        queue.enqueue(stamp)

        XCTAssertEqual(queue.pending.count, 1)
    }

    func test_drain_commitsEveryQueuedRowInOrderAndClearsTheQueue() async {
        let spy = ExecutorSpy()
        let queue = makeQueue()
        let first = commit(id: "00000000-0000-0000-0000-0000000000c1", leadId: "lead-1")
        let second = commit(id: "00000000-0000-0000-0000-0000000000c2", leadId: "lead-2")
        queue.enqueue(first)
        queue.enqueue(second)
        queue.executor = { spy.run($0) }

        await queue.drain()

        XCTAssertEqual(spy.seen.map(\.id), [first.id, second.id])
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertTrue(makeQueue().pending.isEmpty, "a committed row must not come back after relaunch")
    }

    func test_drain_dropsConflictSkippedRowsAlongsideCommittedOnes() async {
        let spy = ExecutorSpy()
        let queue = makeQueue()
        let moved = commit(id: "00000000-0000-0000-0000-0000000000c1", leadId: "lead-1")
        let clean = commit(id: "00000000-0000-0000-0000-0000000000c2", leadId: "lead-2")
        queue.enqueue(moved)
        queue.enqueue(clean)
        spy.outcomes[moved.id] = .conflictSkipped
        queue.executor = { spy.run($0) }

        await queue.drain()

        XCTAssertEqual(spy.seen.map(\.id), [moved.id, clean.id])
        XCTAssertTrue(queue.pending.isEmpty, "a lead that moved on without us is settled, not retried")
    }

    func test_drain_keepsRetryLaterRowsAndRetriesThemNextTime() async {
        let spy = ExecutorSpy()
        let queue = makeQueue()
        let offline = commit(id: "00000000-0000-0000-0000-0000000000c1", leadId: "lead-1")
        let landed = commit(id: "00000000-0000-0000-0000-0000000000c2", leadId: "lead-2")
        queue.enqueue(offline)
        queue.enqueue(landed)
        spy.outcomes[offline.id] = .retryLater
        queue.executor = { spy.run($0) }

        await queue.drain()

        XCTAssertEqual(queue.pending.map(\.id), [offline.id])
        XCTAssertEqual(makeQueue().pending.map(\.id), [offline.id])

        spy.outcomes[offline.id] = .committed
        await queue.drain()

        XCTAssertEqual(spy.seen.map(\.id), [offline.id, landed.id, offline.id])
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func test_drain_withoutAnExecutor_keepsTheQueueIntact() async {
        let queue = makeQueue()
        let stamp = commit(id: "00000000-0000-0000-0000-0000000000c1", leadId: "lead-1")
        queue.enqueue(stamp)

        await queue.drain()

        XCTAssertEqual(queue.pending, [stamp])
        XCTAssertEqual(makeQueue().pending, [stamp], "no committer installed must never mean data loss")
    }

    // MARK: - Helpers

    private func makeQueue() -> MilestoneWriteQueue {
        MilestoneWriteQueue(directory: directory, backgroundWorkEnabled: false)
    }

    private func commit(id: String, leadId: String) -> QueuedMilestoneCommit {
        QueuedMilestoneCommit(
            id: id,
            leadId: leadId,
            companyId: companyA,
            userId: userA,
            milestoneVerb: LeadMilestone.quoteSent.label,
            priorStageRaw: PipelineStage.quoting.rawValue,
            targetStageRaw: PipelineStage.quoted.rawValue,
            stampedAt: localDate(hour: 9, minute: 30)
        )
    }

    /// Whole-second local wall-clock time, built from components so the label
    /// assertions hold in any device time zone (and so a lossy date strategy
    /// shows up as a mismatch, not as rounding noise).
    private func localDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 27
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// Decoded from the wire shape on purpose — the cache has to survive
    /// exactly what PostgREST hands the repository, not a hand-built struct.
    private func leadDTO(id: String) throws -> OpportunityDTO {
        let json = """
        {"id":"\(id)",
         "company_id":"\(companyA)",
         "contact_name":"Helen Vasquez",
         "contact_phone":"+15195551234",
         "address":"812 Beechwood Dr, Kitchener ON",
         "stage":"quoting",
         "stage_entered_at":"2026-07-20T15:04:05.123456+00:00",
         "assigned_to":"\(userA)",
         "assignment_version":3,
         "estimated_value":12400.5,
         "expected_close_date":"2026-08-04",
         "next_follow_up_at":"2026-07-27T07:12:33.456789+00:00",
         "handled_at":"2026-07-26T22:41:09.9Z",
         "ai_summary":"Quote due Friday.",
         "tags":["referral"],
         "images":["https://cdn.example.com/a.jpg","https://cdn.example.com/b.jpg"],
         "latitude":43.4516,
         "longitude":-80.4925,
         "created_at":"2026-07-18T11:00:00Z",
         "updated_at":"2026-07-26T22:41:09.9Z"}
        """
        return try JSONDecoder().decode(OpportunityDTO.self, from: Data(json.utf8))
    }
}

/// Stands in for Task 5's real committer: records what it was handed, in order,
/// and answers with whatever outcome the test needs.
private final class ExecutorSpy {
    private(set) var seen: [QueuedMilestoneCommit] = []
    var outcomes: [String: MilestoneWriteQueue.DrainOutcome] = [:]
    var defaultOutcome: MilestoneWriteQueue.DrainOutcome = .committed

    func run(_ commit: QueuedMilestoneCommit) -> MilestoneWriteQueue.DrainOutcome {
        seen.append(commit)
        return outcomes[commit.id] ?? defaultOutcome
    }
}
