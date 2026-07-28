//
//  LeadMilestoneCommitterTests.swift
//  OPSTests
//
//  The milestone press is the one write a runner makes from the day sheet, and
//  it is made with a thumb, in a truck, sometimes with no signal. Four
//  guarantees are locked here (spec §4):
//
//   1. A press writes exactly two things — the stage move and one honest
//      activity stamp — and opens a 5-second window, nothing more.
//   2. UNDO inside that window returns the lead to EXACTLY where it was and
//      tells nobody, because nothing happened.
//   3. The window closing is what regroups the sheet — once, never twice, and
//      never while the operator's thumb is still over UNDO.
//   4. A press made dark is queued, not lost, and a queued press that lands on
//      a lead somebody else already moved is dropped, not forced.
//
//  Time is a seam: the window is driven by a fake clock and a captured expiry
//  closure, so this suite has no `Task.sleep` and takes no wall-clock seconds.
//

import XCTest
@testable import OPS

@MainActor
final class LeadMilestoneCommitterTests: XCTestCase {

    private let companyId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private let userId = "11111111-1111-1111-1111-111111111111"

    private var directory: URL!
    private var queue: MilestoneWriteQueue!
    private var recorder: Recorder!
    private var committer: LeadMilestoneCommitter!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Background work off: no retry timer, no connectivity observer, and no
        // drain on enqueue — this suite drives the executor itself.
        queue = MilestoneWriteQueue(directory: directory, backgroundWorkEnabled: false)
        recorder = Recorder()
        committer = makeCommitter()
    }

    override func tearDownWithError() throws {
        committer = nil
        queue = nil
        recorder = nil
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 1 · Online press

    func test_onlinePress_movesStageStampsVerbAndOpensTheWindow() async throws {
        let lead = makeLead(stage: .quoting)

        let outcome = await committer.press(.quoteSent, lead: lead, userId: userId, canEdit: true)

        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(recorder.moved.count, 1)
        XCTAssertEqual(recorder.moved.first?.leadId, lead.id)
        XCTAssertEqual(recorder.moved.first?.stage, .quoted)
        XCTAssertTrue(recorder.localFlips.isEmpty, "online presses flip through the server write")

        let activity = try XCTUnwrap(recorder.logged.first)
        XCTAssertEqual(recorder.logged.count, 1)
        XCTAssertEqual(activity.subject, "QUOTE SENT", "the stamp says the verb verbatim")
        XCTAssertEqual(activity.opportunityId, lead.id)
        XCTAssertEqual(activity.companyId, companyId)
        XCTAssertEqual(activity.createdBy, userId)
        XCTAssertEqual(activity.type, ActivityType.note.rawValue)
        XCTAssertEqual(activity.direction, "outbound")

        let pending = try XCTUnwrap(committer.pending)
        XCTAssertEqual(pending.leadId, lead.id)
        XCTAssertEqual(pending.milestone, .quoteSent)
        XCTAssertEqual(pending.priorStage, .quoting)
        XCTAssertEqual(pending.activityId, "activity-1")
        XCTAssertNil(pending.queuedRequestId)
        XCTAssertEqual(pending.deadline, recorder.now.addingTimeInterval(5))
        XCTAssertEqual(LeadMilestoneCommitter.undoWindow, 5)
        XCTAssertEqual(recorder.scheduledDelays, [5])

        // Nothing regroups while UNDO is still on screen.
        XCTAssertTrue(recorder.notified.isEmpty)
    }

    /// A site visit is the one milestone with an exact activity type of its own.
    func test_siteVisitedPress_stampsTheSiteVisitType() async throws {
        let lead = makeLead(stage: .qualifying)

        let outcome = await committer.press(.siteVisited, lead: lead, userId: userId, canEdit: true)

        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(recorder.moved.first?.stage, .quoting)
        let activity = try XCTUnwrap(recorder.logged.first)
        XCTAssertEqual(activity.type, ActivityType.siteVisit.rawValue)
        XCTAssertEqual(activity.subject, "SITE VISITED")
        XCTAssertNil(activity.direction, "a visit is not correspondence — it keeps its own glyph")
    }

    // MARK: - 2 · Undo

    func test_undoInsideTheWindow_reversesBothWritesAndTellsNobody() async throws {
        let lead = makeLead(stage: .quoting)
        _ = await committer.press(.quoteSent, lead: lead, userId: userId, canEdit: true)

        await committer.undo()

        XCTAssertEqual(recorder.moved.count, 2)
        XCTAssertEqual(recorder.moved.last?.stage, .quoting, "stage goes back exactly where it was")
        XCTAssertEqual(recorder.deleted, ["activity-1"], "the stamp is removed, not amended")
        XCTAssertNil(committer.pending)
        XCTAssertEqual(recorder.expiryCancels, 1, "the scheduled regroup is cancelled")
        XCTAssertTrue(recorder.notified.isEmpty, "nothing happened, so nothing regroups")
    }

    /// The expiry closure firing after an undo (the race the operator creates by
    /// pressing UNDO on the last tick) must not resurrect a regroup.
    func test_expiryAfterUndo_isInert() async throws {
        let lead = makeLead(stage: .quoting)
        _ = await committer.press(.quoteSent, lead: lead, userId: userId, canEdit: true)
        await committer.undo()

        recorder.fireExpiry?()

        XCTAssertNil(committer.pending)
        XCTAssertTrue(recorder.notified.isEmpty)
    }

    /// A reversal that does not land leaves the operator looking at a lie. The
    /// sheet is told to reload so the screen shows the server's truth.
    func test_undoWhoseReversalFails_asksTheSheetToReload() async throws {
        let lead = makeLead(stage: .quoting)
        _ = await committer.press(.quoteSent, lead: lead, userId: userId, canEdit: true)
        recorder.moveError = URLError(.timedOut)

        await committer.undo()

        XCTAssertNil(committer.pending)
        XCTAssertEqual(recorder.notified, [lead.id])
    }

    // MARK: - 3 · Window expiry

    func test_windowExpiry_clearsPendingAndNotifiesExactlyOnce() async throws {
        let lead = makeLead(stage: .newLead)
        _ = await committer.press(.contacted, lead: lead, userId: userId, canEdit: true)

        recorder.fireExpiry?()

        XCTAssertNil(committer.pending)
        XCTAssertEqual(recorder.notified, [lead.id])

        // A duplicate fire (a stray timer, a re-entered scheduler) is a no-op.
        recorder.fireExpiry?()
        XCTAssertEqual(recorder.notified, [lead.id])
    }

    // MARK: - 4 · Deadline

    func test_undoAfterTheDeadline_doesNothing() async throws {
        let lead = makeLead(stage: .quoting)
        _ = await committer.press(.quoteSent, lead: lead, userId: userId, canEdit: true)
        let pendingBefore = committer.pending

        recorder.now = recorder.now.addingTimeInterval(6)
        await committer.undo()

        XCTAssertEqual(recorder.moved.count, 1, "no reversal write")
        XCTAssertTrue(recorder.deleted.isEmpty)
        XCTAssertEqual(committer.pending, pendingBefore, "state is untouched")
        XCTAssertEqual(recorder.expiryCancels, 0)
    }

    // MARK: - 5 · One at a time

    func test_secondPressWhileWindowIsOpen_isRefused() async throws {
        let lead = makeLead(stage: .quoting)
        _ = await committer.press(.quoteSent, lead: lead, userId: userId, canEdit: true)
        let other = makeLead(id: "lead-2", stage: .newLead)

        let outcome = await committer.press(.contacted, lead: other, userId: userId, canEdit: true)

        XCTAssertEqual(outcome, .refused)
        XCTAssertEqual(recorder.moved.count, 1)
        XCTAssertEqual(recorder.logged.count, 1)
        XCTAssertEqual(committer.pending?.leadId, lead.id)
    }

    // MARK: - 6 · Edit gate

    func test_pressWithoutEditScope_writesNothing() async throws {
        let lead = makeLead(stage: .quoting)

        let outcome = await committer.press(.quoteSent, lead: lead, userId: userId, canEdit: false)

        XCTAssertEqual(outcome, .refused)
        XCTAssertEqual(recorder.serverCallCount, 0)
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertNil(committer.pending)
    }

    // MARK: - 7 · WON

    func test_wonPress_routesToTheWonFlowAndNeverWrites() async throws {
        let lead = makeLead(stage: .quoted)

        let outcome = await committer.press(.won, lead: lead, userId: userId, canEdit: true)

        XCTAssertEqual(outcome, .requiresWonFlow)
        XCTAssertEqual(recorder.serverCallCount, 0)
        XCTAssertTrue(recorder.localFlips.isEmpty)
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertNil(committer.pending, "no undo chip — the won flow is its own confirm surface")
    }

    // MARK: - 8 · Offline

    func test_offlinePress_queuesTheStampAndFlipsOnlyTheLocalStage() async throws {
        recorder.online = false
        let lead = makeLead(stage: .newLead)

        let outcome = await committer.press(.contacted, lead: lead, userId: userId, canEdit: true)

        XCTAssertEqual(outcome, .queued)
        XCTAssertEqual(recorder.serverCallCount, 0, "no network is attempted when there is none")
        XCTAssertEqual(recorder.localFlips.count, 1)
        XCTAssertEqual(recorder.localFlips.first?.leadId, lead.id)
        XCTAssertEqual(recorder.localFlips.first?.stage, .qualifying)

        let row = try XCTUnwrap(queue.pending.first)
        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(row.leadId, lead.id)
        XCTAssertEqual(row.companyId, companyId)
        XCTAssertEqual(row.userId, userId)
        XCTAssertEqual(row.milestoneVerb, "CONTACTED")
        XCTAssertEqual(row.priorStageRaw, PipelineStage.newLead.rawValue)
        XCTAssertEqual(row.targetStageRaw, PipelineStage.qualifying.rawValue)
        XCTAssertEqual(row.stampedAt, recorder.now)
        XCTAssertEqual(row.id, row.id.lowercased(), "request ids are lowercased uuids")

        let pending = try XCTUnwrap(committer.pending)
        XCTAssertEqual(pending.queuedRequestId, row.id)
        XCTAssertNil(pending.activityId, "there is no server row to point at yet")
        XCTAssertEqual(pending.deadline, recorder.now.addingTimeInterval(5))
    }

    func test_undoOfAQueuedPress_removesTheRowWithoutTouchingTheNetwork() async throws {
        recorder.online = false
        let lead = makeLead(stage: .newLead)
        _ = await committer.press(.contacted, lead: lead, userId: userId, canEdit: true)

        await committer.undo()

        XCTAssertTrue(queue.pending.isEmpty, "the queued press is withdrawn")
        XCTAssertEqual(recorder.localFlips.count, 2)
        XCTAssertEqual(recorder.localFlips.last?.stage, .newLead)
        XCTAssertEqual(recorder.serverCallCount, 0, "nothing was written, so nothing is reversed")
        XCTAssertNil(committer.pending)
        XCTAssertTrue(recorder.notified.isEmpty)
    }

    /// The network the probe promised can still fail. A press that never landed
    /// falls into the same durable queue rather than evaporating.
    func test_onlinePressWhoseMoveFails_fallsIntoTheQueue() async throws {
        recorder.moveError = URLError(.timedOut)
        let lead = makeLead(stage: .quoting)

        let outcome = await committer.press(.quoteSent, lead: lead, userId: userId, canEdit: true)

        XCTAssertEqual(outcome, .queued)
        XCTAssertTrue(recorder.logged.isEmpty, "no stamp for a stage that never moved")
        XCTAssertEqual(queue.pending.first?.milestoneVerb, "QUOTE SENT")
        XCTAssertEqual(recorder.localFlips.first?.stage, .quoted)
        XCTAssertNotNil(committer.pending?.queuedRequestId)
    }

    /// The stage move is the load-bearing write and it already produced a
    /// `stage_transitions` row, which the timeline renders. A failed stamp is a
    /// missing convenience, not a lost event — the window still opens.
    func test_onlinePressWhoseStampFails_stillOpensTheWindow() async throws {
        recorder.logError = URLError(.timedOut)
        let lead = makeLead(stage: .quoting)

        let outcome = await committer.press(.quoteSent, lead: lead, userId: userId, canEdit: true)

        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(recorder.moved.count, 1)
        let pending = try XCTUnwrap(committer.pending)
        XCTAssertNil(pending.activityId)

        // Undo still reverses what actually happened, and only that.
        await committer.undo()
        XCTAssertEqual(recorder.moved.last?.stage, .quoting)
        XCTAssertTrue(recorder.deleted.isEmpty)
    }

    // MARK: - 9 · Queue executor

    func test_queuedCommit_writesStageAndStampWhenTheLeadHasNotMoved() async throws {
        recorder.currentStageRaw = PipelineStage.newLead.rawValue

        let outcome = await committer.commitQueued(makeQueuedCommit())

        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(recorder.moved.count, 1)
        XCTAssertEqual(recorder.moved.first?.stage, .qualifying)
        XCTAssertEqual(recorder.logged.first?.subject, "CONTACTED")
        XCTAssertEqual(recorder.logged.first?.createdBy, userId)
    }

    func test_queuedCommit_skipsWhenSomebodyElseMovedTheLead() async throws {
        recorder.currentStageRaw = PipelineStage.quoted.rawValue

        let outcome = await committer.commitQueued(makeQueuedCommit())

        XCTAssertEqual(outcome, .conflictSkipped)
        XCTAssertEqual(recorder.serverCallCount, 0, "a stale press never drags a lead backwards")
    }

    func test_queuedCommit_retriesWhenTheNetworkIsStillDown() async throws {
        recorder.stageProbeError = URLError(.notConnectedToInternet)

        let outcome = await committer.commitQueued(makeQueuedCommit())

        XCTAssertEqual(outcome, .retryLater)
        XCTAssertEqual(recorder.serverCallCount, 0)
    }

    func test_queuedCommit_retriesWhenTheStageWriteFailsOnTheWire() async throws {
        recorder.currentStageRaw = PipelineStage.newLead.rawValue
        recorder.moveError = URLError(.networkConnectionLost)

        let outcome = await committer.commitQueued(makeQueuedCommit())

        XCTAssertEqual(outcome, .retryLater)
    }

    /// A permanently refused write (RLS, a deleted lead) must not wedge the
    /// queue forever — it is dropped with a log, exactly like a conflict.
    func test_queuedCommit_dropsAPermanentRefusal() async throws {
        recorder.currentStageRaw = PipelineStage.newLead.rawValue
        recorder.moveError = NSError(domain: "PostgrestError", code: 42501)

        let outcome = await committer.commitQueued(makeQueuedCommit())

        XCTAssertEqual(outcome, .conflictSkipped)
    }

    // MARK: - Fixtures

    private func makeLead(id: String = "lead-1", stage: PipelineStage) -> Opportunity {
        Opportunity(id: id, companyId: companyId, contactName: "Marcus Webb", stage: stage)
    }

    private func makeQueuedCommit() -> QueuedMilestoneCommit {
        QueuedMilestoneCommit(
            id: UUID().uuidString.lowercased(),
            leadId: "lead-1",
            companyId: companyId,
            userId: userId,
            milestoneVerb: LeadMilestone.contacted.label,
            priorStageRaw: PipelineStage.newLead.rawValue,
            targetStageRaw: PipelineStage.qualifying.rawValue,
            stampedAt: recorder.now
        )
    }

    private func makeCommitter() -> LeadMilestoneCommitter {
        let recorder = self.recorder!
        return LeadMilestoneCommitter(
            companyId: companyId,
            queue: queue,
            isOnline: { recorder.online },
            moveStage: { leadId, stage in
                if let error = recorder.moveError { throw error }
                recorder.moved.append((leadId, stage))
            },
            flipLocalStage: { leadId, stage in
                recorder.localFlips.append((leadId, stage))
            },
            logActivity: { dto in
                if let error = recorder.logError { throw error }
                recorder.logged.append(dto)
                return "activity-\(recorder.logged.count)"
            },
            deleteActivity: { activityId in
                if let error = recorder.deleteError { throw error }
                recorder.deleted.append(activityId)
            },
            currentStageRaw: { _ in
                if let error = recorder.stageProbeError { throw error }
                return recorder.currentStageRaw
            },
            notifyLeadUpdated: { leadId in recorder.notified.append(leadId) },
            now: { recorder.now },
            schedule: { delay, body in
                recorder.scheduledDelays.append(delay)
                recorder.fireExpiry = body
                return LeadMilestoneCommitter.ScheduledExpiry { recorder.expiryCancels += 1 }
            }
        )
    }

    /// Every seam's traffic, in one place, so a test can assert what the press
    /// did AND what it did not do.
    private final class Recorder {
        var online = true
        var now = Date(timeIntervalSince1970: 1_800_000_000)

        var moved: [(leadId: String, stage: PipelineStage)] = []
        var localFlips: [(leadId: String, stage: PipelineStage)] = []
        var logged: [CreateActivityDTO] = []
        var deleted: [String] = []
        var notified: [String] = []

        var moveError: Error?
        var logError: Error?
        var deleteError: Error?
        var stageProbeError: Error?
        var currentStageRaw = PipelineStage.newLead.rawValue

        var scheduledDelays: [TimeInterval] = []
        var fireExpiry: (@MainActor () -> Void)?
        var expiryCancels = 0

        /// Writes that reached the network, of any kind.
        var serverCallCount: Int { moved.count + logged.count + deleted.count }
    }
}
