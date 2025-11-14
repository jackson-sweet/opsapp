//
//  SyncManager_OLD.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
//  ⚠️ DEPRECATED: This file is being replaced by CentralizedSyncManager.swift
//  Do not add new functionality here. Migrate all references to CentralizedSyncManager.
//

import SwiftUI
import Foundation
import SwiftData
import Combine

@MainActor
@available(*, deprecated, message: "Use CentralizedSyncManager instead")
class SyncManager_OLD {
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
        }
    }
    
    /// Try an alternative approach to upload user profile image to Bubble
    /// This is a fallback method when the primary method fails with specific Bubble API errors
    private func tryFallbackUpload(user: User, image: UIImage) async -> Bool {
        
        do {
            // Compress image again
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
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
                return false
            }
        } catch {
            return false
        }
    }
    
    /// Trigger background sync with intelligent retry
    /// - Parameter forceProjectSync: If true, always sync projects regardless of sync budget
    func triggerBackgroundSync(forceProjectSync: Bool = false) {
        print("[SYNC] 🔵 triggerBackgroundSync called")
        print("[SYNC] syncInProgress: \(syncInProgress)")
        print("[SYNC] isConnected: \(connectivityMonitor.isConnected)")

        guard !syncInProgress, connectivityMonitor.isConnected else {
            if syncInProgress {
                print("[SYNC] ⚠️ Sync already in progress, skipping")
            } else if !connectivityMonitor.isConnected {
                print("[SYNC] ⚠️ No internet connection, skipping sync")
            }
            return
        }

        print("[SYNC] ✅ Starting background sync")
        syncInProgress = true
        syncStateSubject.send(true)

        Task {
            do {
                // First sync company data to get latest subscription info
                await syncCompanyData()

                // Sync clients that need sync (always allowed)
                let clientSyncCount = await syncPendingClientChanges()

                // Sync tasks that need sync (always allowed)
                let taskSyncCount = await syncPendingTaskChanges()

                // Sync users that need sync (always allowed)
                let userSyncCount = await syncPendingUserChanges()

                // Then sync high-priority project items (status changes) if auto-updates are enabled
                var highPriorityCount = 0
                if !preventAutoStatusUpdates {
                    highPriorityCount = await syncPendingProjectStatusChanges()
                } else {
                }

                // Finally, fetch remote data if we didn't exhaust our sync budget OR if forced
                if forceProjectSync || (clientSyncCount + taskSyncCount + userSyncCount + highPriorityCount) < 10 {
                    try await syncProjects()
                } else {
                }

                // Schedule notifications for future projects after sync
                await NotificationManager.shared.scheduleNotificationsForAllProjects(using: modelContext)

                syncInProgress = false
                syncStateSubject.send(false)
            } catch {
                syncInProgress = false
                syncStateSubject.send(false)
            }
        }
    }

    /// Awaitable version of triggerBackgroundSync for onboarding
    /// This ensures the sync completes before continuing
    func performOnboardingSync() async {
        print("[SYNC] 🔵 performOnboardingSync called (awaitable)")
        print("[SYNC] syncInProgress: \(syncInProgress)")
        print("[SYNC] isConnected: \(connectivityMonitor.isConnected)")

        guard !syncInProgress, connectivityMonitor.isConnected else {
            if syncInProgress {
                print("[SYNC] ⚠️ Sync already in progress, skipping")
            } else if !connectivityMonitor.isConnected {
                print("[SYNC] ⚠️ No internet connection, skipping sync")
            }
            return
        }

        print("[SYNC] ✅ Starting onboarding sync")
        syncInProgress = true
        syncStateSubject.send(true)

        do {
            // First sync company data to get latest subscription info
            await syncCompanyData()

            // Sync clients that need sync (always allowed)
            let clientSyncCount = await syncPendingClientChanges()

            // Sync tasks that need sync (always allowed)
            let taskSyncCount = await syncPendingTaskChanges()

            // Sync users that need sync (always allowed)
            let userSyncCount = await syncPendingUserChanges()

            // Then sync high-priority project items (status changes) if auto-updates are enabled
            var highPriorityCount = 0
            if !preventAutoStatusUpdates {
                highPriorityCount = await syncPendingProjectStatusChanges()
            }

            // Force project sync for onboarding
            try await syncProjects()

            // Schedule notifications for future projects after sync
            await NotificationManager.shared.scheduleNotificationsForAllProjects(using: modelContext)

            print("[SYNC] ✅ Onboarding sync completed successfully")

            syncInProgress = false
            syncStateSubject.send(false)
        } catch {
            print("[SYNC] ❌ Onboarding sync failed: \(error)")
            syncInProgress = false
            syncStateSubject.send(false)
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
                        // Leave needsSync=true to retry later in background sync
                    }
                }
            } else {
            }
            
            return true
        } catch {
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
            return false
        }
    }
    
    /// Update user profile image and queue for sync
    @discardableResult
    func updateUserProfileImage(_ user: User, image: UIImage) -> Bool {
        do {
            // Compress image for storage
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
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
            return false
        }
    }
    
    // MARK: - Private Sync Methods
    
    /// Sync company data from Bubble to get latest subscription info
    private func syncCompanyData() async {
        print("[SUBSCRIPTION] syncCompanyData: Starting company sync...")
        
        // Get the current user
        let userDescriptor = FetchDescriptor<User>()
        let users = (try? modelContext.fetch(userDescriptor)) ?? []
        guard let user = users.first(where: { $0.id == UserDefaults.standard.string(forKey: "user_id") }),
              let companyId = user.companyId else {
            print("[SUBSCRIPTION] syncCompanyData: No user or companyId found")
            return
        }
        
        print("[SUBSCRIPTION] syncCompanyData: Fetching company \(companyId) from API...")
        
        // Fetch company data from Bubble
        do {
            print("[SUBSCRIPTION] syncCompanyData: Calling API to fetch company...")
            let companyDTO = try await apiService.fetchCompany(id: companyId)
            print("[SUBSCRIPTION] Company sync complete - Status: \(companyDTO.subscriptionStatus ?? "nil"), Plan: \(companyDTO.subscriptionPlan ?? "nil"), Seats: \(companyDTO.seatedEmployees?.count ?? 0)/\(companyDTO.maxSeats ?? 0)")
            
            // Check if company exists locally
            let descriptor = FetchDescriptor<Company>()
            let allCompanies = (try? modelContext.fetch(descriptor)) ?? []
            let existingCompany = allCompanies.first { $0.id == companyId }
            
            if let company = existingCompany {
                // Update existing company
                print("[SUBSCRIPTION] syncCompanyData: Updating existing company")
                updateCompanyFromDTO(company, companyDTO)
            } else {
                // First time sync - create the company
                print("[SUBSCRIPTION] syncCompanyData: First sync - creating company locally")
                let newCompany = companyDTO.toModel()
                modelContext.insert(newCompany)
            }
            
            try modelContext.save()
            
            // Post notification that company was synced
            NotificationCenter.default.post(name: .companySynced, object: nil)
            
        } catch let decodingError as DecodingError {
            print("[SUBSCRIPTION] syncCompanyData: Decoding error fetching company")
            switch decodingError {
            case .keyNotFound(let key, let context):
                print("[SUBSCRIPTION] Missing key: \(key.stringValue)")
                print("[SUBSCRIPTION] Context: \(context.debugDescription)")
            case .typeMismatch(let type, let context):
                print("[SUBSCRIPTION] Type mismatch: expected \(type)")
                print("[SUBSCRIPTION] Context: \(context.debugDescription)")
                print("[SUBSCRIPTION] Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            case .valueNotFound(let type, let context):
                print("[SUBSCRIPTION] Value not found: \(type)")
                print("[SUBSCRIPTION] Context: \(context.debugDescription)")
            case .dataCorrupted(let context):
                print("[SUBSCRIPTION] Data corrupted: \(context.debugDescription)")
            @unknown default:
                print("[SUBSCRIPTION] Unknown decoding error")
            }
            // Don't force logout on decoding errors - this could be a temporary issue
            print("[SUBSCRIPTION] Company fetch failed due to decoding error - will retry on next sync")
        } catch {
            print("[SUBSCRIPTION] syncCompanyData: Failed to fetch company: \(error)")
            // Check if it's a 404 (company doesn't exist) vs other errors
            if let apiError = error as? APIError, case .httpError(let statusCode) = apiError, statusCode == 404 {
                // Company truly doesn't exist - this is critical
                await handleNoCompanyError()
            } else {
                // Other errors (network, etc) - don't force logout
                print("[SUBSCRIPTION] Company fetch failed due to network/API error - will retry on next sync")
            }
        }
    }
    
    /// Update existing company with data from DTO
    private func updateCompanyFromDTO(_ company: Company, _ companyDTO: CompanyDTO) {
        // Convert DTO to model to get all the processed values
        let updatedCompany = companyDTO.toModel()
            
            // Copy ALL fields from updated company to existing company
            // Basic info
            company.name = updatedCompany.name
            company.externalId = updatedCompany.externalId
            company.companyDescription = updatedCompany.companyDescription
            company.address = updatedCompany.address
            company.latitude = updatedCompany.latitude
            company.longitude = updatedCompany.longitude
            company.phone = updatedCompany.phone
            company.email = updatedCompany.email
            company.website = updatedCompany.website
            company.logoURL = updatedCompany.logoURL
            company.openHour = updatedCompany.openHour
            company.closeHour = updatedCompany.closeHour
            
            // Team and admin management
            company.projectIdsString = updatedCompany.projectIdsString
            company.teamIdsString = updatedCompany.teamIdsString
            company.adminIdsString = updatedCompany.adminIdsString  // CRITICAL - was missing!
            
            // Company details
            company.industryString = updatedCompany.industryString
            company.companySize = updatedCompany.companySize
            company.companyAge = updatedCompany.companyAge
            
            // Subscription fields
            company.subscriptionStatus = updatedCompany.subscriptionStatus
            company.subscriptionPlan = updatedCompany.subscriptionPlan
            company.subscriptionEnd = updatedCompany.subscriptionEnd
            company.subscriptionPeriod = updatedCompany.subscriptionPeriod
            company.maxSeats = updatedCompany.maxSeats
            company.seatedEmployeeIds = updatedCompany.seatedEmployeeIds  // CRITICAL - seated employees list
            company.seatGraceStartDate = updatedCompany.seatGraceStartDate
            // seatGraceEndDate and reactivatedSubscription don't exist in Company model
            company.subscriptionIdsJson = updatedCompany.subscriptionIdsJson
            
            // Trial fields
            company.trialStartDate = updatedCompany.trialStartDate
            company.trialEndDate = updatedCompany.trialEndDate
            
            // Add-ons
            company.hasPrioritySupport = updatedCompany.hasPrioritySupport
            company.dataSetupPurchased = updatedCompany.dataSetupPurchased
            company.dataSetupCompleted = updatedCompany.dataSetupCompleted
            company.dataSetupScheduledDate = updatedCompany.dataSetupScheduledDate
            // prioritySupportPurchaseDate doesn't exist in Company model
            
            // Stripe
            company.stripeCustomerId = updatedCompany.stripeCustomerId
            
            // Update sync timestamp
            company.lastSyncedAt = Date()
    }
    
    /// Handle critical error when no company is found
    @MainActor
    private func handleNoCompanyError() async {
        print("[SUBSCRIPTION] WARNING: No company found for user")
        
        // Check if user has completed onboarding - if not, this is expected
        let userDescriptor = FetchDescriptor<User>()
        let users = (try? modelContext.fetch(userDescriptor)) ?? []
        if let user = users.first(where: { $0.id == UserDefaults.standard.string(forKey: "user_id") }) {
            // If user has no company ID, this might be normal during onboarding
            if user.companyId == nil {
                print("[SUBSCRIPTION] User has no company ID - may be in onboarding")
                return
            }
        }
        
        // Only force logout if this is truly an error (user has company ID but company doesn't exist)
        print("[SUBSCRIPTION] CRITICAL ERROR: Company ID exists but company not found - logging out")
        
        // Clear user session
        UserDefaults.standard.set(false, forKey: "is_authenticated")
        UserDefaults.standard.removeObject(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "company_id")
        
        // Post notification to trigger logout in DataController
        NotificationCenter.default.post(
            name: .forceLogout,
            object: nil,
            userInfo: ["reason": "Company not found"]
        )
        
        // Post notification to show error to user
        NotificationCenter.default.post(
            name: .criticalError,
            object: nil,
            userInfo: ["message": "No company found for your account. Please contact support."]
        )
    }
    
    /// Sync a specific project's status and notes to the backend
    private func syncClientStatus(_ client: Client) async {
        guard client.needsSync else { return }

        print("[SYNC] Syncing client: \(client.id) - \(client.name)")
        print("[SYNC] Client needsSync: \(client.needsSync)")
        print("[SYNC] Client lastSyncedAt: \(client.lastSyncedAt?.description ?? "nil")")

        do {
            if client.lastSyncedAt == nil {
                print("[SYNC] 📝 Client \(client.id) has never been synced - creating NEW client on Bubble")

                let bubbleId = try await apiService.createClient(client)
                print("[SYNC] ✅ Client created on Bubble with ID: \(bubbleId)")

                let oldId = client.id
                client.id = bubbleId
                client.needsSync = false
                client.lastSyncedAt = Date()
                try modelContext.save()

                print("[SYNC] ✅ Updated local client ID from \(oldId) to \(bubbleId)")

                return
            }

            print("[SYNC] Client exists on Bubble, updating information")

            try await apiService.updateClient(
                id: client.id,
                name: client.name,
                email: client.email,
                phone: client.phoneNumber,
                address: client.address
            )
            print("[SYNC] ✅ Updated client information")

            client.needsSync = false
            client.lastSyncedAt = Date()
            try modelContext.save()
            print("[SYNC] ✅ Client \(client.id) synced successfully")
        } catch {
            print("[SYNC] ❌ Failed to sync client \(client.id): \(error)")
        }
    }

    private func syncPendingTaskChanges() async -> Int {
        print("[SYNC] 🔵 syncPendingTaskChanges called")
        let predicate = #Predicate<ProjectTask> { $0.needsSync == true }
        var descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)

        do {
            let pendingTasks = try modelContext.fetch(descriptor)
            print("[SYNC] 📋 Found \(pendingTasks.count) pending tasks to sync")
            var successCount = 0

            for batch in pendingTasks.chunked(into: 10) {
                await withTaskGroup(of: Bool.self) { group in
                    for task in batch {
                        group.addTask {
                            await self.syncTaskStatus(task)
                            return true
                        }
                    }

                    for await success in group {
                        if success {
                            successCount += 1
                        }
                    }
                }
            }

            return successCount
        } catch {
            print("[SYNC] ❌ Failed to fetch pending tasks: \(error)")
            return 0
        }
    }

    private func syncTaskStatus(_ task: ProjectTask) async {
        guard task.needsSync else { return }

        print("[SYNC] Syncing task: \(task.id) - Type: \(task.taskType?.display ?? "Unknown")")
        print("[SYNC] Task needsSync: \(task.needsSync)")
        print("[SYNC] Task lastSyncedAt: \(task.lastSyncedAt?.description ?? "nil")")

        do {
            if task.lastSyncedAt == nil {
                print("[SYNC] 📝 Task \(task.id) has never been synced - creating NEW task on Bubble")

                let taskDTO = TaskDTO(
                    id: task.id,
                    calendarEventId: task.calendarEventId,
                    companyId: task.companyId,
                    completionDate: nil,
                    projectId: task.projectId,
                    scheduledDate: nil,
                    status: task.status.rawValue,
                    taskColor: task.taskColor,
                    taskIndex: task.displayOrder,
                    taskNotes: task.taskNotes,
                    teamMembers: task.getTeamMemberIds(),
                    type: task.taskTypeId,
                    createdDate: nil,
                    modifiedDate: nil,
                    deletedAt: nil
                )

                let createdTask = try await apiService.createTask(taskDTO)
                print("[SYNC] ✅ Task created on Bubble with ID: \(createdTask.id)")

                let oldId = task.id
                task.id = createdTask.id
                task.needsSync = false
                task.lastSyncedAt = Date()
                try modelContext.save()

                print("[SYNC] ✅ Updated local task ID from \(oldId) to \(createdTask.id)")

                if let calendarEvent = task.calendarEvent {
                    print("[SYNC] 📅 Creating CalendarEvent for task on Bubble...")
                    calendarEvent.taskId = createdTask.id

                    // Create calendar event on Bubble
                    let dateFormatter = ISO8601DateFormatter()
                    let eventDTO = CalendarEventDTO(
                        id: calendarEvent.id,
                        color: calendarEvent.color,
                        companyId: calendarEvent.companyId,
                        projectId: calendarEvent.projectId,
                        taskId: createdTask.id,
                        duration: Double(calendarEvent.duration),
                        endDate: calendarEvent.endDate.map { dateFormatter.string(from: $0) },
                        startDate: calendarEvent.startDate.map { dateFormatter.string(from: $0) },
                        teamMembers: calendarEvent.getTeamMemberIds(),
                        title: calendarEvent.title,
                        type: "task",
                        active: calendarEvent.active,
                        createdDate: nil,
                        modifiedDate: nil,
                        deletedAt: nil
                    )

                    let createdEventDTO = try await apiService.createAndLinkCalendarEvent(eventDTO)
                    calendarEvent.id = createdEventDTO.id
                    calendarEvent.needsSync = false
                    calendarEvent.lastSyncedAt = Date()

                    // Update task with calendar event ID
                    task.calendarEventId = createdEventDTO.id
                    try modelContext.save()
                    print("[SYNC] ✅ CalendarEvent created with ID: \(createdEventDTO.id)")
                }

                return
            }

            print("[SYNC] Task exists on Bubble, updating information")

            if task.taskNotes != nil {
                try await apiService.updateTaskNotes(id: task.id, notes: task.taskNotes!)
                print("[SYNC] ✅ Updated task notes")
            }

            if !task.getTeamMemberIds().isEmpty {
                try await apiService.updateTaskTeamMembers(id: task.id, teamMemberIds: task.getTeamMemberIds())
                print("[SYNC] ✅ Updated task team members")
            }

            task.needsSync = false
            task.lastSyncedAt = Date()
            try modelContext.save()
            print("[SYNC] ✅ Task \(task.id) synced successfully")
        } catch {
            print("[SYNC] ❌ Failed to sync task \(task.id): \(error)")
        }
    }

    private func syncProjectStatus(_ project: Project) async {
        // Only sync if project needs sync
        guard project.needsSync else { return }

        print("[SYNC] Syncing project: \(project.id) - \(project.title)")
        print("[SYNC] Project needsSync: \(project.needsSync)")
        print("[SYNC] Project lastSyncedAt: \(project.lastSyncedAt?.description ?? "nil")")

        do {
            // Check if project exists on Bubble (lastSyncedAt == nil means it's a new local project)
            if project.lastSyncedAt == nil {
                print("[SYNC] 📝 Project \(project.id) has never been synced - creating NEW project on Bubble")

                let bubbleId = try await apiService.createProject(project)
                print("[SYNC] ✅ Project created on Bubble with ID: \(bubbleId)")

                // Update local project with Bubble ID
                let oldId = project.id
                project.id = bubbleId
                project.needsSync = false
                project.lastSyncedAt = Date()
                try modelContext.save()

                print("[SYNC] ✅ Updated local project ID from \(oldId) to \(bubbleId)")

                // Create CalendarEvent if project has dates
                if let startDate = project.startDate, let endDate = project.endDate {
                    print("[SYNC] Creating CalendarEvent for project")
                    do {
                        try await createCalendarEventForProject(project, startDate: startDate, endDate: endDate)
                        print("[SYNC] ✅ CalendarEvent created for project")
                    } catch {
                        print("[SYNC] ⚠️ Failed to create CalendarEvent: \(error)")
                    }
                } else {
                    print("[SYNC] ℹ️ Project has no dates - skipping CalendarEvent creation")
                }

                return
            }

            print("[SYNC] Project exists on Bubble, updating status")

            // Different approach based on the status
            if project.status == .completed {
                // For completed projects, use the workflow endpoint
                let newStatus = try await apiService.completeProject(projectId: project.id, status: project.status.rawValue)
                print("[SYNC] ✅ Completed project workflow executed")
            } else {
                // For other statuses, use the regular update endpoint
                try await apiService.updateProjectStatus(id: project.id, status: project.status.rawValue)
                print("[SYNC] ✅ Updated project status to \(project.status.rawValue)")
            }

            // Sync notes if they exist
            if let notes = project.notes, !notes.isEmpty {
                try await apiService.updateProjectNotes(id: project.id, notes: notes)
                print("[SYNC] ✅ Updated project notes")
            }

            // Mark as synced if successful
            project.needsSync = false
            project.lastSyncedAt = Date()
            try modelContext.save()
            print("[SYNC] ✅ Project \(project.id) synced successfully")
        } catch {
            print("[SYNC] ❌ Failed to sync project \(project.id): \(error)")
            // Leave as needsSync=true to retry later
        }
    }
    
    /// Sync any pending client changes
    private func syncPendingClientChanges() async -> Int {
        let predicate = #Predicate<Client> { $0.needsSync == true }
        var descriptor = FetchDescriptor<Client>(predicate: predicate)

        do {
            let pendingClients = try modelContext.fetch(descriptor)
            var successCount = 0

            for batch in pendingClients.chunked(into: 10) {
                await withTaskGroup(of: Bool.self) { group in
                    for client in batch {
                        group.addTask {
                            await self.syncClientStatus(client)
                            return true
                        }
                    }

                    for await success in group {
                        if success {
                            successCount += 1
                        }
                    }
                }
            }

            return successCount
        } catch {
            print("[SYNC] ❌ Failed to fetch pending clients: \(error)")
            return 0
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
            return 0
        }
    }
    
    /// Force sync projects immediately, bypassing sync budget
    func forceSyncProjects() async {
        do {
            try await syncProjects()

            // Also refresh any placeholder clients
            await refreshPlaceholderClients()

        } catch {
        }
    }

    func manualFullSync(companyId: String) async {
        print("[MANUAL_FULL_SYNC] 🚀 Starting comprehensive sync for company: \(companyId)")

        do {
            print("[MANUAL_FULL_SYNC] 📦 Syncing company data...")
            await syncCompanyData()

            print("[MANUAL_FULL_SYNC] 👥 Syncing team members...")
            if let company = try? modelContext.fetch(FetchDescriptor<Company>()).first(where: { $0.id == companyId }) {
                await syncCompanyTeamMembers(company)
            }

            print("[MANUAL_FULL_SYNC] 👤 Syncing clients...")
            await syncCompanyClients(companyId: companyId)

            print("[MANUAL_FULL_SYNC] 📋 Syncing projects...")
            try await syncProjects()

            print("[MANUAL_FULL_SYNC] ✅ Syncing tasks...")
            try await syncCompanyTasks(companyId: companyId)

            print("[MANUAL_FULL_SYNC] 📅 Syncing calendar events...")
            try await syncCompanyCalendarEvents(companyId: companyId)

            print("[MANUAL_FULL_SYNC] 🏷️ Syncing task types...")
            try await syncCompanyTaskTypes(companyId: companyId)

            print("[MANUAL_FULL_SYNC] ✅ Comprehensive sync completed successfully")
        } catch {
            print("[MANUAL_FULL_SYNC] ❌ Error during full sync: \(error)")
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
                        
                    } catch {
                        failedClients.append(client.id)
                    }
                }
                
                // Save all updates
                try modelContext.save()
                
                // If we had failures, try syncing all company clients as a fallback
                if !failedClients.isEmpty {
                    
                    // Get company ID from the first project or user's company
                    if let companyId = try getCompanyId() {
                        await syncCompanyClients(companyId: companyId)
                    } else {
                    }
                }
            }
        } catch {
            
            // Even if the placeholder refresh fails, try to sync all clients as last resort
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
        
        
        // Get IDs of all remote projects
        let remoteProjectIds = Set(remoteProjects.map { $0.id })

        // NOTE: We don't remove unassigned projects when using date-range filtering
        // because old projects outside the date range won't be returned by the API
        // but they should still exist locally for historical reference
        // await removeUnassignedProjects(keepingIds: remoteProjectIds, for: currentUser)
        
        // Process batches to avoid memory pressure
        for batch in remoteProjects.chunked(into: 20) {
            await processRemoteProjects(batch)
            
            // Small delay between batches to prevent UI stutter
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }
        
        // Sync task types for the company (required before tasks)
        do {
            try await syncCompanyTaskTypes(companyId: companyId)
        } catch {
        }

        // Sync calendar events for the company (critical for calendar view)
        // Syncing calendar events for company
        do {
            try await syncCompanyCalendarEvents(companyId: companyId)
        } catch {
        }

        // Sync tasks for all companies (no longer conditional)
        // Syncing tasks for company
        do {
            try await syncCompanyTasks(companyId: companyId)
        } catch {
        }
        
        // Final sync diagnostic summary (removed excessive logging)
    }
    
    /// Remove local projects that the user is no longer assigned to
    private func removeUnassignedProjects(keepingIds remoteIds: Set<String>, for user: User?) async {
        do {
            // Fetch all local projects
            let descriptor = FetchDescriptor<Project>()
            let localProjects = try modelContext.fetch(descriptor)
            
            
            // Find projects to remove (local projects not in remote list)
            let projectsToRemove = localProjects.filter { !remoteIds.contains($0.id) }
            
            if !projectsToRemove.isEmpty {
                for project in projectsToRemove {
                    // IMPORTANT: Delete related calendar events first to avoid orphaned references
                    // Delete the project's primary calendar event
                    if let event = project.primaryCalendarEvent {
                        modelContext.delete(event)
                    }

                    // Delete all task calendar events
                    for task in project.tasks {
                        if let event = task.calendarEvent {
                            modelContext.delete(event)
                        }
                        modelContext.delete(task)
                    }

                    // Now delete the project
                    modelContext.delete(project)
                }

                // Save the deletions
                try modelContext.save()
            } else {
            }
        } catch {
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
            
            
            // Pre-fetch clients for all projects to ensure they're available
            // This prevents "Loading..." placeholder clients from persisting
            let uniqueClientIds = Set(remoteProjects.compactMap { $0.client })
            if !uniqueClientIds.isEmpty {
                await prefetchClients(clientIds: Array(uniqueClientIds))
            }
            
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
                } else {
                    // Only update if not modified locally
                    updateLocalProjectFromRemote(localProject, remoteDTO: remoteDTO)
                    
                    // Sync and link the client if available
                    if let clientId = remoteDTO.client {
                        // Link client to project
                        await linkProjectToClient(project: localProject, clientId: clientId)
                    } else {
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
            modelContext.delete(user)
            try? modelContext.save()
            return
        }
        
        do {
            let userDTO = try await apiService.fetchUser(id: user.id)
            
            // Update user properties that might be missing
            if let phone = userDTO.phone, user.phone == nil {
                user.phone = phone
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
                
                // Add to non-existent cache to prevent future fetch attempts
                nonExistentUserIds.insert(user.id)
                
                // Delete the user from local database
                modelContext.delete(user)
                do {
                    try modelContext.save()
                } catch {
                }
            } else {
            }
        }
    }
    
    /// Populate CalendarEvent team members from team member IDs
    private func populateCalendarEventTeamMembers(_ calendarEvent: CalendarEvent, teamMemberIds: [String]) {
        // Clear existing team members to avoid duplicates
        calendarEvent.teamMembers = []
        
        // Filter out non-existent users from team member IDs
        let validTeamMemberIds = teamMemberIds.filter { !nonExistentUserIds.contains($0) }
        
        // Always set the team member IDs string (with filtered list)
        calendarEvent.setTeamMemberIds(validTeamMemberIds)
        
        // Add users by fetching from the model context
        for memberId in validTeamMemberIds {
            do {
                let userDescriptor = FetchDescriptor<User>(
                    predicate: #Predicate<User> { $0.id == memberId }
                )
                if let user = try modelContext.fetch(userDescriptor).first {
                    calendarEvent.teamMembers.append(user)
                    // Added team member to calendar event
                } else {
                    // Track users that don't exist locally
                    nonExistentUserIds.insert(memberId)
                    // Team member not found for calendar event
                }
            } catch {
                // Failed to fetch team member
            }
        }
    }
    
    /// Update a local project with remote data
    private func updateLocalProjectFromRemote(_ localProject: Project, remoteDTO: ProjectDTO) {
        // Update project title and basic info
        localProject.title = remoteDTO.projectName
        
        // Client name comes from client relationship

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
            // Updated project start date
        } else {
        }
        
        if let completionString = remoteDTO.completion {
            localProject.endDate = DateFormatter.dateFromBubble(completionString)
            // Updated project end date
        } else {
        }
        
        // Update notes and description fields
        localProject.notes = remoteDTO.teamNotes ?? remoteDTO.description
        localProject.projectDescription = remoteDTO.description
        localProject.lastSyncedAt = Date()
        
        // Update company ID from company reference
        if let companyRef = remoteDTO.company {
            localProject.companyId = companyRef.stringValue
        }
        
        // Update eventType - this determines if project uses task-based or project-based scheduling
        if let eventTypeString = remoteDTO.eventType {
            let newEventType = CalendarEventType(rawValue: eventTypeString.lowercased()) ?? .project
            if localProject.eventType != newEventType {
                // Project eventType updated
                localProject.eventType = newEventType
                
                // Update the cached eventType and active status on all related CalendarEvents
                // since the project's scheduling mode changed
                let projectId = localProject.id
                let eventDescriptor = FetchDescriptor<CalendarEvent>(
                    predicate: #Predicate<CalendarEvent> { $0.projectId == projectId }
                )
                if let events = try? modelContext.fetch(eventDescriptor) {
                    for event in events {
                        event.projectEventType = newEventType
                        // Update active status based on new scheduling mode
                        if newEventType == .project {
                            // Project uses traditional scheduling - activate project events, deactivate task events
                            event.active = (event.type == .project && event.taskId == nil)
                        } else {
                            // Project uses task-based scheduling - activate task events, deactivate project events
                            event.active = (event.type == .task && event.taskId != nil)
                        }
                        // Updated cached eventType and active status on CalendarEvent
                    }
                }
            }
        } else {
            // Default to project scheduling if not specified
            if localProject.eventType == nil {
                localProject.eventType = .project
                // Project eventType defaulted to 'project'
            }
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
        
        // Fetch tasks from API
        let remoteTasks = try await apiService.fetchProjectTasks(projectId: projectId)
        
        // Get company's default color (projects don't have their own color)
        let projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == projectId }
        )
        let project = try modelContext.fetch(projectDescriptor).first
        let companyId = project?.companyId ?? ""
        
        let companyDescriptor = FetchDescriptor<Company>(
            predicate: #Predicate<Company> { $0.id == companyId }
        )
        let defaultColor = try modelContext.fetch(companyDescriptor).first?.defaultProjectColor ?? "#9CA3AF"  // Light grey fallback
        
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
                
                // Link team members for new task
                if let teamMemberIds = remoteTask.teamMembers {
                    // Remote task has team member IDs
                    newTask.setTeamMemberIds(teamMemberIds)
                    
                    newTask.teamMembers = []
                    for memberId in teamMemberIds {
                        if let user = try? modelContext.fetch(
                            FetchDescriptor<User>(
                                predicate: #Predicate<User> { $0.id == memberId }
                            )
                        ).first {
                            newTask.teamMembers.append(user)
                        } else {
                            // Team member not found in local database
                        }
                    }
                } else {
                }
                
                
                if let calendarEventId = newTask.calendarEventId, !calendarEventId.isEmpty {
                    if let calendarEvent = try? modelContext.fetch(
                        FetchDescriptor<CalendarEvent>(
                            predicate: #Predicate<CalendarEvent> { $0.id == calendarEventId }
                        )
                    ).first {
                        newTask.calendarEvent = calendarEvent
                        calendarEvent.task = newTask
                    } else {
                    }
                } else if let scheduledDateStr = remoteTask.scheduledDate, !scheduledDateStr.isEmpty {
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
    }
    
    /// Sync all tasks for a company
    func syncCompanyTasks(companyId: String) async throws {
        
        // Fetch all tasks from API
        let remoteTasks = try await apiService.fetchCompanyTasks(companyId: companyId)
        // API RESPONSE: Received tasks from API
        
        // CRITICAL DIAGNOSTIC: Analyze task CalendarEvent linkage from Bubble
        // DATA: Total Tasks from Bubble
        
        let tasksWithCalendarEventId = remoteTasks.filter { $0.calendarEventId != nil && !($0.calendarEventId?.isEmpty ?? true) }
        let tasksWithScheduledDate = remoteTasks.filter { $0.scheduledDate != nil && !($0.scheduledDate?.isEmpty ?? true) }
        let tasksWithBothCalendarAndScheduled = remoteTasks.filter { 
            ($0.calendarEventId != nil && !($0.calendarEventId?.isEmpty ?? true)) && 
            ($0.scheduledDate != nil && !($0.scheduledDate?.isEmpty ?? true))
        }
        let tasksWithScheduledButNoCalendarEvent = remoteTasks.filter {
            ($0.scheduledDate != nil && !($0.scheduledDate?.isEmpty ?? true)) &&
            ($0.calendarEventId == nil || ($0.calendarEventId?.isEmpty ?? false))
        }
        
        // DATA: Tasks with calendarEventId
        // DATA: Tasks with scheduledDate
        // DATA: Tasks with BOTH calendarEventId AND scheduledDate
        // WARNING: Tasks with scheduledDate but NO calendarEventId
        
        // Log problematic tasks
        if !tasksWithScheduledButNoCalendarEvent.isEmpty {
            // CRITICAL CALENDAR EVENT ISSUES:
            for (index, task) in tasksWithScheduledButNoCalendarEvent.prefix(10).enumerated() {
                // Critical task issue
            }
            if tasksWithScheduledButNoCalendarEvent.count > 10 {
            }
        }
        
        // Group tasks by project for analysis
        let tasksByProject = Dictionary(grouping: remoteTasks) { $0.projectId ?? "unknown" }
        // DATA: Tasks for unique projects
        for (projectId, projectTasks) in tasksByProject.prefix(10) {
            let scheduledTasks = projectTasks.filter { $0.scheduledDate != nil && !($0.scheduledDate?.isEmpty ?? true) }
            let tasksWithEvents = projectTasks.filter { $0.calendarEventId != nil && !($0.calendarEventId?.isEmpty ?? true) }
            // Project task summary
        }
        if tasksByProject.count > 10 {
        }
        
        // Collect all unique task type IDs from remote tasks
        let remoteTaskTypeIds = Set(remoteTasks.compactMap { $0.type })
        if !remoteTaskTypeIds.isEmpty {
            // Found unique task types in tasks
            
            // Check which task types we don't have locally
            let localTaskTypes = try modelContext.fetch(FetchDescriptor<TaskType>())
            let localTaskTypeIds = Set(localTaskTypes.map { $0.id })
            let unknownTaskTypeIds = remoteTaskTypeIds.subtracting(localTaskTypeIds)
            
            if !unknownTaskTypeIds.isEmpty {
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
        let defaultColor = try modelContext.fetch(companyDescriptor).first?.defaultProjectColor ?? "#9CA3AF"  // Light grey fallback
        
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
                    
                    // Link team members for new task
                    if let teamMemberIds = remoteTask.teamMembers {
                        // Remote task (batch sync) has team member IDs
                        newTask.setTeamMemberIds(teamMemberIds)
                            
                        newTask.teamMembers = []
                        for memberId in teamMemberIds {
                            if let user = try? modelContext.fetch(
                                FetchDescriptor<User>(
                                    predicate: #Predicate<User> { $0.id == memberId }
                                )
                            ).first {
                                newTask.teamMembers.append(user)
                                } else {
                                // Team member not found in local database
                            }
                        }
                            } else {
                        // Remote task (batch sync) has no team members
                    }
                    
                    // ENHANCED CALENDAR EVENT LINKING FOR BATCH NEW TASK
                    if let calendarEventId = newTask.calendarEventId, !calendarEventId.isEmpty {
                        if let calendarEvent = try? modelContext.fetch(
                            FetchDescriptor<CalendarEvent>(
                                predicate: #Predicate<CalendarEvent> { $0.id == calendarEventId }
                            )
                        ).first {
                            newTask.calendarEvent = calendarEvent
                            calendarEvent.task = newTask
                        } else {
                        }
                    } else if let scheduledDateStr = remoteTask.scheduledDate, !scheduledDateStr.isEmpty {
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
        
        // POST-SYNC TASK ANALYSIS: Verify CalendarEvent linkage
        
        let allTasksDescriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { $0.companyId == companyId }
        )
        let finalTasks = try modelContext.fetch(allTasksDescriptor)
        
        let finalTasksWithCalendarEvent = finalTasks.filter { $0.calendarEvent != nil }
        let finalTasksWithCalendarEventId = finalTasks.filter { $0.calendarEventId != nil && !$0.calendarEventId!.isEmpty }
        let finalTasksWithScheduledDate = finalTasks.filter { $0.scheduledDate != nil }
        let finalTasksWithScheduledButNoEvent = finalTasks.filter { 
            $0.scheduledDate != nil && ($0.calendarEvent == nil || $0.calendarEventId?.isEmpty == true)
        }
        
        // Total tasks in database summary
        // Tasks linked to CalendarEvent summary
        // Tasks with calendarEventId summary
        // Tasks with scheduledDate summary
        // Tasks scheduled but not linked to CalendarEvent summary
        
        if !finalTasksWithScheduledButNoEvent.isEmpty {
            // UNLINKED SCHEDULED TASKS (Calendar won't display):
            for (index, task) in finalTasksWithScheduledButNoEvent.prefix(5).enumerated() {
                // Unlinked scheduled task
                // CalendarEventId
                // CalendarEvent linked status
            }
            if finalTasksWithScheduledButNoEvent.count > 5 {
            }
        }
        
    }
    
    /// Update a local task from a remote DTO
    private func updateTask(_ localTask: ProjectTask, from remoteTask: TaskDTO, defaultColor: String? = nil, taskTypeMap: [String: TaskType]? = nil) {
        if let status = remoteTask.status {
            localTask.status = TaskStatus(rawValue: status) ?? .booked
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
        
        // Update team members
        if let teamMemberIds = remoteTask.teamMembers {
            // UPDATE: Task has team member IDs
            
            localTask.setTeamMemberIds(teamMemberIds)
            
            // Clear and populate actual User objects
            localTask.teamMembers = []
            var linkedCount = 0
            for memberId in teamMemberIds {
                if let user = try? modelContext.fetch(
                    FetchDescriptor<User>(
                        predicate: #Predicate<User> { $0.id == memberId }
                    )
                ).first {
                    localTask.teamMembers.append(user)
                    linkedCount += 1
                    // Linked team member to task
                } else {
                    // Team member not found in local database
                }
            }
            // Task team members updated
        } else {
            localTask.setTeamMemberIds([])
            localTask.teamMembers = []
        }
        
        
        if let calendarEventId = localTask.calendarEventId, !calendarEventId.isEmpty {
            if let calendarEvent = try? modelContext.fetch(
                FetchDescriptor<CalendarEvent>(
                    predicate: #Predicate<CalendarEvent> { $0.id == calendarEventId }
                )
            ).first {
                localTask.calendarEvent = calendarEvent
                calendarEvent.task = localTask
            } else {
            }
        } else if let scheduledDateStr = remoteTask.scheduledDate, !scheduledDateStr.isEmpty {
        }
    }
    
    /// Sync task types for a company
    /// Sync specific task types by their IDs
    func syncSpecificTaskTypes(taskTypeIds: [String], companyId: String) async throws {
        guard !taskTypeIds.isEmpty else { return }


        // Fetch specific task types from API
        let remoteTaskTypes = try await apiService.fetchTaskTypesByIds(ids: taskTypeIds)

        // CRITICAL: Deduplicate remote task types by ID to prevent crash
        var uniqueRemoteTaskTypes: [TaskTypeDTO] = []
        var seenIds = Set<String>()
        for remoteTaskType in remoteTaskTypes {
            if !seenIds.contains(remoteTaskType.id) {
                uniqueRemoteTaskTypes.append(remoteTaskType)
                seenIds.insert(remoteTaskType.id)
            } else {
                print("[SYNC] ⚠️ Skipping duplicate task type ID in specific sync: \(remoteTaskType.id)")
            }
        }

        // Process each task type (deduplicated)
        for remoteTaskType in uniqueRemoteTaskTypes {
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
    }
    
    /// Sync calendar events for a company
    func syncCompanyCalendarEvents(companyId: String) async throws {
        
        // Fetch calendar events from API
        let remoteEvents = try await apiService.fetchCompanyCalendarEvents(companyId: companyId)
        // API RESPONSE: Received calendar events from API
        
        // CRITICAL DIAGNOSTIC: Analyze CalendarEvent data from Bubble
        // DATA: Total CalendarEvents from Bubble
        
        // Analyze event types and task associations
        let projectTypeEvents = remoteEvents.filter { $0.type?.lowercased() == "project" }
        let taskTypeEvents = remoteEvents.filter { $0.type?.lowercased() == "task" }
        let eventsWithTasks = remoteEvents.filter { $0.taskId != nil && !($0.taskId?.isEmpty ?? true) }
        let eventsWithoutTasks = remoteEvents.filter { $0.taskId == nil || ($0.taskId?.isEmpty ?? false) }
        
        // DATA: Project-type events
        // DATA: Task-type events
        // DATA: Events with taskId
        // DATA: Events without taskId
        
        // Analyze by project
        let projectGroups = Dictionary(grouping: remoteEvents) { $0.projectId ?? "unknown" }
        // DATA: Events for unique projects
        for (projectId, events) in projectGroups.prefix(10) {
            let projectEvents = events.filter { $0.type?.lowercased() == "project" }
            let taskEvents = events.filter { $0.type?.lowercased() == "task" }
            // Project events summary
        }
        if projectGroups.count > 10 {
        }
        
        // Search for any Railings events in the remote response
        let railingsRemoteEvents = remoteEvents.filter { ($0.title ?? "").lowercased().contains("railings") }
        if !railingsRemoteEvents.isEmpty {
            // RAILINGS EVENTS IN API RESPONSE
            for (index, event) in railingsRemoteEvents.enumerated() {
                // Railings Remote Event
                // Event Project ID
                // Event Task ID
                // Event team members
            }
        }
        
        // Log summary of remote events
        // API DATA: First 10 remote events
        for (index, event) in remoteEvents.prefix(10).enumerated() {
            // Remote Event
            // Event Project ID
            // Event Task ID
        }
        if remoteEvents.count > 10 {
        }
        
        // Get local events
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate<CalendarEvent> { $0.companyId == companyId }
        )
        let localEvents = try modelContext.fetch(descriptor)
        let localEventIds = Set(localEvents.map { $0.id })
        
        // Process remote events
        // Processing remote events
        for (index, remoteEvent) in remoteEvents.enumerated() {
            let isRailingsEvent = (remoteEvent.title ?? "").lowercased().contains("railings")
            let logPrefix = isRailingsEvent ? "🎯 RAILINGS" : "📅"
            
            if localEventIds.contains(remoteEvent.id) {
                // Update existing event
                if let localEvent = localEvents.first(where: { $0.id == remoteEvent.id }) {
                    // Updating existing event
                    if isRailingsEvent {
                        // Local event shouldDisplay before update
                        // Local event projectEventType before update
                    }
                    updateCalendarEvent(localEvent, from: remoteEvent)
                    if isRailingsEvent {
                        // Local event shouldDisplay after update
                        // Local event projectEventType after update
                    }
                }
            } else {
                // Insert new event
                // Creating new event
                guard let newEvent = remoteEvent.toModel() else {
                    // Failed to create CalendarEvent from DTO
                    continue
                }
                modelContext.insert(newEvent)
                
                if isRailingsEvent {
                    // New event created
                    // Event task ID
                    // Event project ID
                }
                
                // Populate team members from IDs if available
                if let teamMemberIds = remoteEvent.teamMembers, !teamMemberIds.isEmpty {
                    newEvent.setTeamMemberIds(teamMemberIds)
                    populateCalendarEventTeamMembers(newEvent, teamMemberIds: teamMemberIds)
                }
                
                // Link to project if available
                if let projectId = remoteEvent.projectId {
                    // Linking to project ID
                    let projectDescriptor = FetchDescriptor<Project>(
                        predicate: #Predicate<Project> { $0.id == projectId }
                    )
                    if let project = try modelContext.fetch(projectDescriptor).first {
                        newEvent.project = project
                        // CRITICAL: Cache the project's event type for efficient filtering
                        // This must be set for shouldDisplay to work correctly
                        newEvent.projectEventType = project.effectiveEventType
                        
                        if isRailingsEvent {
                            // Project found and linked
                            // Project effective event type
                            // Cached project event type on calendar event
                            // New event shouldDisplay after project link
                        }
                        
                        // Copy team members from project if not already set from API
                        if newEvent.teamMembers.isEmpty && !project.teamMembers.isEmpty {
                            newEvent.teamMembers = project.teamMembers
                            newEvent.setTeamMemberIds(project.getTeamMemberIds())
                            if isRailingsEvent {
                                // Copied team members from project
                            }
                        } else if !newEvent.getTeamMemberIds().isEmpty && newEvent.teamMembers.isEmpty {
                            // Populate team members from stored IDs if not already populated
                            populateCalendarEventTeamMembers(newEvent, teamMemberIds: newEvent.getTeamMemberIds())
                            if isRailingsEvent {
                                // Populated team members from stored IDs
                            }
                        }
                        
                        // If this is a project-level event, set it as the primary calendar event
                        if newEvent.type == .project && project.effectiveEventType == .project {
                            project.primaryCalendarEvent = newEvent
                            // Sync dates from calendar event to project
                            project.syncDatesWithCalendarEvent()
                            if isRailingsEvent {
                            }
                        }
                    } else {
                        if isRailingsEvent {
                        }
                    }
                }
                
                // Link to task if available
                if let taskId = remoteEvent.taskId {
                    // Linking to task ID
                    let taskDescriptor = FetchDescriptor<ProjectTask>(
                        predicate: #Predicate<ProjectTask> { $0.id == taskId }
                    )
                    if let task = try modelContext.fetch(taskDescriptor).first {
                        newEvent.task = task
                        task.calendarEvent = newEvent
                        
                        if isRailingsEvent {
                            // Task found and linked
                            // Task scheduled date
                            // New event shouldDisplay after task link
                        }
                        
                        // Copy team members from task if not already set from API
                        if newEvent.teamMembers.isEmpty && !task.teamMembers.isEmpty {
                            newEvent.teamMembers = task.teamMembers
                            newEvent.setTeamMemberIds(task.getTeamMemberIds())
                            if isRailingsEvent {
                                // Copied team members from task
                            }
                        } else if !newEvent.getTeamMemberIds().isEmpty && newEvent.teamMembers.isEmpty {
                            // Populate team members from stored IDs if not already populated
                            populateCalendarEventTeamMembers(newEvent, teamMemberIds: newEvent.getTeamMemberIds())
                            if isRailingsEvent {
                                // Populated team members from stored IDs
                            }
                        }
                    } else {
                        if isRailingsEvent {
                        }
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
        
        // Post-sync pass: Ensure all events have projectEventType cached for efficient filtering
        for localEvent in localEvents {
            if localEvent.projectEventType == nil, let project = localEvent.project {
                localEvent.updateProjectEventTypeCache(from: project)
                // Cached projectEventType for event
            }
        }
        
        // Save any caching updates
        try modelContext.save()
        
        // Log final state
        let finalDescriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate<CalendarEvent> { $0.companyId == companyId }
        )
        let finalEvents = try modelContext.fetch(finalDescriptor)
        
    }
    
    
    
    /// Update a local calendar event from remote DTO
    private func updateCalendarEvent(_ localEvent: CalendarEvent, from remoteEvent: CalendarEventDTO) {
        localEvent.title = remoteEvent.title ?? ""
        
        // Use multiple date formatters to handle different formats from Bubble
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let alternativeFormatter = ISO8601DateFormatter()
        alternativeFormatter.formatOptions = [.withInternetDateTime]
        
        let bubbleFormatter = DateFormatter()
        bubbleFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        // Parse start date
        if let startDateStr = remoteEvent.startDate {
            if let startDate = dateFormatter.date(from: startDateStr) {
                localEvent.startDate = startDate
            } else if let startDate = alternativeFormatter.date(from: startDateStr) {
                localEvent.startDate = startDate
            } else if let startDate = bubbleFormatter.date(from: startDateStr) {
                localEvent.startDate = startDate
            } else {
            }
        }
        
        // Parse end date
        if let endDateStr = remoteEvent.endDate {
            if let endDate = dateFormatter.date(from: endDateStr) {
                localEvent.endDate = endDate
            } else if let endDate = alternativeFormatter.date(from: endDateStr) {
                localEvent.endDate = endDate
            } else if let endDate = bubbleFormatter.date(from: endDateStr) {
                localEvent.endDate = endDate
            } else {
            }
        }
        
        localEvent.type = CalendarEventType(rawValue: remoteEvent.type?.lowercased() ?? "project") ?? .project
        localEvent.color = remoteEvent.color ?? "#59779F"
        localEvent.duration = Int(remoteEvent.duration ?? 1)
        
        // Populate team members from IDs
        if let teamMemberIds = remoteEvent.teamMembers {
            localEvent.setTeamMemberIds(teamMemberIds)
            populateCalendarEventTeamMembers(localEvent, teamMemberIds: teamMemberIds)
        }
        
        // Ensure projectEventType is set if we have a project relationship
        if let project = localEvent.project {
            // CRITICAL: Cache the project's event type for efficient filtering
            localEvent.projectEventType = project.effectiveEventType
            
            // Copy team members from project if event has no team members
            if localEvent.teamMembers.isEmpty && !project.teamMembers.isEmpty {
                localEvent.teamMembers = project.teamMembers
                localEvent.setTeamMemberIds(project.getTeamMemberIds())
            } else if !localEvent.getTeamMemberIds().isEmpty && localEvent.teamMembers.isEmpty {
                // Populate team members from stored IDs if not already populated
                populateCalendarEventTeamMembers(localEvent, teamMemberIds: localEvent.getTeamMemberIds())
            }
            
            // If this is a project-level event, sync dates back to the project
            if localEvent.type == .project {
                project.syncDatesWithCalendarEvent()
            }
        } else if !localEvent.projectId.isEmpty {
            // Try to link project if not already linked
            let projectId = localEvent.projectId
            do {
                let projectDescriptor = FetchDescriptor<Project>(
                    predicate: #Predicate<Project> { $0.id == projectId }
                )
                if let project = try modelContext.fetch(projectDescriptor).first {
                    localEvent.project = project
                    localEvent.projectEventType = project.effectiveEventType
                    
                    // Copy team members from project if event has no team members
                    if localEvent.teamMembers.isEmpty && !project.teamMembers.isEmpty {
                        localEvent.teamMembers = project.teamMembers
                        localEvent.setTeamMemberIds(project.getTeamMemberIds())
                    } else if !localEvent.getTeamMemberIds().isEmpty && localEvent.teamMembers.isEmpty {
                        // Populate team members from stored IDs if not already populated
                        populateCalendarEventTeamMembers(localEvent, teamMemberIds: localEvent.getTeamMemberIds())
                    }
                }
            } catch {
            }
        }
        
        // Also ensure task is linked if this is a task event
        if localEvent.task == nil, let taskId = localEvent.taskId, !taskId.isEmpty {
            do {
                let taskDescriptor = FetchDescriptor<ProjectTask>(
                    predicate: #Predicate<ProjectTask> { $0.id == taskId }
                )
                if let task = try modelContext.fetch(taskDescriptor).first {
                    localEvent.task = task
                    task.calendarEvent = localEvent
                    
                    // Copy team members from task if event has no team members
                    if localEvent.teamMembers.isEmpty && !task.teamMembers.isEmpty {
                        localEvent.teamMembers = task.teamMembers
                        localEvent.setTeamMemberIds(task.getTeamMemberIds())
                    } else if !localEvent.getTeamMemberIds().isEmpty && localEvent.teamMembers.isEmpty {
                        // Populate team members from stored IDs if not already populated
                        populateCalendarEventTeamMembers(localEvent, teamMemberIds: localEvent.getTeamMemberIds())
                    }
                }
            } catch {
            }
        }
        
        localEvent.lastSyncedAt = Date()
    }
    
    func syncCompanyTaskTypes(companyId: String) async throws {
        
        // Fetch task types from API
        let remoteTaskTypes = try await apiService.fetchCompanyTaskTypes(companyId: companyId)
        
        // Get local task types
        let descriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate<TaskType> { $0.companyId == companyId }
        )
        let localTaskTypes = try modelContext.fetch(descriptor)
        
        // If no remote task types exist, create defaults
        if remoteTaskTypes.isEmpty {
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

        // CRITICAL: Deduplicate remote task types by ID to prevent crash
        // Bubble API sometimes returns duplicate IDs which causes SwiftData unique constraint violation
        var uniqueRemoteTaskTypes: [TaskTypeDTO] = []
        var seenIds = Set<String>()
        for remoteTaskType in remoteTaskTypes {
            if !seenIds.contains(remoteTaskType.id) {
                uniqueRemoteTaskTypes.append(remoteTaskType)
                seenIds.insert(remoteTaskType.id)
            } else {
                print("[SYNC] ⚠️ Skipping duplicate task type ID: \(remoteTaskType.id)")
            }
        }

        // Process remote task types (deduplicated)
        for remoteTaskType in uniqueRemoteTaskTypes {
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

        // Remove local task types not in remote (use deduplicated list)
        let remoteTaskTypeIds = Set(uniqueRemoteTaskTypes.map { $0.id })
        for localTaskType in localTaskTypes {
            if !remoteTaskTypeIds.contains(localTaskType.id) {
                modelContext.delete(localTaskType)
            }
        }
        
        // After syncing, assign icons to task types that don't have them
        let allTaskTypes = try modelContext.fetch(descriptor)
        TaskType.assignIconsToTaskTypes(allTaskTypes)
        
        try modelContext.save()
    }
    
    /// Update tasks when project status changes
    private func updateTasksForProjectStatus(project: Project, projectStatus: Status) {
        switch projectStatus {
        case .inProgress:
            // When project starts, start the first scheduled task
            if let firstScheduledTask = project.tasks
                .filter({ $0.status == .booked })
                .sorted(by: { $0.displayOrder < $1.displayOrder })
                .first {
                firstScheduledTask.status = .inProgress
                firstScheduledTask.needsSync = true
            }
            
        case .completed:
            // When project completes, mark all non-cancelled tasks as completed
            for task in project.tasks {
                if task.status != .cancelled {
                    task.status = .completed
                    task.needsSync = true
                }
            }
            
        default:
            // No automatic task updates for other project statuses
            break
        }
    }
    
    /// Update task status on backend
    func updateTaskStatus(taskId: String, status: TaskStatus) async throws {
        
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
        
    }
    
    // MARK: - Client Management
    
    /// Link a project to its client, fetching the client if needed
    /// Update client contact information via API
    func updateClientContact(clientId: String, name: String, email: String?, phone: String?, address: String?) async throws -> Client? {
        do {
            
            // Call the Bubble workflow API and get the updated client
            let updatedClientDTO = try await apiService.updateClientContact(
                clientId: clientId,
                name: name,
                email: email,
                phone: phone,
                address: address
            )
            
            
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
                
                return existingClient
            } else {
                // Client doesn't exist locally, create it from the API response
                let newClient = updatedClientDTO.toModel()
                modelContext.insert(newClient)
                try modelContext.save()
                
                return newClient
            }
            
        } catch {
            throw error
        }
    }
    
    // MARK: - Sub-Client Methods
    
    func createSubClient(clientId: String, name: String, title: String?, email: String?, phone: String?, address: String?) async throws -> SubClientDTO {
        do {
            
            // Call the API to create sub-client
            let subClientDTO = try await apiService.createSubClient(
                clientId: clientId,
                name: name,
                title: title,
                email: email,
                phone: phone,
                address: address
            )
            
            return subClientDTO
        } catch {
            throw error
        }
    }
    
    func editSubClient(subClientId: String, name: String, title: String?, email: String?, phone: String?, address: String?) async throws -> SubClientDTO {
        do {
            
            // Call the API to edit sub-client
            let subClientDTO = try await apiService.editSubClient(
                subClientId: subClientId,
                name: name,
                title: title,
                email: email,
                phone: phone,
                address: address
            )
            
            return subClientDTO
        } catch {
            throw error
        }
    }
    
    func deleteSubClient(subClientId: String) async throws {
        do {
            
            // Call the API to delete sub-client
            try await apiService.deleteSubClient(subClientId: subClientId)
            
        } catch {
            throw error
        }
    }
    
    /// Refresh a single client's data when viewing project details
    func refreshSingleClient(clientId: String, for project: Project, forceRefresh: Bool = false) async {
        do {
            
            // Fetch fresh data from API
            let clientDTO = try await apiService.fetchClient(id: clientId)
            
            // Check if client already exists locally
            let clientPredicate = #Predicate<Client> { $0.id == clientId }
            let clientDescriptor = FetchDescriptor<Client>(predicate: clientPredicate)
            
            if let existingClient = try modelContext.fetch(clientDescriptor).first {
                // Update existing client with fresh data
                
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
                
                // Check if we have sub-client IDs from the client response
                if let subClientIds = clientDTO.subClientIds, !subClientIds.isEmpty {
                    // Client has sub-client IDs to fetch
                    
                    // Clear existing sub-clients
                    existingClient.subClients.removeAll()
                    
                    // Track how many we successfully fetch
                    var successfulFetches = 0
                    
                    // Fetch each sub-client by ID
                    for subClientId in subClientIds {
                        do {
                            let subClientDTO: SubClientDTO = try await apiService.fetchBubbleObject(
                                objectType: BubbleFields.Types.subClient,
                                id: subClientId
                            )
                            let subClient = subClientDTO.toSubClient()
                            subClient.client = existingClient
                            modelContext.insert(subClient)  // Insert into SwiftData
                            existingClient.subClients.append(subClient)
                            successfulFetches += 1
                        } catch {
                            // Continue with other sub-clients even if one fails
                        }
                    }
                    
                    // If all ID fetches failed, try constraint query as fallback
                    if successfulFetches == 0 && subClientIds.count > 0 {
                        let subClientDTOs = try await apiService.fetchSubClientsForClient(clientId: clientId)
                        
                        for subClientDTO in subClientDTOs {
                            let subClient = subClientDTO.toSubClient()
                            subClient.client = existingClient
                            modelContext.insert(subClient)
                            existingClient.subClients.append(subClient)
                        }
                    }
                } else {
                    // No sub-client IDs in response, trying constraint query
                    // Fallback: Try fetching sub-clients by client ID constraint
                    let subClientDTOs = try await apiService.fetchSubClientsForClient(clientId: clientId)
                    
                    // Clear existing sub-clients and add fresh ones
                    existingClient.subClients.removeAll()
                    for subClientDTO in subClientDTOs {
                        let subClient = subClientDTO.toSubClient()
                        subClient.client = existingClient
                        modelContext.insert(subClient)  // Insert into SwiftData
                        existingClient.subClients.append(subClient)
                    }
                }
                
            } else {
                // Create new client
                let newClient = clientDTO.toModel()
                newClient.companyId = project.companyId
                modelContext.insert(newClient)
                
                // Link to project
                project.client = newClient
                project.clientId = clientId
                newClient.projects.append(project)
                
                // Fetch and add sub-clients for new client
                
                // Check if we have sub-client IDs from the client response
                if let subClientIds = clientDTO.subClientIds, !subClientIds.isEmpty {
                    // New client has sub-client IDs to fetch
                    
                    // Fetch each sub-client by ID
                    for subClientId in subClientIds {
                        do {
                            let subClientDTO: SubClientDTO = try await apiService.fetchBubbleObject(
                                objectType: BubbleFields.Types.subClient,
                                id: subClientId
                            )
                            let subClient = subClientDTO.toSubClient()
                            subClient.client = newClient
                            modelContext.insert(subClient)  // Insert into SwiftData
                            newClient.subClients.append(subClient)
                        } catch {
                            // Continue with other sub-clients even if one fails
                        }
                    }
                } else {
                    // No sub-client IDs in response, trying constraint query
                    // Fallback: Try fetching sub-clients by client ID constraint
                    let subClientDTOs = try await apiService.fetchSubClientsForClient(clientId: clientId)
                    
                    for subClientDTO in subClientDTOs {
                        let subClient = subClientDTO.toSubClient()
                        subClient.client = newClient
                        modelContext.insert(subClient)  // Insert into SwiftData
                        newClient.subClients.append(subClient)
                    }
                }
                
            }
            
            // Save changes
            try modelContext.save()
            
        } catch {
            
            // Handle 404 gracefully
            if case APIError.httpError(let statusCode) = error, statusCode == 404 {
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
                return
            }
            
            
            // Fetch missing clients in batch
            let clientDTOs = try await apiService.fetchClientsByIds(clientIds: missingClientIds)
            
            
            // Convert and save
            for clientDTO in clientDTOs {
                let client = clientDTO.toModel()
                modelContext.insert(client)
            }
            
            // Check for any clients that weren't returned by the API
            let fetchedIds = Set(clientDTOs.map { $0.id })
            let notFoundIds = Set(missingClientIds).subtracting(fetchedIds)
            
            if !notFoundIds.isEmpty {
                // Create placeholder clients for missing ones
                for clientId in notFoundIds {
                    let placeholderClient = Client(
                        id: clientId,
                        name: "Client #\(clientId.prefix(4))",
                        email: nil,
                        phoneNumber: nil,
                        address: nil,
                        companyId: nil,
                        notes: nil
                    )
                    modelContext.insert(placeholderClient)
                }
            }
            
            try modelContext.save()
            
        } catch {
            
            // As a last resort, try to sync all company clients
            if let companyId = try? getCompanyId() {
                await syncCompanyClients(companyId: companyId)
            } else {
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
                // Found existing client for project
                
                project.client = existingClient
                project.clientId = clientId
                
                // Ensure client has this project in its list
                if !existingClient.projects.contains(where: { $0.id == project.id }) {
                    existingClient.projects.append(project)
                }
            } else {
                // Client doesn't exist locally - try to fetch it immediately
                
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
                } catch {
                    clientName = "Client (Syncing...)"
                    
                    // Try to sync all company clients as fallback
                    let companyId = project.companyId
                    if !companyId.isEmpty {
                        await syncCompanyClients(companyId: companyId)
                        
                        // Check if client exists now after company sync
                        let checkPredicate = #Predicate<Client> { $0.id == clientId }
                        let checkDescriptor = FetchDescriptor<Client>(predicate: checkPredicate)
                        if let syncedClient = try? modelContext.fetch(checkDescriptor).first {
                            // Client found after company sync
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
                    address: clientAddress,
                    companyId: project.companyId,
                    notes: nil
                )
                placeholderClient.profileImageURL = clientThumbnail
                modelContext.insert(placeholderClient)
                
                // Link to project
                project.client = placeholderClient
                project.clientId = clientId
                placeholderClient.projects.append(project)
                
            }
            
            // Save the context
            try modelContext.save()
        } catch {
        }
    }
    
    /// Sync all clients for a company
    func syncCompanyClients(companyId: String) async {
        do {
            
            // Fetch all clients for the company from API
            let clientDTOs = try await apiService.fetchCompanyClients(companyId: companyId)
            
            
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
            
        } catch {
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
                    // Debug: Log first user's data
                    if let firstUser = userDTOs.first {
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
                    
                    // Extract role using company admin status first, then employeeType
                    if isAdmin {
                        existingUser.role = .admin
                    } else if let employeeTypeString = userDTO.employeeType {
                        existingUser.role = BubbleFields.EmployeeType.toSwiftEnum(employeeTypeString)
                    } else {
                        existingUser.role = .fieldCrew
                    }
                    
                    // Set isCompanyAdmin based on whether user is in company's admin list
                    existingUser.isCompanyAdmin = isAdmin
                    
                    existingUser.profileImageURL = userDTO.avatar
                    existingUser.isActive = true // Users from API are considered active
                } else {
                    // Extract role using company admin status first, then employeeType
                    let role: UserRole
                    if isAdmin {
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
                    newUser.isCompanyAdmin = isAdmin // Set company admin status
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
        }
    }

    // MARK: - Calendar Event Creation

    private func createCalendarEventForProject(_ project: Project, startDate: Date, endDate: Date) async throws {
        let companyId = project.companyId
        let companyDescriptor = FetchDescriptor<Company>(
            predicate: #Predicate<Company> { $0.id == companyId }
        )
        let defaultColor = try modelContext.fetch(companyDescriptor).first?.defaultProjectColor ?? "#9CA3AF"  // Light grey fallback

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let duration = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1

        let eventDTO = CalendarEventDTO(
            id: UUID().uuidString,
            color: defaultColor,
            companyId: project.companyId,
            projectId: project.id,
            taskId: nil,
            duration: Double(duration),
            endDate: dateFormatter.string(from: endDate),
            startDate: dateFormatter.string(from: startDate),
            teamMembers: project.teamMembers.map { $0.id },
            title: project.effectiveClientName.capitalizedWords(),
            type: "Project",
            active: true,
            createdDate: nil,
            modifiedDate: nil,
            deletedAt: nil
        )

        let createdEvent = try await apiService.createAndLinkCalendarEvent(eventDTO)

        // Create local CalendarEvent and link to project
        await MainActor.run {
            let calendarEvent = CalendarEvent(
                id: createdEvent.id,
                projectId: project.id,
                companyId: project.companyId,
                title: project.effectiveClientName,
                startDate: startDate,
                endDate: endDate,
                color: defaultColor,
                type: .project,
                active: true
            )

            calendarEvent.projectEventType = .project
            calendarEvent.duration = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1
            calendarEvent.teamMemberIdsString = project.teamMembers.map { $0.id }.joined(separator: ",")

            modelContext.insert(calendarEvent)
            project.primaryCalendarEvent = calendarEvent

            try? modelContext.save()
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
