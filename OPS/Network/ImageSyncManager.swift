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

/// Manager for handling image synchronization between local storage, S3, and Bubble API
@MainActor
class ImageSyncManager {
    // Dependencies
    private let modelContext: ModelContext?
    private let apiService: APIService
    private let connectivityMonitor: ConnectivityMonitor
    private let s3Service = S3UploadService.shared
    private let presignedURLService = PresignedURLUploadService.shared
    
    // Configuration flag to use presigned URLs instead of direct S3 upload
    private let usePresignedURLs = false // Set to true to use Lambda presigned URLs
    
    // In-memory queue of pending image uploads
    private var pendingUploads: [PendingImageUpload] = []
    
    // Current sync state
    private var isSyncing = false
    
    /// Initialize the ImageSyncManager with required dependencies
    init(modelContext: ModelContext?, apiService: APIService, connectivityMonitor: ConnectivityMonitor) {
        self.modelContext = modelContext
        self.apiService = apiService
        self.connectivityMonitor = connectivityMonitor
        
        // Clean up UserDefaults bloat first
        cleanupUserDefaultsImageData()
        
        // Load any pending uploads from UserDefaults
        loadPendingUploads()
        print("📱 ImageSyncManager: Initialized with \(pendingUploads.count) pending uploads")
        
        // Set up connectivity change notifications
        setupConnectivityObserver()
        
        // If we're already connected and have pending uploads, try to sync them
        if connectivityMonitor.isConnected && !pendingUploads.isEmpty {
            print("📡 ImageSyncManager: Connected on init with pending uploads, scheduling sync")
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
        print("🌐 ImageSyncManager: Connectivity changed - isConnected: \(connectivityMonitor.isConnected)")
        if connectivityMonitor.isConnected {
            print("📡 ImageSyncManager: Connectivity restored, initiating image sync")
            Task {
                await syncPendingImages()
            }
        } else {
            print("📵 ImageSyncManager: Lost connectivity")
        }
    }
    
    /// Save images using S3 and register them with Bubble
    func saveImages(_ images: [UIImage], for project: Project) async -> [String] {
        print("\n🎯 ImageSyncManager: saveImages called")
        print("  - Images to save: \(images.count)")
        print("  - Project: \(project.id) - \(project.title)")
        print("  - Company ID: \(project.companyId)")
        print("  - Network connected: \(connectivityMonitor.isConnected)")
        
        let companyId = project.companyId
        guard !companyId.isEmpty else {
            print("❌ ImageSyncManager: No company ID for project")
            return []
        }
        
        var savedURLs: [String] = []
        
        if connectivityMonitor.isConnected {
            print("📡 Online mode - uploading to S3")
            do {
                // Upload to S3 (using either direct upload or presigned URLs)
                let s3Results: [(url: String, filename: String)]
                
                if usePresignedURLs {
                    print("  - Using presigned URL method")
                    s3Results = try await presignedURLService.uploadProjectImages(images, for: project, companyId: companyId)
                } else {
                    print("  - Using direct S3 upload method")
                    s3Results = try await s3Service.uploadProjectImages(images, for: project, companyId: companyId)
                }
                
                // Create list of URL strings for Bubble API
                let imageURLs = s3Results.map { $0.url }
                
                // Register with Bubble API
                let requestBody: [String: Any] = [
                    "project_id": project.id,
                    "images": imageURLs  // Just an array of URL strings
                ]
                
                print("🔷 Bubble API Request: upload_project_images")
                print("  - Project ID: \(project.id)")
                print("  - Images to register: \(imageURLs.count)")
                for (index, url) in imageURLs.enumerated() {
                    print("    Image \(index + 1): \(url)")
                }
                
                let uploadURL = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/upload_project_images")!
                print("  - URL: \(uploadURL.absoluteString)")
                
                var request = URLRequest(url: uploadURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(AppConfiguration.bubbleAPIToken)", forHTTPHeaderField: "Authorization")
                
                let requestBodyData = try JSONSerialization.data(withJSONObject: requestBody)
                request.httpBody = requestBodyData
                
                if let bodyString = String(data: requestBodyData, encoding: .utf8) {
                    print("  - Request Body: \(bodyString)")
                }
                
                print("  - Headers:")
                request.allHTTPHeaderFields?.forEach { key, value in
                    if key.lowercased() == "authorization" {
                        print("    - \(key): Bearer [MASKED]")
                    } else {
                        print("    - \(key): \(value)")
                    }
                }
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Bubble API Error: Invalid response type")
                    // S3 upload succeeded but Bubble failed - clean up S3
                    for result in s3Results {
                        try? await s3Service.deleteImageFromS3(url: result.url, companyId: companyId, projectId: project.id)
                    }
                    throw S3Error.bubbleAPIFailed
                }
                
                print("🔶 Bubble API Response:")
                print("  - Status Code: \(httpResponse.statusCode)")
                print("  - Headers: \(httpResponse.allHeaderFields)")
                
                if let responseString = String(data: data, encoding: .utf8) {
                    print("  - Response Body: \(responseString)")
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("❌ Bubble API failed with status \(httpResponse.statusCode)")
                    if let errorBody = String(data: data, encoding: .utf8) {
                        print("❌ Error Response: \(errorBody)")
                    }
                    // S3 upload succeeded but Bubble failed - clean up S3
                    for result in s3Results {
                        try? await s3Service.deleteImageFromS3(url: result.url, companyId: companyId, projectId: project.id)
                    }
                    throw S3Error.bubbleAPIFailed
                }
                
                // Success - return the S3 URLs
                savedURLs = s3Results.map { $0.url }
                
                print("✅ S3 upload and Bubble registration successful!")
                print("  - URLs to add to project: \(savedURLs)")
                
                // Update project with new image URLs
                var currentImages = project.getProjectImages()
                print("  - Current project images: \(currentImages.count)")
                currentImages.append(contentsOf: savedURLs)
                print("  - New total images: \(currentImages.count)")
                
                project.setProjectImageURLs(currentImages)
                
                // Mark project for sync
                project.needsSync = true
                project.syncPriority = 2
                
                // Save changes
                if let modelContext = modelContext {
                    do {
                        try modelContext.save()
                        print("✅ Project updated and saved to local database")
                    } catch {
                        print("❌ Error saving to model context: \(error)")
                    }
                } else {
                    print("⚠️ No model context available to save changes")
                }
                
                print("✅ ImageSyncManager: Successfully uploaded \(savedURLs.count) images to S3 and registered with Bubble")
                
            } catch {
                print("❌ ImageSyncManager: Error uploading images: \(error)")
                print("  - Error type: \(type(of: error))")
                print("  - Will fall back to offline storage")
                
                // For offline mode, save locally and queue for later
                for (index, image) in images.enumerated() {
                    if let localURL = await saveImageLocally(image, for: project, index: index) {
                        savedURLs.append(localURL)
                    }
                }
            }
        } else {
            print("📵 Offline mode - saving locally")
            // Offline - save locally
            for (index, image) in images.enumerated() {
                if let localURL = await saveImageLocally(image, for: project, index: index) {
                    savedURLs.append(localURL)
                    print("  - Saved locally: \(localURL)")
                }
            }
        }
        
        print("\n📊 ImageSyncManager Summary:")
        print("  - Total URLs returned: \(savedURLs.count)")
        print("  - URLs: \(savedURLs)")
        
        return savedURLs
    }
    
    /// Save a single image locally for offline use
    private func saveImageLocally(_ image: UIImage, for project: Project, index: Int) async -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            print("ImageSyncManager: Failed to compress image")
            return nil
        }
        
        let timestamp = Date().timeIntervalSince1970
        let filename = "local_project_\(project.id)_\(timestamp)_\(index).jpg"
        let localURL = "local://project_images/\(filename)"
        
        // Store the image in file system
        let success = ImageFileManager.shared.saveImage(data: imageData, localID: localURL)
        if success {
            print("ImageSyncManager: Stored image data locally for: \(localURL)")
            
            // Create pending upload
            let pendingUpload = PendingImageUpload(
                localURL: localURL,
                projectId: project.id,
                companyId: project.companyId ?? "",
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
    
    /// Delete an image from S3, Bubble, and locally
    func deleteImage(_ urlString: String, from project: Project) async -> Bool {
        print("ImageSyncManager: Deleting image: \(urlString)")
        
        // Check if it's a local URL
        if urlString.starts(with: "local://") {
            // Remove from file system
            ImageFileManager.shared.deleteImage(localID: urlString)
            
            // Remove from pending uploads if present
            pendingUploads.removeAll { $0.localURL == urlString }
            savePendingUploads()
            
            print("ImageSyncManager: Deleted local image: \(urlString)")
            return true
        }
        
        // If it's an S3 URL, delete from S3
        if urlString.contains("s3") && urlString.contains("amazonaws.com") {
            let companyId = project.companyId
            guard !companyId.isEmpty else {
                print("ImageSyncManager: No company ID for project")
                return false
            }
            
            do {
                try await s3Service.deleteImageFromS3(url: urlString, companyId: companyId, projectId: project.id)
                
                // Also remove from local cache if present
                ImageFileManager.shared.deleteImage(localID: urlString)
                
                return true
            } catch {
                print("ImageSyncManager: Error deleting from S3: \(error.localizedDescription)")
                return false
            }
        }
        
        // Handle legacy Bubble URLs
        if urlString.contains("opsapp.co/") && urlString.contains("/img/") {
            // Remove from local cache
            ImageFileManager.shared.deleteImage(localID: urlString)
            return true
        }
        
        return false
    }
    
    /// Sync all pending images to S3 and Bubble
    func syncPendingImages() async {
        print("\n🔄 ImageSyncManager: syncPendingImages called")
        print("  - Is syncing: \(isSyncing)")
        print("  - Is connected: \(connectivityMonitor.isConnected)")
        print("  - Pending uploads count: \(pendingUploads.count)")
        
        guard !isSyncing, connectivityMonitor.isConnected else { 
            if isSyncing {
                print("  - Already syncing, skipping")
            }
            if !connectivityMonitor.isConnected {
                print("  - No network connection, skipping")
            }
            return 
        }
        
        if pendingUploads.isEmpty {
            print("  - No pending uploads to sync")
            return
        }
        
        isSyncing = true
        print("📤 Starting sync of \(pendingUploads.count) pending image uploads")
        
        // Group by project for batch uploading
        var uploadsByProject: [String: [PendingImageUpload]] = [:]
        for upload in pendingUploads {
            if uploadsByProject[upload.projectId] == nil {
                uploadsByProject[upload.projectId] = []
            }
            uploadsByProject[upload.projectId]?.append(upload)
        }
        
        print("  - Grouped into \(uploadsByProject.count) projects")
        
        // Process each project's uploads
        for (projectId, uploads) in uploadsByProject {
            print("  - Syncing \(uploads.count) images for project: \(projectId)")
            await syncImagesForProject(projectId: projectId, uploads: uploads)
        }
        
        isSyncing = false
        print("✅ ImageSyncManager: Completed sync of pending image uploads")
        print("  - Remaining pending uploads: \(pendingUploads.count)")
    }
    
    /// Sync images for a specific project
    private func syncImagesForProject(projectId: String, uploads: [PendingImageUpload]) async {
        guard let project = getProject(by: projectId) else {
            print("ImageSyncManager: Could not find project")
            return
        }
        
        let companyId = project.companyId
        guard !companyId.isEmpty else {
            print("ImageSyncManager: No company ID for project")
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
            print("ImageSyncManager: No valid images to upload")
            return
        }
        
        do {
            // Upload to S3 (using either direct upload or presigned URLs)
            let s3Results: [(url: String, filename: String)]
            
            if usePresignedURLs {
                s3Results = try await presignedURLService.uploadProjectImages(images, for: project, companyId: companyId)
            } else {
                s3Results = try await s3Service.uploadProjectImages(images, for: project, companyId: companyId)
            }
            
            // Create list of URL strings for Bubble API
            let imageURLs = s3Results.map { $0.url }
            
            // Register with Bubble API
            let requestBody: [String: Any] = [
                "project_id": projectId,
                "images": imageURLs  // Just an array of URL strings
            ]
            
            let uploadURL = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/upload_project_images")!
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(AppConfiguration.bubbleAPIToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                // S3 upload succeeded but Bubble failed - clean up S3
                for result in s3Results {
                    try? await s3Service.deleteImageFromS3(url: result.url, companyId: companyId, projectId: projectId)
                }
                throw S3Error.bubbleAPIFailed
            }
            
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
            project.needsSync = true
            
            // Remove from pending uploads
            pendingUploads.removeAll { upload in
                uploads.contains { $0.localURL == upload.localURL }
            }
            savePendingUploads()
            
            // Save changes
            if let modelContext = modelContext {
                try? modelContext.save()
            }
            
            print("ImageSyncManager: Successfully synced \(uploads.count) images for project \(projectId)")
            
        } catch {
            print("ImageSyncManager: Error syncing images: \(error.localizedDescription)")
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
            print("ImageSyncManager: Error fetching project: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Helper to load pending uploads from UserDefaults
    private func loadPendingUploads() {
        if let data = UserDefaults.standard.data(forKey: "pendingImageUploads"),
           let uploads = try? JSONDecoder().decode([PendingImageUpload].self, from: data) {
            pendingUploads = uploads
            print("ImageSyncManager: Loaded \(uploads.count) pending image uploads")
        }
    }
    
    /// Helper to save pending uploads to UserDefaults
    private func savePendingUploads() {
        if let data = try? JSONEncoder().encode(pendingUploads) {
            UserDefaults.standard.set(data, forKey: "pendingImageUploads")
            print("ImageSyncManager: Saved \(pendingUploads.count) pending image uploads")
        }
    }
    
    /// Clean up UserDefaults from image data bloat
    private func cleanupUserDefaultsImageData() {
        print("ImageSyncManager: Starting UserDefaults cleanup...")
        
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
        
        print("ImageSyncManager: Cleanup complete - removed \(removedCount) image keys, saved ~\(totalSizeSaved / 1_000_000) MB")
    }
}

/// Model for a pending image upload
struct PendingImageUpload: Codable {
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
