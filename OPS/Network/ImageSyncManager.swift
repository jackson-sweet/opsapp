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

/// Manager for handling image synchronization between local storage and Bubble API
@MainActor
class ImageSyncManager {
    // Dependencies
    private let modelContext: ModelContext?
    private let apiService: APIService
    private let connectivityMonitor: ConnectivityMonitor
    
    // Constants
    private let bubbleBaseImagesURL = "https://opsapp.co/version-test/img/"
    
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
        
        // Set up connectivity change notifications
        setupConnectivityObserver()
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
            print("ImageSyncManager: Connectivity restored, initiating image sync")
            Task {
                await syncPendingImages()
            }
        }
    }
    
    /// Save image locally and queue it for upload to Bubble
    func saveImage(_ image: UIImage, for project: Project) async -> String {
        // Compress image for storage
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            print("ImageSyncManager: ⚠️ Failed to compress image")
            return ""
        }
        
        // Generate a unique filename
        let timestamp = Date().timeIntervalSince1970
        let filename = "project_\(project.id)_\(timestamp)_\(UUID().uuidString).jpg"
        
        // Create a local URL and bubble URL
        let localURL = "local://project_images/\(filename)"
        let bubbleURL = "\(bubbleBaseImagesURL)\(filename)"
        
        // Store the image in file system
        let success = ImageFileManager.shared.saveImage(data: imageData, localID: localURL)
        if success {
            print("ImageSyncManager: Stored image data locally for: \(localURL)")
            
            // Create pending upload
            let pendingUpload = PendingImageUpload(
                localURL: localURL,
                bubbleURL: bubbleURL,
                projectId: project.id,
                timestamp: Date()
            )
            
            // Add to pending uploads
            pendingUploads.append(pendingUpload)
            savePendingUploads()
            
            // Mark the image as unsynced in the project
            project.addUnsyncedImage(localURL)
            
            // Try to sync immediately if we're online
            if connectivityMonitor.isConnected {
                // Attempt immediate upload
                let uploadSuccess = await uploadImageToBubble(pendingUpload)
                
                if uploadSuccess {
                    // If successful, remove from pending uploads
                    pendingUploads.removeAll { $0.localURL == localURL }
                    savePendingUploads()
                    
                    // Mark the image as synced in the project
                    project.markImageAsSynced(localURL)
                    
                    // Save the project changes
                    if let modelContext = modelContext {
                        try? modelContext.save()
                    }
                    
                    // And process any other pending uploads
                    await syncPendingImages()
                } else {
                    // If immediate upload fails, we'll leave it in pending uploads
                    // but we'll still return the localURL so the UI can show it with an unsynced indicator
                    print("ImageSyncManager: ⚠️ Immediate upload failed, keeping in pending queue")
                }
            }
            
            return localURL
        } else {
            print("ImageSyncManager: ⚠️ Failed to encode image to Base64")
            return ""
        }
    }
    
    /// Delete an image both locally and from the Bubble backend
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
        
        // If it's a Bubble URL, we need to delete it from both local cache and server
        if urlString.contains("opsapp.co/version-test/img/") {
            // Remove local cache
            UserDefaults.standard.removeObject(forKey: urlString)
            
            // If we're online, try to delete from server
            if connectivityMonitor.isConnected {
                // Extract filename from URL
                if let filename = URL(string: urlString)?.lastPathComponent {
                    return await deleteImageFromBubble(filename: filename, projectId: project.id)
                }
            }
        }
        
        return false
    }
    
    /// Delete an image from the Bubble backend
    private func deleteImageFromBubble(filename: String, projectId: String) async -> Bool {
        do {
            // Create the delete request with the exact Bubble API workflow endpoint
            let deleteURL = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/delete_project_images")!
            var request = URLRequest(url: deleteURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Create image object for deletion
            // For deletion, we only need the filename
            let imageObject: [String: Any] = [
                "filename": filename
            ]
            
            let deleteBody: [String: Any] = [
                "project": projectId,
                "image": imageObject  // Using "image" parameter (singular) for single deletion
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: deleteBody)
            
            // Execute the request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check response status
            guard let httpResponse = response as? HTTPURLResponse else {
                print("ImageSyncManager: Invalid response type for image deletion")
                return false
            }
            
            // Log the response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("ImageSyncManager: Delete response (\(httpResponse.statusCode)): \(responseString)")
            }
            
            // Check if the delete was successful
            if (200...299).contains(httpResponse.statusCode) {
                print("ImageSyncManager: Successfully deleted image from Bubble: \(filename)")
                return true
            } else {
                print("ImageSyncManager: Failed to delete image - HTTP \(httpResponse.statusCode)")
                return false
            }
        } catch {
            print("ImageSyncManager: Error deleting image: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Save multiple images locally and queue them for upload
    func saveImages(_ images: [UIImage], for project: Project) async -> [String] {
        var localURLs: [String] = []
        
        for image in images {
            let localURL = await saveImage(image, for: project)
            if !localURL.isEmpty {
                localURLs.append(localURL)
            }
        }
        
        return localURLs
    }
    
    /// Sync all pending images to Bubble
    func syncPendingImages() async {
        guard !isSyncing, connectivityMonitor.isConnected else { return }
        
        isSyncing = true
        print("ImageSyncManager: Starting sync of \(pendingUploads.count) pending image uploads")
        
        // Process uploads in batches of 3 to avoid overwhelming the server
        let batchSize = 3
        // Manually divide into batches rather than using the extension
        let batches = stride(from: 0, to: pendingUploads.count, by: batchSize).map {
            Array(pendingUploads[$0..<min($0 + batchSize, pendingUploads.count)])
        }
        
        for batch in batches {
            // Group images by project for more efficient uploading
            var uploadsByProject: [String: [PendingImageUpload]] = [:]
            
            // Organize by project
            for upload in batch {
                if uploadsByProject[upload.projectId] == nil {
                    uploadsByProject[upload.projectId] = []
                }
                uploadsByProject[upload.projectId]?.append(upload)
            }
            
            // Process each project's uploads
            await withTaskGroup(of: (String, [Bool]).self) { group in
                for (projectId, uploads) in uploadsByProject {
                    group.addTask {
                        let results = await self.syncImagesForProject(projectId: projectId, uploads: uploads)
                        return (projectId, results)
                    }
                }
                
                // Collect results
                for await (projectId, results) in group {
                    print("ImageSyncManager: Completed upload batch for project \(projectId): \(results.filter { $0 }.count)/\(results.count) successful")
                }
            }
        }
        
        isSyncing = false
        print("ImageSyncManager: Completed sync of pending image uploads")
    }
    
    /// Sync multiple images for a single project
    private func syncImagesForProject(projectId: String, uploads: [PendingImageUpload]) async -> [Bool] {
        if uploads.count == 1 {
            // Single image - use the normal method
            let success = await syncSingleImage(uploads[0])
            return [success]
        }
        
        // Multiple images - batch upload them
        do {
            // Create an array of image objects for each image
            var imageObjects: [[String: Any]] = []
            
            for upload in uploads {
                // Extract filename
                let filename = URL(string: upload.bubbleURL)?.lastPathComponent ?? "unnamed_image_\(UUID().uuidString).jpg"
                
                // Get image data from file system
                guard let imageData = upload.imageData else {
                    print("ImageSyncManager: ⚠️ Could not load image data for upload: \(upload.localURL)")
                    continue
                }
                
                // Create the image object with just filename and contents
                let imageObject: [String: Any] = [
                    "filename": filename,
                    "contents": imageData.base64EncodedString()
                ]
                
                imageObjects.append(imageObject)
            }
            
            // Use direct workflow endpoint specifically built for file uploads
            let uploadURL = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/upload_project_images")!
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Create request body exactly as expected by the workflow
            let requestBody: [String: Any] = [
                "project": projectId,
                "images": imageObjects // Array of image objects for batch upload
            ]
            
            // Prepare request body without logging the entire contents
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            // Log request info without the full base64 data
            print("ImageSyncManager: Sending batch image upload for project \(projectId) with \(imageObjects.count) images")
            
            // Log payload size for debugging
            let imageCount = imageObjects.count
            let totalSize = jsonData.count
            print("ImageSyncManager: Sending batch upload with \(imageCount) images, total payload size: \(totalSize) bytes")
            
            // Check if payload might be too large
            if totalSize > 5_000_000 {  // 5MB limit is common
                print("ImageSyncManager: ⚠️ WARNING: Upload payload might be too large (\(totalSize / 1_000_000) MB)")
            }
            
            // Set a longer timeout for large image uploads
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 90.0  // 90 seconds for multiple images
            config.timeoutIntervalForResource = 90.0
            
            let session = URLSession(configuration: config)
            let (data, response) = try await session.data(for: request)
            
            // Check response status
            guard let httpResponse = response as? HTTPURLResponse else {
                print("ImageSyncManager: Invalid response type")
                return uploads.map { _ in false }
            }
            
            // Log the response status code for debugging (without the full response body)
            print("ImageSyncManager: Batch upload response status: \(httpResponse.statusCode)")
            
            // Check if the upload was successful
            if (200...299).contains(httpResponse.statusCode) {
                print("ImageSyncManager: Successfully uploaded \(uploads.count) images for project \(projectId)")
                
                // Update all projects that reference these images
                do {
                    // If the upload was successful, update all projects that reference these images
                    if let projects = try modelContext?.fetch(FetchDescriptor<Project>()) {
                        for upload in uploads {
                            for project in projects {
                                let images = project.getProjectImages()
                                if images.contains(upload.localURL) {
                                    // Replace local URL with Bubble URL
                                    var updatedImages = images
                                    if let index = updatedImages.firstIndex(of: upload.localURL) {
                                        updatedImages[index] = upload.bubbleURL
                                        project.setProjectImageURLs(updatedImages)
                                        project.needsSync = true
                                        project.syncPriority = 2 // Higher priority for image changes
                                    }
                                }
                            }
                        }
                        
                        // Remove from pending uploads and mark as synced in their projects
                        for upload in uploads {
                            // Mark image as synced in all projects that reference it
                            for project in projects {
                                if project.getProjectImages().contains(upload.localURL) {
                                    project.markImageAsSynced(upload.localURL)
                                }
                            }
                            
                            // Remove from pending queue
                            pendingUploads.removeAll { $0.localURL == upload.localURL }
                        }
                        savePendingUploads()
                        
                        // Even after successful upload, store the images locally for offline access
                        for upload in uploads {
                            if let imageData = upload.imageData {
                                _ = ImageFileManager.shared.saveImage(data: imageData, localID: upload.bubbleURL)
                            }
                        }
                    }
                } catch {
                    print("ImageSyncManager: ❌ Error updating project references: \(error.localizedDescription)")
                    // Still consider the upload successful even if we fail to update all references
                }
                
                return uploads.map { _ in true }
            } else {
                print("ImageSyncManager: ⚠️ Failed to upload images in batch - HTTP \(httpResponse.statusCode)")
                
                // Log error without the full response body
                print("ImageSyncManager: Batch upload failed with HTTP status \(httpResponse.statusCode)")
                
                // For Bubble API specific errors, we might need to handle them differently
                if httpResponse.statusCode == 400 {
                    print("ImageSyncManager: Bubble API validation error - check image format")
                } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    print("ImageSyncManager: Authentication or permission error")
                } else if httpResponse.statusCode >= 500 {
                    print("ImageSyncManager: Server error, backing off and will retry later")
                }
                
                // If batch fails, try individual uploads as fallback
                print("ImageSyncManager: Attempting individual uploads as fallback")
                var results: [Bool] = []
                for upload in uploads {
                    let success = await syncSingleImage(upload)
                    results.append(success)
                }
                return results
            }
        } catch {
            print("ImageSyncManager: Error uploading batch of images: \(error.localizedDescription)")
            
            // If batch fails, try individual uploads as fallback
            var results: [Bool] = []
            for upload in uploads {
                let success = await syncSingleImage(upload)
                results.append(success)
            }
            return results
        }
    }
    
    /// Sync a single image to Bubble
    private func syncSingleImage(_ upload: PendingImageUpload) async -> Bool {
        print("ImageSyncManager: Syncing image \(upload.localURL)")
        
        // Use real API call to upload the image
        let success = await uploadImageToBubble(upload)
        
        if success {
            do {
                // If the upload was successful, update all projects that reference this image
                if let projects = try modelContext?.fetch(FetchDescriptor<Project>()) {
                    for project in projects {
                        let images = project.getProjectImages()
                        if images.contains(upload.localURL) {
                            // Replace local URL with Bubble URL
                            var updatedImages = images
                            if let index = updatedImages.firstIndex(of: upload.localURL) {
                                updatedImages[index] = upload.bubbleURL
                                project.setProjectImageURLs(updatedImages)
                                
                                // Mark the image as synced
                                project.markImageAsSynced(upload.localURL)
                                
                                project.needsSync = true
                                project.syncPriority = 2 // Higher priority for image changes
                            }
                        }
                    }
                    
                    // Remove from pending uploads
                    pendingUploads.removeAll { $0.localURL == upload.localURL }
                    savePendingUploads()
                }
            } catch {
                print("ImageSyncManager: ❌ Error updating project references: \(error.localizedDescription)")
                // Still consider the upload successful even if we fail to update all references
            }
            
            // Even after successful upload, store the image locally with Bubble URL for offline access
            // Use ImageFileManager instead of UserDefaults for storing large image data
            if let imageData = upload.imageData {
                let imageFileManager = ImageFileManager.shared
                _ = imageFileManager.saveImage(data: imageData, localID: upload.bubbleURL)
            }
            
            return true
        } else {
            print("ImageSyncManager: ⚠️ Failed to upload image to Bubble")
            return false
        }
    }
    
    /// Upload image to Bubble API using Bubble's custom workflow endpoint
    private func uploadImageToBubble(_ upload: PendingImageUpload) async -> Bool {
        guard connectivityMonitor.isConnected else {
            print("ImageSyncManager: Cannot upload image - no connectivity")
            return false
        }
        
        do {
            // Extract filename from Bubble URL
            let filename = URL(string: upload.bubbleURL)?.lastPathComponent ?? "unnamed_image.jpg"
            
            // Get image data from file system
            guard let imageData = upload.imageData else {
                print("ImageSyncManager: ⚠️ Could not load image data for upload")
                return false
            }
            
            // Convert the image data to base64 for JSON transfer
            let base64ImageString = imageData.base64EncodedString()
            
            // Use direct workflow endpoint specifically built for file uploads
            // This is typically more reliable than trying to update a field directly
            let uploadURL = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/upload_project_images")!
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Create the request body exactly as expected by the workflow
            let requestBody: [String: Any] = [
                "project": upload.projectId,
                "image": [
                    "filename": filename,
                    "contents": base64ImageString
                ]
            ]
            
            // Prepare request body without logging the entire contents
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            // Log request info without the full base64 data
            print("ImageSyncManager: Sending image upload for project \(upload.projectId), filename: \(filename)")
            
            // Log payload size for debugging
            let totalSize = jsonData.count
            print("ImageSyncManager: Sending single image upload, payload size: \(totalSize) bytes")
            
            // Check if payload might be too large
            if totalSize > 2_000_000 {  // 2MB limit for single image
                print("ImageSyncManager: ⚠️ WARNING: Upload payload might be too large (\(totalSize / 1_000_000) MB)")
            }
            
            // Set a longer timeout for large image uploads
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60.0  // 60 seconds
            config.timeoutIntervalForResource = 60.0
            
            let session = URLSession(configuration: config)
            let (data, response) = try await session.data(for: request)
            
            // Check response status
            guard let httpResponse = response as? HTTPURLResponse else {
                print("ImageSyncManager: Invalid response type")
                return false
            }
            
            // Log the response status code for debugging (without the full response body)
            print("ImageSyncManager: Upload response status: \(httpResponse.statusCode)")
            
            // Check if the upload was successful
            if (200...299).contains(httpResponse.statusCode) {
                print("ImageSyncManager: Successfully uploaded image to Bubble: \(filename)")
                return true
            } else {
                // Log detailed error information for debugging
                print("ImageSyncManager: Failed to upload image - HTTP \(httpResponse.statusCode)")
                
                // Log error without the full response body
                print("ImageSyncManager: Image upload failed with HTTP status \(httpResponse.statusCode)")
                
                // For Bubble API specific errors, we might need to handle them differently
                if httpResponse.statusCode == 400 {
                    print("ImageSyncManager: Bubble API validation error - check image format")
                } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    print("ImageSyncManager: Authentication or permission error")
                }
                
                return false
            }
        } catch {
            print("ImageSyncManager: Error uploading image: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Create multipart form data for image upload
    private func createMultipartFormData(boundary: String, imageData: Data, filename: String, projectId: String) -> Data {
        var formData = Data()
        
        // Add the project ID field
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"project\"\r\n\r\n".data(using: .utf8)!)
        formData.append("\(projectId)\r\n".data(using: .utf8)!)
        
        // The Bubble API might be expecting a different format for the images parameter
        // Let's make sure we format it correctly as just "images" without a filename
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"images\"\r\n\r\n".data(using: .utf8)!)
        formData.append("\(imageData.base64EncodedString())\r\n".data(using: .utf8)!)
        
        // End of form data
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return formData
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
            if key.contains("https://") && key.contains(".jpeg") {
                if let data = value as? Data {
                    totalSizeSaved += data.count
                } else if let string = value as? String {
                    totalSizeSaved += string.count
                }
                defaults.removeObject(forKey: key)
                removedCount += 1
            }
        }
        
        // Also check for old pendingImageUploads format that contains imageData
        if let existingData = defaults.data(forKey: "pendingImageUploads") {
            if existingData.count > 1_000_000 { // If over 1MB, it's the old format
                print("ImageSyncManager: Found large pendingImageUploads (\(existingData.count) bytes), migrating...")
                
                // Try to decode old format and migrate to new format
                if let oldUploads = try? JSONDecoder().decode([OldPendingImageUpload].self, from: existingData) {
                    // Migrate to new format by saving image data to file system
                    var newUploads: [PendingImageUpload] = []
                    
                    for oldUpload in oldUploads {
                        // Save image data to file system
                        let success = ImageFileManager.shared.saveImage(data: oldUpload.imageData, localID: oldUpload.localURL)
                        if success {
                            // Create new upload without imageData
                            let newUpload = PendingImageUpload(
                                localURL: oldUpload.localURL,
                                bubbleURL: oldUpload.bubbleURL,
                                projectId: oldUpload.projectId,
                                timestamp: oldUpload.timestamp
                            )
                            newUploads.append(newUpload)
                        }
                    }
                    
                    // Save new format
                    pendingUploads = newUploads
                    savePendingUploads()
                    totalSizeSaved += existingData.count
                } else {
                    // If we can't decode, just remove it
                    defaults.removeObject(forKey: "pendingImageUploads")
                    totalSizeSaved += existingData.count
                }
            }
        }
        
        print("ImageSyncManager: Cleanup complete - removed \(removedCount) image keys, saved ~\(totalSizeSaved / 1_000_000) MB")
    }
}

/// Model for a pending image upload
struct PendingImageUpload: Codable {
    let localURL: String
    let bubbleURL: String
    let projectId: String
    let timestamp: Date
    
    // Store image data in file system instead of this struct
    var imageData: Data? {
        return ImageFileManager.shared.getImageData(localID: localURL)
    }
}

/// Old model for migration purposes
private struct OldPendingImageUpload: Codable {
    let imageData: Data
    let localURL: String
    let bubbleURL: String
    let projectId: String
    let timestamp: Date
}

// Extension removed to avoid conflicts
