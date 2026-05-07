//
//  TaskMaterialRepository.swift
//  OPS
//
//  Writes resolved cut-list rows to public.task_materials. Used by
//  CutListMaterializer at install-task creation (Phase 11).
//

import Foundation
import Supabase

class TaskMaterialRepository {
    private let client: SupabaseClient

    init() {
        self.client = SupabaseService.shared.client
    }

    /// Bulk insert cut-list rows for one or more project tasks. Idempotent
    /// at the caller level — the materializer is responsible for not
    /// double-emitting rows when re-running.
    func createMaterials(_ rows: [CreateTaskMaterialDTO]) async throws {
        guard !rows.isEmpty else { return }
        try await client
            .from("task_materials")
            .insert(rows)
            .execute()
    }

    /// Fetch existing task_materials for a project task (used to skip
    /// re-emitting when a materializer run is repeated).
    func fetchForTask(_ taskId: String) async throws -> [TaskMaterialDTO] {
        try await client
            .from("task_materials")
            .select()
            .eq("task_id", value: taskId)
            .execute()
            .value
    }
}
