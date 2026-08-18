//
//  TeamAndFinanceNotificationRPCTests.swift
//  OPSTests
//
//  The team-management, assignment, photo-storage and cashflow-forecast rails
//  must reach the notification table through the narrow server RPCs, never a
//  direct `notifications` insert — the 2026-07-15 creation hardening revoked
//  app-role INSERT, so every legacy insert on these paths 42501'd and the
//  rail row was never written (bug e302355c ADDENDUM).
//
//  Rewiring them moves three decisions off the client and onto the server:
//  who receives the row, what it says, and whether a row was actually new.
//  These tests pin what the CLIENT still owns after that move.
//
//  What is pinned here:
//    1. Role assignment pushes only when the server reports `created`. A
//       `noop` means the member already holds an unread notice for that role;
//       a push on top of it is noise the rail already refused.
//    2. Invite contacts cross the seam verbatim. The server matches them
//       against the invitation rows it just wrote — a reordered or
//       reformatted list matches nothing and the admin gets no record.
//    3. Assignment pushes target exactly the ids the server returned. Those
//       are the recipients that received NEW rail rows; pushing at the
//       candidate list instead re-pings people whose row was deduped.
//    4. The photo-storage cooldown is stamped for `created` AND `kept` — both
//       mean the rail now carries an accurate unread notice for the device —
//       and never when the call throws.
//    5. Forecast dip/cleared forward their arguments verbatim, compute no
//       recipient list client-side, and — critically — still write the
//       `forecast_alerts` anti-spam ledger when the rail RPC fails. The
//       legacy code returned early on a failed recipient lookup and skipped
//       the ledger entirely, which re-armed the dip alert on the next tick.
//

import XCTest
@testable import OPS

final class TeamAndFinanceNotificationRPCTests: XCTestCase {

    private struct RailFailure: Error {}

    // MARK: - Spies

    /// Records the team-management dispatches and returns a scripted verdict.
    private final class TeamManagementSpy: TeamManagementNotifying, @unchecked Sendable {
        private(set) var roleMemberIds: [String] = []
        private(set) var inviteEmails: [[String]] = []
        private(set) var invitePhones: [[String]] = []
        var verdict = "created"
        var shouldFail = false

        func notifyRoleAssigned(memberId: String) async throws -> String {
            roleMemberIds.append(memberId)
            if shouldFail { throw RailFailure() }
            return verdict
        }

        func notifyTeamInvitesSent(emails: [String], phones: [String]) async throws -> String {
            inviteEmails.append(emails)
            invitePhones.append(phones)
            if shouldFail { throw RailFailure() }
            return verdict
        }
    }

    /// Records the assignment dispatches and returns a scripted recipient list
    /// — the ids the server says received NEW rows.
    private final class AssignmentSpy: ProjectAssignmentNotifying, @unchecked Sendable {
        private(set) var projectIds: [String] = []
        private(set) var projectCandidates: [[String]] = []
        private(set) var taskIds: [String] = []
        private(set) var taskCandidates: [[String]?] = []
        var notified: [String] = []
        var shouldFail = false

        func notifyProjectAssigned(projectId: String, userIds: [String]) async throws -> [String] {
            projectIds.append(projectId)
            projectCandidates.append(userIds)
            if shouldFail { throw RailFailure() }
            return notified
        }

        func notifyTaskAssigned(taskId: String, userIds: [String]?) async throws -> [String] {
            taskIds.append(taskId)
            taskCandidates.append(userIds)
            if shouldFail { throw RailFailure() }
            return notified
        }
    }

    /// Records the photo-storage cap reports and returns a scripted verdict.
    private final class PhotoStorageSpy: PhotoStorageLimitNotifying, @unchecked Sendable {
        private(set) var remainingCounts: [Int] = []
        private(set) var deviceNames: [String] = []
        var verdict = "created"
        var shouldFail = false

        func syncPhotoStorageLimit(photosRemaining: Int, deviceName: String) async throws -> String {
            remainingCounts.append(photosRemaining)
            deviceNames.append(deviceName)
            if shouldFail { throw RailFailure() }
            return verdict
        }
    }

    /// Records the forecast rail dispatches.
    private final class ForecastRailSpy: ForecastRailNotifying, @unchecked Sendable {
        private(set) var dipBalances: [Double] = []
        private(set) var dipWeekStarts: [String] = []
        private(set) var clearedCallCount = 0
        var shouldFail = false

        func syncForecastDip(lowestBalance: Double, weekStart: String) async throws -> [String] {
            dipBalances.append(lowestBalance)
            dipWeekStarts.append(weekStart)
            if shouldFail { throw RailFailure() }
            return ["operator-1", "operator-2"]
        }

        func syncForecastCleared() async throws -> [String] {
            clearedCallCount += 1
            if shouldFail { throw RailFailure() }
            return ["operator-1"]
        }
    }

    /// Stands in for the `forecast_alerts` ledger — the anti-spam cadence the
    /// client still owns.
    private final class ForecastLedgerSpy: ForecastAlertLedgering, @unchecked Sendable {
        var stored: ForecastAlertDTO?
        private(set) var upserts: [UpsertForecastAlertDTO] = []

        init(stored: ForecastAlertDTO? = nil) {
            self.stored = stored
        }

        func fetch() async throws -> ForecastAlertDTO? { stored }

        func upsert(_ dto: UpsertForecastAlertDTO) async throws -> ForecastAlertDTO {
            upserts.append(dto)
            return ForecastAlertDTO(
                companyId: dto.companyId,
                lastDipNotifiedAt: dto.lastDipNotifiedAt,
                lastDipMinBalance: dto.lastDipMinBalance,
                lastDipMinWeekStart: dto.lastDipMinWeekStart,
                lastClearedAt: dto.lastClearedAt,
                dismissedUntilBalance: dto.dismissedUntilBalance,
                updatedAt: "2026-08-17T00:00:00.000Z"
            )
        }
    }

    // MARK: - 1. Role assignment: push follows the server's verdict

    func test_roleAssignmentPushesOnlyWhenTheServerCreatedTheRow() async {
        let spy = TeamManagementSpy()
        spy.verdict = "created"
        var pushCount = 0
        let memberId = "8c31889e-4f2a-4b71-9d33-0a17c5be6d42"

        await TeamNotificationDispatcher.dispatchRoleAssigned(
            memberId: memberId,
            syncer: spy
        ) { pushCount += 1 }

        XCTAssertEqual(
            spy.roleMemberIds,
            [memberId],
            "The server reads the member's RECORDED role from this id — it is the whole input"
        )
        XCTAssertEqual(pushCount, 1, "A created rail row earns its push")
    }

    func test_roleAssignmentSuppressesThePushWhenTheRowWasDeduped() async {
        let spy = TeamManagementSpy()
        spy.verdict = "noop"
        var pushCount = 0

        await TeamNotificationDispatcher.dispatchRoleAssigned(
            memberId: "1f0a5c62-77d4-4f8e-8b90-2c6e4a91d5b3",
            syncer: spy
        ) { pushCount += 1 }

        XCTAssertEqual(spy.roleMemberIds.count, 1, "The RPC is still the one that decides")
        XCTAssertEqual(
            pushCount,
            0,
            "`noop` means an unread notice for this role is already on the rail — a push would be a second telling of the same news"
        )
    }

    func test_roleAssignmentContainsATransportFailureAndSendsNoPush() async {
        let spy = TeamManagementSpy()
        spy.shouldFail = true
        var pushCount = 0

        // No `try` — the role write is already persisted by the time this runs.
        await TeamNotificationDispatcher.dispatchRoleAssigned(
            memberId: "d2bc7743-91e5-4c06-a1f7-6b8093ee2a58",
            syncer: spy
        ) { pushCount += 1 }

        XCTAssertEqual(pushCount, 0, "No rail row, no push — the two must not disagree")
    }

    // MARK: - 2. Invites: both contact lists cross verbatim

    func test_inviteDispatchForwardsBothContactListsVerbatim() async {
        let spy = TeamManagementSpy()
        let emails = ["dana@example.com", "wes@example.com"]
        let phones = ["+15555550123"]

        await TeamNotificationDispatcher.dispatchInvitesSent(
            emails: emails,
            phones: phones,
            syncer: spy
        )

        XCTAssertEqual(
            spy.inviteEmails,
            [emails],
            "The server matches these against the invitation rows it just wrote — order and formatting are load-bearing"
        )
        XCTAssertEqual(spy.invitePhones, [phones])
    }

    func test_inviteDispatchForwardsAnEmptyPhoneListRatherThanInventingOne() async {
        let spy = TeamManagementSpy()

        await TeamNotificationDispatcher.dispatchInvitesSent(
            emails: ["solo@example.com"],
            phones: [],
            syncer: spy
        )

        XCTAssertEqual(spy.invitePhones, [[]], "An SMS-free send reports no phones, not a placeholder")
    }

    func test_inviteDispatchContainsATransportFailure() async {
        let spy = TeamManagementSpy()
        spy.shouldFail = true

        // The invitations themselves are already sent; a failed rail row must
        // never bubble into the sheet's success path.
        await TeamNotificationDispatcher.dispatchInvitesSent(
            emails: ["dana@example.com"],
            phones: [],
            syncer: spy
        )

        XCTAssertEqual(spy.inviteEmails.count, 1)
    }

    // MARK: - 3. Assignments: one call, push at exactly the returned ids

    func test_projectAssignmentMakesOneCallAndPushesOnlyTheReturnedIds() async {
        let spy = AssignmentSpy()
        // Three crew were added; the server reports two got NEW rows — the
        // third already had an unread "added to project" notice.
        spy.notified = ["crew-a", "crew-c"]
        var pushed: [String] = []
        let candidates = ["crew-a", "crew-b", "crew-c"]

        await ProjectAssignmentNotificationDispatcher.dispatchProjectAssigned(
            projectId: "project-77",
            userIds: candidates,
            syncer: spy
        ) { pushed.append($0) }

        XCTAssertEqual(spy.projectIds, ["project-77"], "One call for the whole crew, not one per member")
        XCTAssertEqual(spy.projectCandidates, [candidates], "The candidate list crosses unchanged; the server intersects it with the row")
        XCTAssertEqual(
            pushed,
            ["crew-a", "crew-c"],
            "Push targets rail truth — crew-b's row was deduped, so crew-b is not pinged"
        )
    }

    func test_projectAssignmentSkipsTheCallWhenNobodyWasAdded() async {
        let spy = AssignmentSpy()
        var pushed: [String] = []

        await ProjectAssignmentNotificationDispatcher.dispatchProjectAssigned(
            projectId: "project-77",
            userIds: [],
            syncer: spy
        ) { pushed.append($0) }

        XCTAssertTrue(spy.projectIds.isEmpty, "Nobody was added — there is nothing for the server to announce")
        XCTAssertTrue(pushed.isEmpty)
    }

    func test_projectAssignmentContainsATransportFailureAndSendsNoPush() async {
        let spy = AssignmentSpy()
        spy.shouldFail = true
        var pushed: [String] = []

        await ProjectAssignmentNotificationDispatcher.dispatchProjectAssigned(
            projectId: "project-77",
            userIds: ["crew-a"],
            syncer: spy
        ) { pushed.append($0) }

        XCTAssertTrue(pushed.isEmpty, "The project is saved; a failed rail row must not turn into a lone push")
    }

    func test_taskAssignmentAnnouncesTheRowsWholeRecordedCrew() async {
        let spy = AssignmentSpy()
        spy.notified = ["crew-b"]
        var pushed: [String] = []
        let remoteTaskId = "b1a93011-2c4f-4f9a-8f0e-5f6d7c8b9a01"

        await ProjectAssignmentNotificationDispatcher.dispatchTaskAssigned(
            taskId: remoteTaskId,
            userIds: nil,
            syncer: spy
        ) { pushed.append($0) }

        XCTAssertEqual(spy.taskIds, [remoteTaskId], "The server-side task id — the local id is not what the row is keyed by")
        XCTAssertEqual(
            spy.taskCandidates.count,
            1,
            "One fan-out call for the task, not one per assignee"
        )
        XCTAssertNil(
            spy.taskCandidates[0],
            "At creation the whole recorded crew is new to the task, so the client names nobody and lets the row speak"
        )
        XCTAssertEqual(pushed, ["crew-b"], "Push follows the ids that received NEW rows")
    }

    func test_taskAssignmentContainsATransportFailureAndSendsNoPush() async {
        let spy = AssignmentSpy()
        spy.shouldFail = true
        var pushed: [String] = []

        await ProjectAssignmentNotificationDispatcher.dispatchTaskAssigned(
            taskId: "b1a93011-2c4f-4f9a-8f0e-5f6d7c8b9a01",
            userIds: nil,
            syncer: spy
        ) { pushed.append($0) }

        XCTAssertTrue(pushed.isEmpty)
    }

    // MARK: - 4. Photo storage: the cooldown follows a truthful rail

    func test_photoStorageStampsTheCooldownWhenTheRowWasCreated() async {
        let spy = PhotoStorageSpy()
        spy.verdict = "created"
        var stamped = 0

        await PhotoStorageLimitRailDispatcher.dispatch(
            photosRemaining: 42,
            deviceName: "Jackson's iPhone",
            syncer: spy
        ) { stamped += 1 }

        XCTAssertEqual(spy.remainingCounts, [42])
        XCTAssertEqual(
            spy.deviceNames,
            ["Jackson's iPhone"],
            "The cap is a per-device limit — the device name names the phone that filled up"
        )
        XCTAssertEqual(stamped, 1)
    }

    func test_photoStorageStampsTheCooldownWhenTheServerKeptTheExistingRow() async {
        let spy = PhotoStorageSpy()
        spy.verdict = "kept"
        var stamped = 0

        await PhotoStorageLimitRailDispatcher.dispatch(
            photosRemaining: 7,
            deviceName: "Site iPad",
            syncer: spy
        ) { stamped += 1 }

        XCTAssertEqual(
            stamped,
            1,
            "`kept` means the device's unread notice is already standing — the rail is accurate, so stop re-asking for 24h"
        )
    }

    func test_photoStorageLeavesTheCooldownUnstampedWhenTheCallFails() async {
        let spy = PhotoStorageSpy()
        spy.shouldFail = true
        var stamped = 0

        await PhotoStorageLimitRailDispatcher.dispatch(
            photosRemaining: 7,
            deviceName: "Site iPad",
            syncer: spy
        ) { stamped += 1 }

        XCTAssertEqual(
            stamped,
            0,
            "Nothing reached the rail, so the next sync must be free to report the cap again"
        )
    }

    func test_photoStorageLeavesTheCooldownUnstampedOnAnUnrecognizedVerdict() async {
        let spy = PhotoStorageSpy()
        spy.verdict = "skipped"
        var stamped = 0

        await PhotoStorageLimitRailDispatcher.dispatch(
            photosRemaining: 7,
            deviceName: "Site iPad",
            syncer: spy
        ) { stamped += 1 }

        XCTAssertEqual(stamped, 0, "Only a verdict that means a row is standing may silence the next report")
    }

    // MARK: - 5. Forecast: verbatim args, client-owned ledger, no recipient lookup

    func test_forecastDipForwardsTheBalanceAndWeekVerbatim() async {
        let spy = ForecastRailSpy()
        let ledger = ForecastLedgerSpy()
        let dispatcher = ForecastNotificationDispatcher(
            companyId: "company-1",
            railSyncer: spy,
            ledger: ledger
        )

        await dispatcher.reactTo(result: dangerResult(lowestBalance: -4_820.50))

        XCTAssertEqual(spy.dipBalances, [-4_820.50], "The server renders the currency — it needs the raw number")
        XCTAssertEqual(
            spy.dipWeekStarts,
            ["2026-09-07"],
            "The dip week as a plain date string; the server formats the human copy"
        )
        XCTAssertEqual(ledger.upserts.count, 1, "The anti-spam cadence stays client-owned")
        XCTAssertEqual(ledger.upserts.first?.lastDipMinBalance, -4_820.50)
        XCTAssertEqual(ledger.upserts.first?.lastDipMinWeekStart, "2026-09-07")
    }

    func test_forecastDipStillWritesTheLedgerWhenTheRailCallFails() async {
        let spy = ForecastRailSpy()
        spy.shouldFail = true
        let ledger = ForecastLedgerSpy()
        let dispatcher = ForecastNotificationDispatcher(
            companyId: "company-1",
            railSyncer: spy,
            ledger: ledger
        )

        await dispatcher.reactTo(result: dangerResult(lowestBalance: -1_200))

        XCTAssertEqual(spy.dipBalances.count, 1, "The rail was attempted")
        XCTAssertEqual(
            ledger.upserts.count,
            1,
            "The legacy path returned early when its recipient lookup failed and never wrote the ledger — which re-fired the same dip on the next tick"
        )
    }

    func test_forecastClearedResolvesThroughTheRpcAndMarksTheLedger() async {
        let spy = ForecastRailSpy()
        let ledger = ForecastLedgerSpy(stored: standingDipLedgerRow())
        let dispatcher = ForecastNotificationDispatcher(
            companyId: "company-1",
            railSyncer: spy,
            ledger: ledger
        )

        await dispatcher.reactTo(result: healthyResult())

        XCTAssertEqual(
            spy.clearedCallCount,
            1,
            "One call: the server resolves the standing dip rows and posts the all-clear to the same holders"
        )
        XCTAssertTrue(spy.dipBalances.isEmpty)
        XCTAssertEqual(ledger.upserts.count, 1)
        XCTAssertNotNil(ledger.upserts.first?.lastClearedAt)
        XCTAssertNil(
            ledger.upserts.first?.dismissedUntilBalance,
            "Clearing resets the dismissal so a fresh dip can speak again"
        )
    }

    func test_forecastClearedStillWritesTheLedgerWhenTheRailCallFails() async {
        let spy = ForecastRailSpy()
        spy.shouldFail = true
        let ledger = ForecastLedgerSpy(stored: standingDipLedgerRow())
        let dispatcher = ForecastNotificationDispatcher(
            companyId: "company-1",
            railSyncer: spy,
            ledger: ledger
        )

        await dispatcher.reactTo(result: healthyResult())

        XCTAssertEqual(spy.clearedCallCount, 1)
        XCTAssertEqual(ledger.upserts.count, 1, "A failed rail row must not strand the ledger in its dipped state")
    }

    // MARK: - Fixtures

    private var utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func week(index: Int, start: Date, balance: Double) -> WeeklyProjection {
        WeeklyProjection(
            id: index,
            weekStart: start,
            weekEnd: utcCalendar.date(byAdding: .day, value: 6, to: start)!,
            inflows: 0,
            outflows: 0,
            net: 0,
            balance: balance,
            contributors: []
        )
    }

    /// Two weeks, the second one underwater — the dip week is 2026-09-07.
    private func dangerResult(lowestBalance: Double) -> ForecastResult {
        ForecastResult(
            weeks: [
                week(index: 0, start: utcDate(2026, 8, 31), balance: 5_000),
                week(index: 1, start: utcDate(2026, 9, 7), balance: lowestBalance)
            ],
            state: .danger,
            startingBalance: 5_000,
            startingBalanceAsOf: utcDate(2026, 8, 31),
            lowestWeekIndex: 1,
            lowestBalance: lowestBalance,
            endingBalance: lowestBalance,
            lowWaterThreshold: 2_500,
            layersIncluded: [.committed],
            computedAt: utcDate(2026, 8, 31)
        )
    }

    private func healthyResult() -> ForecastResult {
        ForecastResult(
            weeks: [week(index: 0, start: utcDate(2026, 8, 31), balance: 9_000)],
            state: .healthy,
            startingBalance: 9_000,
            startingBalanceAsOf: utcDate(2026, 8, 31),
            lowestWeekIndex: 0,
            lowestBalance: 9_000,
            endingBalance: 9_000,
            lowWaterThreshold: 2_500,
            layersIncluded: [.committed],
            computedAt: utcDate(2026, 8, 31)
        )
    }

    /// A ledger row describing a dip that was notified and never cleared.
    private func standingDipLedgerRow() -> ForecastAlertDTO {
        ForecastAlertDTO(
            companyId: "company-1",
            lastDipNotifiedAt: "2026-08-10T12:00:00.000Z",
            lastDipMinBalance: -3_000,
            lastDipMinWeekStart: "2026-09-07",
            lastClearedAt: nil,
            dismissedUntilBalance: -2_000,
            updatedAt: "2026-08-10T12:00:00.000Z"
        )
    }
}
