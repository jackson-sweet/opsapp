//
//  ProjectCacheMerge.swift
//  OPS
//
//  The ONE place an authoritative `projects` row becomes a cached SwiftData
//  `Project`. Realtime pushes land here, and so does the post-commit fetch of
//  a lead conversion.
//
//  Why it exists (bug 4cbf2efe): the conversion service used to map its
//  post-commit DTO with `toModel()` and hand the result straight back. A
//  `toModel()` product is DETACHED — nothing inserts it — so the just-created
//  project existed only inside that one Swift value. Every project-by-id
//  lookup in the app reads SwiftData (`DataController.getProject`), so the won
//  toast's VIEW action opened a sheet with nothing to render, and the delta
//  pull could not repair it either: at `assigned` scope a project with no team
//  members yet never comes back down.
//
//  Two callers, one merge, so field-level write protection (`SyncFieldGuard`)
//  and the `ProjectVinylOrderMarker` sibling row can never drift apart:
//
//    RealtimeProcessor  — websocket row for a project already in scope. Keeps
//                         its own origin-suppression check (an insert that is
//                         really our own write echoing back) before calling in.
//    LeadConversionService — the row the guarded convert RPC just committed.
//                         No suppression: the whole point is to materialize a
//                         project the local store has never seen.
//
//  Field protection is not ceremonial here. MATCHING a lead to an EXISTING
//  project pulls that project's server row over a row the operator may have
//  edited offline minutes ago; the pending write has to survive.
//

import Foundation
import SwiftData

enum ProjectCacheMerge {

    /// Wire-name fields a merge may write. These are Supabase column names
    /// (`SyncOperation.changedFields` speaks wire names, not Swift property
    /// names — bug 209281ba), so protection comparisons must use them too.
    static let mergedFields: [String] = [
        "title", "status", "company_id", "client_id", "opportunity_id",
        "address", "latitude", "longitude",
        "start_date", "end_date", "duration",
        "notes", "description", "all_day",
        "team_member_ids", "project_images", "deleted_at",
    ]

    /// Fields an authoritative row must NOT overwrite: those with a pending OR
    /// recently in-flight local write. Same source of truth the realtime path
    /// has always used.
    static func protectedFields(projectId: String, context: ModelContext) -> Set<String> {
        SyncFieldGuard.protectedFields(from: operations(projectId: projectId, context: context), now: Date())
    }

    /// Strictly-`pending` fields. Used only to decide whether `needsSync` may
    /// be cleared — that must stay keyed to un-pushed work so a completed push
    /// still clears the dirty flag promptly.
    static func hasPendingWrite(projectId: String, context: ModelContext) -> Bool {
        operations(projectId: projectId, context: context).contains { $0.status == "pending" }
    }

    /// Deliberately predicate-free, filtered in Swift.
    ///
    /// A `#Predicate` fetch of `SyncOperation` TRAPS (EXC_BREAKPOINT inside
    /// SwiftData, not a thrown error) against a store whose operation table has
    /// never held a row — reproducible in every fresh in-memory container. An
    /// uncatchable trap is unacceptable here: these callers run immediately
    /// after a conversion COMMITS, and a crash on the hydration read would
    /// leave the operator staring at a relaunch while the server holds a
    /// finished project.
    ///
    /// The cost is bounded and small — this path runs once per conversion and
    /// once per project-sheet hydration, never per realtime event. Realtime,
    /// which fires per websocket row, passes its own precomputed sets to
    /// `apply(dto:context:protectedFields:hasPendingWrite:)` and never touches
    /// this at all.
    private static func operations(projectId: String, context: ModelContext) -> [SyncOperation] {
        let entityTypeRaw = SyncEntityType.project.rawValue
        guard let all = try? context.fetch(FetchDescriptor<SyncOperation>()) else { return [] }
        return all.filter { $0.entityType == entityTypeRaw && $0.entityId == projectId }
    }

    /// Applies an authoritative row over the cached project, inserting it when
    /// absent, and returns the CONTEXT-RESIDENT model — never a detached one.
    /// Saves before returning so a caller on the main context can immediately
    /// query the row it just merged.
    @discardableResult
    static func apply(dto: SupabaseProjectDTO, context: ModelContext) throws -> Project {
        try apply(
            dto: dto,
            context: context,
            protectedFields: protectedFields(projectId: dto.id, context: context),
            hasPendingWrite: hasPendingWrite(projectId: dto.id, context: context)
        )
    }

    /// Protection-set-injected variant. Realtime already computes both sets for
    /// its own suppression logic and passes them straight through rather than
    /// re-running the same two fetches.
    @discardableResult
    static func apply(
        dto: SupabaseProjectDTO,
        context: ModelContext,
        protectedFields: Set<String>,
        hasPendingWrite: Bool
    ) throws -> Project {
        let id = dto.id
        let model = dto.toModel()
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })

        let resolved: Project
        if let existing = try context.fetch(descriptor).first {
            if !protectedFields.contains("title")           { existing.title = model.title }
            if !protectedFields.contains("status")          { existing.status = model.status }
            if !protectedFields.contains("company_id")      { existing.companyId = model.companyId }
            if !protectedFields.contains("client_id")       { existing.clientId = model.clientId }
            if !protectedFields.contains("opportunity_id")  { existing.opportunityId = model.opportunityId }
            if !protectedFields.contains("address")         { existing.address = model.address }
            if !protectedFields.contains("latitude")        { existing.latitude = model.latitude }
            if !protectedFields.contains("longitude")       { existing.longitude = model.longitude }
            if !protectedFields.contains("start_date")      { existing.startDate = model.startDate }
            if !protectedFields.contains("end_date")        { existing.endDate = model.endDate }
            if !protectedFields.contains("duration")        { existing.duration = model.duration }
            if !protectedFields.contains("notes")           { existing.notes = model.notes }
            if !protectedFields.contains("description")     { existing.projectDescription = model.projectDescription }
            if !protectedFields.contains("all_day")         { existing.allDay = model.allDay }
            if !protectedFields.contains("team_member_ids") { existing.teamMemberIdsString = model.teamMemberIdsString }
            if !protectedFields.contains("project_images")  { existing.projectImagesString = model.projectImagesString }
            if !protectedFields.contains("deleted_at")      { existing.deletedAt = model.deletedAt }

            try applyVinylOrderMarker(context: context, dto: dto, protectedFields: protectedFields)

            existing.lastSyncedAt = Date()
            if !hasPendingWrite {
                existing.needsSync = false
            }
            resolved = existing
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)

            let marker = dto.toVinylOrderMarkerModel()
            marker.lastSyncedAt = Date()
            context.insert(marker)
            resolved = model
        }

        try context.save()
        return resolved
    }

    private static func applyVinylOrderMarker(
        context: ModelContext,
        dto: SupabaseProjectDTO,
        protectedFields: Set<String>
    ) throws {
        let projectId = dto.id
        let descriptor = FetchDescriptor<ProjectVinylOrderMarker>(
            predicate: #Predicate { $0.id == projectId }
        )
        let marker: ProjectVinylOrderMarker
        if let existing = try context.fetch(descriptor).first {
            marker = existing
        } else {
            marker = ProjectVinylOrderMarker(projectId: projectId)
            context.insert(marker)
        }

        if !protectedFields.contains(ProjectVinylOrderFields.status) {
            marker.status = dto.resolvedVinylOrderStatus
        }
        if !protectedFields.contains(ProjectVinylOrderFields.orderedAt) {
            marker.orderedAt = dto.vinylOrderedAt.flatMap { SupabaseDate.parse($0) }
        }
        if !protectedFields.contains(ProjectVinylOrderFields.orderedBy) {
            marker.orderedBy = dto.vinylOrderedBy
        }
        if !protectedFields.contains(ProjectVinylOrderFields.color) {
            marker.vinylColor = dto.vinylColor
        }
        if !protectedFields.contains(ProjectVinylOrderFields.po) {
            marker.vinylPO = dto.vinylPO
        }
        marker.sourceProjectUpdatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) }
        marker.lastSyncedAt = Date()
    }
}
