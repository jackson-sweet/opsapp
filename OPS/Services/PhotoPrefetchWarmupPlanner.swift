//
//  PhotoPrefetchWarmupPlanner.swift
//  OPS
//

import Foundation

struct PhotoPrefetchWarmupCandidate: Equatable {
    let projectId: String
    let url: String
}

enum PhotoPrefetchWarmupPlanner {

    static func plan(
        projects: [Project],
        now: Date = Date(),
        maxProjects: Int,
        maxPhotos: Int
    ) -> [PhotoPrefetchWarmupCandidate] {
        guard maxProjects > 0, maxPhotos > 0 else { return [] }

        let ordered = projects
            .filter { $0.deletedAt == nil }
            .map { project in
                (project: project, score: score(project, now: now))
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                return lhs.project.title.localizedCaseInsensitiveCompare(rhs.project.title) == .orderedAscending
            }

        var selectedProjects = 0
        var selectedPhotos = 0
        var candidates: [PhotoPrefetchWarmupCandidate] = []

        for entry in ordered {
            guard selectedProjects < maxProjects, selectedPhotos < maxPhotos else { break }

            let remoteURLs = entry.project.getProjectImages().filter(isRemotePhotoURL)
            guard !remoteURLs.isEmpty else { continue }

            selectedProjects += 1
            for url in remoteURLs {
                guard selectedPhotos < maxPhotos else { break }
                candidates.append(PhotoPrefetchWarmupCandidate(projectId: entry.project.id, url: url))
                selectedPhotos += 1
            }
        }

        return candidates
    }

    private static func score(_ project: Project, now: Date) -> TimeInterval {
        var penalty: TimeInterval = 0
        if project.status == .archived || project.status == .closed {
            penalty += 365 * 86_400
        }

        if let start = project.startDate, let end = project.endDate,
           start <= now && now <= end {
            return penalty
        }

        let startDistance = project.startDate.map { abs(now.timeIntervalSince($0)) }
        let endDistance = project.endDate.map { abs(now.timeIntervalSince($0)) }
        if let nearest = [startDistance, endDistance].compactMap({ $0 }).min() {
            return penalty + nearest
        }

        let undatedPenalty: TimeInterval = 90 * 86_400
        let syncDistance = project.lastSyncedAt.map { abs(now.timeIntervalSince($0)) } ?? .greatestFiniteMagnitude
        return penalty + undatedPenalty + syncDistance
    }

    private static func isRemotePhotoURL(_ url: String) -> Bool {
        url.contains("://") || url.hasPrefix("//")
    }
}
