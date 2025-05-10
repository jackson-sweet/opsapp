# OPS App - API Integration Guide

## Bubble.io API Integration

### API Configuration
- **Base URL**: `https://opsapp.co/version-test`
- **API Types**:
  - Data API: `/api/1.1/obj` - For direct data manipulation
  - Workflow API: `/api/1.1/wf` - For triggering Bubble workflows

### Authentication
- All API calls use `APIService` for centralized request handling
- Authentication is managed through `AuthManager`
- Secure token storage in Keychain via `KeychainManager`
- API Calls do not require authentication

### Response Structure
Bubble.io uses specific response formats:
- **List Response**: 
  ```json
  {
    "response": {
      "cursor": 0,
      "results": [{ ... }],
      "remaining": 0,
      "count": 100
    }
  }
  ```
- **Single Object Response**:
  ```json
  {
    "response": { ... }
  }
  ```
- **Workflow Response**:
  ```json
  {
    "response": {
      "result": "success",
      ... // additional fields vary by endpoint
    }
  }
  ```

## Data Models

### Core Models with Field Mappings

#### Project
- `id`: Bubble unique identifier
- `title` → Bubble: `Project Name`
- `clientName` → Bubble: `Client Name`
- `address` → Bubble: `Address` (complex object)
- `startDate` → Bubble: `Start Date`
- `endDate` → Bubble: `Completion`
- `status` → Bubble: `Status`
- `notes` → Bubble: `Team Notes`
- `teamMemberIds` → Bubble: `Team Members` (array)
- `projectImages` → Bubble: `Project Images` (array)

#### User
- `id`: Bubble unique identifier 
- `firstName` → Bubble: `First Name`
- `lastName` → Bubble: `Last Name`
- `email` → Bubble: `Email`
- `phone` → Bubble: `Phone`
- `role` → Bubble: `Role`
- `employeeType` → Bubble: `Employee Type`
- `companyId` → Bubble: `Company`
- `profileImageURL` → Bubble: `Avatar`

#### Company
- `id`: Bubble unique identifier
- `name` → Bubble: `Name`
- `address` → Bubble: `Address` (complex object)
- `email` → Bubble: `Email`
- `phone` → Bubble: `Phone`
- `teamMemberIds` → Bubble: `Team Members` (array)
- `status` → Bubble: `Status`
- `companyCode` → Bubble: `Company Code`

### Enums and Constants

#### Status Values
```swift
enum Status: String {
    case rfq = "RFQ"
    case estimated = "Estimated"
    case accepted = "Accepted"
    case inProgress = "In Progress"
    case completed = "Completed"
    case closed = "Closed"
    case pending = "Pending"
}
```

#### Bubble Fields
Central mapping of field names in `BubbleFields.swift` for consistent reference.

## API Endpoints

### Project Endpoints

#### Fetch Projects
```swift
func fetchProjects() async throws -> [ProjectDTO]
```
Fetches all projects relevant to the current user.

#### Fetch Project by ID
```swift
func fetchProject(id: String) async throws -> ProjectDTO
```
Fetches a single project by its unique ID.

#### Update Project Status
```swift
func updateProjectStatus(id: String, status: String) async throws
```
Updates a project's status using the data API.

#### Complete Project (Workflow)
```swift
func completeProject(projectId: String, status: String) async throws -> String
```
Marks a project as completed using the workflow API.

#### Fetch User Projects
```swift
func fetchUserProjects(userId: String) async throws -> [ProjectDTO]
```
Fetches projects assigned to a specific user.

### User Endpoints

#### Fetch User
```swift
func fetchUser(id: String) async throws -> UserDTO
```
Fetches a single user by ID.

#### Fetch Company Users
```swift
func fetchCompanyUsers(companyId: String) async throws -> [UserDTO]
```
Fetches all users belonging to a specific company.

#### Fetch Users by IDs
```swift
func fetchUsersByIds(userIds: [String]) async throws -> [UserDTO]
```
Fetches multiple users by their IDs.

### Company Endpoints

#### Fetch Company
```swift
func fetchCompany(id: String) async throws -> CompanyDTO
```
Fetches a company by ID.

#### Fetch Company by Code
```swift
func fetchCompanyByCode(code: String) async throws -> CompanyDTO?
```
Fetches a company using its company code.

## Synchronization

### Sync Strategy
- Data is fetched in batches to prevent memory issues
- Changes are tracked with `lastSyncedAt` and `needsSync` flags
- Sync operations are prioritized by importance

### Offline Support
- Local edits are tracked and synced when connectivity is restored
- `ConnectivityMonitor` tracks network availability
- Background sync tasks maintain data freshness

### Image Handling
- Images are managed through `ImageSyncManager`
- Images can be stored locally while offline
- Automatic synchronization when connectivity is restored

## Best Practices

### Error Handling
```swift
do {
    let projects = try await apiService.fetchProjects()
    // Process projects
} catch let error as APIError {
    // Handle API-specific errors with user-friendly messages
    print("API Error: \(error.localizedDescription)")
} catch {
    // Handle other errors
    print("Error fetching projects: \(error.localizedDescription)")
}
```

### Constraints Format
Bubble API requires a specific format for filtering data:
```swift
// Single constraint
let statusConstraint: [String: Any] = [
    "key": "Status",
    "constraint_type": "equals",
    "value": "In Progress"
]

// Multiple constraints (AND)
let combined = ["and": [constraint1, constraint2]]

// Multiple constraints (OR)
let combined = ["or": [constraint1, constraint2]]
```

### Date Handling
Bubble uses ISO8601 format for dates:
```swift
// Extension for working with Bubble dates
extension DateFormatter {
    static func dateFromBubble(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
    
    static func dateToBubble(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}
```

## Authentication Flow

1. User provides credentials (email/password)
2. App makes login request to Bubble workflow API
3. On success, the API returns a token
4. Token is stored securely in Keychain
5. Token is included in subsequent API requests

## Adding New API Endpoints

1. Define DTOs that match Bubble structure
2. Add endpoint method to appropriate extension in APIService
3. Implement data conversion (DTO to SwiftData model)
4. Add sync support in SyncManager if needed
5. Add error handling specific to the endpoint
6. Test endpoint with both online and offline scenarios
