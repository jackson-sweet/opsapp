# OPS App - API Integration Guide

**Last Updated**: August 2025  
**Version**: 1.2.0

## Bubble.io API Integration

### API Configuration
- **Base URL**: `https://opsapp.co/version-test`
- **API Types**:
  - Data API: `/api/1.1/obj` - For direct data manipulation
  - Workflow API: `/api/1.1/wf` - For triggering Bubble workflows

### Authentication
- All API calls use `APIService` for centralized request handling
- Authentication is managed through `AuthManager` with multi-method support
- Secure token storage in Keychain via `KeychainManager`
- Token auto-renewal with 5-minute buffer before expiration
- Fallback to API token when user authentication fails

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
- `id`: Bubble unique identifier (_id)
- `title` → Bubble: `Project Name`
- `clientName` → Bubble: `Client Name`
- `clientEmail` → Bubble: `Client Email`
- `clientPhone` → Bubble: `Client Phone`
- `address` → Bubble: `Address` (BubbleAddress object)
- `startDate` → Bubble: `Start Date`
- `endDate` → Bubble: `Completion`
- `status` → Bubble: `Status`
- `notes` → Bubble: `Team Notes`
- `teamMemberIds` → Bubble: `Team Members` (array of BubbleReference)
- `projectImages` → Bubble: `Project Images` (array of strings)
- `companyId` → Bubble: `Company` (BubbleReference)

#### User
- `id`: Bubble unique identifier 
- `firstName` → Bubble: `First Name`
- `lastName` → Bubble: `Last Name`
- `email` → Bubble: `Email`
- `phone` → Bubble: `Phone`
- `role` → Bubble: `Role` (Field Crew, Office Crew, Admin)
- `employeeType` → Bubble: `Employee Type`
- `companyId` → Bubble: `Company`
- `profileImageURL` → Bubble: `Avatar`
- `homeAddress` → Bubble: `Home Address` (geographic address)

#### Company
- `id`: Bubble unique identifier
- `name` → Bubble: `Company Name`
- `address` → Bubble: `Location` (geographic address)
- `email` → Bubble: `Office Email`
- `phone` → Bubble: `phone`
- `teamMemberIds` → Bubble: `Teams` (array)
- `employees` → Bubble: `Employees` (array of User references)
- `admin` → Bubble: `Admin` (array of User references)
- `companyCode` → Bubble: `company id`
- `description` → Bubble: `Company Description`
- `openHour` → Bubble: `Open Hour`
- `closeHour` → Bubble: `Close Hour`
- `logo` → Bubble: `Logo` (image object)

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

## API Service Features

### Rate Limiting
- Minimum 0.5 seconds between API requests
- Automatic queuing of rapid requests
- Prevents API overload and improves reliability

### Network Resilience
- 30-second timeout for field conditions
- Automatic retry with exponential backoff
- Waits for connectivity before attempting requests
- Comprehensive error handling and logging

## API Endpoints

### Authentication Endpoints

#### Sign Up (Company Owner)
```swift
POST /api/1.1/wf/sign_company_up
Body: {
    "email": String,
    "password": String,
    "userType": "company"
}
```

#### Sign Up (Employee)
```swift
POST /api/1.1/wf/sign_employee_up
Body: {
    "email": String,
    "password": String,
    "userType": "employee"
}
```

#### Join Company
```swift
POST /api/1.1/wf/join_company
Body: {
    "email": String,
    "password": String,
    "firstName": String,
    "lastName": String,
    "phoneNumber": String,
    "companyCode": String
}
```

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

### Task Endpoints

#### Fetch Tasks
```swift
func fetchProjectTasks(projectId: String) async throws -> [TaskDTO]
func fetchCompanyTasks(companyId: String) async throws -> [TaskDTO]
func fetchUserTasks(userId: String) async throws -> [TaskDTO]
```
Fetch tasks by project, company, or user assignment.

#### Update Task Status
```swift
func updateTaskStatus(id: String, status: String) async throws
```
Updates a task's status. Changes sync immediately to Bubble.

#### Update Task Notes
```swift
func updateTaskNotes(id: String, notes: String) async throws
```
Updates a task's notes. Changes sync immediately to Bubble.

### Task Type Endpoints

#### Fetch Task Types
```swift
func fetchCompanyTaskTypes(companyId: String) async throws -> [TaskTypeDTO]
func fetchTaskTypesByIds(ids: [String]) async throws -> [TaskTypeDTO]
```
Fetch task types for a company or by specific IDs.

## Admin Role Management

### Automatic Admin Detection
When syncing company data, the app automatically checks if the current user is listed in the company's admin array:
- The Company DTO includes an `admin` field containing an array of User references
- During company sync, if the current user's ID matches any ID in the admin list, their role is automatically updated to `Admin`
- This ensures users with administrative privileges are properly identified without manual role assignment

### Role Types
- **Field Crew**: Standard field worker role
- **Office Crew**: Office-based worker role  
- **Admin**: Administrative user with elevated privileges (auto-detected from company admin list)

## Synchronization

### Sync Strategy
- Data is fetched in batches to prevent memory issues
- Changes are tracked with `lastSyncedAt` and `needsSync` flags
- Sync operations are prioritized by importance

### Updated Sync Flow (Latest)
1. **Project Sync**: Fetch projects based on user role
2. **Calendar Event Sync**: Fetch all calendar events for company (ensures calendar is populated)
3. **Task Sync**: Fetch all tasks for company
4. **Task Type Sync**: Fetch only specific task types that are referenced by tasks

### Key Changes
- **Calendar Events**: Now synced with projects to ensure calendar is always populated
- **Task Types**: Fetched by specific IDs rather than fetching all
- **No Feature Flags**: All companies have task features enabled
- **Never Create Events Locally**: Calendar events are only synced from Bubble
- **CalendarEvent-Centric Architecture**: CalendarEvents are the single source of truth for dates
- **Real-time Task Updates**: Task status and notes changes sync immediately to API

### Calendar Implementation Details

#### Continuous Scrolling Calendar
The calendar uses an Apple Calendar-like continuous scrolling implementation:
- **MonthGridView**: Implements vertical scrolling through multiple months (±12 months from today)
- **Lazy Loading**: Calendar events are loaded only for visible months to optimize performance
- **Month Snapping**: Calendar automatically snaps to the nearest month when scrolling ends
- **Preference Keys**: Uses `ScrollOffsetPreferenceKey` and `MonthPositionPreferenceKey` to track scroll state

#### Visible Month Tracking
- **visibleMonth**: Property in CalendarViewModel tracks currently visible month
- **Dynamic Updates**: Month picker displays visible month and updates as user scrolls
- **Synchronization**: Selected date and visible month are synchronized in month view mode
- **Today Card**: Always displays today's date regardless of selected/visible month

#### Performance Optimizations
- **Event Caching**: `eventCache` dictionary stores event counts by date key
- **Batch Loading**: Events loaded in batches for visible and adjacent months
- **Debug Logging**: Verbose logging removed from `DataController.getCalendarEventsForCurrentUser()`
- **Scroll State Management**: `isScrolling` flag prevents circular updates between UI and data

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

## Image Upload API Integration

### Overview
The OPS app uses a multi-tier approach for image handling, integrating AWS S3 for storage and Bubble.io for metadata management.

### Image Upload Workflow Endpoints

#### 1. Direct S3 Upload (Default)
The app uploads directly to S3 using AWS v4 signature authentication:
```
PUT https://ops-app-files-prod.s3.us-west-2.amazonaws.com/company-{companyId}/{projectId}/photos/{filename}
```

**Headers Required:**
- `Authorization`: AWS4-HMAC-SHA256 signature
- `X-Amz-Date`: Timestamp in UTC
- `X-Amz-Content-SHA256`: SHA256 hash of image data
- `Content-Type`: image/jpeg
- `Content-Length`: Size in bytes

#### 2. Bubble Image Registration
After S3 upload, register images with project:
```http
POST https://opsapp.co/version-test/api/1.1/wf/upload_project_images

Body:
{
    "project_id": "{project-id}",
    "images": [
        "https://ops-app-files-prod.s3.us-west-2.amazonaws.com/...",
        "https://ops-app-files-prod.s3.us-west-2.amazonaws.com/..."
    ]
}
```

**Note**: The `images` field is an array of URL strings, not objects.

#### 3. Presigned URL Upload (Optional)
If enabled, the app can use presigned URLs via Lambda:
```http
POST https://opsapp.co/version-test/api/1.1/wf/get_presigned_url

Body:
{
    "filename": "123MainSt_IMG_1234567890_0.jpg",
    "contentType": "image/jpeg",
    "projectId": "{project-id}",
    "companyId": "{company-id}"
}

Expected Response:
{
    "uploadUrl": "https://s3.amazonaws.com/...",
    "fileUrl": "https://s3.amazonaws.com/...",
    "fields": {} // Optional, for POST-based uploads
}
```

### Image Storage Structure

#### S3 Path Convention
```
company-{companyId}/{projectId}/photos/{filename}
```

#### Filename Convention
```
{StreetAddress}_IMG_{timestamp}_{index}.jpg
```
- Street address extracted from project location
- Timestamp in Unix epoch format
- Index for multiple images in same upload batch

### Offline Image Handling

When offline, images are stored locally with URLs:
```
local://project_images/{filename}
```

These are queued in `pendingImageUploads` and synced when connectivity returns.

### Image Sync Behavior

#### Deletion Sync
When images are deleted on the web app:
1. Next sync compares local vs remote image sets
2. Deleted images are identified by set difference
3. Local file cache and memory cache are cleaned
4. Project's image list is updated to match server

#### Duplicate Prevention
When uploading new images:
1. Extract existing filenames from project
2. Check for name conflicts before upload
3. Generate unique names with suffixes (_1, _2, etc.)
4. Track names during batch uploads
5. Maximum 100 attempts for unique naming

#### Cache Management
- **Cache Keys**: SHA256 hash of URL (32 chars) + optional suffix
- **One-time Clear**: App clears old truncated cache on first launch
- **Format**: `remote_{32-char-hash}{suffix}`

## Adding New API Endpoints

1. Define DTOs that match Bubble structure
2. Add endpoint method to appropriate extension in APIService
3. Implement data conversion (DTO to SwiftData model)
4. Add sync support in SyncManager if needed
5. Add error handling specific to the endpoint
6. Test endpoint with both online and offline scenarios
