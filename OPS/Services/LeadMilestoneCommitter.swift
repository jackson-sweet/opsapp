//
//  LeadMilestoneCommitter.swift
//  OPS
//
//  The day sheet's one write. A runner presses CONTACTED / SITE VISITED /
//  QUOTE SENT and three things happen at once: the lead's stage advances, the
//  event is stamped on the timeline, and a 5-second window opens in which the
//  whole thing can be taken back (spec §4).
//
//  Everything here exists to make that press safe to make with a thumb, in a
//  truck, at the side of a job:
//
//   • ONE at a time. A second press while a window is open is ignored — not
//     queued behind it, not applied over it. The operator sees exactly one
//     confirmation and exactly one UNDO.
//   • UNDO is a true reversal, not a compensating note: the stage goes back to
//     the value it held at press time and the stamped activity row is deleted
//     (the around-call precedent — the record should say it never happened,
//     because it never did).
//   • Offline is not a failure mode. The connectivity probe is consulted BEFORE
//     the network is touched; a dark press flips the local stage, lands in
//     `MilestoneWriteQueue`, and confirms to the operator identically. A thrown
//     error is the safety net under that decision, never the mechanism.
//   • WON never writes. It returns `.requiresWonFlow` so the card routes into
//     the guarded conversion path; `OpportunityRepository.moveToStage` rejects
//     a direct `.won` write at the boundary as the backstop.
//
//  ── Freeze contract (read this before wiring the sheet, Task 7) ─────────────
//  While `pending != nil` the day sheet MUST render from the groups snapshot it
//  held at press time. The stage flip is optimistic and immediate, so a sheet
//  that re-derives its groups on every change would move the card into WAITING
//  the instant the operator's thumb lifted — yanking UNDO out from under it.
//  The sheet re-derives when `pending` clears; that is what `notifyLeadUpdated`
//  announces at the end of the window.
//  ───────────────────────────────────────────────────────────────────────────
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §4
//

import Foundation
import UIKit

@MainActor
final class LeadMilestoneCommitter: ObservableObject {

    // MARK: - Contract

    /// The press the operator can still take back. One at a time, by design.
    struct PendingCommit: Equatable {
        let leadId: String
        let milestone: LeadMilestone
        /// Where the lead was before the press — the exact value UNDO restores.
        let priorStage: PipelineStage
        /// The stamped row to delete on UNDO. Nil when the press was queued
        /// (no server row exists yet) or when the stamp itself failed.
        let activityId: String?
        /// Non-nil when the press went to `MilestoneWriteQueue` — UNDO
        /// withdraws that row instead of reversing a server write.
        let queuedRequestId: String?
        /// `stampedAt + undoWindow`.
        let deadline: Date
    }

    enum PressOutcome: Equatable {
        /// Written to the server; the window is open.
        case committed
        /// Durably queued (no signal, or the write did not land); window open.
        case queued
        /// WON — the card routes to the guarded conversion flow. Nothing written.
        case requiresWonFlow
        /// No edit scope, a window already open, or a milestone with no stage
        /// to write. Nothing written, nothing queued.
        case refused
    }

    /// A scheduled window close that can be called off when UNDO wins the race.
    struct ScheduledExpiry {
        let cancel: @MainActor () -> Void
        init(cancel: @escaping @MainActor () -> Void) { self.cancel = cancel }
    }

    typealias StageMover = @MainActor (String, PipelineStage) async throws -> Void
    typealias LocalStageFlip = @MainActor (String, PipelineStage) -> Void
    typealias ActivityLogger = @MainActor (CreateActivityDTO) async throws -> String
    typealias ActivityDeleter = @MainActor (String) async throws -> Void
    typealias StageProbe = @MainActor (String) async throws -> String
    typealias ExpiryScheduler =
        @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> ScheduledExpiry

    /// Spec §4 — five seconds. Long enough to catch a mis-tap, short enough
    /// that the sheet is never frozen in a state the operator has stopped
    /// thinking about.
    static let undoWindow: TimeInterval = 5

    /// The card renders its morph + UNDO entirely from this.
    @Published private(set) var pending: PendingCommit?

    private let companyId: String
    private let queue: MilestoneWriteQueue
    private let isOnline: @MainActor () -> Bool
    private let moveStage: StageMover
    private let flipLocalStage: LocalStageFlip
    private let logActivity: ActivityLogger
    private let deleteActivity: ActivityDeleter
    private let currentStageRaw: StageProbe
    private let notifyLeadUpdated: @MainActor (String) -> Void
    private let now: () -> Date
    private let schedule: ExpiryScheduler

    private var expiry: ScheduledExpiry?

    // MARK: - Init

    init(
        companyId: String,
        queue: MilestoneWriteQueue = .shared,
        isOnline: @escaping @MainActor () -> Bool,
        moveStage: @escaping StageMover,
        flipLocalStage: @escaping LocalStageFlip,
        logActivity: @escaping ActivityLogger,
        deleteActivity: @escaping ActivityDeleter,
        currentStageRaw: @escaping StageProbe,
        notifyLeadUpdated: @escaping @MainActor (String) -> Void = LeadMilestoneCommitter.postLeadUpdated,
        now: @escaping () -> Date = Date.init,
        schedule: @escaping ExpiryScheduler = LeadMilestoneCommitter.sleepScheduler
    ) {
        self.companyId = companyId
        self.queue = queue
        self.isOnline = isOnline
        self.moveStage = moveStage
        self.flipLocalStage = flipLocalStage
        self.logActivity = logActivity
        self.deleteActivity = deleteActivity
        self.currentStageRaw = currentStageRaw
        self.notifyLeadUpdated = notifyLeadUpdated
        self.now = now
        self.schedule = schedule

        // Installing the executor is itself a drain trigger (see
        // `MilestoneWriteQueue.executor`), so presses made in a previous
        // launch commit the moment the day sheet appears with signal.
        queue.executor = { [weak self] commit in
            guard let self else { return .retryLater }
            return await self.commitQueued(commit)
        }
    }

    /// Production wiring. The stage move rides the SAME `move_opportunity_stage`
    /// path the console and `LeadStatusMenu` use — the day sheet introduces no
    /// second way to move a lead.
    ///
    /// `isOnline` is supplied by the screen (`DataController.isConnected`);
    /// there is no connectivity singleton to reach for, and inventing one here
    /// would fork the app's one source of network truth.
    convenience init(
        pipeline: PipelineViewModel,
        companyId: String,
        isOnline: @escaping @MainActor () -> Bool,
        queue: MilestoneWriteQueue = .shared
    ) {
        let repository = OpportunityRepository(companyId: companyId)
        self.init(
            companyId: companyId,
            queue: queue,
            isOnline: isOnline,
            moveStage: { leadId, stage in
                try await pipeline.moveToStage(
                    opportunityId: leadId,
                    to: stage,
                    userId: pipeline.currentUserId
                )
            },
            flipLocalStage: { leadId, stage in
                // Offline (and pre-flight for a write that did not land): move
                // the model the sheet is rendering, and nothing else. The
                // queued row is what eventually reaches the server.
                guard let lead = pipeline.allOpportunities.first(where: { $0.id == leadId })
                else { return }
                lead.stage = stage
                lead.stageEnteredAt = Date()
                lead.stageManuallySet = true
                // `allOpportunities` holds reference types, so mutating one
                // element publishes nothing on its own.
                pipeline.objectWillChange.send()
            },
            logActivity: { dto in try await repository.logActivity(dto).id },
            deleteActivity: { activityId in try await repository.deleteActivity(activityId) },
            currentStageRaw: { leadId in try await repository.fetchOne(leadId).stage }
        )
    }

    // MARK: - Press

    /// Stamp the milestone and open the undo window.
    ///
    /// Order is deliberate: gates first (a refused press must never buzz), then
    /// the haptic, then the write. Spec §4 press mechanics.
    @discardableResult
    func press(
        _ milestone: LeadMilestone,
        lead: Opportunity,
        userId: String?,
        canEdit: Bool
    ) async -> PressOutcome {
        // A second press during an open window is ignored, not stacked: the
        // operator has exactly one thing to take back at any moment.
        guard pending == nil else { return .refused }
        guard canEdit else { return .refused }
        // WON is a conversion, not a stamp. No haptic here either — the won
        // sheet arriving is the feedback, and two signals for one press reads
        // like two events.
        guard milestone != .won else { return .requiresWonFlow }
        guard let target = milestone.targetStage else { return .refused }

        let priorStage = lead.stage
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        guard isOnline() else {
            return queuePress(milestone, lead: lead, prior: priorStage, target: target, userId: userId)
        }

        do {
            try await moveStage(lead.id, target)
        } catch {
            // The probe said we had signal and we did not. The press is the
            // operator's work — it goes in the durable queue rather than
            // evaporating with an error toast.
            print("[MILESTONE] \(milestone.label) on \(lead.id) did not land: \(error) — queuing")
            return queuePress(milestone, lead: lead, prior: priorStage, target: target, userId: userId)
        }

        var activityId: String?
        do {
            activityId = try await logActivity(Self.activityDTO(
                for: milestone, leadId: lead.id, companyId: companyId, userId: userId
            ))
        } catch {
            // `move_opportunity_stage` already wrote the `stage_transitions`
            // row, and the timeline merges transitions with activities — the
            // event is on the record either way. Losing the stamp costs the
            // verb line, not the fact.
            print("[MILESTONE] stamp for \(milestone.label) on \(lead.id) failed: \(error)")
        }

        open(PendingCommit(
            leadId: lead.id,
            milestone: milestone,
            priorStage: priorStage,
            activityId: activityId,
            queuedRequestId: nil,
            deadline: now().addingTimeInterval(Self.undoWindow)
        ))
        return .committed
    }

    private func queuePress(
        _ milestone: LeadMilestone,
        lead: Opportunity,
        prior: PipelineStage,
        target: PipelineStage,
        userId: String?
    ) -> PressOutcome {
        flipLocalStage(lead.id, target)

        let requestId = UUID().uuidString.lowercased()
        queue.enqueue(QueuedMilestoneCommit(
            id: requestId,
            leadId: lead.id,
            companyId: companyId,
            // The queue row is Codable with a non-optional operator; an unknown
            // operator is stored empty and sent as nil (the RPC's own default).
            userId: userId ?? "",
            milestoneVerb: milestone.label,
            priorStageRaw: prior.rawValue,
            targetStageRaw: target.rawValue,
            stampedAt: now()
        ))

        open(PendingCommit(
            leadId: lead.id,
            milestone: milestone,
            priorStage: prior,
            activityId: nil,
            queuedRequestId: requestId,
            deadline: now().addingTimeInterval(Self.undoWindow)
        ))
        return .queued
    }

    // MARK: - Undo

    /// Take the press back. Only valid while the window is open; after that,
    /// corrections are deliberate (the stage chip's `LeadStatusMenu`, or FULL
    /// LEAD) rather than accidental.
    func undo() async {
        guard let commit = pending, now() < commit.deadline else { return }

        // Claim the transition BEFORE any await: an expiry firing mid-reversal
        // finds `pending` already cleared and does nothing.
        pending = nil
        expiry?.cancel()
        expiry = nil

        if let requestId = commit.queuedRequestId {
            // Nothing ever reached the server — withdraw the row and put the
            // local stage back. No network, which is the whole point offline.
            queue.remove(id: requestId)
            flipLocalStage(commit.leadId, commit.priorStage)
            return
        }

        var reversalFailed = false
        do {
            try await moveStage(commit.leadId, commit.priorStage)
        } catch {
            print("[MILESTONE] undo of \(commit.milestone.label) on \(commit.leadId) failed: \(error)")
            reversalFailed = true
        }

        if let activityId = commit.activityId {
            do {
                try await deleteActivity(activityId)
            } catch {
                print("[MILESTONE] stamp \(activityId) survived undo: \(error)")
                reversalFailed = true
            }
        }

        guard reversalFailed else { return }
        // The screen is now showing a lead that is not what the server holds.
        // Say so, and make the sheet reload the truth.
        ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
        notifyLeadUpdated(commit.leadId)
    }

    // MARK: - Window

    private func open(_ commit: PendingCommit) {
        pending = commit
        expiry = schedule(Self.undoWindow) { [weak self] in
            guard let self, self.pending == commit else { return }
            self.pending = nil
            self.expiry = nil
            // The window closing is what un-freezes the sheet and lets the card
            // move to its new group (Tasks 7/10 own the motion).
            self.notifyLeadUpdated(commit.leadId)
        }
    }

    /// Production scheduler. `Task.sleep` rather than a `Timer` so the window
    /// cancels cleanly and never outlives the screen.
    static let sleepScheduler: ExpiryScheduler = { delay, body in
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            body()
        }
        return ScheduledExpiry { task.cancel() }
    }

    /// The reload contract `LeadsTabView` already listens on.
    static let postLeadUpdated: @MainActor (String) -> Void = { leadId in
        NotificationCenter.default.post(
            name: Notification.Name("LeadUpdatedSuccess"),
            object: nil,
            userInfo: ["leadId": leadId]
        )
    }

    // MARK: - Queue executor

    /// Commit one press made while dark. Installed on `MilestoneWriteQueue` at
    /// init, so this runs on connectivity restore, on the retry timer, and on
    /// the next launch that reaches the day sheet.
    ///
    /// Idempotence is the stage check, not a server receipt: `move_opportunity_stage`
    /// has no request-id contract, so a press whose response was lost is
    /// recognised by the lead already sitting on the target stage and is
    /// dropped instead of written twice.
    func commitQueued(_ commit: QueuedMilestoneCommit) async -> MilestoneWriteQueue.DrainOutcome {
        guard let milestone = Self.milestone(forVerb: commit.milestoneVerb),
              let target = PipelineStage(rawValue: commit.targetStageRaw) else {
            print("[MILESTONE_QUEUE] unreadable row \(commit.id) (\(commit.milestoneVerb) → "
                  + "\(commit.targetStageRaw)) — dropped")
            return .conflictSkipped
        }

        let currentRaw: String
        do {
            currentRaw = try await currentStageRaw(commit.leadId)
        } catch {
            return Self.isTransient(error)
                ? .retryLater
                : drop(commit, because: "lead unreadable: \(error)")
        }

        guard currentRaw == commit.priorStageRaw else {
            // Somebody moved this lead while we were dark — including, possibly,
            // this very press on a retry whose answer was lost. Last-writer
            // honesty: drop ours, never drag the lead backwards.
            return drop(commit, because: "stage is \(currentRaw), was \(commit.priorStageRaw) at press")
        }

        do {
            try await moveStage(commit.leadId, target)
        } catch {
            return Self.isTransient(error)
                ? .retryLater
                : drop(commit, because: "stage write refused: \(error)")
        }

        do {
            _ = try await logActivity(Self.activityDTO(
                for: milestone,
                leadId: commit.leadId,
                companyId: commit.companyId,
                userId: commit.userId.isEmpty ? nil : commit.userId
            ))
        } catch {
            // Same trade as the online path: the transition row carries the
            // event. Re-running the row would re-attempt the stage move, which
            // would then conflict-skip and lose the stamp anyway.
            print("[MILESTONE_QUEUE] stamp for \(commit.id) failed: \(error)")
        }
        return .committed
    }

    private func drop(_ commit: QueuedMilestoneCommit, because reason: String) -> MilestoneWriteQueue.DrainOutcome {
        print("[MILESTONE_QUEUE] dropped \(commit.milestoneVerb) on lead \(commit.leadId): \(reason)")
        return .conflictSkipped
    }

    /// Transient = the wire. Anything else (RLS refusal, a deleted lead, a
    /// malformed row) is permanent, and a permanent failure must leave the
    /// queue rather than wedge every press behind it forever.
    static func isTransient(_ error: Error) -> Bool {
        if error is URLError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain || nsError.domain == NSPOSIXErrorDomain
    }

    // MARK: - The stamp
    //
    // Type choice, with the timeline as the evidence (`ActivityTimeline` +
    // `LeadStreamRow`):
    //
    //  • SITE VISITED → `.siteVisit`. Exact, and its `mappin.circle.fill` icon
    //    is what the row draws when `direction` is nil — so the visit reads as
    //    a visit, not as correspondence.
    //  • CONTACTED / QUOTE SENT → `.note` + `direction: "outbound"`. The row
    //    renders those as ↑ olive ("your touch landed") with the verb as the
    //    title, which is exactly what happened and nothing more. The tempting
    //    alternatives all assert facts we did not observe: `.call`/`.textMessage`/
    //    `.email` name a channel the button never knew, and `.estimateSent` is
    //    `isSystemGenerated` and belongs to real estimate records — stamping it
    //    from a thumb press would forge one.
    //
    // `bodyText` is deliberately absent: fact-only, the same contract
    // `LeadQuickTouchLogger` holds for TEXT/EMAIL.

    static func activityDTO(
        for milestone: LeadMilestone,
        leadId: String,
        companyId: String,
        userId: String?
    ) -> CreateActivityDTO {
        CreateActivityDTO(
            opportunityId: leadId,
            companyId: companyId,
            type: activityType(for: milestone).rawValue,
            subject: milestone.label,
            direction: direction(for: milestone),
            createdBy: userId
        )
    }

    static func activityType(for milestone: LeadMilestone) -> ActivityType {
        switch milestone {
        case .siteVisited:            return .siteVisit
        case .contacted, .quoteSent:  return .note
        case .won:                    return .won
        }
    }

    private static func direction(for milestone: LeadMilestone) -> String? {
        switch milestone {
        case .contacted, .quoteSent: return "outbound"
        case .siteVisited, .won:     return nil
        }
    }

    /// Queue rows carry the verb, not the case — one lookup, so the queue file
    /// stays human-readable and survives a rename of the enum.
    static func milestone(forVerb verb: String) -> LeadMilestone? {
        [LeadMilestone.contacted, .siteVisited, .quoteSent, .won]
            .first { $0.label == verb }
    }
}
