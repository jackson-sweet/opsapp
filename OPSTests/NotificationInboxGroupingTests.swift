//
//  NotificationInboxGroupingTests.swift
//  OPSTests
//
//  Bug 589e3b1e — 89 identical "Reply waiting, no owner" rows, every one a dead
//  tap, because their email threads carry no lead. These tests pin the two
//  halves of the fix: the pure grouping rule, and the batched resolver seam
//  that feeds it (one request, once per thread id, cached for the list).
//

import XCTest
@testable import OPS

final class NotificationInboxGroupingTests: XCTestCase {

    // MARK: - Fixtures

    /// The production shape, verified against prod on 2026-09-09:
    /// `type=system`, `deep_link_type=inbox`, `action_url=/inbox/<thread>`,
    /// `dedupe_key=phase-c-actor-unavailable:<thread>`, `persistent=true`.
    private func replyWaiting(
        id: String,
        threadId: String,
        title: String = "Reply waiting, no owner",
        isRead: Bool = false,
        persistent: Bool? = true,
        createdAt: String = "2026-09-09T00:44:37.303224+00:00"
    ) -> NotificationDTO {
        NotificationDTO(
            id: id,
            userId: "user-1",
            companyId: "company-1",
            type: "system",
            title: title,
            body: "OPS did not draft this customer reply because no one is assigned to the lead.",
            projectId: nil,
            noteId: nil,
            expenseId: nil,
            batchId: nil,
            deepLinkType: "inbox",
            actionUrl: "/inbox/\(threadId)",
            actionLabel: "Assign this lead",
            persistent: persistent,
            dedupeKey: "phase-c-actor-unavailable:\(threadId)",
            resolvedAt: nil,
            resolvedBy: nil,
            resolutionReason: nil,
            isRead: isRead,
            createdAt: createdAt
        )
    }

    private func plainRow(
        id: String,
        type: String = "task_assignment",
        projectId: String? = nil,
        actionUrl: String? = nil,
        dedupeKey: String? = nil,
        deepLinkType: String? = nil,
        createdAt: String = "2026-09-09T01:00:00.000000+00:00"
    ) -> NotificationDTO {
        NotificationDTO(
            id: id,
            userId: "user-1",
            companyId: "company-1",
            type: type,
            title: "Task assigned",
            body: "Deck rebuild",
            projectId: projectId,
            noteId: nil,
            expenseId: nil,
            batchId: nil,
            deepLinkType: deepLinkType,
            actionUrl: actionUrl,
            actionLabel: nil,
            persistent: false,
            dedupeKey: dedupeKey,
            resolvedAt: nil,
            resolvedBy: nil,
            resolutionReason: nil,
            isRead: false,
            createdAt: createdAt
        )
    }

    private let threadA = "ded5e3b4-876e-4f0e-a2cc-80dff95ee01f"
    private let threadB = "f80461eb-ff27-4c77-b43b-c290b4a59f98"
    private let threadC = "c2b51eab-1fa9-4e25-9ca7-6ff3b00fb9bd"
    private let leadId   = "9c137fe0-a1e1-4945-b248-00141ce89fc8"

    // MARK: - The rule: which rows can be grouped at all

    func testOnlyThreadOnlyRowsAreCandidates() {
        // The production row: its sole routing signal is the inbox thread.
        XCTAssertEqual(
            NotificationInboxGrouping.emailThreadRouteId(for: replyWaiting(id: "n1", threadId: threadA)),
            threadA
        )

        // An opportunity id in the action url is a live destination — never grouped.
        XCTAssertNil(NotificationInboxGrouping.emailThreadRouteId(
            for: plainRow(
                id: "n2",
                type: "system",
                actionUrl: "/inbox?thread=\(threadA)&opportunityId=\(leadId)",
                deepLinkType: "inbox"
            )
        ))

        // An opportunity id in the dedupe key is a live destination too.
        XCTAssertNil(NotificationInboxGrouping.emailThreadRouteId(
            for: plainRow(
                id: "n3",
                type: "leads_waiting",
                actionUrl: "/inbox/\(threadA)",
                dedupeKey: "lead_lifecycle:operator_follow_up_miss:\(leadId)"
            )
        ))

        // A row that carries a project opens that project.
        XCTAssertNil(NotificationInboxGrouping.emailThreadRouteId(
            for: plainRow(
                id: "n4",
                type: "system",
                projectId: "project-1",
                actionUrl: "/inbox/\(threadA)",
                deepLinkType: "inbox"
            )
        ))

        // A row with no lead signal at all is not a candidate.
        XCTAssertNil(NotificationInboxGrouping.emailThreadRouteId(for: plainRow(id: "n5")))
    }

    // MARK: - The rule: resolution states

    func testUnresolvedThreadsAreLeftAlone() {
        let rows = [
            replyWaiting(id: "n1", threadId: threadA),
            replyWaiting(id: "n2", threadId: threadB)
        ]
        // Empty map = nothing looked up (offline, or the read threw).
        let items = NotificationInboxGrouping.items(for: rows, threadLeads: [:])
        XCTAssertEqual(items.map(\.id), ["n1", "n2"])
    }

    func testThreadsWithALeadKeepTheirOwnRow() {
        let rows = [replyWaiting(id: "n1", threadId: threadA)]
        let items = NotificationInboxGrouping.items(
            for: rows,
            threadLeads: [threadA: leadId]
        )
        XCTAssertEqual(items.map(\.id), ["n1"])
    }

    func testResolvedToNothingRowsCollapseIntoOneGroup() {
        let rows = [
            plainRow(id: "top", createdAt: "2026-09-09T02:00:00.000000+00:00"),
            replyWaiting(id: "n1", threadId: threadA, createdAt: "2026-09-09T01:00:00.000000+00:00"),
            replyWaiting(id: "n2", threadId: threadB, createdAt: "2026-09-09T00:30:00.000000+00:00"),
            plainRow(id: "mid", createdAt: "2026-09-09T00:20:00.000000+00:00"),
            replyWaiting(id: "n3", threadId: threadC, createdAt: "2026-09-09T00:10:00.000000+00:00")
        ]
        let items = NotificationInboxGrouping.items(
            for: rows,
            threadLeads: [threadA: nil, threadB: "   ", threadC: nil]
        )

        // One group, seated where its newest member sat.
        XCTAssertEqual(items.map(\.id), ["top", UnlinkedInboxGroup.rowId, "mid"])

        guard case .unlinkedInbox(let group) = items[1] else {
            return XCTFail("expected the inbox group in slot 1")
        }
        XCTAssertEqual(group.memberIds, ["n1", "n2", "n3"])
        XCTAssertEqual(group.count, 3)
        XCTAssertEqual(group.unreadCount, 3)
        XCTAssertFalse(group.isRead)
        // Newest member's timestamp, so the row buckets where it belongs.
        XCTAssertEqual(group.newestCreatedAt, "2026-09-09T01:00:00.000000+00:00")
    }

    func testBlankOpportunityIdCountsAsNoLead() {
        let items = NotificationInboxGrouping.items(
            for: [replyWaiting(id: "n1", threadId: threadA)],
            threadLeads: [threadA: ""]
        )
        XCTAssertEqual(items.map(\.id), [UnlinkedInboxGroup.rowId])
    }

    // MARK: - The group's own facts

    func testPersistentMembersForbidMarkRead() {
        // Production: every member is persistent, so the row offers no lever.
        let persistent = NotificationInboxGrouping.items(
            for: [replyWaiting(id: "n1", threadId: threadA)],
            threadLeads: [threadA: nil]
        )
        guard case .unlinkedInbox(let persistentGroup) = persistent[0] else {
            return XCTFail("expected a group")
        }
        XCTAssertFalse(persistentGroup.isMarkReadPermitted)

        // A group of ordinary rows may be cleared.
        let ordinary = NotificationInboxGrouping.items(
            for: [replyWaiting(id: "n1", threadId: threadA, persistent: false)],
            threadLeads: [threadA: nil]
        )
        guard case .unlinkedInbox(let ordinaryGroup) = ordinary[0] else {
            return XCTFail("expected a group")
        }
        XCTAssertTrue(ordinaryGroup.isMarkReadPermitted)

        // One persistent member is enough to withhold the action.
        let mixed = NotificationInboxGrouping.items(
            for: [
                replyWaiting(id: "n1", threadId: threadA, persistent: false),
                replyWaiting(id: "n2", threadId: threadB, persistent: true)
            ],
            threadLeads: [threadA: nil, threadB: nil]
        )
        guard case .unlinkedInbox(let mixedGroup) = mixed[0] else {
            return XCTFail("expected a group")
        }
        XCTAssertFalse(mixedGroup.isMarkReadPermitted)
    }

    func testSourceReadoutNamesAndRanksTheRowsItReplaced() {
        let homogeneous = NotificationInboxGrouping.items(
            for: [
                replyWaiting(id: "n1", threadId: threadA),
                replyWaiting(id: "n2", threadId: threadB)
            ],
            threadLeads: [threadA: nil, threadB: nil]
        )
        guard case .unlinkedInbox(let oneTitle) = homogeneous[0] else {
            return XCTFail("expected a group")
        }
        XCTAssertEqual(oneTitle.sources, [.init(title: "Reply waiting, no owner", count: 2)])

        let mixed = NotificationInboxGrouping.items(
            for: [
                replyWaiting(id: "n1", threadId: threadA, title: "Email files need review"),
                replyWaiting(id: "n2", threadId: threadB),
                replyWaiting(id: "n3", threadId: threadC)
            ],
            threadLeads: [threadA: nil, threadB: nil, threadC: nil]
        )
        guard case .unlinkedInbox(let twoTitles) = mixed[0] else {
            return XCTFail("expected a group")
        }
        // Densest first, even though the singleton was seen first.
        XCTAssertEqual(twoTitles.sources, [
            .init(title: "Reply waiting, no owner", count: 2),
            .init(title: "Email files need review", count: 1)
        ])
    }

    func testUnreadCountTracksMembers() {
        let items = NotificationInboxGrouping.items(
            for: [
                replyWaiting(id: "n1", threadId: threadA, isRead: true),
                replyWaiting(id: "n2", threadId: threadB, isRead: true)
            ],
            threadLeads: [threadA: nil, threadB: nil]
        )
        guard case .unlinkedInbox(let group) = items[0] else {
            return XCTFail("expected a group")
        }
        XCTAssertEqual(group.unreadCount, 0)
        XCTAssertTrue(group.isRead)
    }

    // MARK: - Copy

    func testCopyIsHonestAndCountsCorrectly() {
        XCTAssertEqual(
            NotificationInboxGrouping.Copy.body(count: 1),
            "1 customer reply with no lead attached. Handle it on the web."
        )
        XCTAssertEqual(
            NotificationInboxGrouping.Copy.body(count: 85),
            "85 customer replies with no lead attached. Handle them on the web."
        )
        // No exclamation points, no emoji, sentence case for content.
        XCTAssertFalse(NotificationInboxGrouping.Copy.body(count: 3).contains("!"))
        XCTAssertEqual(NotificationInboxGrouping.Copy.title, "Inbox replies waiting")
    }

    // MARK: - The batched resolver seam

    /// Records every batch it is asked for, so a test can prove there was
    /// exactly one, and that a second pass asks for nothing.
    private final class RecordingResolver: EmailThreadLeadResolving, @unchecked Sendable {
        private(set) var batches: [[String]] = []
        var answers: [String: String?] = [:]
        var error: Error?

        func opportunityIds(forEmailThreadIds ids: [String]) async throws -> [String: String?] {
            batches.append(ids)
            if let error { throw error }
            var resolved: [String: String?] = [:]
            for id in ids { resolved[id] = answers[id] ?? String?.none }
            return resolved
        }
    }

    func testThreadIdsNeedingResolutionDeduplicatesAndSkipsTheCache() {
        let rows = [
            replyWaiting(id: "n1", threadId: threadA),
            replyWaiting(id: "n2", threadId: threadA),   // same thread, cited twice
            replyWaiting(id: "n3", threadId: threadB),
            plainRow(id: "n4")                            // no thread at all
        ]
        XCTAssertEqual(
            NotificationInboxGrouping.threadIdsNeedingResolution(in: rows),
            [threadA, threadB]
        )
        XCTAssertEqual(
            NotificationInboxGrouping.threadIdsNeedingResolution(
                in: rows,
                alreadyResolved: [threadA]
            ),
            [threadB]
        )
    }

    @MainActor
    func testCacheBatchesOnceAndNeverRepeatsAThread() async {
        let resolver = RecordingResolver()
        resolver.answers = [threadA: leadId]
        let cache = NotificationThreadLeadCache()

        let rows = [
            replyWaiting(id: "n1", threadId: threadA),
            replyWaiting(id: "n2", threadId: threadA),
            replyWaiting(id: "n3", threadId: threadB)
        ]

        await cache.resolve(for: rows, using: resolver)

        // ONE request, carrying both distinct threads.
        XCTAssertEqual(resolver.batches.count, 1)
        XCTAssertEqual(Set(resolver.batches[0]), Set([threadA, threadB]))
        XCTAssertEqual(cache.resolved[threadA] ?? nil, leadId)
        XCTAssertTrue(cache.resolved.keys.contains(threadB))
        XCTAssertNil(cache.resolved[threadB] ?? nil)

        // The same rows again — and a repeat of one of them — cost nothing.
        await cache.resolve(for: rows, using: resolver)
        await cache.resolve(for: [replyWaiting(id: "n4", threadId: threadA)], using: resolver)
        XCTAssertEqual(resolver.batches.count, 1)

        // Only the genuinely new thread goes out.
        await cache.resolve(for: [replyWaiting(id: "n5", threadId: threadC)], using: resolver)
        XCTAssertEqual(resolver.batches.count, 2)
        XCTAssertEqual(resolver.batches[1], [threadC])
    }

    @MainActor
    func testAFailedReadGroupsNothing() async {
        struct Boom: Error {}
        let resolver = RecordingResolver()
        resolver.error = Boom()
        let cache = NotificationThreadLeadCache()

        let rows = [replyWaiting(id: "n1", threadId: threadA)]
        await cache.resolve(for: rows, using: resolver)

        XCTAssertTrue(cache.resolved.isEmpty)
        // The rail renders exactly as it did before the fix.
        XCTAssertEqual(
            NotificationInboxGrouping.items(for: rows, threadLeads: cache.resolved).map(\.id),
            ["n1"]
        )
    }
}
