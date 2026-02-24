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
    private let connectivityMonitor: ConnectivityMonitor
    private let presignedURLService = PresignedURLUploadService.shared
    
    // In-memory queue of pending image uploads
    private var pendingUploads: [PendingImageUpload] = []
    
    // Current sync state
    @Published private var isSyncing = false
    
    // Progress tracking
    @Published var syncProgress: Double = 0
    @Published var syncingProjectId: String? = nil
    
    /// Initialize the ImageSyncManager with required dependencies
    init(modelContext: ModelContext?, connectivityMonitor: ConnectivityMonitor) {
        self.modelContext = modelContext
        self.connectivityMonitor = connectivityMonitor
        
        // Clean up UserDefaults bloat first
        cleanupUserDefaultsImageData()
        
        // Load any pending uploads from UserDefaults
        loadPendingUploads()
        
        // Set up connectivity change notifications
        setupConnectivityObserver()
        
        // If we're already connected and have pending uploads, try to sync them
        if connectivityMonitor.isConnected && !pendingUploads.isEmpty {
            Task {
                // Small delay to ensure everything is initialized
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await syncPendingImages()
            }
        }
    }
    
    /// Setup observer for connectivity changes to trigger syncs when coming online
    private func setupConnectivityObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectivityChanged),
            name: ConnectivityMonitor.connectivityChangedNotification,
            object: nil
        )
    }
    
    @objc private func connectivityChanged() {
        if connectivityMonitor.isConnected {
            Task {
                await syncPendingImages()
            }
        } else {
        }
    }
    
    /// Save images using S3 and update Supabase
    func saveImages(_ images: [UIImage], for project: Project) async -> [String] {
        let companyId = project.companyId
        guard !companyId.isEmpty else {
            return []
        }

        var savedURLs: [String] = []

        if connectivityMonitor.isConnected {
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

                // Mark project for sync
                project.needsSync = true
                project.syncPriority = 2

                if let modelContext = modelContext {
                    try? modelContext.save()
                }

            } catch {
                // Offline fallback - save locally and queue for later
                for (index, image) in images.enumerated() {
                    if let localURL = await saveImageLocally(image, for: project, index: index) {
                        savedURLs.append(localURL)
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
            
            return localURL
        }
        
        return nil
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
        
        guard !isSyncing, connectivityMonitor.isConnected else { 
            if isSyncing {
            }
            if !connectivityMonitor.isConnected {
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

            project.needsSync = true

            // Remove from pending uploads
            pendingUploads.removeAll { upload in
                uploads.contains { $0.localURL == upload.localURL }
            }
            savePendingUploads()

            if let modelContext = modelContext {
                try? modelContext.save()
            }

        } catch {
            print("[IMAGE_SYNC] Failed to sync images for project \(projectId): \(error)")
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
