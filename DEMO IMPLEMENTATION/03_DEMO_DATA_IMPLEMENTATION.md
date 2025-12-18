# DEMO DATA IMPLEMENTATION GUIDE

How to seed, manage, and clean up Top Gun demo data for the tutorial.

---

## 1. ID STRATEGY

All demo entities use `DEMO_` prefix for easy identification and cleanup:

```swift
struct DemoIDs {
    // Team Members
    static let peteMitchell = "DEMO_USER_MAVERICK"
    static let nickBradshaw = "DEMO_USER_GOOSE"
    static let tomKazansky = "DEMO_USER_ICEMAN"
    static let mikeMetcalf = "DEMO_USER_VIPER"
    static let rickHeatherly = "DEMO_USER_JESTER"

    // Clients
    static let miramarFlight = "DEMO_CLIENT_MIRAMAR"
    static let charlieBlackwood = "DEMO_CLIENT_CHARLIE"
    static let oClub = "DEMO_CLIENT_OCLUB"
    static let fightertown = "DEMO_CLIENT_FIGHTERTOWN"
    static let officerHousing = "DEMO_CLIENT_HOUSING"

    // Task Types
    static let cleaning = "DEMO_TASKTYPE_CLEANING"
    static let demolition = "DEMO_TASKTYPE_DEMOLITION"
    static let painting = "DEMO_TASKTYPE_PAINTING"
    static let sealing = "DEMO_TASKTYPE_SEALING"
    static let paving = "DEMO_TASKTYPE_PAVING"
    static let landscaping = "DEMO_TASKTYPE_LANDSCAPING"
    static let installation = "DEMO_TASKTYPE_INSTALLATION"
    static let pressureWash = "DEMO_TASKTYPE_PRESSUREWASH"
    static let diagnostic = "DEMO_TASKTYPE_DIAGNOSTIC"
    static let removal = "DEMO_TASKTYPE_REMOVAL"
    static let coating = "DEMO_TASKTYPE_COATING"
    static let planting = "DEMO_TASKTYPE_PLANTING"

    // Projects (15 total)
    static let migDetailing = "DEMO_PROJECT_MIG"
    static let lockerRoom = "DEMO_PROJECT_LOCKER"
    static let housingLandscape = "DEMO_PROJECT_LANDSCAPE1"
    static let charlieDriveway = "DEMO_PROJECT_DRIVEWAY"
    static let oClubKitchen = "DEMO_PROJECT_KITCHEN"
    static let flightDeck = "DEMO_PROJECT_FLIGHTDECK"
    static let oClubPatio = "DEMO_PROJECT_PATIO"
    static let hangarSiding = "DEMO_PROJECT_HANGAR"
    static let charlieOffice = "DEMO_PROJECT_OFFICE"
    static let parkingLot = "DEMO_PROJECT_PARKING"
    static let jetInterior = "DEMO_PROJECT_JET"
    static let runwayCrack = "DEMO_PROJECT_RUNWAY"
    static let briefingRoom = "DEMO_PROJECT_BRIEFING"
    static let poolDeck = "DEMO_PROJECT_POOL"
    static let oClubLandscape = "DEMO_PROJECT_LANDSCAPE2"

    // Company
    static let demoCompany = "DEMO_COMPANY_TOPGUN"
}
```

---

## 2. DATE CALCULATION

All dates relative to seed time:

```swift
struct DemoDateCalculator {
    private let seedDate: Date

    init(seedDate: Date = Date()) {
        self.seedDate = Calendar.current.startOfDay(for: seedDate)
    }

    /// Past date: current - N days
    func past(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: seedDate)!
    }

    /// Current date (today)
    var current: Date { seedDate }

    /// Future date: current + N days
    func future(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: seedDate)!
    }

    /// Determine task status based on scheduled date
    func taskStatus(for scheduledDate: Date) -> TaskStatus {
        let dayDiff = Calendar.current.dateComponents([.day], from: seedDate, to: scheduledDate).day ?? 0

        if dayDiff < -1 {
            return .completed
        } else if dayDiff >= -1 && dayDiff <= 1 {
            return .inProgress
        } else {
            return .booked
        }
    }
}
```

---

## 3. DATA STRUCTURES

### Team Members
```swift
struct DemoTeamMemberData {
    let id: String
    let firstName: String
    let lastName: String
    let specializations: [String]  // Task type IDs they can be assigned to

    static let all: [DemoTeamMemberData] = [
        DemoTeamMemberData(
            id: DemoIDs.peteMitchell,
            firstName: "Pete",
            lastName: "Mitchell",
            specializations: [DemoIDs.coating, DemoIDs.sealing, DemoIDs.painting]
        ),
        DemoTeamMemberData(
            id: DemoIDs.nickBradshaw,
            firstName: "Nick",
            lastName: "Bradshaw",
            specializations: [DemoIDs.installation, DemoIDs.removal]
        ),
        DemoTeamMemberData(
            id: DemoIDs.tomKazansky,
            firstName: "Tom",
            lastName: "Kazansky",
            specializations: [DemoIDs.demolition, DemoIDs.pressureWash]
        ),
        DemoTeamMemberData(
            id: DemoIDs.mikeMetcalf,
            firstName: "Mike",
            lastName: "Metcalf",
            specializations: [DemoIDs.diagnostic, DemoIDs.cleaning]
        ),
        DemoTeamMemberData(
            id: DemoIDs.rickHeatherly,
            firstName: "Rick",
            lastName: "Heatherly",
            specializations: [DemoIDs.landscaping, DemoIDs.planting, DemoIDs.paving]
        )
    ]
}
```

### Clients
```swift
struct DemoClientData {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    static let all: [DemoClientData] = [
        DemoClientData(
            id: DemoIDs.miramarFlight,
            name: "Miramar Flight Academy",
            address: "9800 Anderson St, San Diego, CA 92126",
            latitude: 32.8734,
            longitude: -117.1439
        ),
        DemoClientData(
            id: DemoIDs.charlieBlackwood,
            name: "Charlie Blackwood",
            address: "10452 Scripps Lake Dr, San Diego, CA 92131",
            latitude: 32.9067,
            longitude: -117.1156
        ),
        DemoClientData(
            id: DemoIDs.oClub,
            name: "O'Club Bar & Grill",
            address: "8680 Miralani Dr, San Diego, CA 92126",
            latitude: 32.8945,
            longitude: -117.1423
        ),
        DemoClientData(
            id: DemoIDs.fightertown,
            name: "Fightertown Hangars LLC",
            address: "5915 Mira Mesa Blvd, San Diego, CA 92121",
            latitude: 32.9134,
            longitude: -117.1512
        ),
        DemoClientData(
            id: DemoIDs.officerHousing,
            name: "Miramar Officer Housing",
            address: "11056 Portobelo Dr, San Diego, CA 92124",
            latitude: 32.8523,
            longitude: -117.1012
        )
    ]
}
```

### Task Types
```swift
struct DemoTaskTypeData {
    let id: String
    let display: String
    let color: String  // Hex
    let icon: String   // SF Symbol

    static let all: [DemoTaskTypeData] = [
        DemoTaskTypeData(id: DemoIDs.cleaning, display: "Cleaning", color: "#A8D8B9", icon: "sparkles"),
        DemoTaskTypeData(id: DemoIDs.demolition, display: "Demolition", color: "#E8A87C", icon: "hammer.fill"),
        DemoTaskTypeData(id: DemoIDs.painting, display: "Painting", color: "#89B4E8", icon: "paintbrush.fill"),
        DemoTaskTypeData(id: DemoIDs.sealing, display: "Sealing", color: "#B4C7E8", icon: "drop.fill"),
        DemoTaskTypeData(id: DemoIDs.paving, display: "Paving", color: "#C4B7D4", icon: "rectangle.split.3x3.fill"),
        DemoTaskTypeData(id: DemoIDs.landscaping, display: "Landscaping", color: "#8FD4A4", icon: "leaf.fill"),
        DemoTaskTypeData(id: DemoIDs.installation, display: "Installation", color: "#D4A8C7", icon: "wrench.and.screwdriver.fill"),
        DemoTaskTypeData(id: DemoIDs.pressureWash, display: "Pressure Wash", color: "#E8D48A", icon: "wind"),
        DemoTaskTypeData(id: DemoIDs.diagnostic, display: "Diagnostic", color: "#8AD4D4", icon: "magnifyingglass"),
        DemoTaskTypeData(id: DemoIDs.removal, display: "Removal", color: "#E8B89A", icon: "trash.fill"),
        DemoTaskTypeData(id: DemoIDs.coating, display: "Coating", color: "#7AA8D4", icon: "paintpalette.fill"),
        DemoTaskTypeData(id: DemoIDs.planting, display: "Planting", color: "#B8E8A8", icon: "camera.macro")
    ]
}
```

### Projects with Tasks
```swift
struct DemoProjectData {
    let id: String
    let title: String
    let clientId: String
    let description: String?
    let notes: String?
    let tasks: [DemoTaskData]

    struct DemoTaskData {
        let taskTypeId: String
        let crewIds: [String]
        let daysFromCurrent: Int  // Negative = past, 0 = today, positive = future
        let notes: String?
    }
}

// Example: Flight Deck Coating (IN_PROGRESS)
let flightDeckProject = DemoProjectData(
    id: DemoIDs.flightDeck,
    title: "Flight Deck Coating",
    clientId: DemoIDs.miramarFlight,
    description: "Recoat helicopter landing pad. Must meet military slip-resistance spec.",
    notes: "CO signed off on 48hr cure time. No flight ops until Friday.",
    tasks: [
        DemoTaskData(
            taskTypeId: DemoIDs.removal,
            crewIds: [DemoIDs.nickBradshaw],
            daysFromCurrent: -3,
            notes: "Old coating came up easier than expected"
        ),
        DemoTaskData(
            taskTypeId: DemoIDs.coating,
            crewIds: [DemoIDs.peteMitchell],
            daysFromCurrent: 0,
            notes: "Using MIL-PRF-24667 gray, 2 coats"
        ),
        DemoTaskData(
            taskTypeId: DemoIDs.sealing,
            crewIds: [DemoIDs.peteMitchell],
            daysFromCurrent: 2,
            notes: "Anti-slip aggregate in final coat"
        )
    ]
)
```

---

## 4. SEEDING IMPLEMENTATION

### Main Seeder Class
```swift
@MainActor
class TutorialDemoDataManager {
    private let context: ModelContext
    private let dateCalculator: DemoDateCalculator

    init(context: ModelContext) {
        self.context = context
        self.dateCalculator = DemoDateCalculator()
    }

    // MARK: - Public API

    func seedAllDemoData() async throws {
        // Order matters due to relationships
        try await seedTaskTypes()
        try await seedUsers()
        try await seedClients()
        try await seedProjects()
        try context.save()
    }

    func cleanupAllDemoData() async throws {
        try await deleteProjects()
        try await deleteClients()
        try await deleteTaskTypes()
        try await deleteUsers()
        try context.save()
    }

    func assignCurrentUserToTasks(userId: String) async throws {
        // For employee flow: add current user to 2-3 today tasks
        // Implementation below
    }

    // MARK: - Seeding Methods

    private func seedTaskTypes() async throws {
        for data in DemoTaskTypeData.all {
            let taskType = TaskType(
                id: data.id,
                display: data.display,
                color: data.color,
                companyId: DemoIDs.demoCompany,
                isDefault: false,
                icon: data.icon
            )
            context.insert(taskType)
        }
    }

    private func seedUsers() async throws {
        for data in DemoTeamMemberData.all {
            let user = User(
                id: data.id,
                firstName: data.firstName,
                lastName: data.lastName,
                companyId: DemoIDs.demoCompany
            )
            // Set role based on first character of callsign
            user.role = .fieldCrew
            context.insert(user)
        }
    }

    private func seedClients() async throws {
        for data in DemoClientData.all {
            let client = Client(
                id: data.id,
                name: data.name,
                address: data.address,
                companyId: DemoIDs.demoCompany
            )
            client.latitude = data.latitude
            client.longitude = data.longitude
            context.insert(client)
        }
    }

    private func seedProjects() async throws {
        for projectData in DemoProjectData.all {
            // Create project
            let project = Project(
                id: projectData.id,
                title: projectData.title,
                status: .accepted  // Will be computed based on tasks
            )
            project.projectDescription = projectData.description
            project.notes = projectData.notes
            project.companyId = DemoIDs.demoCompany

            // Link client
            if let client = fetchClient(id: projectData.clientId) {
                project.client = client
                project.clientId = client.id
                project.address = client.address
                project.latitude = client.latitude
                project.longitude = client.longitude
            }

            context.insert(project)

            // Create tasks
            for (index, taskData) in projectData.tasks.enumerated() {
                let taskId = "\(projectData.id)_TASK_\(index)"
                let scheduledDate = dateCalculator.dateForOffset(taskData.daysFromCurrent)
                let taskStatus = dateCalculator.taskStatus(for: scheduledDate)

                let task = ProjectTask(
                    id: taskId,
                    projectId: project.id,
                    taskTypeId: taskData.taskTypeId,
                    companyId: DemoIDs.demoCompany,
                    status: taskStatus
                )
                task.taskNotes = taskData.notes
                task.project = project
                task.displayOrder = index

                // Link task type
                if let taskType = fetchTaskType(id: taskData.taskTypeId) {
                    task.taskType = taskType
                }

                // Assign crew
                let crewUsers = taskData.crewIds.compactMap { fetchUser(id: $0) }
                task.teamMembers = crewUsers
                task.setTeamMemberIds(taskData.crewIds)

                // Create calendar event
                let calendarEvent = CalendarEvent(
                    id: "\(taskId)_EVENT",
                    projectId: project.id,
                    taskId: taskId,
                    title: task.displayTitle,
                    startDate: scheduledDate,
                    endDate: scheduledDate,
                    companyId: DemoIDs.demoCompany
                )
                calendarEvent.color = task.effectiveColor
                calendarEvent.setTeamMemberIds(taskData.crewIds)
                calendarEvent.teamMembers = crewUsers

                context.insert(calendarEvent)
                task.calendarEvent = calendarEvent
                task.calendarEventId = calendarEvent.id

                context.insert(task)
                project.tasks.append(task)
            }

            // Update project status based on tasks
            project.status = computeProjectStatus(tasks: project.tasks)

            // Update project team members from tasks
            project.updateTeamMembersFromTasks(in: context)
        }
    }

    // MARK: - Helper Methods

    private func computeProjectStatus(tasks: [ProjectTask]) -> Status {
        if tasks.isEmpty { return .accepted }
        if tasks.contains(where: { $0.status == .inProgress }) { return .inProgress }
        if tasks.allSatisfy({ $0.status == .completed }) { return .completed }
        return .accepted
    }

    private func fetchClient(id: String) -> Client? {
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchTaskType(id: String) -> TaskType? {
        let descriptor = FetchDescriptor<TaskType>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchUser(id: String) -> User? {
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
```

---

## 5. EMPLOYEE FLOW: ASSIGN CURRENT USER

For the employee tutorial flow, dynamically add the current user to demo tasks:

```swift
extension TutorialDemoDataManager {
    func assignCurrentUserToTasks(userId: String) async throws {
        // Get current user
        guard let currentUser = fetchUser(id: userId) else { return }

        // Find tasks scheduled for today (IN_PROGRESS status)
        let todayTasks = try fetchTodayDemoTasks()

        // Assign current user to first 2-3 tasks
        let tasksToAssign = Array(todayTasks.prefix(3))

        for task in tasksToAssign {
            // Add to team members
            if !task.teamMembers.contains(where: { $0.id == userId }) {
                task.teamMembers.append(currentUser)
                var ids = task.getTeamMemberIds()
                ids.append(userId)
                task.setTeamMemberIds(ids)
            }

            // Update calendar event
            if let event = task.calendarEvent {
                if !event.teamMembers.contains(where: { $0.id == userId }) {
                    event.teamMembers.append(currentUser)
                    var eventIds = event.getTeamMemberIds()
                    eventIds.append(userId)
                    event.setTeamMemberIds(eventIds)
                }
            }
        }

        try context.save()
    }

    private func fetchTodayDemoTasks() throws -> [ProjectTask] {
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { task in
                task.id.hasPrefix("DEMO_") && task.status == .inProgress
            }
        )
        return try context.fetch(descriptor)
    }
}
```

---

## 6. CLEANUP IMPLEMENTATION

```swift
extension TutorialDemoDataManager {
    func cleanupAllDemoData() async throws {
        // Delete in reverse order of creation to respect relationships

        // 1. Delete calendar events
        let eventDescriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.id.hasPrefix("DEMO_") }
        )
        let events = try context.fetch(eventDescriptor)
        events.forEach { context.delete($0) }

        // 2. Delete tasks
        let taskDescriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.id.hasPrefix("DEMO_") }
        )
        let tasks = try context.fetch(taskDescriptor)
        tasks.forEach { context.delete($0) }

        // 3. Delete projects
        let projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id.hasPrefix("DEMO_") }
        )
        let projects = try context.fetch(projectDescriptor)
        projects.forEach { context.delete($0) }

        // 4. Delete clients
        let clientDescriptor = FetchDescriptor<Client>(
            predicate: #Predicate { $0.id.hasPrefix("DEMO_") }
        )
        let clients = try context.fetch(clientDescriptor)
        clients.forEach { context.delete($0) }

        // 5. Delete task types
        let taskTypeDescriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate { $0.id.hasPrefix("DEMO_") }
        )
        let taskTypes = try context.fetch(taskTypeDescriptor)
        taskTypes.forEach { context.delete($0) }

        // 6. Delete users (except current user if they were demo)
        let userDescriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.id.hasPrefix("DEMO_") }
        )
        let users = try context.fetch(userDescriptor)
        users.forEach { context.delete($0) }

        try context.save()
    }
}
```

---

## 7. COMPLETE PROJECT DATA

Full list of all 15 projects with tasks (implement in `DemoProjectData.all`):

```swift
extension DemoProjectData {
    static let all: [DemoProjectData] = [
        // COMPLETED (5)
        migDetailing,
        lockerRoomRenovation,
        officerHousingLandscape,
        charlieDrivewaySealing,
        oClubKitchenHood,

        // IN_PROGRESS (5)
        flightDeckCoating,
        oClubPatioResurface,
        hangarSidingRepair,
        charlieHomeOffice,
        parkingLotStriping,

        // ACCEPTED with future tasks (formerly "SCHEDULED" in spec - 5 projects)
        jetInteriorReupholstery,
        runwayCrackRepair,
        briefingRoomTechInstall,
        poolDeckSealing,
        oClubEntranceLandscaping
    ]
}
```

See `TopGun_Demo_Database.md` for complete task details for each project.

---

## 8. IMAGE ASSET STRATEGY

**RESOLVED:** Assets are available in `Assets.xcassets/Images/Demo/`

### Project Images (14 assets)
| Asset Name | Project |
|------------|---------|
| `briefing_room_current` | Briefing Room Tech Install |
| `flight_deck_before` | Flight Deck Coating |
| `flight_deck_progress` | Flight Deck Coating |
| `hangar_exterior` | Hangar Siding Repair |
| `hangar_siding_damage` | Hangar Siding Repair |
| `home_office_demo` | Charlie's Home Office |
| `home_office_paint_samples` | Charlie's Home Office |
| `jet_interior_current` | Jet Interior Reupholstery |
| `oclub_patio_area` | O'Club Patio Resurface |
| `oclub_patio_demo` | O'Club Patio Resurface |
| `parking_lot_washed` | Parking Lot Striping |
| `runway_cracks` | Runway Crack Repair |
| `runway_overview` | Runway Crack Repair |

### Team Member Avatars (5 assets)
| Asset Name | Team Member |
|------------|-------------|
| `pete` | Pete Mitchell |
| `nick` | Nick Bradshaw |
| `tom` | Tom Kazansky |
| `mike` | Mike Metcalf |
| `rick` | Rick Heatherly |

### Usage in Code
```swift
// For project images - store asset name in projectImagesString
project.projectImagesString = "flight_deck_before,flight_deck_progress"

// For team member avatars - store asset name in avatarURL
user.avatarURL = "pete"  // Will be loaded via Image("pete")
```

### Note on Photo Adding
The employee tutorial flow allows **real photo capture** - not mocked.
User can use camera/photo library as in production.
