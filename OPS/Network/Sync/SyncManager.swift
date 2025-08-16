//
//  SyncManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import SwiftUI
import Foundation
import SwiftData
import Combine

@MainActor
class SyncManager {
    // MARK: - Sync State Publisher
    // MARK: - Properties
    
    typealias UserIdProvider = () -> String?
    private let userIdProvider: UserIdProvider
    
    let modelContext: ModelContext
    private let apiService: APIService
    private let connectivityMonitor: ConnectivityMonitor
    private let backgroundTaskManager: BackgroundTaskManager
    
    // Flag to prevent automatic status updates
    private var preventAutoStatusUpdates: Bool = false
    
    // Cache of non-existent user IDs to prevent repeated fetch attempts
    private var nonExistentUserIds: Set<String> = []
    
    /// Add a user ID to the non-existent cache
    func addNonExistentUserId(_ userId: String) {
        nonExistentUserIds.insert(userId)
    }
    
    private(set) var syncInProgress = false {
        didSet {
            // Publish state changes
            syncStateSubject.send(syncInProgress)
        }
    }
    
    private var syncStateSubject = PassthroughSubject<Bool, Never>()
    var syncStatePublisher: AnyPublisher<Bool, Never> {
        syncStateSubject.eraseToAnyPublisher()
    }
    
    var isConnected: Bool {
        connectivityMonitor.isConnected
    }
    
    // Status updates control
    var areAutoStatusUpdatesEnabled: Bool {
        return !preventAutoStatusUpdates
    }
    
    // MARK: - Initialization
    init(modelContext: ModelContext,
         apiService: APIService,
         connectivityMonitor: ConnectivityMonitor,
         backgroundTaskManager: BackgroundTaskManager = BackgroundTaskManager(),
         userIdProvider: @escaping UserIdProvider = { return nil }) {
        
        self.modelContext = modelContext
        self.apiService = apiService
        self.connectivityMonitor = connectivityMonitor
        self.backgroundTaskManager = backgroundTaskManager
        self.userIdProvider = userIdProvider
        
        // Load auto status updates setting from UserDefaults
        let userDefaults = UserDefaults.standard
        self.preventAutoStatusUpdates = !userDefaults.bool(forKey: "autoStatusUpdates", defaultValue: true)
        
    }
    
    // MARK: - Public Methods
    
    // MARK: Task Update Methods
    
    /// Update task status via API
    public func updateTaskStatus(id: String, status: String) async throws {
        try await apiService.updateTaskStatus(id: id, status: status)
    }
    
    /// Update task notes via API
    public func updateTaskNotes(id: String, notes: String) async throws {
        try await apiService.updateTaskNotes(id: id, notes: notes)
    }
    
    /// Sync a user to the API
    func syncUser(_ user: User) async {
        guard !syncInProgress, connectivityMonitor.isConnected else {
            return
        }
        
        syncInProgress = true
        syncStateSubject.send(true)
        
        do {
            
            // Create user update payload - only include fields that users can edit
            // Include user_id for workflow processing
            var userPayload: [String: String] = [
                "user_id": user.id,
                "first_name": user.firstName,
                "last_name": user.lastName,
                "phone": user.phone ?? ""
            ]
            
            // Add home address if available
            if let homeAddress = user.homeAddress {
                userPayload["home_address"] = homeAddress
            }
            
            // Convert to JSON
            let jsonData = try JSONSerialization.data(withJSONObject: userPayload)
            
            // Make POST request to Bubble workflow for updating user
            // Bubble doesn't consistently support PATCH across all endpoints, so we'll use POST to a workflow endpoint
            let endpoint = "api/1.1/wf/update_user_profile"
            let _: EmptyResponse = try await apiService.executeRequest(
                endpoint: endpoint,
                method: "POST",
                body: jsonData
            )
            
            
            // Mark as synced
            user.needsSync = false
            user.lastSyncedAt = Date()
            try modelContext.save()
            
            // Remove profile image upload handling - we'll only sync profile data now
            // We will rely on the API to fetch profile images instead of uploading them
        } catch {
            print("SyncManager: Error syncing user: \(error.localizedDescription)")
        }
        
        syncInProgress = false
        syncStateSubject.send(false)
    }
    
    /// Upload a user's profile image to Bubble
    private func uploadUserProfileImage(_ image: UIImage, for user: User) async {
        
        do {
            // 1. Compress image to a reasonable size
            let targetSize = CGSize(width: min(image.size.width, 1200), height: min(image.size.height, 1200))
            let resizedImage = image.resized(to: targetSize)
            
            guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
                print("❌ SyncManager: Failed to compress profile image")
                return
            }
            
            
            // 2. Create a unique filename
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "profile_\(user.id)_\(timestamp).jpg"
            
            // Use simpler multipart form data approach with only the required fields
            
            // Set up the multipart form boundary
            let boundary = "Boundary-\(UUID().uuidString)"
            var formData = Data()
            
            // Add ONLY the user_id field 
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition: form-data; name=\"user_id\"\r\n\r\n".data(using: .utf8)!)
            formData.append("\(user.id)\r\n".data(using: .utf8)!)
            
            // Add ONLY the image field with binary data directly (no temp files)
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            formData.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            formData.append(imageData)
            formData.append("\r\n".data(using: .utf8)!)
            
            // End the multipart form
            formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            // Log form data details
            
            // 7. Create the request with properly formatted URL
            // Make sure URL doesn't have trailing slash issues
            let baseURLString = AppConfiguration.bubbleBaseURL.absoluteString.trimmingCharacters(in: ["/"])
            let uploadURL = URL(string: "\(baseURLString)/api/1.1/wf/upload_user_profile_image")!
            
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = formData
            
            // Log the full URL and request headers for debugging
            request.allHTTPHeaderFields?.forEach { key, value in
            }
            
            // 8. Detailed debug logging
            
            if let formPreview = String(data: formData.prefix(500), encoding: .utf8) {
            }
            
            // 9. Create a custom session with longer timeouts for field operations
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60.0   // 60 seconds timeout
            config.timeoutIntervalForResource = 60.0
            let session = URLSession(configuration: config)
            
            
            // 10. Execute the request
            let (data, response) = try await session.data(for: request)
            
            
            // 11. Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                return
            }
            
            // 12. Complete response logging for both success and failure
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            
            // If we're getting a 400 error with specific missing parameter message, 
            // let's try an alternative approach
            if httpResponse.statusCode == 400 && responseString.contains("Missing parameter for workflow upload_user_profile_image: parameter image") {
                
                // Try the fallback approach - some APIs expect a different format
                let _ = await tryFallbackUpload(user: user, image: image)
                return
            }
            
            // 13. Only proceed if we got a success response
            guard (200...299).contains(httpResponse.statusCode) else {
                print("❌ SyncManager: Profile image upload FAILED (HTTP \(httpResponse.statusCode))")
                return
            }
            
            
            // 14. Parse the response to get the uploaded image URL
            // First dump the full response for debugging
            
            // Try to dump as formatted JSON
            if let responseData = responseString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: responseData),
               let formattedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
               let formattedString = String(data: formattedData, encoding: .utf8) {
            }
            
            // If there's a status field in the response and it's an error, log it
            if responseString.contains("\"status\":\"ERROR\"") || responseString.contains("\"statusCode\":400") {
                print("❌ SyncManager: Error in response: \(responseString)")
            }
            
            // 15. Try ALL possible response formats that Bubble might use
            var imageURL: String? = nil
            
            // Try to parse the response properly based on Bubble API structure
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Print all keys for debugging
                
                // If response contains 'body' field which often contains error info
                if let body = json["body"] as? [String: Any] {
                    if let status = body["status"] as? String, 
                       let message = body["message"] as? String {
                        print("❌ SyncManager: API Error - Status: \(status), Message: \(message)")
                    }
                }
                
                // Try formats in cascading order (most likely first)
                // Added all possible fields that might contain the URL
                
                // Format 1: Direct field at root level - try all common field names
                let possibleURLKeys = ["profile_url", "avatar", "Avatar", "image_url", "url", "image", "file_url", "profile_image"]
                
                for key in possibleURLKeys {
                    if let url = json[key] as? String {
                        imageURL = url
                        break
                    }
                }
                
                // Format 2: Inside response wrapper
                if imageURL == nil, let response = json["response"] as? [String: Any] {
                    // Print response keys for debugging
                    
                    for key in possibleURLKeys {
                        if let url = response[key] as? String {
                            imageURL = url
                            break
                        }
                    }
                    
                    // Format 3: Nested user object
                    if imageURL == nil, let userObj = response["user"] as? [String: Any] {
                        
                        for key in possibleURLKeys {
                            if let url = userObj[key] as? String {
                                imageURL = url
                                break
                            }
                        }
                    }
                }
            }
            
            // 16. Update the user model if we found a URL
            if let imageURL = imageURL {
                // Update the user's profile image URL
                user.profileImageURL = imageURL
                
                // Clear the imageData since we've uploaded it successfully
                user.profileImageData = nil
                user.needsSync = false
                
                // Cache the image for immediate use
                ImageCache.shared.set(image, forKey: imageURL)
                
                try modelContext.save()
            } else {
            }
            
            
        } catch {
            print("❌ SyncManager: Error uploading profile image: \(error.localizedDescription)")
        }
    }
    
    /// Try an alternative approach to upload user profile image to Bubble
    /// This is a fallback method when the primary method fails with specific Bubble API errors
    private func tryFallbackUpload(user: User, image: UIImage) async -> Bool {
        
        do {
            // Compress image again
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                print("❌ SyncManager: Failed to compress profile image in fallback")
                return false
            }
            
            // Create a unique filename
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "profile_\(user.id)_\(timestamp).jpg"
            
            // Create the request with the correct URL
            let url = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/upload_user_profile_image")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            // Use a very simple boundary
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            // Create body with ONLY user_id and image fields
            var body = Data()
            
            // Add user_id field
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"user_id\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(user.id)\r\n".data(using: .utf8)!)
            
            // Add image field - ONLY THESE TWO FIELDS
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
            
            // Close the form
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            request.httpBody = body
            
            
            // Execute the request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check the response
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            
            // Log the response
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            
            // Check if the request was successful
            if (200...299).contains(httpResponse.statusCode) {
                
                // Try to parse the response to get the image URL
                var imageURL: String? = nil
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Check all common locations where the URL might be
                    let possibleKeys = ["image_url", "url", "avatar", "Avatar", "profile_image", "profile_url"]
                    
                    // Check root level
                    for key in possibleKeys {
                        if let url = json[key] as? String {
                            imageURL = url
                            break
                        }
                    }
                    
                    // Check response wrapper
                    if imageURL == nil, let response = json["response"] as? [String: Any] {
                        for key in possibleKeys {
                            if let url = response[key] as? String {
                                imageURL = url
                                break
                            }
                        }
                    }
                }
                
                // Update the user model if we found a URL
                if let imageURL = imageURL {
                    user.profileImageURL = imageURL
                    user.profileImageData = nil
                    user.needsSync = false
                    
                    // Cache the image for immediate display
                    ImageCache.shared.set(image, forKey: imageURL)
                    
                    try modelContext.save()
                    
                    return true
                } else {
                    return false
                }
            } else {
                print("❌ FALLBACK: Upload failed with status \(httpResponse.statusCode)")
                return false
            }
        } catch {
            print("❌ FALLBACK: Error during upload: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Trigger background sync with intelligent retry
    /// - Parameter forceProjectSync: If true, always sync projects regardless of sync budget
    func triggerBackgroundSync(forceProjectSync: Bool = false) {
        guard !syncInProgress, connectivityMonitor.isConnected else {
            if syncInProgress {
                print("🟡 SyncManager: Sync already in progress, skipping")
            } else if !connectivityMonitor.isConnected {
                print("🟡 SyncManager: No internet connection, skipping sync")
            }
            return
        }
        
        print("🔵 SyncManager: Starting background sync (forceProjectSync: \(forceProjectSync))")
        syncInProgress = true
        syncStateSubject.send(true)
        
        Task {
            do {
                // First sync users that need sync (always allowed)
                print("🔵 SyncManager: Syncing pending user changes...")
                let userSyncCount = await syncPendingUserChanges()
                print("🔵 SyncManager: Synced \(userSyncCount) users")
                
                // Then sync high-priority project items (status changes) if auto-updates are enabled
                var highPriorityCount = 0
                if !preventAutoStatusUpdates {
                    print("🔵 SyncManager: Syncing pending project status changes...")
                    highPriorityCount = await syncPendingProjectStatusChanges()
                    print("🔵 SyncManager: Synced \(highPriorityCount) project status changes")
                } else {
                    print("🟡 SyncManager: Auto status updates disabled, skipping project status sync")
                }
                
                // Finally, fetch remote data if we didn't exhaust our sync budget OR if forced
                if forceProjectSync || (userSyncCount + highPriorityCount) < 10 {
                    print("🔵 SyncManager: Fetching remote projects...")
                    try await syncProjects()
                    print("🟢 SyncManager: Project sync completed")
                } else {
                    print("🟡 SyncManager: Sync budget exhausted, skipping project fetch")
                }
                
                // Schedule notifications for future projects after sync
                print("🔵 SyncManager: Scheduling project notifications...")
                await NotificationManager.shared.scheduleNotificationsForAllProjects(using: modelContext)
                
                syncInProgress = false
                syncStateSubject.send(false)
                print("🟢 SyncManager: Background sync completed")
            } catch {
                print("🔴 SyncManager: Background sync failed: \(error.localizedDescription)")
                syncInProgress = false
                syncStateSubject.send(false)
            }
        }
    }
    
    /// Sync any pending user changes
    private func syncPendingUserChanges() async -> Int {
        // Find users that need sync
        let predicate = #Predicate<User> { $0.needsSync == true }
        let descriptor = FetchDescriptor<User>(predicate: predicate)
        
        do {
            let pendingUsers = try modelContext.fetch(descriptor)
            var successCount = 0
            
            // Process users one at a time to avoid overwhelming the API
            for user in pendingUsers {
                await syncUser(user)
                successCount += 1
                
                // Small delay between users
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            return successCount
        } catch {
            print("SyncManager: Failed to fetch pending users: \(error.localizedDescription)")
            return 0
        }
    }
    
    /// Update project status locally and queue for sync
    @discardableResult
    func updateProjectStatus(projectId: String, status: Status, forceSync: Bool = false) -> Bool {
        let predicate = #Predicate<Project> { $0.id == projectId }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)
        
        do {
            let projects = try modelContext.fetch(descriptor)
            guard let project = projects.first else {
                return false
            }
            
            // Update status locally
            project.status = status
            project.needsSync = true
            project.syncPriority = 3 // Highest priority
            
            // Update timestamps based on status
            if status == .inProgress && project.startDate == nil {
                project.startDate = Date()
            } else if status == .completed && project.endDate == nil {
                project.endDate = Date()
            }
            
            // Update task status if project uses task-based scheduling
            if project.eventType == .task && !project.tasks.isEmpty {
                updateTasksForProjectStatus(project: project, projectStatus: status)
            }
            
            // Save local changes
            try modelContext.save()
            
            // Queue sync if online and either auto-updates are enabled or forceSync is true
            if connectivityMonitor.isConnected && (!preventAutoStatusUpdates || forceSync) {
                
                // Don't await - allow to happen in background
                Task {
                    await syncProjectStatus(project)
                }
            } else if preventAutoStatusUpdates && !forceSync {
            } else if !connectivityMonitor.isConnected {
            }
            
            return true
        } catch {
            print("SyncManager: Failed to update project status locally: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Update project notes locally and queue for sync
    @discardableResult
    func updateProjectNotes(projectId: String, notes: String) -> Bool {
        let predicate = #Predicate<Project> { $0.id == projectId }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)
        
        do {
            let projects = try modelContext.fetch(descriptor)
            guard let project = projects.first else {
                return false
            }
            
            
            // Check if notes are actually different to avoid unnecessary updates
            if project.notes == notes {
                return true
            }
            
            // Update notes locally
            project.notes = notes
            project.needsSync = true
            project.syncPriority = 2 // Medium-high priority
            
            // Save local changes
            try modelContext.save()
            
            // Queue sync if online - do this immediately for notes (user is waiting)
            if connectivityMonitor.isConnected {
                Task {
                    do {
                        try await apiService.updateProjectNotes(id: project.id, notes: notes)
                        
                        await MainActor.run {
                            project.needsSync = false
                            project.lastSyncedAt = Date()
                            try? modelContext.save()
                        }
                        
                    } catch {
                        print("❌ SyncManager: Failed to sync project notes: \(error.localizedDescription)")
                        // Leave needsSync=true to retry later in background sync
                    }
                }
            } else {
            }
            
            return true
        } catch {
            print("❌ SyncManager: Failed to update project notes locally: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Update user name locally and queue for sync
    @discardableResult
    func updateUserName(_ user: User, firstName: String, lastName: String) -> Bool {
        do {
            // Update user locally
            user.firstName = firstName
            user.lastName = lastName
            user.needsSync = true
            
            // Save changes
            try modelContext.save()
            
            // Queue sync if online
            if connectivityMonitor.isConnected {
                Task {
                    await syncUser(user)
                }
            }
            
            return true
        } catch {
            print("SyncManager: Failed to update user name locally: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Update user phone number locally and queue for sync
    @discardableResult
    func updateUserPhone(_ user: User, phone: String) -> Bool {
        do {
            // Update user locally
            user.phone = phone
            user.needsSync = true
            
            // Save changes
            try modelContext.save()
            
            // Queue sync if online
            if connectivityMonitor.isConnected {
                Task {
                    await syncUser(user)
                }
            }
            
            return true
        } catch {
            print("SyncManager: Failed to update user phone locally: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Update user profile image and queue for sync
    @discardableResult
    func updateUserProfileImage(_ user: User, image: UIImage) -> Bool {
        do {
            // Compress image for storage
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                print("SyncManager: Failed to compress user profile image")
                return false
            }
            
            // Store image data
            user.profileImageData = imageData
            user.needsSync = true
            
            // Save locally
            try modelContext.save()
            
            // Queue sync if online
            if connectivityMonitor.isConnected {
                Task {
                    await syncUser(user)
                }
            }
            
            return true
        } catch {
            print("SyncManager: Failed to update user profile image locally: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Private Sync Methods
    
    /// Sync a specific project's status and notes to the backend
    private func syncProjectStatus(_ project: Project) async {
        // Only sync if project needs sync
        guard project.needsSync else { return }
        
        do {
            // Different approach based on the status
            if project.status == .completed {
                // For completed projects, use the workflow endpoint
                let newStatus = try await apiService.completeProject(projectId: project.id, status: project.status.rawValue)
            } else {
                // For other statuses, use the regular update endpoint
                try await apiService.updateProjectStatus(id: project.id, status: project.status.rawValue)
            }
            
            // Sync notes if they exist
            if let notes = project.notes, !notes.isEmpty {
                try await apiService.updateProjectNotes(id: project.id, notes: notes)
            }
            
            // Mark as synced if successful
            project.needsSync = false
            project.lastSyncedAt = Date()
            try modelContext.save()
        } catch {
            // Leave as needsSync=true to retry later
            print("❌ SyncManager: Failed to sync project status or notes: \(error.localizedDescription)")
        }
    }
    
    /// Sync any pending project status changes
    private func syncPendingProjectStatusChanges() async -> Int {
        // Skip status synchronization if auto-updates are disabled
        if preventAutoStatusUpdates {
            return 0
        }
        
        // Find projects that need sync, ordered by priority
        let predicate = #Predicate<Project> { $0.needsSync == true }
        var descriptor = FetchDescriptor<Project>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.syncPriority, order: .reverse)]
        
        do {
            let pendingProjects = try modelContext.fetch(descriptor)
            var successCount = 0
            
            
            // Process in batches of 10 to avoid large transaction costs
            for batch in pendingProjects.chunked(into: 10) {
                await withTaskGroup(of: Bool.self) { group in
                    for project in batch {
                        group.addTask {
                            await self.syncProjectStatus(project)
                            return true
                        }
                    }
                    
                    for await success in group {
                        if success {
                            successCount += 1
                        }
                    }
                }
                
                // Give UI a chance to breathe between batches
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            return successCount
        } catch {
            print("Failed to fetch pending projects: \(error.localizedDescription)")
            return 0
        }
    }
    
    /// Force sync projects immediately, bypassing sync budget
    func forceSyncProjects() async {
        print("🔵 SyncManager: Force syncing projects...")
        do {
            try await syncProjects()
            
            // Also refresh any placeholder clients
            await refreshPlaceholderClients()
            
            print("🟢 SyncManager: Force project sync completed")
        } catch {
            print("🔴 SyncManager: Force project sync failed: \(error.localizedDescription)")
        }
    }
    
    /// Refresh any clients that are still showing placeholder data
    private func refreshPlaceholderClients() async {
        do {
            // Find clients that need refreshing (placeholder names)
            let placeholderPredicate = #Predicate<Client> { client in
                client.name.contains("Syncing") || 
                client.name.contains("Loading") || 
                client.name == "Unknown Client"
            }
            let descriptor = FetchDescriptor<Client>(predicate: placeholderPredicate)
            let placeholderClients = try modelContext.fetch(descriptor)
            
            if !placeholderClients.isEmpty {
                print("🔄 SyncManager: Found \(placeholderClients.count) placeholder clients to refresh")
                
                var failedClients: [String] = []
                
                for client in placeholderClients {
                    do {
                        let clientDTO = try await apiService.fetchClient(id: client.id)
                        
                        // Update the client with real data
                        client.name = clientDTO.name ?? "Unknown Client"
                        client.email = clientDTO.emailAddress
                        client.phoneNumber = clientDTO.phoneNumber
                        client.address = clientDTO.address?.formattedAddress
                        client.profileImageURL = clientDTO.thumbnail
                        
                        print("✅ Updated placeholder client to '\(client.name)'")
                    } catch {
                        print("⚠️ Failed to refresh client \(client.id): \(error)")
                        failedClients.append(client.id)
                    }
                }
                
                // Save all updates
                try modelContext.save()
                
                // If we had failures, try syncing all company clients as a fallback
                if !failedClients.isEmpty {
                    print("⚠️ SyncManager: \(failedClients.count) clients failed to sync individually")
                    print("🔄 SyncManager: Attempting to sync all company clients as fallback...")
                    
                    // Get company ID from the first project or user's company
                    if let companyId = try getCompanyId() {
                        await syncCompanyClients(companyId: companyId)
                    } else {
                        print("❌ SyncManager: Could not determine company ID for fallback sync")
                    }
                }
            }
        } catch {
            print("🔴 Failed to refresh placeholder clients: \(error)")
            
            // Even if the placeholder refresh fails, try to sync all clients as last resort
            print("🔄 SyncManager: Attempting fallback sync of all company clients...")
            if let companyId = try? getCompanyId() {
                await syncCompanyClients(companyId: companyId)
            }
        }
    }
    
    /// Helper method to get the company ID for the current user
    private func getCompanyId() throws -> String? {
        // Try to get from a project first
        var projectDescriptor = FetchDescriptor<Project>()
        projectDescriptor.fetchLimit = 1
        
        let projects = try modelContext.fetch(projectDescriptor)
        if let project = projects.first {
            return project.companyId
        }
        
        // Try to get from the current user
        var userDescriptor = FetchDescriptor<User>()
        userDescriptor.fetchLimit = 1
        
        let users = try modelContext.fetch(userDescriptor)
        if let user = users.first,
           let companyId = user.companyId {
            return companyId
        }
        
        return nil
    }
    
    /// Sync projects between local storage and backend
    private func syncProjects() async throws {
        print("🔵 SyncManager: Starting project sync...")
        
        // Get user ID from the provider closure
        guard let userId = userIdProvider() else {
            print("🔴 SyncManager: No user ID available from provider")
            return
        }
        
        print("🔵 SyncManager: User ID: \(userId)")
        
        // Get current user to check role
        let currentUser: User? = await MainActor.run {
            // Find current user in context
            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { $0.id == userId }
            )
            if let user = try? modelContext.fetch(descriptor).first {
                return user
            }
            return nil
        }
        
        // Get company ID for the user
        let companyId = currentUser?.companyId ?? UserDefaults.standard.string(forKey: "currentUserCompanyId")
        
        guard let companyId = companyId else {
            print("🔴 SyncManager: No company ID available for user")
            return
        }
        
        print("🔵 SyncManager: Company ID: \(companyId)")
        print("🔵 SyncManager: User role: \(currentUser?.role.displayName ?? "unknown")")
        
        var remoteProjects: [ProjectDTO] = []
        
        // Fetch projects based on user role
        if let user = currentUser, (user.role == UserRole.admin || user.role == UserRole.officeCrew) {
            // Admin and Office Crew get ALL company projects
            print("🔵 SyncManager: Fetching ALL company projects (admin/office role)")
            remoteProjects = try await apiService.fetchCompanyProjects(companyId: companyId)
        } else {
            // Field Crew only gets assigned projects
            print("🔵 SyncManager: Fetching user's assigned projects (field crew role)")
            remoteProjects = try await apiService.fetchUserProjects(userId: userId)
        }
        
        print("🟢 SyncManager: Fetched \(remoteProjects.count) projects from API")
        
        // Get IDs of all remote projects
        let remoteProjectIds = Set(remoteProjects.map { $0.id })
        
        // Remove local projects that are no longer in the remote list
        // This handles when users are unassigned from projects
        await removeUnassignedProjects(keepingIds: remoteProjectIds, for: currentUser)
        
        // Process batches to avoid memory pressure
        for batch in remoteProjects.chunked(into: 20) {
            await processRemoteProjects(batch)
            
            // Small delay between batches to prevent UI stutter
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }
        
        // Sync calendar events for the company (critical for calendar view)
        print("📅 Syncing calendar events for company...")
        do {
            try await syncCompanyCalendarEvents(companyId: companyId)
        } catch {
            print("⚠️ Failed to sync calendar events: \(error)")
        }
        
        // Sync tasks for all companies (no longer conditional)
        print("📋 Syncing tasks for company...")
        do {
            try await syncCompanyTasks(companyId: companyId)
        } catch {
            print("⚠️ Failed to sync tasks: \(error)")
        }
    }
    
    /// Remove local projects that the user is no longer assigned to
    private func removeUnassignedProjects(keepingIds remoteIds: Set<String>, for user: User?) async {
        do {
            // Fetch all local projects
            let descriptor = FetchDescriptor<Project>()
            let localProjects = try modelContext.fetch(descriptor)
            
            print("🔍 Checking for unassigned projects...")
            print("  - Local projects: \(localProjects.count)")
            print("  - Remote projects: \(remoteIds.count)")
            
            // Find projects to remove (local projects not in remote list)
            let projectsToRemove = localProjects.filter { !remoteIds.contains($0.id) }
            
            if !projectsToRemove.isEmpty {
                print("🗑️ Removing \(projectsToRemove.count) unassigned projects:")
                for project in projectsToRemove {
                    print("  - Removing: \(project.title) (ID: \(project.id))")
                    modelContext.delete(project)
                }
                
                // Save the deletions
                try modelContext.save()
                print("✅ Successfully removed unassigned projects")
            } else {
                print("✅ No unassigned projects to remove")
            }
        } catch {
            print("❌ Error removing unassigned projects: \(error)")
        }
    }
    
    // MARK: - Auto Status Updates Control
    
    /// Disable automatic status updates to backend
    func disableAutoStatusUpdates() {
        preventAutoStatusUpdates = true
    }
    
    /// Enable automatic status updates to backend
    func enableAutoStatusUpdates() {
        preventAutoStatusUpdates = false
    }
    
    /// Toggle automatic status updates
    @discardableResult
    func toggleAutoStatusUpdates() -> Bool {
        preventAutoStatusUpdates.toggle()
        return !preventAutoStatusUpdates // Return true if enabled, false if disabled
    }
    
    /// Force sync all pending project status changes
    func forceSyncPendingStatusChanges() async -> Int {
        return await syncPendingProjectStatusChanges()
    }
    
    /// Process remote projects and update local database
    private func processRemoteProjects(_ remoteProjects: [ProjectDTO]) async {
        print("🔵 SyncManager: Processing \(remoteProjects.count) remote projects")
        
        do {
            // Efficiently handle the projects in memory to reduce database pressure
            let localProjectIds = try fetchLocalProjectIds()
            let usersMap = try fetchUsersMap()
            
            print("🔵 SyncManager: Found \(localProjectIds.count) existing local projects")
            
            // Pre-fetch clients for all projects to ensure they're available
            // This prevents "Loading..." placeholder clients from persisting
            let uniqueClientIds = Set(remoteProjects.compactMap { $0.client })
            if !uniqueClientIds.isEmpty {
                print("🔵 SyncManager: Pre-fetching \(uniqueClientIds.count) unique clients")
                await prefetchClients(clientIds: Array(uniqueClientIds))
            }
            
            for remoteProject in remoteProjects {
                // Debug: Check if this project has a client
                if let clientId = remoteProject.client {
                    print("📋 Project '\(remoteProject.projectName)' has client ID: \(clientId)")
                } else {
                    print("📋 Project '\(remoteProject.projectName)' has NO client ID")
                }
                
                if localProjectIds.contains(remoteProject.id) {
                    await updateExistingProject(remoteProject, usersMap: usersMap)
                } else {
                    await insertNewProject(remoteProject, usersMap: usersMap)
                }
            }
            
            // Save once at the end for better performance
            try modelContext.save()
        } catch {
            print("Failed to process remote projects: \(error)")
        }
    }
    
    /// Fetch just the IDs of local projects for efficient existence checking
    private func fetchLocalProjectIds() throws -> Set<String> {
        let descriptor = FetchDescriptor<Project>()
        let projects = try modelContext.fetch(descriptor)
        return Set(projects.map { $0.id })
    }
    
    /// Create a map of users by ID for efficient relationship handling
    private func fetchUsersMap() throws -> [String: User] {
        let descriptor = FetchDescriptor<User>()
        let users = try modelContext.fetch(descriptor)
        
        // Handle potential duplicate IDs by logging and filtering
        var uniqueUsers: [String: User] = [:]
        let userIds = users.map { $0.id }
        
        // Check for duplicates
        let duplicateIds = Set(userIds.filter { id in
            userIds.filter { $0 == id }.count > 1
        })
        
        if !duplicateIds.isEmpty {
            
            // Just use the first instance of each user with a duplicate ID
            for user in users {
                if uniqueUsers[user.id] == nil {
                    uniqueUsers[user.id] = user
                }
            }
            return uniqueUsers
        } else {
            // No duplicates, use the faster method
            return Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        }
    }
    
    /// Update an existing project efficiently
    private func updateExistingProject(_ remoteDTO: ProjectDTO, usersMap: [String: User]) async {
        do {
            
            
            
            let predicate = #Predicate<Project> { $0.id == remoteDTO.id }
            let descriptor = FetchDescriptor<Project>(predicate: predicate)
            
            if let localProject = try modelContext.fetch(descriptor).first {
                // Check if project needs sync
                if localProject.needsSync {
                    print("⚠️ Skipping update for '\(remoteDTO.projectName)' - has local changes")
                } else {
                    // Only update if not modified locally
                    updateLocalProjectFromRemote(localProject, remoteDTO: remoteDTO)
                    
                    // Sync and link the client if available
                    if let clientId = remoteDTO.client {
                        print("🔗 Linking client \(clientId) to project '\(remoteDTO.projectName)'")
                        await linkProjectToClient(project: localProject, clientId: clientId)
                    } else {
                        print("⚠️ No client to link for project '\(remoteDTO.projectName)'")
                    }
                }
                
                // Update team members
                if let teamMembers = remoteDTO.teamMembers {
                    let teamMemberIds = teamMembers.map { $0 }
                    localProject.setTeamMemberIds(teamMemberIds)
                    updateProjectTeamMembers(localProject, teamMemberIds: teamMemberIds, usersMap: usersMap)
                }
            }
        } catch {
            print("Error updating project \(remoteDTO.id): \(error.localizedDescription)")
        }
    }
    
    /// Insert a new project efficiently
    private func insertNewProject(_ remoteDTO: ProjectDTO, usersMap: [String: User]) async {
        let newProject = remoteDTO.toModel()
        modelContext.insert(newProject)
        
        // Sync and link the client if available
        if let clientId = remoteDTO.client {
            await linkProjectToClient(project: newProject, clientId: clientId)
        }
        
        // Set up relationships
        if let teamMembers = remoteDTO.teamMembers {
            let teamMemberIds = teamMembers.map { $0 }
            updateProjectTeamMembers(newProject, teamMemberIds: teamMemberIds, usersMap: usersMap)
        }
    }
    
    /// Update project's team members relationship efficiently
    private func updateProjectTeamMembers(_ project: Project, teamMemberIds: [String], usersMap: [String: User]) {
        // Clear existing team members to avoid duplicates
        project.teamMembers = []
        
        // Filter out non-existent users from team member IDs
        let validTeamMemberIds = teamMemberIds.filter { !nonExistentUserIds.contains($0) }
        
        // Always set the team member IDs string (with filtered list)
        project.setTeamMemberIds(validTeamMemberIds)
        
        // Add only existing users (avoid fetching again)
        for memberId in validTeamMemberIds {
            if let user = usersMap[memberId] {
                project.teamMembers.append(user)
                
                // Update inverse relationship if needed
                if !user.assignedProjects.contains(where: { $0.id == project.id }) {
                    user.assignedProjects.append(project)
                }
                
                // If user doesn't have phone number, mark for refresh
                if user.phone == nil {
                    Task {
                        await refreshUserData(user)
                    }
                }
            }
        }
        
    }
    
    /// Refresh user data from API if needed
    private func refreshUserData(_ user: User) async {
        // Skip if we already know this user doesn't exist
        if nonExistentUserIds.contains(user.id) {
            print("⏭️ SyncManager: Skipping fetch for known non-existent user \(user.id)")
            modelContext.delete(user)
            try? modelContext.save()
            return
        }
        
        do {
            let userDTO = try await apiService.fetchUser(id: user.id)
            
            // Update user properties that might be missing
            if let phone = userDTO.phone, user.phone == nil {
                user.phone = phone
                print("📱 SyncManager: Updated phone number for \(user.fullName): \(phone)")
            }
            
            // Update other potentially missing fields
            if let email = userDTO.email ?? userDTO.authentication?.email?.email, user.email == nil {
                user.email = email
            }
            
            if let avatarUrl = userDTO.avatar, user.profileImageURL == nil {
                user.profileImageURL = avatarUrl
            }
            
            // Save the context
            try modelContext.save()
        } catch {
            // Check if this is a 404 error (user deleted from Bubble)
            if let apiError = error as? APIError, case .httpError(let statusCode) = apiError, statusCode == 404 {
                print("🗑️ SyncManager: User \(user.id) not found (404), deleting from local database")
                
                // Add to non-existent cache to prevent future fetch attempts
                nonExistentUserIds.insert(user.id)
                
                // Delete the user from local database
                modelContext.delete(user)
                do {
                    try modelContext.save()
                    print("✅ SyncManager: Deleted user \(user.id) from local database")
                } catch {
                    print("❌ SyncManager: Failed to delete user \(user.id): \(error)")
                }
            } else {
                print("⚠️ SyncManager: Failed to refresh user \(user.id): \(error)")
            }
        }
    }
    
    /// Update a local project with remote data
    private func updateLocalProjectFromRemote(_ localProject: Project, remoteDTO: ProjectDTO) {
        // Update project title and basic info
        localProject.title = remoteDTO.projectName
        
        // Update client name directly
        localProject.clientName = remoteDTO.clientName ?? "Unknown Client"
        
        // Update address and location
        if let bubbleAddress = remoteDTO.address {
            localProject.address = bubbleAddress.formattedAddress
            localProject.latitude = bubbleAddress.lat
            localProject.longitude = bubbleAddress.lng
        }
        
        // Update project images - handle both populated and empty arrays (for deletions)
        if let projectImages = remoteDTO.projectImages {
            let remoteImageURLs = Set(projectImages)
            let localImageURLs = Set(localProject.getProjectImages())
            
            // Find images that were deleted on the server
            let deletedImages = localImageURLs.subtracting(remoteImageURLs)
            
            if !deletedImages.isEmpty {
                
                // Clean up local cache for deleted images
                for deletedURL in deletedImages {
                    // Remove from file cache
                    _ = ImageFileManager.shared.deleteImage(localID: deletedURL)
                    // Remove from memory cache
                    ImageCache.shared.remove(forKey: deletedURL)
                }
            }
            
            // Update project with server's image list (handles both additions and deletions)
            localProject.projectImagesString = projectImages.joined(separator: ",")
        } else {
            // If projectImages is nil, clear all local images
            let localImages = localProject.getProjectImages()
            if !localImages.isEmpty {
                
                // Clean up local cache
                for imageURL in localImages {
                    _ = ImageFileManager.shared.deleteImage(localID: imageURL)
                    ImageCache.shared.remove(forKey: imageURL)
                }
            }
            
            localProject.projectImagesString = ""
        }
        
        // Update dates
        if let startDateString = remoteDTO.startDate {
            localProject.startDate = DateFormatter.dateFromBubble(startDateString)
            print("📅 Project '\(localProject.title)' - Start date: \(startDateString) -> \(localProject.startDate?.description ?? "nil")")
        } else {
            print("⚠️ Project '\(localProject.title)' - No start date in API response")
        }
        
        if let completionString = remoteDTO.completion {
            localProject.endDate = DateFormatter.dateFromBubble(completionString)
            print("📅 Project '\(localProject.title)' - End date: \(completionString) -> \(localProject.endDate?.description ?? "nil")")
        } else {
            print("⚠️ Project '\(localProject.title)' - No completion date in API response")
        }
        
        // Update notes and description fields
        localProject.notes = remoteDTO.teamNotes ?? remoteDTO.description
        localProject.projectDescription = remoteDTO.description
        localProject.lastSyncedAt = Date()
        
        // Update company ID from company reference
        if let companyRef = remoteDTO.company {
            localProject.companyId = companyRef.stringValue
        }
        
        // IMPORTANT: Only update status if project is not already being modified locally
        // This prevents automatic status updates when app is opened
        if !localProject.needsSync || !preventAutoStatusUpdates {
            localProject.status = BubbleFields.JobStatus.toSwiftEnum(remoteDTO.status)
        } else {
        }
    }
    
    // MARK: - Task Management
    
    /// Sync tasks for a project
    func syncProjectTasks(projectId: String) async throws {
        print("🔵 SyncManager: Syncing tasks for project \(projectId)")
        
        // Fetch tasks from API
        let remoteTasks = try await apiService.fetchProjectTasks(projectId: projectId)
        print("📥 Received \(remoteTasks.count) tasks from API")
        
        // Get company's default color (projects don't have their own color)
        let projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == projectId }
        )
        let project = try modelContext.fetch(projectDescriptor).first
        let companyId = project?.companyId ?? ""
        
        let companyDescriptor = FetchDescriptor<Company>(
            predicate: #Predicate<Company> { $0.id == companyId }
        )
        let defaultColor = try modelContext.fetch(companyDescriptor).first?.defaultProjectColor ?? "#59779F"
        
        // Get local tasks
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { $0.projectId == projectId }
        )
        let localTasks = try modelContext.fetch(descriptor)
        let localTaskIds = Set(localTasks.map { $0.id })
        
        // Process remote tasks
        for remoteTask in remoteTasks {
            if localTaskIds.contains(remoteTask.id) {
                // Update existing task with project color as default
                if let localTask = localTasks.first(where: { $0.id == remoteTask.id }) {
                    updateTask(localTask, from: remoteTask, defaultColor: defaultColor)
                }
            } else {
                // Insert new task with project color as default
                let newTask = remoteTask.toModel(defaultColor: defaultColor)
                modelContext.insert(newTask)
                
                // Link to project if available
                if let project = try? modelContext.fetch(
                    FetchDescriptor<Project>(
                        predicate: #Predicate<Project> { $0.id == projectId }
                    )
                ).first {
                    newTask.project = project
                    project.tasks.append(newTask)
                }
            }
        }
        
        // Remove local tasks not in remote
        let remoteTaskIds = Set(remoteTasks.map { $0.id })
        for localTask in localTasks {
            if !remoteTaskIds.contains(localTask.id) {
                modelContext.delete(localTask)
            }
        }
        
        try modelContext.save()
        print("✅ Tasks synced successfully for project \(projectId)")
    }
    
    /// Sync all tasks for a company
    func syncCompanyTasks(companyId: String) async throws {
        print("🔵 SyncManager: Syncing all tasks for company \(companyId)")
        
        // Fetch all tasks from API
        let remoteTasks = try await apiService.fetchCompanyTasks(companyId: companyId)
        print("📥 Received \(remoteTasks.count) tasks from API")
        
        // Collect all unique task type IDs from remote tasks
        let remoteTaskTypeIds = Set(remoteTasks.compactMap { $0.type })
        if !remoteTaskTypeIds.isEmpty {
            print("📋 Found \(remoteTaskTypeIds.count) unique task types in tasks")
            
            // Check which task types we don't have locally
            let localTaskTypes = try modelContext.fetch(FetchDescriptor<TaskType>())
            let localTaskTypeIds = Set(localTaskTypes.map { $0.id })
            let unknownTaskTypeIds = remoteTaskTypeIds.subtracting(localTaskTypeIds)
            
            if !unknownTaskTypeIds.isEmpty {
                print("🔄 Need to fetch \(unknownTaskTypeIds.count) missing task types")
                try await syncSpecificTaskTypes(taskTypeIds: Array(unknownTaskTypeIds), companyId: companyId)
            }
        }
        
        // Refresh task types after potential sync
        let localTaskTypes = try modelContext.fetch(FetchDescriptor<TaskType>())
        let taskTypeMap = Dictionary(uniqueKeysWithValues: localTaskTypes.map { ($0.id, $0) })
        
        // Get company's default color
        let companyDescriptor = FetchDescriptor<Company>(
            predicate: #Predicate<Company> { $0.id == companyId }
        )
        let defaultColor = try modelContext.fetch(companyDescriptor).first?.defaultProjectColor ?? "#59779F"
        
        // Get local tasks
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { $0.companyId == companyId }
        )
        let localTasks = try modelContext.fetch(descriptor)
        let localTaskIds = Set(localTasks.map { $0.id })
        
        // Process in batches for performance
        for batch in remoteTasks.chunked(into: 20) {
            for remoteTask in batch {
                if localTaskIds.contains(remoteTask.id) {
                    // Update existing task
                    if let localTask = localTasks.first(where: { $0.id == remoteTask.id }) {
                        updateTask(localTask, from: remoteTask, defaultColor: defaultColor, taskTypeMap: taskTypeMap)
                    }
                } else {
                    // Insert new task with company's default color
                    let newTask = remoteTask.toModel(defaultColor: defaultColor)
                    modelContext.insert(newTask)
                    
                    // Link to task type if available
                    if let taskTypeId = remoteTask.type,
                       let taskType = taskTypeMap[taskTypeId] {
                        newTask.taskType = taskType
                        newTask.taskTypeId = taskTypeId
                    }
                    
                    // Link to project if available
                    if let projectId = remoteTask.projectId,
                       let project = try? modelContext.fetch(
                        FetchDescriptor<Project>(
                            predicate: #Predicate<Project> { $0.id == projectId }
                        )
                    ).first {
                        newTask.project = project
                        if !project.tasks.contains(where: { $0.id == newTask.id }) {
                            project.tasks.append(newTask)
                        }
                    }
                }
            }
            
            // Small delay between batches
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }
        
        // Remove local tasks not in remote
        let remoteTaskIds = Set(remoteTasks.map { $0.id })
        for localTask in localTasks {
            if !remoteTaskIds.contains(localTask.id) {
                modelContext.delete(localTask)
            }
        }
        
        try modelContext.save()
        print("✅ All tasks synced successfully for company \(companyId)")
    }
    
    /// Update a local task from a remote DTO
    private func updateTask(_ localTask: ProjectTask, from remoteTask: TaskDTO, defaultColor: String? = nil, taskTypeMap: [String: TaskType]? = nil) {
        if let status = remoteTask.status {
            localTask.status = TaskStatus(rawValue: status) ?? .scheduled
        }
        if let taskColor = remoteTask.taskColor {
            localTask.taskColor = taskColor
        } else if let defaultColor = defaultColor {
            // Use company default if no color specified
            localTask.taskColor = defaultColor
        }
        localTask.taskNotes = remoteTask.taskNotes
        localTask.displayOrder = remoteTask.taskIndex ?? 0
        localTask.calendarEventId = remoteTask.calendarEventId
        
        // Update task type if provided
        if let taskTypeId = remoteTask.type {
            localTask.taskTypeId = taskTypeId
            // Try to link to actual task type object if available
            if let taskTypeMap = taskTypeMap,
               let taskType = taskTypeMap[taskTypeId] {
                localTask.taskType = taskType
            } else if let taskType = try? modelContext.fetch(
                FetchDescriptor<TaskType>(
                    predicate: #Predicate<TaskType> { $0.id == taskTypeId }
                )
            ).first {
                localTask.taskType = taskType
            }
        }
        
        if let teamMembers = remoteTask.teamMembers {
            localTask.setTeamMemberIds(teamMembers)
        }
    }
    
    /// Sync task types for a company
    /// Sync specific task types by their IDs
    func syncSpecificTaskTypes(taskTypeIds: [String], companyId: String) async throws {
        guard !taskTypeIds.isEmpty else { return }
        
        print("🔵 SyncManager: Fetching \(taskTypeIds.count) specific task types")
        
        // Fetch specific task types from API
        let remoteTaskTypes = try await apiService.fetchTaskTypesByIds(ids: taskTypeIds)
        print("📥 Received \(remoteTaskTypes.count) task types from API")
        
        // Process each task type
        for remoteTaskType in remoteTaskTypes {
            // Check if exists locally
            let descriptor = FetchDescriptor<TaskType>(
                predicate: #Predicate<TaskType> { $0.id == remoteTaskType.id }
            )
            let existing = try modelContext.fetch(descriptor).first
            
            if let existingType = existing {
                // Update existing
                existingType.display = remoteTaskType.display
                existingType.color = remoteTaskType.color
                existingType.isDefault = remoteTaskType.isDefault ?? false
                // Keep existing icon and display order
            } else {
                // Create new
                let newTaskType = remoteTaskType.toModel()
                newTaskType.companyId = companyId
                modelContext.insert(newTaskType)
            }
        }
        
        // Assign icons to any task types that don't have them
        let allTaskTypes = try modelContext.fetch(FetchDescriptor<TaskType>(
            predicate: #Predicate<TaskType> { $0.companyId == companyId }
        ))
        TaskType.assignIconsToTaskTypes(allTaskTypes)
        
        try modelContext.save()
        print("✅ Specific task types synced successfully")
    }
    
    /// Sync calendar events for a company
    func syncCompanyCalendarEvents(companyId: String) async throws {
        print("🔵 SyncManager: Syncing calendar events for company \(companyId)")
        
        // Fetch calendar events from API
        let remoteEvents = try await apiService.fetchCompanyCalendarEvents(companyId: companyId)
        print("📥 Received \(remoteEvents.count) calendar events from API")
        
        // Get local events
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate<CalendarEvent> { $0.companyId == companyId }
        )
        let localEvents = try modelContext.fetch(descriptor)
        let localEventIds = Set(localEvents.map { $0.id })
        
        // Process remote events
        for remoteEvent in remoteEvents {
            if localEventIds.contains(remoteEvent.id) {
                // Update existing event
                if let localEvent = localEvents.first(where: { $0.id == remoteEvent.id }) {
                    updateCalendarEvent(localEvent, from: remoteEvent)
                }
            } else {
                // Insert new event
                guard let newEvent = remoteEvent.toModel() else {
                    print("⚠️ Failed to create CalendarEvent from DTO: \(remoteEvent.id)")
                    continue
                }
                modelContext.insert(newEvent)
                
                // Link to project if available
                if let projectId = remoteEvent.projectId {
                    let projectDescriptor = FetchDescriptor<Project>(
                        predicate: #Predicate<Project> { $0.id == projectId }
                    )
                    if let project = try modelContext.fetch(projectDescriptor).first {
                        newEvent.project = project
                        // Cache the project's event type for efficient filtering
                        newEvent.projectEventType = project.effectiveEventType
                        
                        // If this is a project-level event, set it as the primary calendar event
                        if newEvent.type == .project && project.effectiveEventType == .project {
                            project.primaryCalendarEvent = newEvent
                            // Sync dates from calendar event to project
                            project.syncDatesWithCalendarEvent()
                        }
                    }
                }
                
                // Link to task if available
                if let taskId = remoteEvent.taskId {
                    let taskDescriptor = FetchDescriptor<ProjectTask>(
                        predicate: #Predicate<ProjectTask> { $0.id == taskId }
                    )
                    if let task = try modelContext.fetch(taskDescriptor).first {
                        newEvent.task = task
                        task.calendarEvent = newEvent
                    }
                }
            }
        }
        
        // Remove local events not in remote
        let remoteEventIds = Set(remoteEvents.map { $0.id })
        for localEvent in localEvents {
            if !remoteEventIds.contains(localEvent.id) {
                modelContext.delete(localEvent)
            }
        }
        
        try modelContext.save()
        print("✅ Calendar events synced successfully for company \(companyId)")
    }
    
    /// Update a local calendar event from remote DTO
    private func updateCalendarEvent(_ localEvent: CalendarEvent, from remoteEvent: CalendarEventDTO) {
        localEvent.title = remoteEvent.title ?? ""
        
        let dateFormatter = ISO8601DateFormatter()
        if let startDateStr = remoteEvent.startDate, let startDate = dateFormatter.date(from: startDateStr) {
            localEvent.startDate = startDate
        }
        
        if let endDateStr = remoteEvent.endDate, let endDate = dateFormatter.date(from: endDateStr) {
            localEvent.endDate = endDate
        }
        
        localEvent.type = CalendarEventType(rawValue: remoteEvent.type?.lowercased() ?? "project") ?? .project
        localEvent.color = remoteEvent.color ?? "#59779F"
        localEvent.duration = Int(remoteEvent.duration ?? 1)
        
        if let teamMembers = remoteEvent.teamMembers {
            localEvent.setTeamMemberIds(teamMembers)
        }
        
        // If this is a project-level event, sync dates back to the project
        if localEvent.type == .project, let project = localEvent.project {
            project.syncDatesWithCalendarEvent()
        }
        
        localEvent.lastSyncedAt = Date()
    }
    
    func syncCompanyTaskTypes(companyId: String) async throws {
        print("🔵 SyncManager: Syncing task types for company \(companyId)")
        
        // Fetch task types from API
        let remoteTaskTypes = try await apiService.fetchCompanyTaskTypes(companyId: companyId)
        print("📥 Received \(remoteTaskTypes.count) task types from API")
        
        // Get local task types
        let descriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate<TaskType> { $0.companyId == companyId }
        )
        let localTaskTypes = try modelContext.fetch(descriptor)
        
        // If no remote task types exist, create defaults
        if remoteTaskTypes.isEmpty {
            print("📝 No task types found, creating defaults...")
            let defaultTypes = TaskType.createDefaults(companyId: companyId)
            for taskType in defaultTypes {
                modelContext.insert(taskType)
                
                // Also create in API
                _ = try? await apiService.createTaskType(TaskTypeDTO.from(taskType))
            }
            try modelContext.save()
            return
        }
        
        let localTaskTypeIds = Set(localTaskTypes.map { $0.id })
        
        // Process remote task types
        for remoteTaskType in remoteTaskTypes {
            if localTaskTypeIds.contains(remoteTaskType.id) {
                // Update existing task type
                if let localTaskType = localTaskTypes.first(where: { $0.id == remoteTaskType.id }) {
                    localTaskType.display = remoteTaskType.display
                    localTaskType.color = remoteTaskType.color
                    // Keep existing icon if it exists (icon field doesn't exist in Bubble)
                    // Icon will be assigned later if it's nil
                    localTaskType.isDefault = remoteTaskType.isDefault ?? false
                    // Keep existing display order or set to 0 if not set
                    if localTaskType.displayOrder == 0 {
                        localTaskType.displayOrder = 0
                    }
                }
            } else {
                // Insert new task type
                let newTaskType = remoteTaskType.toModel()
                newTaskType.companyId = companyId  // Set company ID since it's not in the DTO
                modelContext.insert(newTaskType)
            }
        }
        
        // Remove local task types not in remote
        let remoteTaskTypeIds = Set(remoteTaskTypes.map { $0.id })
        for localTaskType in localTaskTypes {
            if !remoteTaskTypeIds.contains(localTaskType.id) {
                modelContext.delete(localTaskType)
            }
        }
        
        // After syncing, assign icons to task types that don't have them
        let allTaskTypes = try modelContext.fetch(descriptor)
        TaskType.assignIconsToTaskTypes(allTaskTypes)
        
        try modelContext.save()
        print("✅ Task types synced successfully for company \(companyId)")
    }
    
    /// Update tasks when project status changes
    private func updateTasksForProjectStatus(project: Project, projectStatus: Status) {
        switch projectStatus {
        case .inProgress:
            // When project starts, start the first scheduled task
            if let firstScheduledTask = project.tasks
                .filter({ $0.status == .scheduled })
                .sorted(by: { $0.displayOrder < $1.displayOrder })
                .first {
                firstScheduledTask.status = .inProgress
                firstScheduledTask.needsSync = true
                print("🔵 Started task: \(firstScheduledTask.taskType?.display ?? "Task")")
            }
            
        case .completed:
            // When project completes, mark all non-cancelled tasks as completed
            for task in project.tasks {
                if task.status != .cancelled {
                    task.status = .completed
                    task.needsSync = true
                }
            }
            print("✅ Marked \(project.tasks.filter { $0.status == .completed }.count) tasks as completed")
            
        default:
            // No automatic task updates for other project statuses
            break
        }
    }
    
    /// Update task status on backend
    func updateTaskStatus(taskId: String, status: TaskStatus) async throws {
        print("🔵 SyncManager: Updating task \(taskId) status to \(status.rawValue)")
        
        // Update locally first
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { $0.id == taskId }
        )
        
        if let task = try modelContext.fetch(descriptor).first {
            task.status = status
            task.needsSync = true
            try modelContext.save()
        }
        
        // Update on backend
        try await apiService.updateTaskStatus(id: taskId, status: status.rawValue)
        
        // Mark as synced
        if let task = try modelContext.fetch(descriptor).first {
            task.needsSync = false
            try modelContext.save()
        }
        
        print("✅ Task status updated successfully")
    }
    
    // MARK: - Client Management
    
    /// Link a project to its client, fetching the client if needed
    /// Update client contact information via API
    func updateClientContact(clientId: String, name: String, email: String?, phone: String?, address: String?) async throws -> Client? {
        do {
            print("📝 SyncManager: Updating client contact info for \(clientId)")
            
            // Call the Bubble workflow API and get the updated client
            let updatedClientDTO = try await apiService.updateClientContact(
                clientId: clientId,
                name: name,
                email: email,
                phone: phone,
                address: address
            )
            
            print("✅ Client contact updated via API")
            print("📥 Received updated client data from API:")
            print("  - Name: \(updatedClientDTO.name ?? "nil")")
            print("  - Email: \(updatedClientDTO.emailAddress ?? "nil")")
            print("  - Phone: \(updatedClientDTO.phoneNumber ?? "nil")")
            print("  - Address: \(updatedClientDTO.address?.formattedAddress ?? "nil")")
            
            // Update local client with the data returned from API
            let clientPredicate = #Predicate<Client> { $0.id == clientId }
            let clientDescriptor = FetchDescriptor<Client>(predicate: clientPredicate)
            
            if let existingClient = try modelContext.fetch(clientDescriptor).first {
                // Update with actual values from API response
                existingClient.name = updatedClientDTO.name ?? "Unknown Client"
                existingClient.email = updatedClientDTO.emailAddress
                existingClient.phoneNumber = updatedClientDTO.phoneNumber
                
                if let address = updatedClientDTO.address {
                    existingClient.address = address.formattedAddress
                    existingClient.latitude = address.lat
                    existingClient.longitude = address.lng
                } else {
                    existingClient.address = nil
                    existingClient.latitude = nil
                    existingClient.longitude = nil
                }
                
                existingClient.lastSyncedAt = Date()
                
                try modelContext.save()
                print("✅ Local client updated with API response data")
                
                return existingClient
            } else {
                // Client doesn't exist locally, create it from the API response
                let newClient = updatedClientDTO.toModel()
                modelContext.insert(newClient)
                try modelContext.save()
                
                print("✅ Created new local client from API response")
                return newClient
            }
            
        } catch {
            print("❌ SyncManager: Failed to update client contact: \(error)")
            throw error
        }
    }
    
    // MARK: - Sub-Client Methods
    
    func createSubClient(clientId: String, name: String, title: String?, email: String?, phone: String?, address: String?) async throws -> SubClientDTO {
        do {
            print("📝 SyncManager: Creating sub-client for client \(clientId)")
            
            // Call the API to create sub-client
            let subClientDTO = try await apiService.createSubClient(
                clientId: clientId,
                name: name,
                title: title,
                email: email,
                phone: phone,
                address: address
            )
            
            print("✅ SyncManager: Sub-client created successfully")
            return subClientDTO
        } catch {
            print("❌ SyncManager: Failed to create sub-client: \(error)")
            throw error
        }
    }
    
    func editSubClient(subClientId: String, name: String, title: String?, email: String?, phone: String?, address: String?) async throws -> SubClientDTO {
        do {
            print("📝 SyncManager: Editing sub-client \(subClientId)")
            
            // Call the API to edit sub-client
            let subClientDTO = try await apiService.editSubClient(
                subClientId: subClientId,
                name: name,
                title: title,
                email: email,
                phone: phone,
                address: address
            )
            
            print("✅ SyncManager: Sub-client updated successfully")
            return subClientDTO
        } catch {
            print("❌ SyncManager: Failed to edit sub-client: \(error)")
            throw error
        }
    }
    
    func deleteSubClient(subClientId: String) async throws {
        do {
            print("🗑 SyncManager: Deleting sub-client \(subClientId)")
            
            // Call the API to delete sub-client
            try await apiService.deleteSubClient(subClientId: subClientId)
            
            print("✅ SyncManager: Sub-client deleted successfully")
        } catch {
            print("❌ SyncManager: Failed to delete sub-client: \(error)")
            throw error
        }
    }
    
    /// Refresh a single client's data when viewing project details
    func refreshSingleClient(clientId: String, for project: Project, forceRefresh: Bool = false) async {
        do {
            print("🔄 SyncManager: Refreshing single client \(clientId) (force: \(forceRefresh))")
            
            // Fetch fresh data from API
            let clientDTO = try await apiService.fetchClient(id: clientId)
            
            // Check if client already exists locally
            let clientPredicate = #Predicate<Client> { $0.id == clientId }
            let clientDescriptor = FetchDescriptor<Client>(predicate: clientPredicate)
            
            if let existingClient = try modelContext.fetch(clientDescriptor).first {
                // Update existing client with fresh data
                print("📝 Updating existing client '\(existingClient.name)' with fresh data")
                
                existingClient.name = clientDTO.name ?? "Unknown Client"
                existingClient.email = clientDTO.emailAddress
                existingClient.phoneNumber = clientDTO.phoneNumber
                existingClient.profileImageURL = clientDTO.thumbnail
                
                if let address = clientDTO.address {
                    existingClient.address = address.formattedAddress
                    existingClient.latitude = address.lat
                    existingClient.longitude = address.lng
                }
                
                existingClient.lastSyncedAt = Date()
                
                // Fetch and update sub-clients based on IDs from client response
                print("🔵 Fetching sub-clients for client '\(existingClient.name)'")
                
                // Check if we have sub-client IDs from the client response
                if let subClientIds = clientDTO.subClientIds, !subClientIds.isEmpty {
                    print("📋 Client has \(subClientIds.count) sub-client IDs to fetch: \(subClientIds)")
                    
                    // Clear existing sub-clients
                    existingClient.subClients.removeAll()
                    
                    // Track how many we successfully fetch
                    var successfulFetches = 0
                    
                    // Fetch each sub-client by ID
                    for subClientId in subClientIds {
                        do {
                            print("  🔵 Fetching sub-client with ID: \(subClientId)")
                            let subClientDTO: SubClientDTO = try await apiService.fetchBubbleObject(
                                objectType: BubbleFields.Types.subClient,
                                id: subClientId
                            )
                            let subClient = subClientDTO.toSubClient()
                            subClient.client = existingClient
                            modelContext.insert(subClient)  // Insert into SwiftData
                            existingClient.subClients.append(subClient)
                            successfulFetches += 1
                            print("  ✅ Fetched sub-client: \(subClient.name)")
                        } catch {
                            print("  ⚠️ Failed to fetch sub-client \(subClientId): \(error)")
                            // Continue with other sub-clients even if one fails
                        }
                    }
                    
                    // If all ID fetches failed, try constraint query as fallback
                    if successfulFetches == 0 && subClientIds.count > 0 {
                        print("⚠️ All sub-client ID fetches failed, trying constraint query as fallback")
                        let subClientDTOs = try await apiService.fetchSubClientsForClient(clientId: clientId)
                        print("  🔵 Found \(subClientDTOs.count) sub-clients via constraint query")
                        
                        for subClientDTO in subClientDTOs {
                            let subClient = subClientDTO.toSubClient()
                            subClient.client = existingClient
                            modelContext.insert(subClient)
                            existingClient.subClients.append(subClient)
                            print("  ✅ Added sub-client via constraint: \(subClient.name)")
                        }
                    }
                } else {
                    print("📋 No sub-client IDs in response, trying constraint query")
                    // Fallback: Try fetching sub-clients by client ID constraint
                    let subClientDTOs = try await apiService.fetchSubClientsForClient(clientId: clientId)
                    print("  🔵 Found \(subClientDTOs.count) sub-clients via constraint query")
                    
                    // Clear existing sub-clients and add fresh ones
                    existingClient.subClients.removeAll()
                    for subClientDTO in subClientDTOs {
                        let subClient = subClientDTO.toSubClient()
                        subClient.client = existingClient
                        modelContext.insert(subClient)  // Insert into SwiftData
                        existingClient.subClients.append(subClient)
                        print("  ✅ Added sub-client via constraint: \(subClient.name)")
                    }
                }
                
                print("✅ Client updated: Name='\(existingClient.name)', Email='\(existingClient.email ?? "nil")', Phone='\(existingClient.phoneNumber ?? "nil")', SubClients=\(existingClient.subClients.count)")
            } else {
                // Create new client
                print("🆕 Creating new client from fresh data")
                let newClient = clientDTO.toModel()
                newClient.companyId = project.companyId
                modelContext.insert(newClient)
                
                // Link to project
                project.client = newClient
                project.clientId = clientId
                newClient.projects.append(project)
                
                // Fetch and add sub-clients for new client
                print("🔵 Fetching sub-clients for new client '\(newClient.name)'")
                
                // Check if we have sub-client IDs from the client response
                if let subClientIds = clientDTO.subClientIds, !subClientIds.isEmpty {
                    print("📋 New client has \(subClientIds.count) sub-client IDs to fetch: \(subClientIds)")
                    
                    // Fetch each sub-client by ID
                    for subClientId in subClientIds {
                        do {
                            print("  🔵 Fetching sub-client with ID: \(subClientId)")
                            let subClientDTO: SubClientDTO = try await apiService.fetchBubbleObject(
                                objectType: BubbleFields.Types.subClient,
                                id: subClientId
                            )
                            let subClient = subClientDTO.toSubClient()
                            subClient.client = newClient
                            modelContext.insert(subClient)  // Insert into SwiftData
                            newClient.subClients.append(subClient)
                            print("  ✅ Fetched sub-client: \(subClient.name)")
                        } catch {
                            print("  ⚠️ Failed to fetch sub-client \(subClientId): \(error)")
                            // Continue with other sub-clients even if one fails
                        }
                    }
                } else {
                    print("📋 No sub-client IDs in response, trying constraint query")
                    // Fallback: Try fetching sub-clients by client ID constraint
                    let subClientDTOs = try await apiService.fetchSubClientsForClient(clientId: clientId)
                    print("  🔵 Found \(subClientDTOs.count) sub-clients via constraint query")
                    
                    for subClientDTO in subClientDTOs {
                        let subClient = subClientDTO.toSubClient()
                        subClient.client = newClient
                        modelContext.insert(subClient)  // Insert into SwiftData
                        newClient.subClients.append(subClient)
                        print("  ✅ Added sub-client via constraint: \(subClient.name)")
                    }
                }
                
                print("✅ New client created: Name='\(newClient.name)', Email='\(newClient.email ?? "nil")', Phone='\(newClient.phoneNumber ?? "nil")', SubClients=\(newClient.subClients.count)")
            }
            
            // Save changes
            try modelContext.save()
            
        } catch {
            print("❌ SyncManager: Failed to refresh client \(clientId): \(error)")
            
            // Handle 404 gracefully
            if case APIError.httpError(let statusCode) = error, statusCode == 404 {
                print("⚠️ Client \(clientId) not found (404)")
            }
        }
    }
    
    /// Pre-fetch multiple clients in batch to avoid individual API calls
    private func prefetchClients(clientIds: [String]) async {
        do {
            // Get existing client IDs to avoid re-fetching
            let existingClients = try modelContext.fetch(FetchDescriptor<Client>())
            let existingClientIds = Set(existingClients.map { $0.id })
            
            // Filter to only fetch missing clients
            let missingClientIds = clientIds.filter { !existingClientIds.contains($0) }
            
            if missingClientIds.isEmpty {
                print("✅ All \(clientIds.count) clients already exist locally")
                return
            }
            
            print("🔵 SyncManager: Fetching \(missingClientIds.count) missing clients from API")
            
            // Fetch missing clients in batch
            let clientDTOs = try await apiService.fetchClientsByIds(clientIds: missingClientIds)
            
            print("🟢 SyncManager: Fetched \(clientDTOs.count) clients from API")
            
            // Convert and save
            for clientDTO in clientDTOs {
                let client = clientDTO.toModel()
                modelContext.insert(client)
            }
            
            // Check for any clients that weren't returned by the API
            let fetchedIds = Set(clientDTOs.map { $0.id })
            let notFoundIds = Set(missingClientIds).subtracting(fetchedIds)
            
            if !notFoundIds.isEmpty {
                print("⚠️ \(notFoundIds.count) clients not found in API response")
                // Create placeholder clients for missing ones
                for clientId in notFoundIds {
                    let placeholderClient = Client(
                        id: clientId,
                        name: "Client #\(clientId.prefix(4))",
                        email: nil,
                        phoneNumber: nil,
                        address: nil
                    )
                    modelContext.insert(placeholderClient)
                }
            }
            
            try modelContext.save()
            
        } catch {
            print("❌ SyncManager: Failed to prefetch clients: \(error)")
            
            // As a last resort, try to sync all company clients
            print("🔄 SyncManager: Attempting fallback sync of all company clients...")
            if let companyId = try? getCompanyId() {
                await syncCompanyClients(companyId: companyId)
            } else {
                print("❌ SyncManager: Could not determine company ID for fallback sync")
            }
        }
    }
    
    private func linkProjectToClient(project: Project, clientId: String) async {
        do {
            // First check if we already have this client locally
            let clientPredicate = #Predicate<Client> { $0.id == clientId }
            let clientDescriptor = FetchDescriptor<Client>(predicate: clientPredicate)
            
            if let existingClient = try modelContext.fetch(clientDescriptor).first {
                // Client exists locally, just link it
                print("✅ Found existing client '\(existingClient.name)' for project '\(project.title)'")
                
                project.client = existingClient
                project.clientId = clientId
                
                // Ensure client has this project in its list
                if !existingClient.projects.contains(where: { $0.id == project.id }) {
                    existingClient.projects.append(project)
                }
            } else {
                // Client doesn't exist locally - try to fetch it immediately
                print("📝 Client \(clientId) not found locally for project '\(project.title)' - fetching from API")
                
                // Try to fetch the client data immediately
                var clientName = "Unknown Client"
                var clientEmail: String? = nil
                var clientPhone: String? = nil
                var clientAddress: String? = nil
                var clientThumbnail: String? = nil
                
                do {
                    let clientDTO = try await apiService.fetchClient(id: clientId)
                    clientName = clientDTO.name ?? "Unknown Client"
                    clientEmail = clientDTO.emailAddress
                    clientPhone = clientDTO.phoneNumber
                    clientAddress = clientDTO.address?.formattedAddress
                    clientThumbnail = clientDTO.thumbnail
                    print("✅ Successfully fetched client '\(clientName)' from API")
                } catch {
                    print("⚠️ Failed to fetch client \(clientId) from API: \(error)")
                    print("📝 Creating placeholder that will retry on next sync")
                    clientName = "Client (Syncing...)"
                    
                    // Try to sync all company clients as fallback
                    let companyId = project.companyId
                    if !companyId.isEmpty {
                        print("🔄 Attempting to sync all company clients as fallback...")
                        await syncCompanyClients(companyId: companyId)
                        
                        // Check if client exists now after company sync
                        let checkPredicate = #Predicate<Client> { $0.id == clientId }
                        let checkDescriptor = FetchDescriptor<Client>(predicate: checkPredicate)
                        if let syncedClient = try? modelContext.fetch(checkDescriptor).first {
                            print("✅ Client found after company sync!")
                            project.client = syncedClient
                            project.clientId = clientId
                            if !syncedClient.projects.contains(where: { $0.id == project.id }) {
                                syncedClient.projects.append(project)
                            }
                            try? modelContext.save()
                            return
                        }
                    }
                }
                
                let placeholderClient = Client(
                    id: clientId,
                    name: clientName,
                    email: clientEmail,
                    phoneNumber: clientPhone,
                    address: clientAddress
                )
                placeholderClient.companyId = project.companyId
                placeholderClient.profileImageURL = clientThumbnail
                modelContext.insert(placeholderClient)
                
                // Link to project
                project.client = placeholderClient
                project.clientId = clientId
                placeholderClient.projects.append(project)
                
                print("📎 Linked placeholder client to project '\(project.title)'")
            }
            
            // Save the context
            try modelContext.save()
        } catch {
            print("⚠️ SyncManager: Failed to link client \(clientId) to project: \(error)")
        }
    }
    
    /// Sync all clients for a company
    func syncCompanyClients(companyId: String) async {
        do {
            print("🔵 SyncManager: Fetching clients for company \(companyId)")
            
            // Fetch all clients for the company from API
            let clientDTOs = try await apiService.fetchCompanyClients(companyId: companyId)
            
            print("🔵 SyncManager: Fetched \(clientDTOs.count) clients from API")
            
            // Get existing clients for this company
            let existingDescriptor = FetchDescriptor<Client>(
                predicate: #Predicate<Client> { client in
                    client.companyId == companyId
                }
            )
            let existingClients = try modelContext.fetch(existingDescriptor)
            let existingClientIds = Set(existingClients.map { $0.id })
            
            // Create set of current client IDs from API
            let currentClientIds = Set(clientDTOs.map { $0.id })
            
            // Delete clients that are no longer in the API response
            for client in existingClients {
                if !currentClientIds.contains(client.id) {
                    print("🗑️ SyncManager: Removing client \(client.name) - no longer in company")
                    modelContext.delete(client)
                }
            }
            
            // Process each client from API
            for clientDTO in clientDTOs {
                if let existingClient = existingClients.first(where: { $0.id == clientDTO.id }) {
                    // Update existing client
                    existingClient.name = clientDTO.name ?? "Unknown Client"
                    existingClient.email = clientDTO.emailAddress
                    existingClient.phoneNumber = clientDTO.phoneNumber
                    
                    if let address = clientDTO.address {
                        existingClient.address = address.formattedAddress
                        existingClient.latitude = address.lat
                        existingClient.longitude = address.lng
                    }
                    
                    existingClient.lastSyncedAt = Date()
                } else {
                    // Create new client
                    let newClient = clientDTO.toModel()
                    newClient.companyId = companyId
                    modelContext.insert(newClient)
                }
            }
            
            // Save all changes
            try modelContext.save()
            
            print("🟢 SyncManager: Client sync completed")
        } catch {
            print("❌ SyncManager: Failed to sync clients: \(error)")
        }
    }
    
    /// Sync team members for a company
    /// - Parameter company: The company to fetch team members for
    @MainActor
    func syncCompanyTeamMembers(_ company: Company) async {
        
        // Determine which approach to use: company-based or ID-based
        let useCompanyBasedApproach = true // This gives us all users in the company
        
        do {
            var userDTOs: [UserDTO] = []
            
            if useCompanyBasedApproach {
                // Approach 1: Fetch users by company ID (more efficient)
                
                // Execute the API call with the correct constraint format
                userDTOs = try await apiService.fetchCompanyUsers(companyId: company.id)
                
                if !userDTOs.isEmpty {
                    print("📱 SyncManager: Fetched \(userDTOs.count) team members for company")
                    // Debug: Log first user's data
                    if let firstUser = userDTOs.first {
                        print("📱 First user data sample:")
                        print("  - Name: \(firstUser.nameFirst ?? "nil") \(firstUser.nameLast ?? "nil")")
                        print("  - Email: \(firstUser.email ?? "nil")")
                        print("  - Phone: \(firstUser.phone ?? "nil")")
                    }
                }
            } else {
                // Approach 2: Fetch users by their IDs (more targeted but requires multiple IDs)
                let teamIds = company.getTeamIds()
                
                guard !teamIds.isEmpty else {
                    return
                }
                
                userDTOs = try await apiService.fetchUsersByIds(userIds: teamIds)
            }
            
            // Get all existing User objects for this company
            let companyId = company.id
            let existingUsersDescriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { user in 
                    user.companyId == companyId
                }
            )
            let existingUsers = try modelContext.fetch(existingUsersDescriptor)
            
            // Create a set of user IDs from the API response
            let currentUserIds = Set(userDTOs.map { $0.id })
            
            // Delete users that are no longer in the company
            for user in existingUsers {
                if !currentUserIds.contains(user.id) {
                    print("🗑️ SyncManager: Removing user \(user.fullName) - no longer in company")
                    modelContext.delete(user)
                }
            }
            
            // Clear existing team members to avoid duplicates
            company.teamMembers = []
            
            // Get admin IDs from company if available
            let adminIds = company.getAdminIds()
            
            // Create or update User and TeamMember objects from the DTOs
            for userDTO in userDTOs {
                // Check if this user is an admin
                let isAdmin = adminIds.contains(userDTO.id)
                
                // Update or create User object
                if let existingUser = existingUsers.first(where: { $0.id == userDTO.id }) {
                    // Update existing user
                    existingUser.firstName = userDTO.nameFirst ?? ""
                    existingUser.lastName = userDTO.nameLast ?? ""
                    existingUser.email = userDTO.email
                    existingUser.phone = userDTO.phone
                    
                    // Extract role from userType and employeeType
                    if userDTO.userType == BubbleFields.UserType.admin {
                        existingUser.role = .admin
                    } else if let employeeTypeString = userDTO.employeeType {
                        existingUser.role = BubbleFields.EmployeeType.toSwiftEnum(employeeTypeString)
                    } else {
                        existingUser.role = .fieldCrew
                    }
                    
                    existingUser.profileImageURL = userDTO.avatar
                    existingUser.isActive = true // Users from API are considered active
                } else {
                    // Extract role for new user
                    let role: UserRole
                    if userDTO.userType == BubbleFields.UserType.admin {
                        role = .admin
                    } else if let employeeTypeString = userDTO.employeeType {
                        role = BubbleFields.EmployeeType.toSwiftEnum(employeeTypeString)
                    } else {
                        role = .fieldCrew
                    }
                    
                    // Create new User object
                    let newUser = User(
                        id: userDTO.id,
                        firstName: userDTO.nameFirst ?? "",
                        lastName: userDTO.nameLast ?? "",
                        role: role,
                        companyId: company.id
                    )
                    newUser.email = userDTO.email
                    newUser.phone = userDTO.phone
                    newUser.profileImageURL = userDTO.avatar
                    newUser.isActive = true // Users from API are considered active
                    modelContext.insert(newUser)
                }
                
                // Create TeamMember object
                let teamMember = TeamMember.fromUserDTO(userDTO, isAdmin: isAdmin)
                teamMember.company = company
                company.teamMembers.append(teamMember)
                
                if let email = teamMember.email {
                }
                if let phone = teamMember.phone {
                }
            }
            
            // Mark team members as synced
            company.teamMembersSynced = true
            company.lastSyncedAt = Date()
            
            // Save changes to the database
            try modelContext.save()
            
        } catch {
            print("❌ SyncManager: Failed to sync team members: \(error.localizedDescription)")
        }
    }
}

// MARK: - Extensions

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension UserDefaults {
    /// Get a boolean value with a default value if the key doesn't exist
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
}
