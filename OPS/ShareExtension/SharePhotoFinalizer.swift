//
//  SharePhotoFinalizer.swift
//  OPS
//
//  Lands share-extension photos that are already on S3 into a project: appends
//  their URLs to projects.project_images (text[]), inserts project_photos rows
//  for the web portal, and posts a completion notification to the uploader via
//  the narrow `notify_share_photos_finalized` RPC (the server derives the
//  recipient, the project title, and the copy).
//
//  Deliberately REST-only (no SwiftData, no @MainActor) so it works when iOS
//  relaunches the app in the BACKGROUND to deliver a background-URLSession
//  completion — at which point the SwiftUI scene (and DataController.modelContext)
//  may not exist. Mirrors the project_photos / project_images contract that
//  ImageSyncManager uses for the in-app "add photos" flow.
//

import Foundation

/// Seam for the share-completion rail row. Conformed to by
/// `NotificationRepository` (the `notify_share_photos_finalized` RPC); tests
/// substitute a spy.
protocol SharePhotoFinalizeNotifying {
    /// Returns the server's verdict for the row it created.
    @discardableResult
    func notifySharePhotosFinalized(projectId: String, photoCount: Int) async throws -> String
}

extension NotificationRepository: SharePhotoFinalizeNotifying {}

enum SharePhotoFinalizer {

    private struct ProjectImagesRow: Decodable {
        let project_images: [String]?
    }

    private struct ProjectPhotoInsert: Encodable {
        let project_id: String
        let company_id: String
        let url: String
        let source: String
        let uploaded_by: String
        let is_client_visible: Bool
        let taken_at: String
    }

    /// Finalizes a batch of already-uploaded photo URLs for one project. Returns
    /// true when the durable writes (project_images + project_photos) succeed, so
    /// the caller can clear the jobs. The notification is best-effort.
    ///
    /// `projectTitle` no longer feeds the notification — the RPC reads the title
    /// off the project row server-side — but it stays on the signature because
    /// the queued-job manifest carries it and the caller passes it through.
    static func finalize(
        publicURLs: [String],
        projectId: String,
        companyId: String,
        projectTitle: String,
        uploadedBy: String
    ) async -> Bool {
        guard !publicURLs.isEmpty else { return true }
        let client = SupabaseService.shared.client

        // 1) Append to projects.project_images (read-modify-write, dedup by URL).
        do {
            let rows: [ProjectImagesRow] = try await client
                .from("projects")
                .select("project_images")
                .eq("id", value: projectId)
                .limit(1)
                .execute()
                .value
            var current = rows.first?.project_images ?? []
            let fresh = publicURLs.filter { !current.contains($0) }
            if !fresh.isEmpty {
                current.append(contentsOf: fresh)
                try await client
                    .from("projects")
                    .update(["project_images": current])
                    .eq("id", value: projectId)
                    .execute()
            }
        } catch {
            print("[SHARE_FINALIZE] project_images update failed for \(projectId): \(error)")
            return false
        }

        // 2) Mirror into project_photos so the web portal renders them. Source
        //    "in_progress" matches the in-app gallery add (the photo_source enum
        //    has no share-specific label, and the semantics are identical).
        //    Idempotent: skip URLs already present so a finalize retry (same URL)
        //    can't insert a duplicate row.
        struct URLRow: Decodable { let url: String }
        var existingPhotoURLs: Set<String> = []
        do {
            let rows: [URLRow] = try await client
                .from("project_photos")
                .select("url")
                .eq("project_id", value: projectId)
                .execute()
                .value
            existingPhotoURLs = Set(rows.map { $0.url })
        } catch {
            // Existence check failed — fall through and insert; a rare duplicate
            // portal row is better than a missing one.
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let photoRows = publicURLs
            .filter { !existingPhotoURLs.contains($0) }
            .map { url in
                ProjectPhotoInsert(
                    project_id: projectId,
                    company_id: companyId,
                    url: url,
                    source: "in_progress",
                    uploaded_by: uploadedBy,
                    is_client_visible: false,
                    taken_at: timestamp
                )
            }
        if !photoRows.isEmpty {
            do {
                try await client
                    .from("project_photos")
                    .insert(photoRows)
                    .execute()
            } catch {
                print("[SHARE_FINALIZE] project_photos insert failed for \(projectId): \(error)")
                return false
            }
        }

        // 3) Completion notification to the uploader — confirms the share landed,
        //    deep-links to the project. Best-effort.
        await postCompletionNotification(
            count: publicURLs.count,
            projectId: projectId,
            uploadedBy: uploadedBy,
            companyId: companyId
        )
        return true
    }

    /// Internal (not private) so the notification seam can be exercised with a
    /// spy syncer.
    ///
    /// The RPC derives the recipient (the calling operator, i.e. the uploader),
    /// the project title, and the rendered copy from server rows — none of that
    /// travels from here. `uploadedBy` / `companyId` are therefore not payload
    /// but a precondition: an empty identity means there is no authenticated
    /// share context to attribute the row to, so skip the call entirely.
    static func postCompletionNotification(
        count: Int,
        projectId: String,
        uploadedBy: String,
        companyId: String,
        syncer: SharePhotoFinalizeNotifying = NotificationRepository()
    ) async {
        guard !uploadedBy.isEmpty, !companyId.isEmpty else { return }
        do {
            let action = try await syncer.notifySharePhotosFinalized(
                projectId: projectId,
                photoCount: count
            )
            print("[SHARE_FINALIZE] completion notification \(action) for \(projectId)")
        } catch {
            print("[SHARE_FINALIZE] completion notification failed for \(projectId): \(error)")
        }
    }
}
