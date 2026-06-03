//
//  PriorityQueueViewModel.swift
//  OPS
//
//  Backs the shared PriorityQueueView: the ordered task list, the waterline
//  (ranked above / unranked below), drag-reorder → rank writes, and the
//  schedule runner. Reads/writes priority via DataController; scheduling via
//  the existing AutoScheduleManager entry points.
//

import Foundation
import SwiftUI

@MainActor
final class PriorityQueueViewModel: ObservableObject {
    @Published var ranked: [ProjectTask] = []        // above the waterline, priority order
    @Published var unranked: [ProjectTask] = []      // below the waterline, default order
    @Published var includeUnranked = false
    @Published var rescheduleScheduled = false
    @Published var anchorDate = Date()
    @Published var previewPlan: SchedulePlan?         // non-nil → present preview
    @Published var pendingConfirmCount = 0           // scheduled tasks a run would move
    @Published var justScheduledCount: Int?           // set after a batch commit → drives the confirmation overlay

    private let dataController: DataController

    init(dataController: DataController) {
        self.dataController = dataController
        reload()
    }

    /// Load all active company tasks, split by waterline.
    func reload() {
        let active = dataController.getAllTasks().filter { $0.status == .active && $0.deletedAt == nil }
        ranked = active.filter { $0.priorityRank != nil }.sorted { lhs, rhs in
            let lr = lhs.priorityRank ?? 0, rr = rhs.priorityRank ?? 0
            return lr == rr ? lhs.id < rhs.id : lr < rr
        }
        unranked = active.filter { $0.priorityRank == nil }.sorted { ($0.lastSyncedAt ?? .distantPast) > ($1.lastSyncedAt ?? .distantPast) }
    }

    // MARK: Reorder

    /// Move a task within the ranked zone to `index` and persist a fractional rank.
    func moveRanked(taskId: String, to index: Int) {
        guard let current = ranked.firstIndex(where: { $0.id == taskId }) else { return }
        var working = ranked
        let task = working.remove(at: current)
        let clamped = min(max(index, 0), working.count)
        working.insert(task, at: clamped)
        ranked = working
        persistRank(forIndex: clamped, in: working)
    }

    /// Pull an unranked task above the waterline at `index`.
    func rank(taskId: String, at index: Int) {
        guard let task = unranked.first(where: { $0.id == taskId }) else { return }
        unranked.removeAll { $0.id == taskId }
        let clamped = min(max(index, 0), ranked.count)
        ranked.insert(task, at: clamped)
        persistRank(forIndex: clamped, in: ranked)
    }

    /// Drop a ranked task below the waterline (unrank).
    func unrank(taskId: String) {
        guard let task = ranked.first(where: { $0.id == taskId }) else { return }
        ranked.removeAll { $0.id == taskId }
        unranked.insert(task, at: 0)
        dataController.reorderPriority(taskId: taskId, newRank: nil)
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
        for t in newUnranked { ranks[t.id] = Double?.none }
        dataController.bulkSetPriority(ranks)
    }

    /// Assign a fractional rank to the task now at `index` in `list`, normalizing if tight.
    private func persistRank(forIndex index: Int, in list: [ProjectTask]) {
        let id = list[index].id
        let lower = index > 0 ? list[index - 1].priorityRank : nil
        let upper = index < list.count - 1 ? list[index + 1].priorityRank : nil
        if let l = lower, let u = upper, FractionalRank.needsNormalization(between: l, and: u) {
            let normalized = FractionalRank.normalize(orderedIds: list.map(\.id))
            var ranks: [String: Double?] = [:]
            for (k, v) in normalized { ranks[k] = v }
            dataController.bulkSetPriority(ranks)
            for t in list { t.priorityRank = normalized[t.id] }
        } else {
            let rank = FractionalRank.between(lower, upper)
            list[index].priorityRank = rank
            dataController.reorderPriority(taskId: id, newRank: rank)
        }
    }

    // MARK: Run

    /// Count already-scheduled, unlocked tasks a run would move (for the confirm dialog).
    func scheduledMoveCount() -> Int {
        let scope = rescheduleScheduled ? (ranked + (includeUnranked ? unranked : [])) : []
        return scope.filter { $0.startDate != nil && !$0.scheduleLocked }.count
    }

    /// Build the batch plan (Schedule All).
    func buildPlan() {
        previewPlan = dataController.autoSchedulePriorityQueue(
            orderedTaskIds: ranked.map(\.id), includeUnranked: includeUnranked, anchorDate: anchorDate)
    }

    /// Commit a built plan: write each placement via the existing schedule writer.
    func commit(plan: SchedulePlan) async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()   // beat 1: received
        let byId = Dictionary(dataController.getAllTasks().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for p in plan.placements {
            guard let task = byId[p.id] else { continue }
            try? await dataController.updateTaskSchedule(task: task, startDate: p.startDate, endDate: p.endDate, manualEdit: false)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)   // beat 2: confirmed
        justScheduledCount = plan.placements.count
        previewPlan = nil
        reload()
    }

    /// One-at-a-time: schedule the top unscheduled ranked task immediately.
    func tapToPlaceNext() async {
        guard let task = ranked.first(where: { $0.startDate == nil }) else { return }
        let plan = dataController.autoScheduleSingleTask(task, teamMemberIds: Set(task.getTeamMemberIds()), anchorDate: anchorDate)
        if let p = plan.placements.first {
            try? await dataController.updateTaskSchedule(task: task, startDate: p.startDate, endDate: p.endDate, manualEdit: false)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        reload()
    }
}
