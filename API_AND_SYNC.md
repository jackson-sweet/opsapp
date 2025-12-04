# OPS API & Sync Architecture

**Purpose**: This document provides Claude (AI assistant) with complete context on OPS app API integration, sync strategies, and network operations. This enables accurate implementation of API calls, sync logic, and offline-first features.

**Last Updated**: December 4, 2025

---

## Table of Contents
1. [API Overview](#api-overview)
2. [API Endpoints by Entity](#api-endpoints-by-entity)
3. [Sync Architecture](#sync-architecture)
4. [CentralizedSyncManager](#centralizedsyncmanager)
5. [Image Upload & Sync](#image-upload--sync)
6. [Error Handling & Retry Logic](#error-handling--retry-logic)
7. [Network Configuration](#network-configuration)

---

## API Overview

### Backend: Bubble.io REST API

**Base URL**: `https://ops-app-36508.bubbleapps.io/version-test/api/1.1`

**Authentication**: Bearer token in Authorization header
```
Authorization: Bearer {userToken}
```

**Rate Limiting**:
- Minimum 0.5s between requests
- 30-second timeout for field conditions
- Automatic exponential backoff on failures

### API Types

Bubble provides two API endpoint types:

#### 1. Data API (CRUD Operations)
**Base**: `/api/1.1/obj/{dataType}`
- GET: Fetch records
- POST: Create records
- PATCH: Update records
- DELETE: Delete records (deprecated - use soft delete workflow)

#### 2. Workflow API (Custom Operations)
**Base**: `/api/1.1/wf/{workflowName}`
- POST: Trigger custom backend workflows
- Used for: Complex operations, batch updates, soft deletes, image registration

---

## API Endpoints by Entity

### Project Endpoints

#### Fetch Company Projects (Admin/Office Crew)
```
GET /api/1.1/obj/project
Query Parameters:
  - constraints: [{"key": "Company", "constraint_type": "equals", "value": "{companyId}"}]
  - constraints: [{"key": "Deleted Date", "constraint_type": "is_empty"}] (exclude deleted)

Returns: Array of ProjectDTO
```

#### Fetch User Projects (Field Crew)
```
GET /api/1.1/obj/project
Query Parameters:
  - constraints: [{"key": "Team Members", "constraint_type": "contains", "value": "{userId}"}]
  - constraints: [{"key": "Deleted Date", "constraint_type": "is_empty"}]

Returns: Array of ProjectDTO
```

#### Create Project
```
POST /api/1.1/obj/project
Body:
{
  "Name": "Project Name",
  "Company": "{companyId}",
  "Client": "{clientId}",
  "Status": "RFQ",
  "Color": "#59779F",
  "Street Address": "123 Main St",
  "City": "Austin",
  "State": "TX",
  "Zip": "78701",
  "Lat": 30.2672,
  "Long": -97.7431,
  "Team Members": ["{userId1}", "{userId2}"],
  "Notes": "Project description"
}

Returns: { "id": "{newProjectId}", "status": "success" }
```

#### Update Project
```
PATCH /api/1.1/obj/project/{projectId}
Body: Same as create (only include fields to update)

Returns: { "status": "success" }
```

#### Update Project Status
```
POST /api/1.1/wf/update_project_status
Body:
{
  "project_id": "{projectId}",
  "status": "In Progress"
}

Returns: { "status": "success" }
```

#### Soft Delete Project
```
POST /api/1.1/wf/delete_project
Body:
{
  "project_id": "{projectId}"
}

Action: Sets deletedAt = current date/time
Returns: { "status": "success" }
```

---

### Task Endpoints

#### Fetch Company Tasks
```
GET /api/1.1/obj/task
Query Parameters:
  - constraints: [{"key": "Project.Company", "constraint_type": "equals", "value": "{companyId}"}]
  - constraints: [{"key": "Deleted Date", "constraint_type": "is_empty"}]

Returns: Array of TaskDTO
```

#### Create Task
```
POST /api/1.1/obj/task
Body:
{
  "Project": "{projectId}",
  "Title": "Task title",
  "Task Type": "{taskTypeId}",
  "Status": "Booked",
  "Task Index": 0,
  "Team Members": ["{userId1}"],
  "Calendar Event": "{calendarEventId}",
  "Notes": "Task notes"
}

Returns: { "id": "{newTaskId}", "status": "success" }
```

#### Update Task
```
PATCH /api/1.1/obj/task/{taskId}
Body: Fields to update

Returns: { "status": "success" }
```

#### Update Task Status
```
POST /api/1.1/wf/update_task_status
Body:
{
  "task_id": "{taskId}",
  "status": "In Progress"
}

Returns: { "status": "success" }
```

#### Update Task Notes
```
POST /api/1.1/wf/update_task_notes
Body:
{
  "task_id": "{taskId}",
  "notes": "Updated notes text"
}

Returns: { "status": "success" }
```

---

### CalendarEvent Endpoints

#### Fetch Company Calendar Events
```
GET /api/1.1/obj/calendarevent
Query Parameters:
  - constraints: [{"key": "Company", "constraint_type": "equals", "value": "{companyId}"}]
  - constraints: [{"key": "Deleted Date", "constraint_type": "is_empty"}]
  - constraints: [{"key": "Start Date", "constraint_type": "greater than", "value": "2025-01-01"}]

Returns: Array of CalendarEventDTO
```

#### Create Calendar Event
```
POST /api/1.1/obj/calendarevent
Body:
{
  "Company": "{companyId}",
  "Project": "{projectId}",
  "Task": "{taskId}",
  "Title": "Event title",
  "Start Date": "2025-11-18T09:00:00Z",
  "End Date": "2025-11-18T17:00:00Z",
  "Color": "#59779F"
}

Returns: { "id": "{newEventId}", "status": "success" }
```

**Note**: Post-migration (Nov 2025), all calendar events must have taskId. No more eventType or active fields.

---

### Client Endpoints

#### Fetch Company Clients
```
GET /api/1.1/obj/client
Query Parameters:
  - constraints: [{"key": "Company", "constraint_type": "equals", "value": "{companyId}"}]
  - constraints: [{"key": "Deleted Date", "constraint_type": "is_empty"}]

Returns: Array of ClientDTO (includes subClients array)
```

#### Create Client
```
POST /api/1.1/obj/client
Body:
{
  "Company": "{companyId}",
  "Name": "Client Name",
  "Email": "client@example.com",
  "Phone Number": "512-555-1234",
  "Street Address": "123 Main St",
  "City": "Austin",
  "State": "TX",
  "Zip": "78701",
  "avatar": "https://s3.amazonaws.com/..."
}

Returns: { "id": "{newClientId}", "status": "success" }
```

#### Update Client Contact Info
```
POST /api/1.1/wf/update_client_contact
Body:
{
  "client_id": "{clientId}",
  "email": "newemail@example.com",
  "phone": "512-555-5678"
}

Returns: { "status": "success" }
```

#### Create Sub-Client
```
POST /api/1.1/wf/create_subclient
Body:
{
  "client_id": "{clientId}",
  "name": "Sub-client Name",
  "email": "subcontact@example.com",
  "phone": "512-555-9999",
  "role": "Manager"
}

Returns: { "id": "{newSubClientId}", "status": "success" }
```

---

### User Endpoints

#### Fetch Company Users
```
GET /api/1.1/obj/user
Query Parameters:
  - constraints: [{"key": "Company", "constraint_type": "equals", "value": "{companyId}"}]
  - constraints: [{"key": "Deleted Date", "constraint_type": "is_empty"}]

Returns: Array of UserDTO
```

#### Update User
```
PATCH /api/1.1/obj/user/{userId}
Body: Fields to update

Returns: { "status": "success" }
```

**Role Assignment Logic** (Critical - Fixed Nov 3, 2025):
1. Check if userId in `company.adminIds` → role = .admin
2. Else check `employeeType` field → convert using BubbleFields mapping
3. Else default to .fieldCrew

**Employee Type Mapping**:
```
Bubble Value        → iOS Role
"Office Crew"       → .officeCrew
"Field Crew"        → .fieldCrew
"Admin"             → .admin
nil/missing         → .fieldCrew (default)
```

---

### Company Endpoints

#### Fetch Company
```
GET /api/1.1/obj/company/{companyId}

Returns: CompanyDTO
```

#### Update Company
```
PATCH /api/1.1/obj/company/{companyId}
Body:
{
  "Company Name": "Updated Name",
  "Default Project Color": "#59779F",
  "logo": "https://s3.amazonaws.com/..."
}

Returns: { "status": "success" }
```

---

### TaskType Endpoints

#### Fetch Company Task Types
```
GET /api/1.1/obj/tasktype
Query Parameters:
  - constraints: [{"key": "Company", "constraint_type": "equals", "value": "{companyId}"}]
  - constraints: [{"key": "Deleted Date", "constraint_type": "is_empty"}]

Returns: Array of TaskTypeDTO
```

#### Create Task Type
```
POST /api/1.1/obj/tasktype
Body:
{
  "Company": "{companyId}",
  "Display": "Custom Task",
  "Color": "#FF5733",
  "Icon": "hammer.fill",
  "Is Default": false,
  "Display Order": 10
}

Returns: { "id": "{newTaskTypeId}", "status": "success" }
```

---

## Sync Architecture

### Triple-Layer Sync Strategy

The OPS app uses a three-tiered sync approach to balance responsiveness with reliability:

#### Layer 1: Immediate Sync (User Actions)
**Trigger**: User makes a change (status update, notes edit, etc.)
**Strategy**: Immediate API call if online
**Fallback**: Mark needsSync=true if offline

```swift
func updateProjectStatus(project: Project, newStatus: Status) async {
    // Optimistic update (immediate UI feedback)
    project.status = newStatus
    try? modelContext.save()

    // Immediate sync if online
    if isConnected {
        do {
            try await apiService.updateProjectStatus(
                projectId: project.id,
                status: newStatus.rawValue
            )
            project.needsSync = false
        } catch {
            project.needsSync = true  // Retry later
        }
    } else {
        project.needsSync = true      // Queue for sync
    }
}
```

#### Layer 2: Event-Driven Sync
**Triggers**:
- App launches (after authentication)
- Network connectivity restored
- App returns to foreground
- Subscription status changes

**Strategy**: Sync critical data immediately

```swift
// In DataController.swift
func setupConnectivityMonitoring() {
    connectivityMonitor.onConnectionTypeChanged = { [weak self] connectionType in
        guard connectionType != .none else { return }

        // Ignore first callback (initialization)
        guard self?.hasHandledInitialConnection == true else {
            self?.hasHandledInitialConnection = true
            return
        }

        // Connection restored - trigger sync
        Task { @MainActor in
            await self?.syncManager?.triggerBackgroundSync()
        }
    }
}
```

#### Layer 3: Periodic Retry Sync
**Trigger**: Timer-based check every 3 minutes
**Condition**: Only if pending syncs exist (needsSync=true)
**Strategy**: Sync items that failed in Layers 1 & 2

```swift
// Periodic timer in DataController
func startPeriodicSyncTimer() {
    syncTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
        Task { @MainActor in
            await self?.checkPendingSyncs()
        }
    }
}

func checkPendingSyncs() async {
    guard isConnected else { return }

    // Check for unsync items
    let hasPendingProjects = try? modelContext.fetch(
        FetchDescriptor<Project>(
            predicate: #Predicate { $0.needsSync == true }
        )
    ).count ?? 0 > 0

    if hasPendingProjects {
        await syncManager?.triggerBackgroundSync()
    }
}
```

---

## CentralizedSyncManager

**Location**: `/Network/Sync/CentralizedSyncManager.swift`

**Purpose**: Single source of truth for all sync operations. All sync logic centralized in one file for easy debugging and maintenance.

### Master Sync Functions

#### 1. syncAll() - Manual Complete Sync
Called when user taps "Sync" button or force refresh.

```swift
@MainActor
func syncAll() async throws {
    guard !syncInProgress, isConnected else {
        throw SyncError.alreadySyncing
    }

    syncInProgress = true
    defer { syncInProgress = false }

    print("[SYNC_ALL] 🔄 Starting complete sync...")

    // Sync in dependency order (parents before children)
    try await syncCompany()         // 1. Company & subscription
    try await syncUsers()           // 2. Team members
    try await syncClients()         // 3. Clients
    try await syncTaskTypes()       // 4. Task type templates
    try await syncProjects()        // 5. Projects
    try await syncTasks()           // 6. Tasks (requires projects)
    try await syncCalendarEvents()  // 7. Calendar events (requires projects/tasks)

    lastSyncDate = Date()
    print("[SYNC_ALL] ✅ Complete sync finished")
}
```

#### 2. syncAppLaunch() - App Startup Sync
Called after successful authentication.

```swift
@MainActor
func syncAppLaunch() async throws {
    guard !syncInProgress, isConnected else { return }

    syncInProgress = true
    defer { syncInProgress = false }

    print("[SYNC_LAUNCH] 🚀 Starting app launch sync...")

    // Critical data first (blocking)
    try await syncCompany()
    try await syncUsers()
    try await syncProjects()
    try await syncCalendarEvents()

    // Less critical data in background
    Task.detached(priority: .background) {
        try? await self.syncClients()
        try? await self.syncTaskTypes()
        try? await self.syncTasks()
    }

    lastSyncDate = Date()
    print("[SYNC_LAUNCH] ✅ App launch sync finished")
}
```

#### 3. syncBackgroundRefresh() - Periodic Refresh
Called by timer or connectivity restoration.

```swift
@MainActor
func syncBackgroundRefresh() async throws {
    guard !syncInProgress, isConnected else { return }

    syncInProgress = true
    defer { syncInProgress = false }

    print("[SYNC_BG] 🔄 Background refresh...")

    // Only sync data likely to have changed (with date filter)
    try await syncProjects(sinceDate: lastSyncDate)
    try await syncTasks(sinceDate: lastSyncDate)
    try await syncCalendarEvents(sinceDate: lastSyncDate)

    lastSyncDate = Date()
    print("[SYNC_BG] ✅ Background refresh complete")
}
```

#### 4. triggerBackgroundSync() - Debounced Trigger
Public method with debouncing to prevent duplicate syncs.

```swift
func triggerBackgroundSync(forceProjectSync: Bool = false) {
    // Debounce: Don't trigger if sync occurred < 2 seconds ago
    if let lastTrigger = lastSyncTriggerTime,
       Date().timeIntervalSince(lastTrigger) < minimumSyncInterval {
        print("[TRIGGER_BG_SYNC] ⏭️ Skipping - sync triggered recently")
        return
    }

    lastSyncTriggerTime = Date()
    guard !syncInProgress, isConnected else { return }

    Task { @MainActor in
        if forceProjectSync {
            try? await syncAll()
        } else {
            try? await syncBackgroundRefresh()
        }
    }
}
```

**Debouncing** (Added Nov 15, 2025):
- Minimum 2-second interval between sync triggers
- Prevents duplicate syncs during app launch
- Fixes issue where connectivity monitor and app launch both triggered sync

### Individual Entity Sync Functions

All entity sync functions follow this pattern:

```swift
@MainActor
func syncEntity() async throws {
    // 1. Fetch from Bubble API
    let dtos = try await apiService.fetchEntities()

    // 2. Handle soft deletions
    let remoteIds = Set(dtos.map { $0.id })
    try await handleEntityDeletions(keepingIds: remoteIds)

    // 3. Upsert each entity (update or insert)
    for dto in dtos {
        let entity = try await getOrCreateEntity(id: dto.id)
        // Update properties from DTO
        entity.property = dto.property
        entity.deletedAt = parseDate(dto.deletedAt)
        entity.needsSync = false
        entity.lastSyncedAt = Date()
    }

    // 4. Save to SwiftData
    try modelContext.save()

    print("[SYNC_ENTITY] ✅ Synced \(dtos.count) entities")
}
```

### Soft Delete Handling

```swift
private func handleProjectDeletions(keepingIds: Set<String>) async throws {
    let allProjects = try? modelContext.fetch(FetchDescriptor<Project>())

    let now = Date()
    let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!

    for project in allProjects ?? [] {
        if !keepingIds.contains(project.id) {
            // Only soft delete if:
            // 1. Not already deleted
            // 2. Synced within last 30 days
            // 3. Not a historical project (> 1 year old)
            if project.deletedAt == nil &&
               (project.lastSyncedAt ?? .distantPast) > thirtyDaysAgo {

                print("[DELETION] 🗑️ Soft deleting: \(project.name)")
                project.deletedAt = now

                // Cascade to related entities
                for task in project.tasks {
                    task.deletedAt = now
                }
            }
        }
    }
}
```

**30-Day Window**: Items deleted within last 30 days are soft-deleted. Older items are preserved as historical data.

---

## Image Upload & Sync

### Multi-Tier Image Architecture

**Storage Tiers**:
1. **AWS S3** - Primary remote storage
2. **Local File System** - Offline cache and pending uploads
3. **Memory Cache** - Fast re-display during session
4. **UserDefaults** - Legacy (migrated to file system)

### Image Flow

#### 1. Capture/Select Images
```swift
// User selects up to 10 images
ImagePicker(selectedImages: $selectedImages, limit: 10)

// Process and compress
for image in selectedImages {
    let compressedData = image.jpegData(compressionQuality: 0.7)
    let filename = generateFilename(project: project, index: index)
    // ... upload or save locally
}
```

#### 2. Filename Generation
```swift
func generateFilename(project: Project, timestamp: Date, index: Int) -> String {
    let streetAddress = project.street?.replacingOccurrences(of: " ", with: "_") ?? "Unknown"
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let dateStr = formatter.string(from: timestamp)

    return "\(streetAddress)_IMG_\(dateStr)_\(index).jpg"
}
```

**Format**: `{StreetAddress}_IMG_{timestamp}_{index}.jpg`
**Example**: `123_Main_St_IMG_20251118_143022_0.jpg`

#### 3. Upload Decision

```swift
func saveImages(project: Project, images: [UIImage]) async {
    if isConnected {
        // Online: Upload to S3
        await uploadToS3(project: project, images: images)
    } else {
        // Offline: Save locally with local:// prefix
        await saveLocally(project: project, images: images)
    }
}
```

#### 4A. Online Upload to S3

```swift
func uploadToS3(project: Project, images: [UIImage]) async {
    for (index, image) in images.enumerated() {
        // 1. Compress image
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { continue }

        // 2. Generate filename
        let filename = generateFilename(project: project, index: index)

        // 3. Generate AWS v4 signature
        let signature = generateAWSSignature(
            filename: filename,
            contentType: "image/jpeg"
        )

        // 4. Upload to S3
        let s3URL = try await s3UploadService.upload(
            data: imageData,
            filename: filename,
            contentType: "image/jpeg",
            signature: signature
        )

        // 5. Register with Bubble
        try await apiService.addProjectImage(
            projectId: project.id,
            imageURL: s3URL
        )

        // 6. Update project
        project.addImage(s3URL)
        project.needsSync = false
    }
}
```

**S3 Configuration**:
```
Bucket: ops-app-files-prod
Region: us-west-2
Path: company-{companyId}/{projectId}/photos/{filename}
```

#### 4B. Offline Save Locally

```swift
func saveLocally(project: Project, images: [UIImage]) async {
    for (index, image) in images.enumerated() {
        // 1. Compress
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { continue }

        // 2. Generate filename
        let filename = generateFilename(project: project, index: index)

        // 3. Save to Documents/ProjectImages/
        let fileURL = documentsDirectory
            .appendingPathComponent("ProjectImages")
            .appendingPathComponent(filename)

        try? imageData.write(to: fileURL)

        // 4. Create local URL with prefix
        let localURL = "local://project_images/\(filename)"

        // 5. Add to pending uploads queue
        addToPendingUploads(PendingImageUpload(
            localURL: localURL,
            projectId: project.id,
            companyId: project.companyId,
            timestamp: Date()
        ))

        // 6. Update project
        project.addImage(localURL)
        project.addUnsyncedImage(localURL)
        project.needsSync = true
    }
}
```

#### 5. Background Sync (Offline → Online)

```swift
func syncPendingImages() async {
    let pending = loadPendingUploads()
    let grouped = Dictionary(grouping: pending, by: { $0.projectId })

    for (projectId, uploads) in grouped {
        var uploadedURLs: [String] = []

        // Upload each image to S3
        for upload in uploads {
            do {
                let imageData = try loadLocalImage(upload.localURL)
                let s3URL = try await s3UploadService.upload(
                    data: imageData,
                    filename: extractFilename(upload.localURL)
                )
                uploadedURLs.append(s3URL)
            } catch {
                print("[IMAGE_SYNC] Failed to upload: \(error)")
                continue
            }
        }

        // Register all with Bubble
        if !uploadedURLs.isEmpty {
            try? await apiService.addProjectImages(
                projectId: projectId,
                imageURLs: uploadedURLs
            )

            // Update project: replace local URLs with S3 URLs
            if let project = fetchProject(id: projectId) {
                for (local, s3) in zip(uploads.map { $0.localURL }, uploadedURLs) {
                    project.replaceImage(local, with: s3)
                    project.removeUnsyncedImage(local)
                }
                project.needsSync = false
            }

            // Remove from pending queue
            removeFromPendingUploads(uploads)
        }
    }
}
```

### Image Fetching (Display)

Multi-tier cache check:

```swift
func loadImage(url: String) async -> UIImage? {
    // 1. Check memory cache
    if let cached = imageCache.get(url) {
        return cached
    }

    // 2. Check file system (local:// URLs)
    if url.hasPrefix("local://") {
        if let image = loadFromFileSystem(url) {
            imageCache.set(url, image)
            return image
        }
    }

    // 3. Check file system (cached remote URLs)
    if let image = loadCachedRemoteImage(url) {
        imageCache.set(url, image)
        return image
    }

    // 4. Download from network
    if let image = try? await downloadImage(url) {
        saveToFileSystem(url, image)
        imageCache.set(url, image)
        return image
    }

    return nil
}
```

### Image Deletion Sync

```swift
func syncProjectImages() async {
    // Fetch remote image list from API
    let remoteImages = try? await apiService.fetchProjectImages(projectId: project.id)
    let remoteSet = Set(remoteImages ?? [])

    // Get local images
    let localImages = project.getProjectImages()
    let localSet = Set(localImages.filter { !$0.hasPrefix("local://") })

    // Find deleted images (in local but not in remote)
    let deletedImages = localSet.subtracting(remoteSet)

    // Clean up caches
    for deletedURL in deletedImages {
        imageCache.remove(deletedURL)
        removeFromFileSystem(deletedURL)
        project.removeImage(deletedURL)
    }
}
```

---

## Error Handling & Retry Logic

### Sync Errors

```swift
enum SyncError: Error {
    case notConnected
    case alreadySyncing
    case missingUserId
    case missingCompanyId
    case apiError(Error)
    case dataCorruption
    case unauthorized
}
```

### Retry with Exponential Backoff

```swift
func syncWithRetry<T>(
    operation: () async throws -> T,
    maxRetries: Int = 3
) async throws -> T {
    var lastError: Error?

    for attempt in 1...maxRetries {
        do {
            return try await operation()
        } catch {
            lastError = error
            print("[SYNC] ⚠️ Attempt \(attempt) failed: \(error)")

            if attempt < maxRetries {
                // Exponential backoff: 2^attempt seconds
                let delay = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    throw lastError ?? SyncError.apiError(NSError(domain: "Unknown", code: -1))
}
```

**Retry Schedule**:
- Attempt 1: Immediate
- Attempt 2: 2 seconds delay
- Attempt 3: 4 seconds delay
- Give up: Throw error, mark needsSync=true

### API Service Configuration

```swift
class APIService {
    private let baseURL = "https://ops-app-36508.bubbleapps.io/version-test/api/1.1"
    private let timeout: TimeInterval = 30.0  // 30 seconds for field conditions
    private let minRequestInterval: TimeInterval = 0.5  // Rate limiting

    private var lastRequestTime: Date?

    func performRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        // Rate limiting
        if let lastRequest = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < minRequestInterval {
                try await Task.sleep(nanoseconds: UInt64((minRequestInterval - elapsed) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()

        // Create request
        var request = URLRequest(url: URL(string: baseURL + endpoint)!)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        // Decode
        return try JSONDecoder().decode(T.self, from: data)
    }
}
```

---

## Network Configuration

### Connectivity Monitoring

```swift
class ConnectivityMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    var isConnected: Bool = false
    var connectionType: ConnectionType = .none
    var onConnectionTypeChanged: ((ConnectionType) -> Void)?

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let newIsConnected = path.status == .satisfied

            let newConnectionType: ConnectionType
            if path.usesInterfaceType(.wifi) {
                newConnectionType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                newConnectionType = .cellular
            } else {
                newConnectionType = .none
            }

            DispatchQueue.main.async {
                self?.isConnected = newIsConnected
                if self?.connectionType != newConnectionType {
                    self?.connectionType = newConnectionType
                    self?.onConnectionTypeChanged?(newConnectionType)
                }
            }
        }

        monitor.start(queue: queue)
    }
}
```

**Connection Types**:
- `.none` - No network
- `.wifi` - WiFi connected
- `.cellular` - Cellular data
- `.ethernet` - Ethernet (rare on iOS)

### Sync Timing Summary

| Trigger | Function | When | Data Synced |
|---------|----------|------|-------------|
| **Manual Sync** | `syncAll()` | User taps sync button | Everything |
| **App Launch** | `syncAppLaunch()` | After authentication | Critical data first |
| **Network Restored** | `triggerBackgroundSync()` | Connection detected | Changed data only |
| **Periodic Retry** | Timer + `checkPendingSyncs()` | Every 3 min if pending | Items with needsSync=true |
| **User Action** | Individual update API | Immediate on change | Single item |

---

## Critical Fixes & Known Issues

### Recent Fixes

#### 1. Manual Sync Data Loss (Fixed Nov 3, 2025)
**Problem**: Manual sync caused all projects to disappear.
**Root Causes**:
- EmployeeType conversion checking wrong values ("Office" vs "Office Crew")
- syncUsers() not checking company.adminIds for admin status
- Admin users downgraded to Field Crew → only fetched assigned projects → soft deleted all others

**Fix**:
- Updated BubbleFields.EmployeeType mapping to match actual Bubble values
- Added company.adminIds check before employeeType check
- Three-tier role assignment: adminIds → employeeType → default

#### 2. App Launch Duplicate Syncs (Fixed Nov 15, 2025)
**Problem**: 2-4 concurrent syncs during app launch (900 records instead of 296).
**Root Causes**:
- App launch triggered sync
- Connectivity monitor initialization triggered sync
- Multiple rapid connectivity state changes

**Fix**:
- Added 2-second debouncing in triggerBackgroundSync()
- Ignore initial connectivity monitor callback
- Reduced sync triggers from ~4 to 1

### Known Issues

1. **Bubble Backend Uses "Scheduled" Status**
   - iOS uses "Booked" status (renamed Nov 2025)
   - DTOs handle backward compatibility
   - TODO: Update Bubble to use "Booked" consistently

2. **AWS Credentials Hardcoded**
   - S3UploadService has hardcoded access keys
   - TODO: Move to secure configuration service
   - Consider temporary credentials via STS

---

**End of API_AND_SYNC.md**

This document provides Claude with complete API and sync architecture context for accurate implementation of network operations and offline-first features.
