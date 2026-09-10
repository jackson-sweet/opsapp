import Foundation
import SwiftData

struct PhotoPrefetchPlan: Sendable {
    let warmupURLs: [String]
    let orderedURLs: [String]
}

@ModelActor
actor PhotoPrefetchProjectReader {
    func read(now: Date, warmupProjectCap: Int, warmupPhotoCap: Int) throws -> PhotoPrefetchPlan {
        let projects = try modelContext.fetch(FetchDescriptor<Project>()).filter { $0.deletedAt == nil }
        let warmup = PhotoPrefetchWarmupPlanner.plan(projects: projects, now: now, maxProjects: warmupProjectCap, maxPhotos: warmupPhotoCap)
        let ordered = projects.sorted {
            let lhs = distance($0, now: now), rhs = distance($1, now: now)
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
        var seen = Set<String>()
        let urls = ordered.flatMap { $0.getProjectImages() }.compactMap { raw -> String? in
            let url = raw.hasPrefix("//") ? "https:" + raw : raw
            guard let scheme = URL(string: url)?.scheme, ["https", "http"].contains(scheme.lowercased()), seen.insert(url).inserted else { return nil }
            return url
        }
        return PhotoPrefetchPlan(warmupURLs: warmup.map(\.url), orderedURLs: urls)
    }
    private func distance(_ project: Project, now: Date) -> TimeInterval {
        if let start = project.startDate, let end = project.endDate, start <= now && now <= end { return 0 }
        if let nearest = [project.startDate, project.endDate].compactMap({ $0.map { abs(now.timeIntervalSince($0)) } }).min() { return nearest }
        return 90 * 86_400 + (project.lastSyncedAt.map { abs(now.timeIntervalSince($0)) } ?? .greatestFiniteMagnitude)
    }

    nonisolated static func plan(container: ModelContainer, now: Date, warmupProjectCap: Int, warmupPhotoCap: Int) async throws -> PhotoPrefetchPlan {
        let reader = PhotoPrefetchProjectReader(modelContainer: container)
        return try await reader.read(now: now, warmupProjectCap: warmupProjectCap, warmupPhotoCap: warmupPhotoCap)
    }
}
