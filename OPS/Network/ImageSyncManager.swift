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
                imageData: imageData,
                localURL: localURL,
                bubbleURL: bubbleURL,
                projectId: project.id,
                timestamp: Date()
            )
            
            // Add to pending uploads
            pendingUploads.append(pendingUpload)
            savePendingUploads()
            
            // Try to sync if we're online
            if connectivityMonitor.isConnected {
                Task {
                    await syncPendingImages()
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
            // Create the delete request
            let deleteURL = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/delete_project_image")!
            var request = URLRequest(url: deleteURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Create request body
            let deleteBody: [String: String] = [
                "project_id": projectId,
                "filename": filename
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
            await withTaskGroup(of: Bool.self) { group in
                for upload in batch {
                    group.addTask {
                        await self.syncSingleImage(upload)
                    }
                }
                
                // Wait for all tasks in the group to complete
                for await _ in group {
                    // Just collecting results
                }
            }
        }
        
        isSyncing = false
        print("ImageSyncManager: Completed sync of pending image uploads")
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
            let imageFileManager = ImageFileManager.shared
            _ = imageFileManager.saveImage(data: upload.imageData, localID: upload.bubbleURL)
            
            return true
        } else {
            print("ImageSyncManager: ⚠️ Failed to upload image to Bubble")
            return false
        }
    }
    
    /// Upload image to Bubble API
    private func uploadImageToBubble(_ upload: PendingImageUpload) async -> Bool {
        guard connectivityMonitor.isConnected else {
            print("ImageSyncManager: Cannot upload image - no connectivity")
            return false
        }
        
        do {
            // Extract filename from Bubble URL
            let filename = URL(string: upload.bubbleURL)?.lastPathComponent ?? "unnamed_image.jpg"
            
            // Prepare the multipart form data
            let boundary = "Boundary-\(UUID().uuidString)"
            let formData = createMultipartFormData(
                boundary: boundary,
                imageData: upload.imageData,
                filename: filename,
                projectId: upload.projectId
            )
            
            // Create the upload request to the specific Bubble API endpoint for image uploads
            let uploadURL = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/upload_project_image")!
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = formData
            
            // Execute the request with a longer timeout for slow connections
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
            
            // Log the response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("ImageSyncManager: Upload response (\(httpResponse.statusCode)): \(responseString)")
            }
            
            // Check if the upload was successful
            if (200...299).contains(httpResponse.statusCode) {
                print("ImageSyncManager: Successfully uploaded image to Bubble: \(filename)")
                return true
            } else {
                print("ImageSyncManager: Failed to upload image - HTTP \(httpResponse.statusCode)")
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
        formData.append("Content-Disposition: form-data; name=\"project_id\"\r\n\r\n".data(using: .utf8)!)
        formData.append("\(projectId)\r\n".data(using: .utf8)!)
        
        // Add the image file
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        formData.append(imageData)
        formData.append("\r\n".data(using: .utf8)!)
        
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
}

/// Model for a pending image upload
struct PendingImageUpload: Codable {
    let imageData: Data
    let localURL: String
    let bubbleURL: String
    let projectId: String
    let timestamp: Date
}

// Extension removed to avoid conflicts