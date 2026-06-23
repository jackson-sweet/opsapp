//
//  SharePhotoFinalizer.swift
//  OPS
//
//  Lands share-extension photos that are already on S3 into a project: appends
//  their URLs to projects.project_images (text[]), inserts project_photos rows
//  for the web portal, and posts a completion notification to the uploader.
//
//  Deliberately REST-only (no SwiftData, no @MainActor) so it works when iOS
//  relaunches the app in the BACKGROUND to deliver a background-URLSession
//  completion — at which point the SwiftUI scene (and DataController.modelContext)
//  may not exist. Mirrors the project_photos / project_images contract that
//  ImageSyncManager uses for the in-app "add photos" flow.
//

import Foundation

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
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let photoRows = publicURLs.map { url in
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
        do {
            try await client
                .from("project_photos")
                .insert(photoRows)
                .execute()
        } catch {
            print("[SHARE_FINALIZE] project_photos insert failed for \(projectId): \(error)")
            return false
        }

        // 3) Completion notification to the uploader — confirms the share landed,
        //    deep-links to the project. Best-effort.
        await postCompletionNotification(
            count: publicURLs.count,
            projectId: projectId,
            projectTitle: projectTitle,
            uploadedBy: uploadedBy,
            companyId: companyId
        )
        return true
    }

    private static func postCompletionNotification(
        count: Int,
        projectId: String,
        projectTitle: String,
        uploadedBy: String,
        companyId: String
    ) async {
        guard !uploadedBy.isEmpty, !companyId.isEmpty else { return }
        let title = count == 1 ? "Photo added" : "Photos added"
        let body = count == 1 ? "1 photo on \(projectTitle)" : "\(count) photos on \(projectTitle)"
        do {
            let dto = NotificationRepository.CreateNotificationDTO(
                userId: uploadedBy,
                companyId: companyId,
                type: "photo_uploaded",
                title: title,
                body: body,
                projectId: projectId,
                noteId: nil,
                expenseId: nil,
                batchId: nil,
                deepLinkType: "projectNotes",
                persistent: nil,
                actionUrl: "ops://projects/\(projectId)",
                actionLabel: "View"
            )
            try await NotificationRepository().createNotification(dto)
        } catch {
            print("[SHARE_FINALIZE] completion notification failed for \(projectId): \(error)")
        }
    }
}
