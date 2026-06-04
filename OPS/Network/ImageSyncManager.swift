//
//  ImageSyncManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI
import SwiftData
import Foundation
import Network

/// Manager for handling image synchronization between local storage, S3, and Supabase
@MainActor
class ImageSyncManager: ObservableObject {
    // Dependencies
    private let modelContext: ModelContext?
    private let connectivity: ConnectivityManager
    private let presignedURLService = PresignedURLUploadService.shared

    // In-memory queue of pending image uploads
    private var pendingUploads: [PendingImageUpload] = []

    // Current sync state
    @Published private var isSyncing = false

    // Progress tracking
    @Published var syncProgress: Double = 0
    @Published var syncingProjectId: String? = nil

    /// Bug e5310f3d — published map of in-flight uploads keyed by project
    /// id. The carousel observes this so each newly added photo appears
    /// immediately as a placeholder card with a spinner that resolves
    /// once S3 returns the public URL.
    @Published var inFlightUploads: [String: [InFlightUpload]] = [:]

    /// Bug b171536b — periodic retry timer for the pending-upload queue.
    /// `connectivityChanged` only fires on a binary connected/disconnected
    /// edge, but a weak-connection upload that silently times out at the
    /// HTTP layer never causes that edge — so the queued image would sit
    /// untouched until the next app launch. This timer kicks in whenever
    /// the queue is non-empty and retries every 30 seconds, regardless of
    /// the connectivity state vector. Stops itself once the queue drains.
    private var retryTimer: Timer?
    private static let retryInterval: TimeInterval = 30

    /// Initialize the ImageSyncManager with required dependencies
    init(modelContext: ModelContext?, connectivity: ConnectivityManager) {
        self.modelContext = modelContext
        self.connectivity = connectivity

        // Clean up UserDefaults bloat first
        cleanupUserDefaultsImageData()

        // Load any pending uploads from UserDefaults
        loadPendingUploads()

        // Set up connectivity change notifications
        setupConnectivityObserver()

        // If we're already connected and have pending uploads, try to sync them
        if connectivity.isConnected && !pendingUploads.isEmpty {
            Task {
                // Small delay to ensure everything is initialized
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await syncPendingImages()
            }
        }

        // Bug b171536b — if a previous session left items in the queue,
        // keep the periodic retry running so they get a fair shake even
        // without a connectivity edge.
        startRetryTimerIfNeeded()
    }

    /// Setup observer for connectivity changes to trigger syncs when coming online
    private func setupConnectivityObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectivityChanged),
            name: ConnectivityManager.connectivityChangedNotification,
            object: nil
        )
    }

    @objc private func connectivityChanged() {
        if connectivity.isConnected {
            Task {
                await syncPendingImages()
            }
        }
    }
    
    /// Save images using S3 and update Supabase
    func saveImages(_ images: [UIImage], for project: Project, notifyCrew: Bool = true) async -> [String] {
        let companyId = project.companyId
        guard !companyId.isEmpty else {
            return []
        }

        // Bug e5310f3d — surface in-flight uploads to the UI immediately
        // so the carousel can show placeholder cards with loaders. Each
        // pending upload carries a UIImage we can render right away while
        // the bytes climb to S3.
        //
        // Auto-bug-reporting (May-12 follow-up): only `endInFlightUploads`
        // when we know the upload settled cleanly. If a permanent error
        // hits, we flip the tile to failed state and KEEP it in the map so
        // the user sees the red badge instead of a silent disappearance.
        let placeholders = beginInFlightUploads(images, for: project)
        let placeholderIds = placeholders.map { $0.id }
        var savedURLs: [String] = []
        var tilesShouldRemainAsFailed = false

        defer {
            // Only clear tiles that did NOT end up in the failed state.
            if !tilesShouldRemainAsFailed {
                endInFlightUploads(placeholderIds, for: project.id)
            }
        }

        if connectivity.isConnected {
            do {
                // Upload to S3 via presigned URLs
                let s3Results = try await presignedURLService.uploadProjectImages(images, for: project, companyId: companyId)

                savedURLs = s3Results.map { $0.url }

                // Update project with new image URLs
                var currentImages = project.getProjectImages()
                currentImages.append(contentsOf: savedURLs)

                project.setProjectImageURLs(currentImages)

                // Update Supabase directly with new image URLs
                try await SupabaseService.shared.client
                    .from("projects")
                    .update(["project_images": currentImages])
                    .eq("id", value: project.id)
                    .execute()

                // Bug 7b43be32 + May-12 follow-up — also insert one
                // project_photos row per URL so the web client portal can
                // see them. The May-12 outage came from RLS rejecting this
                // insert; insertProjectPhotoRows now auto-bugs + returns
                // false so we can flip the tile to failed and surface the
                // portal-sync failure even though S3+projects succeeded.
                let uploaderId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
                let portalMirrorSucceeded = await insertProjectPhotoRows(
                    urls: savedURLs,
                    projectId: project.id,
                    companyId: companyId,
                    uploadedBy: uploaderId,
                    source: "in_progress"
                )

                if !portalMirrorSucceeded {
                    markInFlightUploadsFailed(
                        ids: placeholderIds,
                        for: project.id,
                        lastError: "Portal sync failed — photo saved locally but not yet visible in the client portal."
                    )
                    tilesShouldRemainAsFailed = true
                }

                // Notify assigned crew that new photos landed on the project.
                // Gallery "add photos" actions notify; the note-attachment path
                // passes notifyCrew:false so a photo-bearing note doesn't fire a
                // second notification. Best-effort, and the uploader is excluded.
                if notifyCrew && portalMirrorSucceeded {
                    notifyCrewOfAddedPhotos(
                        project: project,
                        uploaderId: uploaderId,
                        photoCount: savedURLs.count,
                        firstURL: savedURLs.first
                    )
                }

                // Images uploaded to S3 and Supabase updated — no further sync needed
                project.needsSync = false
                project.lastSyncedAt = Date()

                if let modelContext = modelContext {
                    try? modelContext.save()
                }

            } catch {
                // Classify before falling through. Permanent errors here
                // mean the projects row update or S3 upload itself was
                // rejected — auto-bug + surface red badge. Transient is
                // the normal offline-fallback path (save locally, drain
                // later via syncPendingImages).
                let kind = UploadErrorClassifier.classify(error)
                if case .permanent(let code, let reason) = kind {
                    await AutoBugReporter.shared.report(
                        screen: "ImageSyncManager.saveImages",
                        suspectedFile: "ImageSyncManager.swift",
                        errorCode: code,
                        summary: "saveImages permanent failure for project \(project.id): \(reason)",
                        metadata: [
                            "project_id": project.id,
                            "image_count": images.count
                        ]
                    )
                    markInFlightUploadsFailed(
                        ids: placeholderIds,
                        for: project.id,
                        lastError: "Upload rejected by server — \(reason). Tap to retry."
                    )
                    tilesShouldRemainAsFailed = true
                } else {
                    // Transient (or unknown) — fall back to local save so
                    // the periodic retry timer picks it up later.
                    DebugLogger.shared.log(
                        "saveImages transient/unknown failure (\(kind)) for \(project.id): \(error)",
                        level: .warning,
                        category: "ImageSyncManager"
                    )
                    for (index, image) in images.enumerated() {
                        if let localURL = await saveImageLocally(image, for: project, index: index) {
                            savedURLs.append(localURL)
                        }
                    }
                }
            }
        } else {
            // Offline - save locally
            for (index, image) in images.enumerated() {
                if let localURL = await saveImageLocally(image, for: project, index: index) {
                    savedURLs.append(localURL)
                }
            }
        }

        return savedURLs
    }

    /// Fire the "photos added" notification to assigned crew. Resolves the
    /// recipient list + uploader name on the main actor (cheap local reads),
    /// then performs the in-app + push writes in a task so the upload return
    /// isn't blocked. Best-effort — failures log only and never affect the
    /// upload result.
    private func notifyCrewOfAddedPhotos(project: Project, uploaderId: String, photoCount: Int, firstURL: String?) {
        guard photoCount > 0 else { return }
        let recipientIds = project.getTeamMemberIds().filter { $0 != uploaderId && !$0.isEmpty }
        guard !recipientIds.isEmpty else { return }
        let companyId = project.companyId
        guard !companyId.isEmpty else { return }
        let projectId = project.id
        let projectTitle = project.title

        // Resolve the uploader's display name from the local roster.
        let uploaderName: String = {
            guard let context = modelContext, !uploaderId.isEmpty else { return "A teammate" }
            let descriptor = FetchDescriptor<TeamMember>(predicate: #Predicate { $0.id == uploaderId })
            return (try? context.fetch(descriptor).first?.fullName) ?? "A teammate"
        }()

        let title = photoCount == 1 ? "\(uploaderName) added a photo" : "\(uploaderName) added photos"
        let body = photoCount == 1 ? "1 photo on \(projectTitle)" : "\(photoCount) photos on \(projectTitle)"

        Task {
            let notificationRepo = NotificationRepository()
            for recipientId in recipientIds {
                do {
                    let dto = NotificationRepository.CreateNotificationDTO(
                        userId: recipientId,
                        companyId: companyId,
                        type: "photo_uploaded",
                        title: title,
                        body: body,
                        projectId: projectId,
                        noteId: nil,
                        expenseId: nil,
                        batchId: nil,
                        deepLinkType: "projectNotes"
                    )
                    try await notificationRepo.createNotification(dto)
                } catch {
                    print("[IMAGE_SYNC] Failed to create in-app photos-added notification for \(recipientId): \(error)")
                }
            }
            do {
                try await OneSignalService.shared.notifyPhotosAdded(
                    userIds: recipientIds,
                    uploaderName: uploaderName,
                    photoCount: photoCount,
                    projectName: projectTitle,
                    projectId: projectId,
                    imageUrl: firstURL
                )
            } catch {
                print("[IMAGE_SYNC] Failed to send photos-added push: \(error)")
            }
        }
    }

    /// Bug 7b43be32 — insert a project_photos row for each newly uploaded
    /// URL so the web client portal can render the photo. Best-effort: a
    /// failure here doesn't block the upload (the file is already in S3
    /// and on the project row), it just means the photo won't appear in
    /// the portal until the next reconciliation pass. We default
    /// `is_client_visible` to false to match the column default; the crew
    /// opts each photo in via the per-photo toggle.
    ///
    /// Returns whether the insert succeeded so the caller can drive the
    /// in-flight tile state (May-12 follow-up).
    @discardableResult
    private func insertProjectPhotoRows(
        urls: [String],
        projectId: String,
        companyId: String,
        uploadedBy: String,
        source: String
    ) async -> Bool {
        guard !urls.isEmpty else { return true }

        struct ProjectPhotoInsert: Codable {
            let project_id: String
            let company_id: String
            let url: String
            let source: String
            let uploaded_by: String
            let is_client_visible: Bool
            let taken_at: String
        }

        // Single ISO8601 timestamp for the whole batch keeps the rows
        // grouped chronologically without needing to invent per-photo EXIF.
        let timestamp = ISO8601DateFormatter().string(from: Date())

        let rows = urls.map { url in
            ProjectPhotoInsert(
                project_id: projectId,
                company_id: companyId,
                url: url,
                source: source,
                uploaded_by: uploadedBy,
                is_client_visible: false,
                taken_at: timestamp
            )
        }

        do {
            try await SupabaseService.shared.client
                .from("project_photos")
                .insert(rows)
                .execute()
            return true
        } catch {
            // May-12 outage site. Was: `print(error)` and continue silently,
            // which let an RLS tightening on project_photos.INSERT swallow
            // 3 days of Crew/Unassigned uploads with zero signal. Now:
            // classify, auto-bug if permanent, return false so the carousel
            // can render a failed tile.
            let kind = await AutoBugReporter.shared.reportIfPermanent(
                error,
                screen: "ImageSyncManager.insertProjectPhotoRows",
                suspectedFile: "ImageSyncManager.swift",
                summary: "project_photos INSERT failed for project \(projectId): \(error.localizedDescription)",
                metadata: [
                    "project_id": projectId,
                    "company_id": companyId,
                    "url_count": urls.count,
                    "source": source
                ]
            )
            DebugLogger.shared.log(
                "project_photos insert failed (\(kind)) for \(projectId): \(error)",
                level: .error,
                category: "ImageSyncManager"
            )
            return false
        }
    }

    /// Bug 7b43be32 — flip a single photo's portal visibility on the
    /// server. The local model write is the caller's responsibility (they
    /// already have a project handle and want the UI to update on tap).
    /// Best-effort write: an error logs but does not surface to the user
    /// because the local UI has already moved.
    func setPhotoClientVisibility(url: String, isVisible: Bool, projectId: String) async throws {
        struct ProjectPhotoVisibilityUpdate: Codable {
            let is_client_visible: Bool
        }

        try await SupabaseService.shared.client
            .from("project_photos")
            .update(ProjectPhotoVisibilityUpdate(is_client_visible: isVisible))
            .eq("project_id", value: projectId)
            .eq("url", value: url)
            .execute()
    }

    /// Bug 7b43be32 — pull the live client-visibility set for a project
    /// from Supabase and hydrate `Project.clientVisibleImagesString` so
    /// the per-photo toggle reflects what the customer actually sees in
    /// the portal. Runs on project detail open. Best-effort: a network
    /// failure leaves the existing local values in place rather than
    /// emptying them.
    func refreshClientVisibility(for project: Project) async {
        struct VisibilityRow: Decodable {
            let url: String
            let is_client_visible: Bool
        }

        do {
            let rows: [VisibilityRow] = try await SupabaseService.shared.client
                .from("project_photos")
                .select("url, is_client_visible")
                .eq("project_id", value: project.id)
                .is("deleted_at", value: nil)
                .execute()
                .value

            let visibleURLs = rows.filter { $0.is_client_visible }.map { $0.url }
            project.setClientVisibleImages(visibleURLs)
            try? modelContext?.save()
        } catch {
            print("[IMAGE_SYNC] Failed to refresh client visibility for \(project.id): \(error)")
        }
    }
    
    /// Save a single image locally for offline use
    private func saveImageLocally(_ image: UIImage, for project: Project, index: Int) async -> String? {
        // Resize image if it's too large
        let resizedImage = resizeImageIfNeeded(image)

        // Use adaptive compression based on image size
        let compressionQuality = getAdaptiveCompressionQuality(for: resizedImage)

        guard let imageData = resizedImage.jpegData(compressionQuality: compressionQuality) else {
            return nil
        }

        // Log image size
        let sizeInMB = Double(imageData.count) / (1024 * 1024)

        let timestamp = Date().timeIntervalSince1970
        let filename = "local_project_\(project.id)_\(timestamp)_\(index).jpg"
        let localURL = "local://project_images/\(filename)"

        // Store the image in file system
        let success = ImageFileManager.shared.saveImage(data: imageData, localID: localURL)
        if success {

            // Create pending upload
            let pendingUpload = PendingImageUpload(
                localURL: localURL,
                projectId: project.id,
                companyId: project.companyId,
                timestamp: Date()

            )

            // Add to pending uploads
            pendingUploads.append(pendingUpload)
            savePendingUploads()

            // Mark the image as unsynced in the project
            project.addUnsyncedImage(localURL)

            // Bug b171536b — also append the local URL to the project's
            // visible image list so the carousel renders the photo
            // immediately, even when the upload's still queued. Local
            // URLs render via ImageFileManager, and `syncImagesForProject`
            // swaps each local URL out for the S3 URL once the upload
            // succeeds, so the substitution is invisible to the user.
            // Without this, a weak-connection failure left the photo
            // saved on disk but missing from the UI — making the user
            // think the upload had silently dropped it.
            var currentImages = project.getProjectImages()
            if !currentImages.contains(localURL) {
                currentImages.append(localURL)
                project.setProjectImageURLs(currentImages)
            }

            // Bug b171536b — kick the periodic retry timer so the queue
            // gets reattempted even if connectivity never toggles.
            startRetryTimerIfNeeded()

            return localURL
        }

        return nil
    }

    // MARK: - Periodic Retry Timer (Bug b171536b)

    private func startRetryTimerIfNeeded() {
        guard retryTimer == nil, !pendingUploads.isEmpty else { return }
        retryTimer = Timer.scheduledTimer(
            withTimeInterval: Self.retryInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.pendingUploads.isEmpty {
                    self.stopRetryTimer()
                    return
                }
                if self.connectivity.isConnected {
                    await self.syncPendingImages()
                }
                if self.pendingUploads.isEmpty {
                    self.stopRetryTimer()
                }
            }
        }
    }

    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }
    
    /// Delete an image from S3 and locally
    func deleteImage(_ urlString: String, from project: Project) async -> Bool {
        // Check if it's a local URL
        if urlString.starts(with: "local://") {
            _ = ImageFileManager.shared.deleteImage(localID: urlString)
            pendingUploads.removeAll { $0.localURL == urlString }
            savePendingUploads()
            return true
        }

        // If it's an S3 URL, remove from local cache
        if urlString.contains("s3") && urlString.contains("amazonaws.com") {
            _ = ImageFileManager.shared.deleteImage(localID: urlString)
            return true
        }

        // Handle legacy URLs
        if urlString.contains("opsapp.co/") && urlString.contains("/img/") {
            ImageFileManager.shared.deleteImage(localID: urlString)
            return true
        }

        return false
    }

    /// Sync all pending images to S3 and Supabase
    func syncPendingImages() async {
        
        guard !isSyncing, connectivity.isConnected else { 
            if isSyncing {
            }
            if !connectivity.isConnected {
            }
            return 
        }
        
        if pendingUploads.isEmpty {
            return
        }
        
        isSyncing = true
        
        // Group by project for batch uploading
        var uploadsByProject: [String: [PendingImageUpload]] = [:]
        for upload in pendingUploads {
            if uploadsByProject[upload.projectId] == nil {
                uploadsByProject[upload.projectId] = []
            }
            uploadsByProject[upload.projectId]?.append(upload)
        }
        
        
        // Process each project's uploads
        for (projectId, uploads) in uploadsByProject {
            await syncImagesForProject(projectId: projectId, uploads: uploads)
        }
        
        isSyncing = false
    }
    
    /// Sync images for a specific project
    private func syncImagesForProject(projectId: String, uploads: [PendingImageUpload]) async {
        guard let project = getProject(by: projectId) else {
            return
        }

        let companyId = project.companyId
        guard !companyId.isEmpty else {
            return
        }

        // Convert pending uploads to UIImages
        let images = uploads.compactMap { upload in
            if let imageData = ImageFileManager.shared.getImageData(localID: upload.localURL) {
                return UIImage(data: imageData)
            }
            return upload.originalImage
        }

        guard !images.isEmpty else {
            return
        }

        do {
            // Upload to S3 via presigned URLs
            let s3Results = try await presignedURLService.uploadProjectImages(images, for: project, companyId: companyId)

            // Success - update project with S3 URLs
            var currentImages = project.getProjectImages()

            // Replace local URLs with S3 URLs
            for (index, upload) in uploads.enumerated() {
                if let localIndex = currentImages.firstIndex(of: upload.localURL),
                   index < s3Results.count {
                    currentImages[localIndex] = s3Results[index].url
                    project.markImageAsSynced(upload.localURL)
                }
            }

            project.setProjectImageURLs(currentImages)

            // Update Supabase directly
            try await SupabaseService.shared.client
                .from("projects")
                .update(["project_images": currentImages])
                .eq("id", value: project.id)
                .execute()

            // Bug 7b43be32 — also write project_photos rows for each newly
            // synced URL so the web client portal sees them. Mirrors the
            // online-path insert in saveImages.
            let uploaderId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
            await insertProjectPhotoRows(
                urls: s3Results.map { $0.url },
                projectId: project.id,
                companyId: companyId,
                uploadedBy: uploaderId,
                source: "in_progress"
            )

            // Images uploaded to S3 and Supabase updated — no further sync needed
            project.needsSync = false
            project.lastSyncedAt = Date()

            // Remove from pending uploads
            pendingUploads.removeAll { upload in
                uploads.contains { $0.localURL == upload.localURL }
            }
            savePendingUploads()

            if let modelContext = modelContext {
                try? modelContext.save()
            }

            // Bug b171536b — drop the periodic retry timer once the
            // queue is empty so we're not waking up the runloop every
            // 30s for nothing.
            if pendingUploads.isEmpty {
                stopRetryTimer()
            }

        } catch {
            // Bug b171536b — keep the queue intact and ensure the retry
            // timer is alive so the next pass fires automatically. Weak
            // connections often need several tries.
            //
            // Auto-bug-reporting (May-12 follow-up): classify before
            // retrying. A permanent rejection (RLS 42501, 4xx) will keep
            // failing forever on the same poisoned item — auto-bug AND
            // drop the offending uploads from the queue so we don't burn
            // the retry timer on a rejection the server will never accept.
            // Transient errors stay queued for the next pass.
            let kind = UploadErrorClassifier.classify(error)
            if case .permanent(let code, let reason) = kind {
                await AutoBugReporter.shared.report(
                    screen: "ImageSyncManager.syncImagesForProject",
                    suspectedFile: "ImageSyncManager.swift",
                    errorCode: code,
                    summary: "Offline-drain permanent failure for project \(projectId): \(reason)",
                    metadata: [
                        "project_id": projectId,
                        "queued_count": uploads.count
                    ]
                )
                // Drop the poisoned items — the retry loop would otherwise
                // hit the same rejection every 30s forever.
                pendingUploads.removeAll { upload in
                    uploads.contains { $0.localURL == upload.localURL }
                }
                savePendingUploads()
            } else {
                DebugLogger.shared.log(
                    "syncImagesForProject transient/unknown failure (\(kind)) for \(projectId): \(error)",
                    level: .warning,
                    category: "ImageSyncManager"
                )
            }
            startRetryTimerIfNeeded()
        }
    }
    
    /// Helper to get project by ID
    private func getProject(by id: String) -> Project? {
        guard let modelContext = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.id == id }
            )
            let projects = try modelContext.fetch(descriptor)
            return projects.first
        } catch {
            return nil
        }
    }
    
    /// Helper to load pending uploads from UserDefaults
    private func loadPendingUploads() {
        if let data = UserDefaults.standard.data(forKey: "pendingImageUploads"),
           let uploads = try? JSONDecoder().decode([PendingImageUpload].self, from: data) {
            pendingUploads = uploads
        }
    }
    
    /// Helper to save pending uploads to UserDefaults
    private func savePendingUploads() {
        if let data = try? JSONEncoder().encode(pendingUploads) {
            UserDefaults.standard.set(data, forKey: "pendingImageUploads")
        }
    }
    
    /// Clean up UserDefaults from image data bloat
    private func cleanupUserDefaultsImageData() {
        
        let defaults = UserDefaults.standard
        var removedCount = 0
        var totalSizeSaved = 0
        
        // Get all keys
        let dictionaryRepresentation = defaults.dictionaryRepresentation()
        
        for (key, value) in dictionaryRepresentation {
            // Remove image URL keys (these contain base64 image data)
            if key.contains("https://") && (key.contains(".jpeg") || key.contains(".jpg") || key.contains(".png")) {
                if let data = value as? Data {
                    totalSizeSaved += data.count
                } else if let string = value as? String {
                    totalSizeSaved += string.count
                }
                defaults.removeObject(forKey: key)
                removedCount += 1
            }
        }
        
    }
    
    // MARK: - Public Methods for Progress Tracking
    
    /// Clear all pending image syncs
    func clearAllPendingUploads() {
        
        // Clear from memory
        let count = pendingUploads.count
        pendingUploads.removeAll()
        
        // Clear from UserDefaults
        UserDefaults.standard.removeObject(forKey: "pendingImageUploads")
        
        // Reset sync state
        isSyncing = false
        syncProgress = 0
        syncingProjectId = nil
        
    }
    
    /// Get current pending uploads
    func getPendingUploads() -> [PendingImageUpload] {
        return pendingUploads
    }
    
    /// Check if there are pending uploads
    var hasPendingUploads: Bool {
        return !pendingUploads.isEmpty
    }
    
    /// Get count of pending uploads
    var pendingUploadCount: Int {
        return pendingUploads.count
    }
    
    // MARK: - In-Flight Upload Tracking (Bug e5310f3d)

    /// Register a batch of UIImages as in-flight uploads for a project.
    /// Returns the placeholders (id + UIImage) so the caller can clear
    /// them when the upload settles. Always called on the main actor.
    private func beginInFlightUploads(_ images: [UIImage], for project: Project) -> [InFlightUpload] {
        let projectId = project.id
        let placeholders = images.map { InFlightUpload(id: UUID().uuidString, image: $0) }
        var current = inFlightUploads[projectId] ?? []
        current.append(contentsOf: placeholders)
        inFlightUploads[projectId] = current
        return placeholders
    }

    /// Remove placeholders for a finished upload batch. The carousel will
    /// re-render with only the resolved S3 URLs left in the project's
    /// project_images list.
    private func endInFlightUploads(_ ids: [String], for projectId: String) {
        guard var current = inFlightUploads[projectId] else { return }
        let idSet = Set(ids)
        current.removeAll { idSet.contains($0.id) }
        if current.isEmpty {
            inFlightUploads.removeValue(forKey: projectId)
        } else {
            inFlightUploads[projectId] = current
        }
    }

    /// Auto-bug-reporting (May-12 follow-up): flip the failed flag for a
    /// set of in-flight tiles so the carousel can render them with a red
    /// badge + tap-to-retry instead of silently disappearing. Called from
    /// catch sites that hit a permanent rejection (RLS, 4xx, validation).
    func markInFlightUploadsFailed(
        ids: [String],
        for projectId: String,
        lastError: String?
    ) {
        guard var current = inFlightUploads[projectId] else { return }
        let idSet = Set(ids)
        for index in current.indices where idSet.contains(current[index].id) {
            current[index].failed = true
            current[index].lastError = lastError
        }
        inFlightUploads[projectId] = current
    }

    /// Drop a single failed tile from the carousel — used when the user
    /// taps "dismiss" on a permanent-failure tile after acknowledging it.
    /// (Tap-to-retry uses retryFailedInFlightUpload instead.)
    func dismissFailedInFlightUpload(id: String, for projectId: String) {
        endInFlightUploads([id], for: projectId)
    }

    /// Public accessor — used by the carousel to render upload spinners.
    func currentInFlightUploads(for projectId: String) -> [InFlightUpload] {
        return inFlightUploads[projectId] ?? []
    }

    /// Re-attempt a failed in-flight upload by running a fresh upload
    /// through `saveImages`. The old failed tile is removed BEFORE
    /// `saveImages` runs so the carousel transitions cleanly:
    /// `[failed tile]` → (briefly nothing) → `[new spinning tile]` →
    /// `[resolved photo OR new failed tile]`. Removing the old tile after
    /// `saveImages` returns would leave the user looking at TWO tiles
    /// for the duration of the upload (the old failed one and the new
    /// spinning one) — confusing.
    func retryFailedInFlightUpload(id: String, for projectId: String) async {
        guard let current = inFlightUploads[projectId],
              let upload = current.first(where: { $0.id == id }),
              upload.failed else { return }

        let image = upload.image

        // Drop the failed tile first so the carousel doesn't briefly
        // render two tiles for the same retry.
        endInFlightUploads([id], for: projectId)

        guard let project = getProject(by: projectId) else { return }
        _ = await saveImages([image], for: project)
    }

    // MARK: - Image Processing Helpers
    
    /// Resize image if it exceeds maximum dimensions
    private func resizeImageIfNeeded(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 2048 // Maximum width or height
        
        guard image.size.width > maxDimension || image.size.height > maxDimension else {
            return image
        }
        
        let aspectRatio = image.size.width / image.size.height
        let newSize: CGSize
        
        if image.size.width > image.size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
    
    /// Get adaptive compression quality based on image size
    private func getAdaptiveCompressionQuality(for image: UIImage) -> CGFloat {
        let pixelCount = image.size.width * image.size.height
        
        // Higher resolution images get more compression
        if pixelCount > 4_000_000 { // > 4MP
            return 0.5
        } else if pixelCount > 2_000_000 { // > 2MP
            return 0.6
        } else if pixelCount > 1_000_000 { // > 1MP
            return 0.7
        } else {
            return 0.8
        }
    }
}

/// Bug e5310f3d — represents a single image actively being uploaded
/// to S3 and Supabase. The carousel renders one placeholder per item
/// in this list while the upload finishes; the placeholder dissolves
/// into the real photo once `inFlightUploads` no longer contains it.
///
/// Auto-bug-reporting (May-12 follow-up): when an upload hits a permanent
/// server rejection (RLS denied, validation, 4xx), `failed = true` and
/// `lastError` carries the human-readable cause. The carousel renders
/// the tile with a red corner badge and tap-to-retry instead of removing
/// it, so the user sees that the photo did NOT make it to the project.
public struct InFlightUpload: Identifiable {
    public let id: String
    public let image: UIImage
    public var failed: Bool
    public var lastError: String?

    public init(id: String, image: UIImage, failed: Bool = false, lastError: String? = nil) {
        self.id = id
        self.image = image
        self.failed = failed
        self.lastError = lastError
    }
}

/// Model for a pending image upload
public struct PendingImageUpload: Codable {
    let localURL: String
    let projectId: String
    let companyId: String
    let timestamp: Date
    
    // Store reference to original image for offline sync
    var originalImage: UIImage? {
        if let imageData = ImageFileManager.shared.getImageData(localID: localURL) {
            return UIImage(data: imageData)
        }
        return nil
    }
    
    // Custom encoding to avoid storing UIImage
    enum CodingKeys: String, CodingKey {
        case localURL, projectId, companyId, timestamp
    }
}
