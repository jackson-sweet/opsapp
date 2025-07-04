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
    func triggerBackgroundSync() {
        guard !syncInProgress, connectivityMonitor.isConnected else {
            return
        }
        
        syncInProgress = true
        syncStateSubject.send(true)
        
        Task {
            do {
                // First sync users that need sync (always allowed)
                let userSyncCount = await syncPendingUserChanges()
                
                // Then sync high-priority project items (status changes) if auto-updates are enabled
                var highPriorityCount = 0
                if !preventAutoStatusUpdates {
                    highPriorityCount = await syncPendingProjectStatusChanges()
                } else {
                }
                
                // Finally, fetch remote data if we didn't exhaust our sync budget
                if (userSyncCount + highPriorityCount) < 10 {
                    try await syncProjects()
                }
                
                // Schedule notifications for future projects after sync
                await NotificationManager.shared.scheduleNotificationsForAllProjects(using: modelContext)
                
                syncInProgress = false
                syncStateSubject.send(false)
            } catch {
                print("SyncManager: Background sync failed: \(error.localizedDescription)")
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
    
    /// Sync projects between local storage and backend
    private func syncProjects() async throws {
        // Get user ID from the provider closure
        guard let userId = userIdProvider() else {
            return
        }
        
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
            return
        }
        
        var remoteProjects: [ProjectDTO] = []
        
        // Fetch projects based on user role
        if let user = currentUser, (user.role == UserRole.admin || user.role == UserRole.officeCrew) {
            // Admin and Office Crew get ALL company projects
            remoteProjects = try await apiService.fetchCompanyProjects(companyId: companyId)
        } else {
            // Field Crew only gets assigned projects
            remoteProjects = try await apiService.fetchUserProjects(userId: userId)
        }
        
        
        // Process batches to avoid memory pressure
        for batch in remoteProjects.chunked(into: 20) {
            await processRemoteProjects(batch)
            
            // Small delay between batches to prevent UI stutter
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
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
        do {
            // Efficiently handle the projects in memory to reduce database pressure
            let localProjectIds = try fetchLocalProjectIds()
            let usersMap = try fetchUsersMap()
            
            for remoteProject in remoteProjects {
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
            
            if let localProject = try modelContext.fetch(descriptor).first, !localProject.needsSync {
                // Only update if not modified locally
                updateLocalProjectFromRemote(localProject, remoteDTO: remoteDTO)
                
                
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
        
        // Always set the team member IDs string
        project.setTeamMemberIds(teamMemberIds)
        
        // Add only existing users (avoid fetching again)
        for memberId in teamMemberIds {
            if let user = usersMap[memberId] {
                project.teamMembers.append(user)
                
                // Update inverse relationship if needed
                if !user.assignedProjects.contains(where: { $0.id == project.id }) {
                    user.assignedProjects.append(project)
                }
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
        }
        
        if let completionString = remoteDTO.completion {
            localProject.endDate = DateFormatter.dateFromBubble(completionString)
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
                }
            } else {
                // Approach 2: Fetch users by their IDs (more targeted but requires multiple IDs)
                let teamIds = company.getTeamIds()
                
                guard !teamIds.isEmpty else {
                    return
                }
                
                userDTOs = try await apiService.fetchUsersByIds(userIds: teamIds)
            }
            
            
            // Clear existing team members to avoid duplicates
            company.teamMembers = []
            
            // Get admin IDs from company if available
            let adminIds = company.getAdminIds()
            
            // Create TeamMember objects from the DTOs
            for userDTO in userDTOs {
                // Check if this user is an admin
                let isAdmin = adminIds.contains(userDTO.id)
                
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
