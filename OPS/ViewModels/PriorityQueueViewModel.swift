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
    @Published var previewPlan: SchedulePlan?
    @Published var justScheduledCount: Int?           // set after a batch commit → drives the confirmation overlay

    private let dataController: DataController

    init(dataController: DataController) {
        self.dataController = dataController
        reload()
    }

    /// Load active (non-terminal, non-deleted) projects, split by waterline.
    func reload() {
        let active = dataController.getProjects().filter {
            $0.deletedAt == nil && $0.status != .completed && $0.status != .closed && $0.status != .archived
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

    /// Ordered candidate project ids: ranked, then unranked if included.
    private var orderedCandidateIds: [String] {
        includeUnranked ? (ranked.map(\.id) + unranked.map(\.id)) : ranked.map(\.id)
    }

    func buildPlan() {
        previewPlan = dataController.autoSchedulePriorityProjects(orderedProjectIds: orderedCandidateIds, anchorDate: anchorDate)
    }

    func commit(plan: SchedulePlan) async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let byId = Dictionary(dataController.getAllTasks().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for p in plan.placements {
            guard let task = byId[p.id] else { continue }
            try? await dataController.updateTaskSchedule(task: task, startDate: p.startDate, endDate: p.endDate, manualEdit: false)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        justScheduledCount = plan.placements.count
        previewPlan = nil
        reload()
    }

    /// One-at-a-time: schedule the top ranked project that still has unscheduled tasks.
    func tapToPlaceNext() async {
        guard let project = ranked.first(where: { p in
            p.tasks.contains { $0.deletedAt == nil && $0.status == .active && ($0.startDate == nil || $0.endDate == nil) }
        }) else { return }
        let plan = dataController.autoScheduleProjectV2(project.id, anchorDate: anchorDate)
        let byId = Dictionary(dataController.getAllTasks().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for p in plan.placements {
            guard let task = byId[p.id] else { continue }
            try? await dataController.updateTaskSchedule(task: task, startDate: p.startDate, endDate: p.endDate, manualEdit: false)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        reload()
    }
}
