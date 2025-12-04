# OPS Data Models & Bubble Integration

**Purpose**: This document provides Claude (AI assistant) with complete context on OPS app data architecture, SwiftData models, Bubble field mappings, and data handling patterns. This enables accurate code generation and debugging without introducing data integrity issues.

**Last Updated**: December 4, 2025

---

## Table of Contents
1. [SwiftData Models](#swiftdata-models)
2. [Bubble Field Mappings](#bubble-field-mappings)
3. [DTOs (Data Transfer Objects)](#dtos-data-transfer-objects)
4. [SwiftData Best Practices](#swiftdata-best-practices)
5. [Query Predicates & Soft Delete](#query-predicates--soft-delete)
6. [CalendarEvent Filtering Logic](#calendarevent-filtering-logic)
7. [Task Scheduling System](#task-scheduling-system)

---

## SwiftData Models

### Core Entities (8 Models)

#### 1. Project
**Primary entity** for project management with task-based scheduling support.

```swift
@Model
final class Project: Identifiable {
    // Identity
    var id: String                    // Unique identifier
    var title: String                 // Project title (note: 'title' not 'name')
    var companyId: String            // Parent company
    var clientId: String?            // Associated client Bubble ID

    // Stored Dates (from API)
    var startDate: Date?             // Project start date from API
    var endDate: Date?               // Project end date from API
    var duration: Int?               // Duration in days from API

    // Computed Dates (from tasks - Task-Only Scheduling Nov 2025)
    var computedStartDate: Date? {    // Earliest task start date
        tasks.compactMap { $0.calendarEvent?.startDate }.min()
    }
    var computedEndDate: Date? {      // Latest task end date
        tasks.compactMap { $0.calendarEvent?.endDate }.max()
    }

    // Location
    var address: String?             // Full formatted address
    var latitude: Double?
    var longitude: Double?

    // Project Details
    var notes: String?
    var projectDescription: String?
    var status: Status               // RFQ, Estimated, Accepted, InProgress, Completed, Closed, Archived
    var allDay: Bool                 // All-day scheduling flag
    var projectImagesString: String = ""     // Comma-separated S3 URLs
    var unsyncedImagesString: String = ""   // Comma-separated local URLs

    // Team (stored as comma-separated string)
    var teamMemberIdsString: String = ""

    // Sync
    var needsSync: Bool = false
    var syncPriority: Int = 1        // 1-3, higher = more urgent
    var lastSyncedAt: Date?
    var deletedAt: Date?             // Soft delete timestamp

    // Relationships
    @Relationship(deleteRule: .nullify) var client: Client?
    @Relationship(deleteRule: .noAction) var teamMembers: [User]
    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.project) var tasks: [ProjectTask] = []

    // Transient properties (not persisted)
    @Transient var lastTapped: Date?
    @Transient var coordinatorData: [String: Any]?
}
```

**Status Workflow:**
```
RFQ → Estimated → Accepted → In Progress → Completed → Closed
                                                      ↘ Archived
```

#### 2. ProjectTask
**Full-featured task model** with team assignment and calendar integration.

```swift
@Model
final class ProjectTask {
    // Identity
    var id: String
    var projectId: String
    var companyId: String
    var taskIndex: Int?              // Index for task ordering (based on startDate)
    var displayOrder: Int = 0        // Display order within project

    // Task Details
    var customTitle: String?         // Optional custom title (overrides taskType.display)
    var taskNotes: String?
    var status: TaskStatus = .booked // Booked (formerly Scheduled), InProgress, Completed, Cancelled
    var taskTypeId: String           // References TaskType
    var taskColor: String            // Hex color code

    // Team (stored as comma-separated string)
    var teamMemberIdsString: String = ""

    // Calendar Integration
    var calendarEventId: String?     // Links to CalendarEvent

    // Sync
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    // Relationships
    @Relationship(deleteRule: .nullify) var project: Project?
    @Relationship(deleteRule: .cascade) var calendarEvent: CalendarEvent?
    @Relationship(deleteRule: .nullify) var taskType: TaskType?
    @Relationship(deleteRule: .noAction) var teamMembers: [User] = []

    // Computed Properties
    var displayTitle: String         // Returns customTitle or taskType.display
    var effectiveColor: String       // Returns taskType.color or taskColor
    var scheduledDate: Date?         // From calendarEvent.startDate
    var completionDate: Date?        // From calendarEvent.endDate
}
```

**Status Workflow:**
```
Booked → In Progress → Completed
       ↘ Cancelled
```

**Important**: Status renamed from "Scheduled" to "Booked" in November 2025. DTOs handle backward compatibility with Bubble.

#### 3. CalendarEvent
**Single source of truth** for all calendar display. Task-only scheduling as of Nov 2025.

```swift
@Model
final class CalendarEvent: Hashable {
    // Identity
    var id: String
    var companyId: String
    var projectId: String
    var taskId: String?              // Links to task

    // Dates
    var startDate: Date?
    var endDate: Date?
    var duration: Int                // Days

    // Display
    var title: String
    var color: String                // Hex color code

    // Team (stored as comma-separated string)
    var teamMemberIdsString: String = ""

    // Sync
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    // Relationships
    @Relationship(deleteRule: .nullify) var project: Project?
    @Relationship(deleteRule: .nullify, inverse: \ProjectTask.calendarEvent) var task: ProjectTask?
    @Relationship(deleteRule: .noAction) var teamMembers: [User] = []

    // Computed Properties
    var isMultiDay: Bool             // True if spans multiple days
    var spannedDates: [Date]         // All dates this event covers
}
```

**Post-Migration Behavior:**
- All calendar events should be task-based (taskId set)
- Project dates are computed from task calendar events
- BubbleFields.swift still has `eventType` and `active` fields for API compatibility

#### 4. TaskType
**Customizable task categories** with visual identity.

```swift
@Model
final class TaskType {
    var id: String
    var companyId: String
    var name: String                 // e.g., "Framing", "Electrical", "Plumbing"
    var color: String                // Hex color for UI
    var icon: String                 // SF Symbol name
    var isDefault: Bool = false      // System-provided vs user-created
    var sortOrder: Int = 0           // Display ordering

    var deletedAt: Date?
}
```

**Predefined Types:**
- Framing, Electrical, Plumbing, HVAC, Roofing, Flooring, Painting, Drywall, Concrete, Landscaping, General

#### 5. Client
**Client management** with sub-client support.

```swift
@Model
final class Client {
    var id: String
    var companyId: String
    var name: String
    var emailAddress: String?
    var phoneNumber: String?

    // Address
    var street: String?
    var city: String?
    var state: String?
    var zipCode: String?

    // Contact
    var avatar: String?              // S3 URL for client photo

    // Relationships
    @Relationship(deleteRule: .cascade) var subClients: [SubClient] = []

    var deletedAt: Date?
}
```

#### 6. SubClient
**Additional contacts** for a client.

```swift
@Model
final class SubClient {
    var id: String
    var clientId: String
    var name: String
    var emailAddress: String?
    var phoneNumber: String?
    var role: String?                // "Manager", "Foreman", etc.

    var deletedAt: Date?
}
```

#### 7. User
**Team member** with role-based permissions.

```swift
@Model
final class User {
    var id: String
    var companyId: String
    var nameFirst: String
    var nameLast: String
    var email: String
    var phoneNumber: String?

    // Role & Permissions
    var role: EmployeeType = .fieldCrew  // .admin, .officeCrew, .fieldCrew
    var isCompanyAdmin: Bool = false     // Determined by company.adminIds array
    var isSeated: Bool = true            // Subscription seat allocation

    // Authentication
    var authenticationMethod: AuthenticationMethod = .standard

    var deletedAt: Date?
}
```

**Role Hierarchy:**
```
Admin (company.adminIds) - Full access
  ├── Billing/subscriptions
  ├── Team member termination
  └── All Office Crew permissions

Office Crew - Management access
  ├── Client/project/task CRUD
  ├── Job Board access
  └── Analytics viewing

Field Crew - Limited access
  ├── View assigned projects
  └── Update task status
```

#### 8. Company
**Organization entity** managing subscription and defaults.

```swift
@Model
final class Company {
    var id: String
    var name: String
    var adminIds: [String] = []      // User IDs with admin role
    var seatedEmployeeIds: [String] = [] // User IDs with active seats
    var defaultProjectColor: String = "#59779F"
    var logo: String?                // S3 URL

    var deletedAt: Date?
}
```

---

## Bubble Field Mappings

### BubbleFields.swift Constants

All API communication uses `BubbleFields.swift` constants to ensure consistency. **Never hardcode field names.**

#### Project Fields
```swift
struct BubbleFields {
    struct Project {
        static let id = "_id"
        static let name = "Name"
        static let companyId = "Company"
        static let clientId = "Client"
        static let status = "Status"
        static let color = "Color"
        static let notes = "Notes"
        static let street = "Street Address"
        static let city = "City"
        static let state = "State"
        static let zipCode = "Zip"
        static let latitude = "Lat"
        static let longitude = "Long"
        static let teamMembers = "Team Members"    // Array of User IDs
        static let projectImages = "Project Images" // Array of S3 URLs
        static let deletedAt = "Deleted Date"

        // Removed in Task-Only Migration (Nov 2025):
        // static let eventType = "eventType"
        // static let calendarEventId = "Calendar Event"
    }
}
```

#### Task Fields
```swift
struct BubbleFields {
    struct Task {
        static let id = "_id"
        static let projectId = "Project"         // lowercase 'd'
        static let title = "Title"
        static let notes = "Notes"
        static let status = "Status"
        static let taskTypeId = "Task Type"
        static let taskIndex = "Task Index"      // Display order
        static let teamMembers = "Team Members"  // Array of User IDs
        static let calendarEventId = "Calendar Event"
        static let deletedAt = "Deleted Date"
    }
}
```

**Status Mapping (iOS ↔ Bubble):**
```
iOS: .booked      ↔ Bubble: "Scheduled" or "Booked" (backward compatible)
iOS: .inProgress  ↔ Bubble: "In Progress"
iOS: .completed   ↔ Bubble: "Completed"
iOS: .cancelled   ↔ Bubble: "Cancelled"
```

#### CalendarEvent Fields
```swift
struct BubbleFields {
    struct CalendarEvent {
        static let id = "_id"
        static let companyId = "Company"         // lowercase 'c'
        static let projectId = "Project"         // lowercase 'p'
        static let taskId = "Task"               // lowercase 't'
        static let title = "Title"
        static let startDate = "Start Date"
        static let endDate = "End Date"
        static let color = "Color"
        static let deletedAt = "Deleted Date"

        // Removed in Task-Only Migration (Nov 2025):
        // static let eventType = "eventType"
        // static let active = "active_boolean"
    }
}
```

#### Client Fields
```swift
struct BubbleFields {
    struct Client {
        static let id = "_id"
        static let companyId = "Company"
        static let name = "Name"
        static let emailAddress = "Email"        // camelCase
        static let phoneNumber = "Phone Number"
        static let street = "Street Address"
        static let city = "City"
        static let state = "State"
        static let zipCode = "Zip"
        static let avatar = "avatar"             // was "Thumbnail"
        static let subClients = "subClients"     // was "Sub Clients"
        static let deletedAt = "Deleted Date"
    }
}
```

#### User Fields
```swift
struct BubbleFields {
    struct User {
        static let id = "_id"
        static let companyId = "Company"
        static let nameFirst = "Name First"
        static let nameLast = "Name Last"
        static let email = "Email"
        static let phoneNumber = "Phone Number"
        static let employeeType = "Employee Type"
        static let isSeated = "Seated"
        static let deletedAt = "Deleted Date"
    }
}
```

**Employee Type Mapping (Bubble → iOS):**
```
"Office Crew" → .officeCrew
"Field Crew"  → .fieldCrew
"Admin"       → .admin
nil/missing   → Check company.adminIds, else default to .fieldCrew
```

**Critical**: EmployeeType bug fixed Nov 3, 2025. iOS was checking for wrong values ("Office", "Crew") instead of actual Bubble values ("Office Crew", "Field Crew").

---

## DTOs (Data Transfer Objects)

### Purpose
DTOs provide clean separation between Bubble API responses and SwiftData models. They handle:
- Field name mapping (Bubble → iOS)
- Type conversion (String dates → Date objects)
- Backward compatibility (status naming changes)
- Soft delete support

### ProjectDTO
```swift
struct ProjectDTO: Decodable {
    let id: String
    let name: String
    let company: String?             // Company ID
    let client: String?              // Client ID
    let status: String?
    let color: String?
    let notes: String?
    let street: String?
    let city: String?
    let state: String?
    let zipCode: String?
    let latitude: Double?
    let longitude: Double?
    let teamMembers: [String]?       // User IDs array
    let projectImages: [BubbleImage]?
    let deletedAt: String?           // ISO8601 string

    // Removed in Task-Only Migration:
    // let eventType: String?
    // let calendarEventId: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name = "Name"
        case company = "Company"
        case client = "Client"
        case status = "Status"
        case color = "Color"
        case notes = "Notes"
        case street = "Street Address"
        case city = "City"
        case state = "State"
        case zipCode = "Zip"
        case latitude = "Lat"
        case longitude = "Long"
        case teamMembers = "Team Members"
        case projectImages = "Project Images"
        case deletedAt = "Deleted Date"
    }

    func toModel() -> Project {
        let project = Project(
            id: id,
            name: name,
            companyId: company ?? "",
            clientId: client
        )
        project.status = Status(rawValue: status ?? "") ?? .rfq
        project.color = color ?? "#FFFFFF"
        project.notes = notes ?? ""
        // ... map all fields
        project.deletedAt = parseDate(deletedAt)
        return project
    }
}
```

### TaskDTO
```swift
struct TaskDTO: Decodable {
    let id: String
    let projectId: String?
    let title: String?
    let notes: String?
    let status: String?
    let taskTypeId: String?
    let taskIndex: Int?
    let teamMembers: [String]?
    let calendarEventId: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case projectId = "Project"        // lowercase 'd'
        case title = "Title"
        case notes = "Notes"
        case status = "Status"
        case taskTypeId = "Task Type"
        case taskIndex = "Task Index"
        case teamMembers = "Team Members"
        case calendarEventId = "Calendar Event"
        case deletedAt = "Deleted Date"
    }

    func toModel() -> ProjectTask {
        let task = ProjectTask(
            id: id,
            projectId: projectId ?? "",
            title: title ?? ""
        )
        // Handle "Scheduled" → "Booked" migration
        if let statusStr = status {
            if statusStr == "Scheduled" {
                task.status = .booked
            } else {
                task.status = TaskStatus(rawValue: statusStr) ?? .booked
            }
        }
        // ... map other fields
        task.deletedAt = parseDate(deletedAt)
        return task
    }
}
```

### CalendarEventDTO
```swift
struct CalendarEventDTO: Decodable {
    let id: String
    let companyId: String?
    let projectId: String?
    let taskId: String?
    let title: String?
    let startDate: String?           // ISO8601
    let endDate: String?             // ISO8601
    let color: String?
    let deletedAt: String?

    // Removed in Task-Only Migration:
    // let type: String?
    // let active: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case companyId = "Company"
        case projectId = "Project"
        case taskId = "Task"
        case title = "Title"
        case startDate = "Start Date"
        case endDate = "End Date"
        case color = "Color"
        case deletedAt = "Deleted Date"
    }

    func toModel(companyDefaultColor: String = "#59779F") -> CalendarEvent {
        let event = CalendarEvent(
            id: id,
            companyId: companyId ?? "",
            startDate: parseDate(startDate) ?? Date(),
            endDate: parseDate(endDate) ?? Date()
        )
        event.projectId = projectId
        event.taskId = taskId
        event.title = title ?? ""
        event.color = color ?? companyDefaultColor
        event.deletedAt = parseDate(deletedAt)
        return event
    }
}
```

---

## SwiftData Best Practices

### Critical Defensive Patterns

#### 1. Never Pass Models to Background Tasks
```swift
// ✅ CORRECT: Pass IDs
Task.detached {
    await processProject(projectId: project.id)
}

// ❌ INCORRECT: Passing model causes crashes
Task.detached {
    await processProject(project: project)  // CRASH!
}
```

#### 2. Always Fetch Fresh Models
```swift
func processProject(projectId: String) async {
    let context = ModelContext(sharedModelContainer)
    guard let project = try? context.fetch(
        FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectId }
        )
    ).first else { return }

    // Work with fresh model from this context
    project.needsSync = false
    try? context.save()
}
```

#### 3. Use @MainActor for UI Operations
```swift
@MainActor
func updateProject() {
    let context = dataController.modelContext
    // All SwiftData operations on main thread
}
```

#### 4. Explicit ModelContext.save()
```swift
// Always save explicitly after changes
project.name = "Updated Name"
try? modelContext.save()  // Don't rely on auto-save
```

#### 5. Avoid .id() Modifiers
```swift
// ❌ INCORRECT: Causes view recreation and SwiftData issues
TabView(selection: $selectedTab)
    .id(selectedTab)

// ✅ CORRECT: Let SwiftUI manage identity
TabView(selection: $selectedTab)
```

#### 6. Complete Data Wipe on Logout
```swift
func logout() {
    // Delete all data to prevent cross-user contamination
    try? modelContext.delete(model: Project.self)
    try? modelContext.delete(model: User.self)
    try? modelContext.delete(model: Client.self)
    // ... delete all entity types
    try? modelContext.save()

    // Clear UserDefaults
    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
}
```

---

## Query Predicates & Soft Delete

### Soft Delete Strategy

All models have `deletedAt: Date?` for soft delete support. This preserves historical data while hiding deleted items from normal queries.

**30-Day Window:**
- Items deleted < 30 days ago: Kept with deletedAt timestamp
- Items deleted > 30 days ago: Permanently deleted (future enhancement)

### Default Query Predicate

**Always filter out deleted items:**

```swift
// ✅ CORRECT: Exclude deleted items
@Query(
    filter: #Predicate<Project> { $0.deletedAt == nil },
    sort: \Project.name
) var projects: [Project]

// ❌ INCORRECT: Shows deleted items
@Query(sort: \Project.name) var projects: [Project]
```

### Entity-Specific Predicates

#### Active Projects
```swift
@Query(
    filter: #Predicate<Project> {
        $0.deletedAt == nil &&
        $0.status != .closed &&
        $0.status != .archived
    }
) var activeProjects: [Project]
```

#### User's Assigned Projects (Field Crew)
```swift
func userProjects(userId: String) -> [Project] {
    let descriptor = FetchDescriptor<Project>(
        predicate: #Predicate {
            $0.deletedAt == nil &&
            $0.teamMemberIds.contains(userId)
        }
    )
    return try? modelContext.fetch(descriptor) ?? []
}
```

#### Today's Calendar Events
```swift
@Query(
    filter: #Predicate<CalendarEvent> {
        $0.deletedAt == nil &&
        $0.startDate >= startOfToday &&
        $0.startDate < startOfTomorrow
    }
) var todaysEvents: [CalendarEvent]
```

### Sync Manager Soft Delete Logic

```swift
func syncProjects() async {
    // Fetch from API
    let remoteDTOs = try await apiService.fetchProjects()
    let remoteIds = Set(remoteDTOs.map { $0.id })

    // Fetch local projects
    let localProjects = try? modelContext.fetch(
        FetchDescriptor<Project>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
    )

    // Soft delete items not in remote set
    let now = Date()
    for project in localProjects ?? [] {
        if !remoteIds.contains(project.id) {
            project.deletedAt = now
        }
    }

    // Upsert remote items
    for dto in remoteDTOs {
        let project = dto.toModel()
        modelContext.insert(project)
    }

    try? modelContext.save()
}
```

---

## CalendarEvent Filtering Logic

### Post-Migration Simplification (Nov 2025)

With task-only scheduling, calendar event filtering is simpler:

```swift
// All calendar events are task-based
@Query(
    filter: #Predicate<CalendarEvent> {
        $0.deletedAt == nil &&
        $0.taskId != nil  // All events must have taskId
    }
) var calendarEvents: [CalendarEvent]
```

### Historical Context (Pre-Migration)

**Old Logic (removed):**
- Projects had `eventType` (.project or .task)
- CalendarEvents had `type` and `active` fields
- `shouldDisplay` property filtered based on project's scheduling mode
- If project used project-based scheduling, only show project-level events
- If project used task-based scheduling, only show task-level events

**This complexity is now removed.** All projects use task-based scheduling.

---

## Task Scheduling System

### Task-Based Scheduling Architecture

**As of November 2025**, all projects use task-based scheduling exclusively.

#### Key Concepts

1. **Project Dates are Computed**
   - `project.computedStartDate` = earliest task start
   - `project.computedEndDate` = latest task end
   - No stored dates on Project model

2. **Calendar Display**
   - Each ProjectTask has a linked CalendarEvent
   - Calendar queries filter by CalendarEvent (not Project)
   - Project cards show aggregated task dates

3. **Team Assignment**
   - Projects have `teamMemberIds` (overall team)
   - Tasks have `teamMemberIds` (task-specific team)
   - Task team changes automatically update project team

#### Creating Tasks

```swift
// 1. Create ProjectTask
let task = ProjectTask(
    id: UUID().uuidString,
    projectId: project.id,
    title: "Framing",
    taskIndex: project.tasks.count
)
task.status = .booked
task.taskTypeId = framingType.id
task.teamMemberIds = selectedTeamIds

// 2. Create CalendarEvent
let event = CalendarEvent(
    id: UUID().uuidString,
    companyId: project.companyId,
    startDate: startDate,
    endDate: endDate
)
event.projectId = project.id
event.taskId = task.id
event.title = "\(project.name) - \(task.title)"
event.color = project.color

// 3. Link and save
task.calendarEventId = event.id
modelContext.insert(task)
modelContext.insert(event)
try? modelContext.save()

// 4. Sync to API
await syncManager.createTask(task)
await syncManager.createCalendarEvent(event)
```

#### Task Status Workflow

```
Booked (default) → In Progress → Completed
               ↘ Cancelled

State Transitions:
- Booked → In Progress: Task started
- In Progress → Completed: Task finished
- Any → Cancelled: Task cancelled
- Cancelled → Booked: Reactivate task
```

#### Task Types

**System includes 11 predefined types:**
- Framing, Electrical, Plumbing, HVAC, Roofing
- Flooring, Painting, Drywall, Concrete, Landscaping, General

**Custom types:**
- Companies can create custom TaskTypes
- Each type has color, icon, and sort order
- Deletion requires reassigning affected tasks

---

## Migration Notes

### Task-Only Scheduling Migration (Nov 18, 2025)

**Changes:**
- ✅ Removed `project.eventType` field
- ✅ Removed `project.primaryCalendarEvent` field
- ✅ Removed `CalendarEvent.type` enum
- ✅ Removed `CalendarEvent.active` boolean
- ✅ Added `project.computedStartDate` computed property
- ✅ Added `project.computedEndDate` computed property
- ✅ One-time migration: deleted all project-level calendar events
- ✅ Simplified calendar filtering logic
- ✅ Updated all DTOs to exclude removed fields

**Impact:**
- All calendar display now flows through task calendar events
- Project dates dynamically computed from tasks
- Simpler architecture, less complexity
- No dual-mode logic required

### Status Renaming (Nov 11, 2025)

**Change:** Task status "Scheduled" → "Booked"

**Backward Compatibility:**
```swift
// DTOs handle both "Scheduled" (Bubble) and "Booked" (iOS)
if statusStr == "Scheduled" {
    task.status = .booked
} else {
    task.status = TaskStatus(rawValue: statusStr) ?? .booked
}
```

**TODO:** Update Bubble backend to use "Booked" consistently

---

## Data Health Validation

### Launch Health Check

On app launch, validate critical data integrity:

```swift
func performHealthCheck() {
    var issues: [String] = []

    // Check for current user
    guard let user = currentUser else {
        issues.append("No current user")
    }

    // Check for company
    guard let company = user?.company else {
        issues.append("No company")
    }

    // Check for minimum data
    let projectCount = countProjects()
    if projectCount == 0 && user?.role == .admin {
        issues.append("Admin with zero projects")
    }

    // Recovery if needed
    if !issues.isEmpty {
        await performRecoverySync()
    }
}
```

### Common Data Issues

1. **Role Assignment Bug** (Fixed Nov 3, 2025)
   - Users syncing as Field Crew instead of Admin
   - Caused all projects to disappear
   - Fix: Check `company.adminIds` first, then `employeeType`

2. **Cross-User Data Contamination**
   - User A sees User B's data after logout
   - Fix: Complete data wipe on logout

3. **Sync Deletion Cascade**
   - Soft delete removing too many items
   - Fix: 30-day window before permanent deletion

---

## File Structure

```
/OPS/DataModels/
  ├── Project.swift
  ├── ProjectTask.swift
  ├── CalendarEvent.swift
  ├── TaskType.swift
  ├── Client.swift
  ├── SubClient.swift
  ├── User.swift
  ├── Company.swift
  ├── Status.swift
  ├── UserRole.swift
  ├── BubbleTypes.swift
  ├── BubbleImage.swift
  ├── TeamMember.swift
  ├── OpsContact.swift
  ├── SubscriptionEnums.swift
  └── TaskStatusOption.swift

/OPS/Network/DTOs/
  ├── ProjectDTO.swift
  ├── TaskDTO.swift
  ├── CalendarEventDTO.swift
  ├── TaskTypeDTO.swift
  ├── ClientDTO.swift
  ├── SubClientDTO.swift
  ├── UserDTO.swift
  ├── CompanyDTO.swift
  ├── AppMessageDTO.swift
  ├── OpsContactDTO.swift
  └── TaskStatusOptionDTO.swift

/OPS/Network/API/
  ├── BubbleFields.swift      // Field name constants
  └── APIService.swift         // API client

/OPS/Network/Sync/
  └── CentralizedSyncManager.swift
```

---

**End of DATA_AND_MODELS.md**

This document provides Claude with complete data architecture context for accurate code generation and debugging.
