import Foundation
import SwiftData

extension DataActor {
    /// Exactly two scoped reads per refresh. Fetch errors propagate, so a
    /// temporarily unavailable store can never become a false zero rail clear.
    func reviewSnapshot(for request: ReviewSnapshotRequest) throws -> ReviewSnapshot {
        let companyID = request.scope.companyID
        let tasks = try modelContext.fetch(FetchDescriptor<ProjectTask>(predicate: #Predicate {
            $0.companyId == companyID && $0.deletedAt == nil
        }))
        let projects = try modelContext.fetch(FetchDescriptor<Project>(predicate: #Predicate {
            $0.companyId == companyID && $0.deletedAt == nil
        }))
        return ReviewSnapshotCalculator.compute(tasks: tasks, projects: projects, request: request)
    }
}
