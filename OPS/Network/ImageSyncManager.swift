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
        
        // Store the image in UserDefaults
        if let imageBase64 = imageData.base64EncodedString() as String? {
            UserDefaults.standard.set(imageBase64, forKey: localURL)
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
        
        do {
            // Simulate the API call for now
            let success = await simulateImageUpload(upload)
            
            if success {
                // If the upload was successful, update all projects that reference this image
                if let projects = try? modelContext?.fetch(FetchDescriptor<Project>()) {
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
                
                return true
            } else {
                print("ImageSyncManager: ⚠️ Failed to upload image to Bubble")
                return false
            }
        } catch {
            print("ImageSyncManager: ❌ Error syncing image: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Simulate an image upload to Bubble (for now)
    private func simulateImageUpload(_ upload: PendingImageUpload) async -> Bool {
        // In a real implementation, this would make an API call to Bubble
        // For now, just simulate a successful upload after a delay
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Store the image with the Bubble URL too (for demo purposes)
        if let imageBase64 = upload.imageData.base64EncodedString() as String? {
            UserDefaults.standard.set(imageBase64, forKey: upload.bubbleURL)
            print("ImageSyncManager: Simulated successful upload: \(upload.bubbleURL)")
            return true
        }
        
        return false
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