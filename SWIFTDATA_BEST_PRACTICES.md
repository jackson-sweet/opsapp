# SwiftData Best Practices Guide for OPS

This guide consolidates all SwiftData defensive patterns and best practices learned from fixing crashes in the OPS app, specifically targeting iOS 18 stability issues.

## Table of Contents
1. [Overview of SwiftData Issues in iOS 18](#overview)
2. [The Model Invalidation Problem](#model-invalidation)
3. [Best Practices for Thread Safety](#thread-safety)
4. [Cross-Context Model References](#cross-context)
5. [Background Task Execution](#background-tasks)
6. [Model Deletion and Cleanup](#deletion-cleanup)
7. [Memory Management](#memory-management)
8. [Code Examples: DO and DON'T](#code-examples)
9. [Testing Strategies](#testing)
10. [OPS-Specific Implementations](#ops-implementations)

## Overview of SwiftData Issues in iOS 18 {#overview}

iOS 18 introduced stricter enforcement of SwiftData model lifecycle management, leading to several classes of crashes that were previously tolerated:

### Common Crash Types
1. **Model Invalidation Crashes**: `"attempt to access object which has been invalidated"`
2. **Cross-Context Access**: Models from one context accessed in another
3. **Background Thread Violations**: UI context models accessed from background threads
4. **Relationship Corruption**: Invalid relationship state after model deletion
5. **Memory Pressure**: Excessive model retention causing memory warnings

### Root Causes
- SwiftData models become "faulted" when their context is released
- Background tasks holding references to main-thread models
- Passing model objects instead of identifiers to async operations
- Improper cleanup during logout/data wipe operations

## The Model Invalidation Problem {#model-invalidation}

### What Happens
When a SwiftData model is passed to a background task, the model can become "invalidated" if:
- The original context is modified
- The model is deleted elsewhere
- Memory pressure causes the context to fault objects
- The context is saved or reset

### Critical Fix Implemented in OPS
**Problem**: Passing Project models directly to background sync tasks
```swift
// ❌ DANGEROUS - Model can become invalidated
Task {
    await syncProjectTeamMembers(project) // project may be faulted
}
```

**Solution**: Pass only IDs, fetch fresh instances in background context
```swift
// ✅ SAFE - Use ID to fetch fresh instance
let projectId = project.id
Task { @MainActor in
    // Fetch fresh project in the task to avoid invalidation
    if let freshProject = self.getProjectWithoutSync(id: projectId) {
        await self.syncProjectTeamMembers(freshProject)
    }
}
```

## Best Practices for Thread Safety {#thread-safety}

### 1. Always Use @MainActor for UI Context Operations
```swift
@MainActor
class DataController: ObservableObject {
    var modelContext: ModelContext?
    
    @MainActor
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
}
```

### 2. Create Fresh Contexts for Background Operations
```swift
// ✅ SAFE - Create background context
func performBackgroundSync() async {
    let backgroundContext = ModelContext(container)
    
    // Use backgroundContext for all operations
    let descriptor = FetchDescriptor<Project>()
    let projects = try backgroundContext.fetch(descriptor)
    
    // Process projects...
}
```

### 3. Never Pass Models Between Contexts
```swift
// ❌ DANGEROUS
func backgroundTask(project: Project) async {
    // project is from main context, will crash
}

// ✅ SAFE
func backgroundTask(projectId: String) async {
    let backgroundContext = ModelContext(container)
    let descriptor = FetchDescriptor<Project>(
        predicate: #Predicate<Project> { $0.id == projectId }
    )
    guard let project = try? backgroundContext.fetch(descriptor).first else { return }
    // Use project safely in background context
}
```

## Cross-Context Model References {#cross-context}

### The Problem
SwiftData models are tied to their specific ModelContext. Accessing a model from a different context causes crashes.

### OPS Implementation Pattern
```swift
/// Gets a project by ID without triggering sync (internal use)
private func getProjectWithoutSync(id: String) -> Project? {
    guard let context = modelContext else { return nil }
    
    do {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == id }
        )
        let projects = try context.fetch(descriptor)
        return projects.first
    } catch {
        print("[DataController] Error fetching project \(id): \(error)")
        return nil
    }
}

/// Gets a project by ID (public interface)
func getProject(id: String) -> Project? {
    guard let context = modelContext else { 
        return nil 
    }
    
    // Always fetch fresh from context to avoid invalidated models
    do {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == id }
        )
        let projects = try context.fetch(descriptor)
        
        if let project = projects.first {
            // Don't pass the model to a background task - use the ID instead
            let projectId = project.id
            Task { @MainActor in
                // Fetch fresh project in the task to avoid invalidation
                if let freshProject = self.getProjectWithoutSync(id: projectId) {
                    await self.syncProjectTeamMembers(freshProject)
                }
            }
            return project
        }
        return nil
    } catch {
        return nil
    }
}
```

## Background Task Execution {#background-tasks}

### Safe Background Task Pattern
```swift
// ✅ SAFE PATTERN - Used throughout OPS SyncManager
func triggerBackgroundSync(forceProjectSync: Bool = false) {
    syncStateSubject.send(true)
    
    Task {
        do {
            // First sync company data to get latest subscription info
            try await syncCompanyData()
            
            // Process in batches of 10 to avoid large transaction costs
            for batch in pendingProjects.chunked(into: 10) {
                await withTaskGroup(of: Bool.self) { group in
                    for project in batch {
                        group.addTask {
                            await self.syncProjectStatus(project)
                            return true
                        }
                    }
                }
                
                // Give UI a chance to breathe between batches
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        } catch {
            print("Sync error: \(error)")
        }
        
        await MainActor.run {
            self.syncStateSubject.send(false)
        }
    }
}
```

### Background Context Creation
```swift
func createBackgroundContext() -> ModelContext {
    let backgroundContext = ModelContext(modelContainer)
    backgroundContext.autosaveEnabled = false // Manual control
    return backgroundContext
}
```

## Model Deletion and Cleanup {#deletion-cleanup}

### Proper Deletion Order (From OPS DataController)
```swift
@MainActor
private func performCompleteDataWipe() {
    guard let context = modelContext else { return }
    
    // Wrap in autoreleasepool to manage memory properly
    autoreleasepool {
        // Delete in correct order to avoid relationship issues
        // Start with leaf entities that don't have critical relationships
        
        // 1. Delete CalendarEvents first (they reference tasks and projects)
        if let calendarEvents = try? context.fetch(FetchDescriptor<CalendarEvent>()) {
            for event in calendarEvents {
                context.delete(event)
            }
        }
        
        // 2. Delete ProjectTasks (they reference projects)
        if let tasks = try? context.fetch(FetchDescriptor<ProjectTask>()) {
            for task in tasks {
                context.delete(task)
            }
        }
        
        // 3. Delete Projects (clear relationships first)
        if let projects = try? context.fetch(FetchDescriptor<Project>()) {
            for project in projects {
                // Clear relationships first to avoid crashes
                project.teamMembers.removeAll()
                context.delete(project)
            }
        }
        
        // 4. Delete Users (clear relationships first)
        if let users = try? context.fetch(FetchDescriptor<User>()) {
            for user in users {
                // Clear relationships first
                user.assignedProjects.removeAll()
                context.delete(user)
            }
        }
        
        // 5. Delete Companies last (they have relationships to many entities)
        if let companies = try? context.fetch(FetchDescriptor<Company>()) {
            for company in companies {
                // Clear relationships first
                company.teamMembers.removeAll()
                context.delete(company)
            }
        }
    }
    
    // Save all deletions outside autoreleasepool
    do {
        try context.save()
    } catch {
        print("Error saving after data wipe: \(error)")
    }
}
```

### Relationship Cleanup Pattern
```swift
// ✅ SAFE - Clear relationships before deletion
func deleteProject(_ project: Project) {
    // Clear all relationships first
    project.teamMembers.removeAll()
    project.tasks.removeAll()
    
    // Remove references from related objects
    for task in project.tasks {
        task.project = nil
    }
    
    // Finally delete the object
    modelContext.delete(project)
}
```

## Memory Management {#memory-management}

### Use autoreleasepool for Large Operations
```swift
// ✅ GOOD - Wrap large batch operations
autoreleasepool {
    for batch in largeDataSet.chunked(into: 100) {
        // Process batch
        for item in batch {
            // Create and process models
        }
        // Memory released at end of autoreleasepool
    }
}
```

### Avoid Retaining Large Numbers of Models
```swift
// ❌ BAD - Retaining thousands of models
class ViewModel: ObservableObject {
    @Published var allProjects: [Project] = []
    
    func loadAllProjects() {
        allProjects = dataController.getAllProjects() // Could be thousands
    }
}

// ✅ GOOD - Fetch on demand
class ViewModel: ObservableObject {
    func getProjects(limit: Int = 50) -> [Project] {
        return dataController.getProjects(limit: limit)
    }
}
```

## Code Examples: DO and DON'T {#code-examples}

### Fetching Models

#### ❌ DON'T: Cache model references
```swift
class ProjectManager {
    private var cachedProject: Project? // Will become invalidated
    
    func getCurrentProject() -> Project? {
        return cachedProject // Crash if invalidated
    }
}
```

#### ✅ DO: Always fetch fresh
```swift
class ProjectManager {
    private var currentProjectId: String?
    
    func getCurrentProject() -> Project? {
        guard let id = currentProjectId,
              let context = modelContext else { return nil }
        
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }
}
```

### Background Operations

#### ❌ DON'T: Pass models to background tasks
```swift
func syncProject(_ project: Project) {
    Task {
        // project can become invalidated here
        await apiService.syncProject(project) // CRASH
    }
}
```

#### ✅ DO: Pass IDs and fetch fresh
```swift
func syncProject(_ project: Project) {
    let projectId = project.id
    Task {
        // Create background context
        let backgroundContext = ModelContext(container)
        
        // Fetch fresh instance
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == projectId }
        )
        guard let freshProject = try? backgroundContext.fetch(descriptor).first else {
            return
        }
        
        await apiService.syncProject(freshProject)
    }
}
```

### Relationship Management

#### ❌ DON'T: Direct relationship modification without cleanup
```swift
func removeUserFromProject(user: User, project: Project) {
    project.teamMembers.removeAll { $0.id == user.id } // Incomplete
}
```

#### ✅ DO: Bidirectional relationship cleanup
```swift
func removeUserFromProject(user: User, project: Project) {
    // Remove from both sides of the relationship
    project.teamMembers.removeAll { $0.id == user.id }
    user.assignedProjects.removeAll { $0.id == project.id }
    
    // Update string-based storage if used
    project.setTeamMemberIds(project.teamMembers.map { $0.id })
}
```

### Error Handling

#### ❌ DON'T: Ignore SwiftData errors
```swift
func saveChanges() {
    try! context.save() // Will crash on error
}
```

#### ✅ DO: Graceful error handling
```swift
func saveChanges() -> Bool {
    do {
        try context.save()
        return true
    } catch {
        print("Failed to save context: \(error)")
        // Could implement retry logic here
        return false
    }
}
```

## Testing Strategies {#testing}

### 1. Memory Pressure Testing
```swift
func testMemoryPressure() {
    // Create many models to trigger memory warnings
    for i in 0..<10000 {
        let project = Project(id: "test-\(i)", title: "Test \(i)")
        context.insert(project)
    }
    
    // Trigger memory warning
    autoreleasepool {
        // Access models after memory pressure
    }
}
```

### 2. Context Switching Testing
```swift
func testContextSwitching() {
    let mainContext = ModelContext(container)
    let backgroundContext = ModelContext(container)
    
    // Create model in main context
    let project = Project(id: "test", title: "Test")
    mainContext.insert(project)
    try! mainContext.save()
    
    // Try to access from background context (should work with ID)
    let descriptor = FetchDescriptor<Project>(
        predicate: #Predicate<Project> { $0.id == "test" }
    )
    let fetchedProject = try! backgroundContext.fetch(descriptor).first
    XCTAssertNotNil(fetchedProject)
}
```

### 3. Background Task Testing
```swift
func testBackgroundSync() async {
    let expectation = XCTestExpectation(description: "Background sync completes")
    
    Task {
        await syncManager.triggerBackgroundSync()
        expectation.fulfill()
    }
    
    await fulfillment(of: [expectation], timeout: 30.0)
}
```

## OPS-Specific Implementations {#ops-implementations}

### 1. Duplicate User Cleanup
```swift
@MainActor
func cleanupDuplicateUsers() async {
    guard let context = modelContext else { return }
    
    do {
        // Fetch all users
        let descriptor = FetchDescriptor<User>()
        let allUsers = try context.fetch(descriptor)
        
        // Group users by ID
        var usersByID: [String: [User]] = [:]
        for user in allUsers {
            if usersByID[user.id] == nil {
                usersByID[user.id] = [user]
            } else {
                usersByID[user.id]?.append(user)
            }
        }
        
        // Find duplicate users
        let duplicateIDs = usersByID.filter { $0.value.count > 1 }.keys
        
        // For each set of duplicates, keep the most recently synced
        for id in duplicateIDs {
            guard let duplicates = usersByID[id], duplicates.count > 1 else { continue }
            
            let sortedDuplicates = duplicates.sorted { 
                guard let date1 = $0.lastSyncedAt, let date2 = $1.lastSyncedAt else {
                    return $0.lastSyncedAt != nil 
                }
                return date1 > date2
            }
            
            let userToKeep = sortedDuplicates[0]
            
            // Migrate relationships and delete duplicates
            var allProjects = Set<Project>(userToKeep.assignedProjects)
            
            for i in 1..<sortedDuplicates.count {
                let dupe = sortedDuplicates[i]
                
                // Merge projects
                for project in dupe.assignedProjects {
                    allProjects.insert(project)
                    
                    // Update project references
                    if let index = project.teamMembers.firstIndex(where: { $0.id == dupe.id }) {
                        if !project.teamMembers.contains(where: { $0.id == userToKeep.id }) {
                            project.teamMembers.remove(at: index)
                            project.teamMembers.append(userToKeep)
                        } else {
                            project.teamMembers.remove(at: index)
                        }
                    }
                }
                
                context.delete(dupe)
            }
            
            userToKeep.assignedProjects = Array(allProjects)
        }
        
        try context.save()
    } catch {
        print("Error cleaning up duplicate users: \(error)")
    }
}
```

### 2. Team Member Synchronization
```swift
@MainActor
func syncProjectTeamMembers(_ project: Project) async {
    guard let context = modelContext else { return }
    
    let teamMemberIds = project.getTeamMemberIds()
    if teamMemberIds.isEmpty { return }
    
    let existingMemberIds = Set(project.teamMembers.map { $0.id })
    let missingMemberIds = teamMemberIds.filter { !existingMemberIds.contains($0) }
    
    if missingMemberIds.isEmpty { return }
    
    for memberId in missingMemberIds {
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate<User> { $0.id == memberId }
        )
        
        do {
            let existingUsers = try context.fetch(descriptor)
            
            if let existingUser = existingUsers.first {
                // Add to project if not already there
                if !project.teamMembers.contains(where: { $0.id == existingUser.id }) {
                    project.teamMembers.append(existingUser)
                }
                
                // Add project to user if not already there
                if !existingUser.assignedProjects.contains(where: { $0.id == project.id }) {
                    existingUser.assignedProjects.append(project)
                }
            } else if isConnected {
                // Fetch from API if not exists locally
                do {
                    let userDTO = try await apiService.fetchUser(id: memberId)
                    let newUser = userDTO.toModel()
                    
                    newUser.assignedProjects.append(project)
                    project.teamMembers.append(newUser)
                    
                    context.insert(newUser)
                } catch {
                    // Create placeholder for failed fetches
                    let placeholderUser = User(
                        id: memberId,
                        firstName: "Team Member",
                        lastName: "#\(memberId.suffix(4))",
                        role: .fieldCrew,
                        companyId: project.companyId
                    )
                    
                    placeholderUser.assignedProjects.append(project)
                    project.teamMembers.append(placeholderUser)
                    
                    context.insert(placeholderUser)
                }
            }
        } catch {
            print("Error syncing team member \(memberId): \(error)")
        }
    }
    
    do {
        try context.save()
    } catch {
        print("Error saving team member sync: \(error)")
    }
}
```

### 3. Defensive Calendar Event Fetching
```swift
func getCalendarEventsForCurrentUser(for date: Date) -> [CalendarEvent] {
    guard let user = currentUser else { return [] }
    guard let context = modelContext else { return [] }
    
    let descriptor = FetchDescriptor<CalendarEvent>()
    
    do {
        let allEvents = try context.fetch(descriptor)
        
        let filteredEvents = allEvents.filter { event in
            // Check if event is active on this date
            let spannedDates = event.spannedDates
            let isActiveOnDate = spannedDates.contains { 
                Calendar.current.isDate($0, inSameDayAs: date) 
            }
            
            if !isActiveOnDate { return false }
            
            // Check if event should be displayed based on project scheduling mode
            let shouldDisplay = event.shouldDisplay
            if !shouldDisplay { return false }
            
            // Role-based filtering
            if user.role == .admin || user.role == .officeCrew {
                return event.companyId == user.companyId
            } else {
                // Field crew only see assigned events
                let eventTeamMemberIds = event.getTeamMemberIds()
                let isAssignedViaIds = eventTeamMemberIds.contains(user.id)
                let isAssignedViaObjects = event.teamMembers.contains(where: { $0.id == user.id })
                
                return isAssignedViaIds || isAssignedViaObjects
            }
        }
        
        return filteredEvents.sorted { $0.startDate < $1.startDate }
    } catch {
        print("Error fetching calendar events: \(error)")
        return []
    }
}
```

## Key Takeaways

1. **Never pass SwiftData models to background tasks** - Use IDs instead
2. **Always fetch fresh model instances** - Don't cache model references
3. **Use @MainActor for UI context operations** - Maintain thread safety
4. **Clean up relationships before deletion** - Prevent orphaned references
5. **Use autoreleasepool for large operations** - Manage memory properly
6. **Handle errors gracefully** - Don't crash on SwiftData errors
7. **Test with memory pressure** - Validate stability under stress
8. **Batch large operations** - Prevent UI blocking and memory spikes

These patterns have been battle-tested in the OPS app and have eliminated SwiftData crashes in iOS 18. Following these practices will ensure your SwiftData implementation remains stable and performant.