//
//  PriorityQueueViewModel.swift
//  OPS
//
//  Backs PriorityQueueView: the ranked/unranked PROJECT list (waterline),
//  drag-reorder → Project.priorityRank writes, and the schedule runner that
//  drives the existing project-batch scheduler in ranked order.
//

import Foundation
import SwiftUI

@MainActor
final class PriorityQueueViewModel: ObservableObject {
    @Published var ranked: [Project] = []        // above the waterline, priority order
    @Published var unranked: [Project] = []      // below, default order
    @Published var includeUnranked = false
    @Published var anchorDate = Date()
    @Published var previewPlan: PlanPreview?
    @Published var justScheduledCount: Int?           // set after a batch commit → drives the confirmation overlay

    /// Identifiable wrapper so the preview drives `.sheet(item:)` with a STABLE
    /// identity. The old code fed `.sheet(item:)` a box whose id was a fresh
    /// `UUID()` minted on every render, so SwiftUI saw a "new" item each redraw
    /// and churned the sheet (dismiss → re-present). One UUID per built plan fixes it.
    struct PlanPreview: Identifiable {
        let id = UUID()
        let plan: SchedulePlan
    }

    private let dataController: DataController

    init(dataController: DataController) {
        self.dataController = dataController
        reload()
    }

    /// Load schedulable (accepted / in-progress, non-deleted) projects, split by
    /// waterline. Pre-acceptance projects (`.rfq`, `.estimated`) haven't been
    /// greenlit, so auto-scheduling their tasks would assign dates to work that
    /// isn't accepted yet — they're excluded here on the same `Status.isActive`
    /// rule the job board task list uses (`isJobBoardTaskListVisible`).
    func reload() {
        let active = dataController.getProjects().filter {
            $0.deletedAt == nil && $0.status.isActive
        }
        ranked = active.filter { $0.priorityRank != nil }.sorted { lhs, rhs in
            let lr = lhs.priorityRank ?? 0, rr = rhs.priorityRank ?? 0
            return lr == rr ? lhs.id < rhs.id : lr < rr
        }
        unranked = active.filter { $0.priorityRank == nil }.sorted {
            ($0.lastSyncedAt ?? .distantPast) > ($1.lastSyncedAt ?? .distantPast)
        }
    }

    // MARK: Reorder

    func moveRanked(projectId: String, to index: Int) {
        guard let current = ranked.firstIndex(where: { $0.id == projectId }) else { return }
        var working = ranked
        let p = working.remove(at: current)
        let clamped = min(max(index, 0), working.count)
        working.insert(p, at: clamped)
        ranked = working
        persistRank(forIndex: clamped, in: working)
    }

    func rank(projectId: String, at index: Int) {
        guard let p = unranked.first(where: { $0.id == projectId }) else { return }
        unranked.removeAll { $0.id == projectId }
        let clamped = min(max(index, 0), ranked.count)
        ranked.insert(p, at: clamped)
        persistRank(forIndex: clamped, in: ranked)
    }

    func unrank(projectId: String) {
        guard let p = ranked.first(where: { $0.id == projectId }) else { return }
        ranked.removeAll { $0.id == projectId }
        unranked.insert(p, at: 0)
        dataController.reorderProjectPriority(projectId: projectId, newRank: nil)
    }

    /// Move the waterline so the first `count` of the combined list become ranked.
    func setWaterline(rankedCount newCount: Int) {
        let combined = ranked + unranked
        let clamped = min(max(newCount, 0), combined.count)
        let newRanked = Array(combined.prefix(clamped))
        let newUnranked = Array(combined.suffix(combined.count - clamped))
        ranked = newRanked
        unranked = newUnranked
        var ranks: [String: Double?] = [:]
        let normalized = FractionalRank.normalize(orderedIds: newRanked.map(\.id))
        for (id, r) in normalized { ranks[id] = r }
        for p in newUnranked { ranks[p.id] = Double?.none }
        dataController.bulkSetProjectPriority(ranks)
    }

    private func persistRank(forIndex index: Int, in list: [Project]) {
        let id = list[index].id
        let lower = index > 0 ? list[index - 1].priorityRank : nil
        let upper = index < list.count - 1 ? list[index + 1].priorityRank : nil
        if let l = lower, let u = upper, FractionalRank.needsNormalization(between: l, and: u) {
            let normalized = FractionalRank.normalize(orderedIds: list.map(\.id))
            var ranks: [String: Double?] = [:]
            for (k, v) in normalized { ranks[k] = v }
            dataController.bulkSetProjectPriority(ranks)
            for p in list { p.priorityRank = normalized[p.id] }
        } else {
            let rank = FractionalRank.between(lower, upper)
            list[index].priorityRank = rank
            dataController.reorderProjectPriority(projectId: id, newRank: rank)
        }
    }

    // MARK: Run

    /// A project still has work to auto-schedule: an active, non-deleted task
    /// missing a start or end date. Shared by the run buttons' enable state and
    /// the SCHEDULE NEXT selector so the UI and the engine agree on "schedulable".
    func hasSchedulableTask(_ project: Project) -> Bool {
        project.tasks.contains { $0.deletedAt == nil && $0.status == .active && ($0.startDate == nil || $0.endDate == nil) }
    }

    /// Candidate projects for SCHEDULE ALL — ranked, plus unranked when included.
    private var scheduleAllCandidates: [Project] {
        includeUnranked ? ranked + unranked : ranked
    }

    /// SCHEDULE ALL is live only when some candidate actually has work to place.
    /// (The old `!ranked.isEmpty` check both ignored INCLUDE UNRANKED and let the
    /// button build an empty plan when every ranked task was already scheduled.)
    var canScheduleAll: Bool { scheduleAllCandidates.contains(where: hasSchedulableTask) }

    /// SCHEDULE NEXT is live only when a RANKED project still has work to place.
    var canScheduleNext: Bool { ranked.contains(where: hasSchedulableTask) }

    func buildPlan() {
        let plan = dataController.autoSchedulePriorityProjects(
            orderedProjectIds: scheduleAllCandidates.map(\.id), anchorDate: anchorDate)
        guard !plan.placements.isEmpty else {
            // Nothing landed — don't present an empty review sheet.
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()   // beat 1: plan ready for review
        previewPlan = PlanPreview(plan: plan)
    }

    /// Write each placement via the schedule writer. Returns the number actually
    /// committed (a placement whose task can't be found is skipped, not counted).
    @discardableResult
    private func applyPlacements(_ plan: SchedulePlan) async -> Int {
        // Route through the batched apply: one save, one index recalc per project,
        // one coalesced push, and ONE schedule summary per crew member. The old
        // per-placement updateTaskSchedule loop froze the main thread and flooded
        // the network (a push + per-member notifications PER task).
        await dataController.applySchedulePlan(plan)
    }

    func commit(plan: SchedulePlan) async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()    // beat 1: received
        let committed = await applyPlacements(plan)
        previewPlan = nil
        UINotificationFeedbackGenerator().notificationOccurred(committed > 0 ? .success : .warning)  // beat 2: confirmed
        justScheduledCount = committed
        reload()
    }

    /// One-at-a-time: schedule the top ranked project that still has unscheduled tasks.
    func tapToPlaceNext() async {
        guard let project = ranked.first(where: hasSchedulableTask) else { return }
        let plan = dataController.autoScheduleProjectV2(project.id, anchorDate: anchorDate)
        let committed = await applyPlacements(plan)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if committed > 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            justScheduledCount = committed
        }
        reload()
    }
}
