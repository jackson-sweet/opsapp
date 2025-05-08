# Guidelines for Claude Code Assistant

## General Guidelines
- Be concise and direct in explanations
- Prioritize changes that align with existing code style and patterns
- Test changes thoroughly before confirming success
- Aim for simplicity and maintainability in all solutions

## Code Quality Principles

### Clean Coding
- Write self-explanatory code with meaningful naming
- Keep functions concise and focused on a single responsibility
- Prefer clarity over cleverness
- Limit nesting to 2-3 levels maximum
- Use Swift's type system for safety and clarity
- Prefer Swift idioms and language features when appropriate

### Modularity
- Organize code into logical, reusable components
- Use MVVM architecture consistently throughout the app
- Keep view code separate from business logic
- Create clear boundaries between app layers
- Make dependencies explicit rather than implicit
- Design components for independent testing

### Preventing Redundancy
- Eliminate duplicate code through abstraction
- Create reusable component libraries for UI elements
- Consolidate common functionality into shared services
- Don't create parallel implementations of the same feature
- Prefer composition over inheritance
- Follow the DRY principle (Don't Repeat Yourself)
- Validate that new code doesn't duplicate existing functionality

### Debugging Optimization
- Use descriptive print statements with consistent formatting
- Include context information in log messages (component name, function, etc.)
- Add appropriate error handling with specific error types
- Ensure errors bubble up to appropriate UI handlers
- Include debug-only features that can be toggled off in production

## Git Commits
- Do NOT add author information in commit messages
- Do NOT add Claude attribution in commit messages
- Keep commit messages clear and descriptive
- Use imperative style for commit messages (e.g. "Fix...", "Add...", not "Fixed..." or "Added...")
- Link to relevant issues or requirements when applicable
- Group related changes into coherent commits

## Code Style
- Match existing project style conventions
- Avoid introducing new patterns unless requested
- Comment code only when explicitly requested
- Use meaningful variable and function names
- Follow Swift naming conventions:
  - Use camelCase for variables and functions
  - Use PascalCase for types
  - Use descriptive enum cases
- Structure files consistently:
  - Extensions at the bottom
  - MARK comments to separate logical sections
  - Properties before methods

## SwiftUI Patterns
- Use environment objects for dependency injection
- Prefer @Binding over @State when appropriate
- Keep view components small and focused
- Extract complex subviews into separate components
- Use preview providers for all UI components
- Leverage composition to build complex views

## Testing
- Always run a build check after making changes
- Test functionality when possible
- Report any warnings or errors that appear during build
- Consider different device sizes and orientations
- Test features in both light and dark mode
- Ensure accessibility support for UI components

## Error Handling
- Add appropriate error handling to new code
- Enhance existing error handling as needed
- Provide user-friendly error messages
- Use Swift's error handling mechanisms consistently
- Prefer structured errors over string messages
- Always log errors for debugging purposes

## User Data Management
- Be careful with user data persistence
- Ensure proper data clearing between sessions
- Handle authentication state carefully
- Use SwiftData for complex persistence
- Use UserDefaults only for simple preferences and flags
- Clear sensitive data when logging out
- Validate data integrity when loading from persistence

## UI/UX
- Follow existing UI patterns
- Ensure UI elements are properly aligned
- Make sure text is readable and appropriately sized
- Support dark mode throughout the app
- Use the established color system from OPSStyle
- Design for glove-friendly touch targets for all interactive elements
- Consider outdoor visibility and variable lighting conditions
- Create consistent visual hierarchies across screens

## API Integration and Data Structure

### Bubble.io API Integration

#### API Configuration
- **Base URL**: The app uses `https://opsapp.co/version-test` as the Bubble.io API base URL
- **API Token**: A public API token is used as a fallback when no user authentication is available
- **API Paths**:
  - Data API: `/api/1.1/obj` - For direct data manipulation
  - Workflow API: `/api/1.1/wf` - For triggering Bubble workflows

#### Authentication Flow
- Authentication is managed through `AuthManager` which handles:
  - User login with email/password
  - Secure token storage in Keychain
  - Token expiration and refresh
  - Authorization for API requests
- Authentication errors are user-friendly and tailored for field workers

#### API Request/Response Structure
- All API calls use `APIService` which provides:
  - Centralized request handling with proper error management
  - Automatic retry for network issues
  - Response parsing and decoding
  - Rate limiting protection
- Responses follow specific Bubble.io formats:
  - List responses: `BubbleListResponse<T>` with results wrapper
  - Single object responses: `BubbleObjectResponse<T>`

#### API Error Handling
- Custom `APIError` and `AuthError` types with field-worker-friendly error messages
- Structured error handling with specific scenarios:
  - Authentication failures
  - Network issues
  - Server errors
  - Decoding problems
  - Rate limiting
- Robust retry logic for transient errors

### Data Model Structure

#### Core Domain Models
1. **Project**
   - Central entity for field crew operations
   - Maps to Bubble "Project" collection
   - Contains job status, location, scheduling, and team assignment information
   - Supports image attachments and notes

2. **User**
   - Represents field workers and office staff
   - Maps to Bubble "User" collection
   - Contains role information, authentication details, and profile data
   - Maintains relationship with assigned projects

3. **Company**
   - Organization entity
   - Maps to Bubble "Company" collection
   - Contains company information, branding, and operational details

#### Domain Enums
- **Status**: Job status values matching Bubble's "Job Status" custom type
  - RFQ, Estimated, Accepted, In Progress, Completed, Closed
- **UserRole**: Field/Office role distinction
  - Field Crew, Office Crew
- **UserType**: User category
  - Company, Employee, Client, Admin, Contractor, Other

#### Data Transfer Objects (DTOs)
- DTOs exactly match Bubble.io data structure
- Conversion methods (`toModel()`) transform API responses into SwiftData models
- Custom `CodingKeys` map Swift properties to Bubble field names

#### Data Relationships
- Projects have team members (users)
- Users have assigned projects
- Companies have projects and team members
- Relationships are maintained bidirectionally

### Synchronization Strategy

#### Sync Management
- `SyncManager` handles bidirectional synchronization between local and remote data
- Data is fetched in batches to prevent memory issues
- Changes are tracked with `lastSyncedAt` and `needsSync` flags
- Sync operations are prioritized by importance (status changes > data updates)

#### Offline Support
- Local edits are tracked and synced when connectivity is restored
- `ConnectivityMonitor` tracks network availability
- Background sync tasks maintain data freshness
- Changes made offline are preserved until successfully synced

#### Image Handling
- Images are managed through `ImageSyncManager`
- Project and profile images have special handling
- Images can be stored locally while offline
- Automatic synchronization of images when connectivity is restored

### API Endpoints

#### Project Endpoints
- Fetch all projects
- Fetch projects by status, date, or user assignment
- Update project status
- Update project notes and details

#### User Endpoints
- Fetch user profile
- Update user information
- User authentication
- Fetch users by role or company

#### Company Endpoints
- Fetch company details
- Fetch company projects and team members
- Update company information

### Best Practices for API Development

1. **Field-Centric Design**
   - API calls are optimized for field conditions with poor connectivity
   - Error messages are written for field workers
   - Timeouts and retries are calibrated for mobile networks

2. **Data Efficiency**
   - Fetches only necessary data to minimize bandwidth usage
   - Local caching to reduce API calls
   - Batched updates to reduce round trips

3. **Resilience**
   - Graceful handling of network interruptions
   - Data integrity preservation during sync
   - Appropriate fallbacks when API is unavailable

4. **Security**
   - Token-based authentication
   - Secure storage of credentials
   - Proper validation of input/output

5. **Development Patterns**
   - Use Swift Concurrency (async/await) for all API calls
   - Follow consistent error handling patterns
   - Document all API integrations
   - Keep Bubble field mapping centralized in BubbleFields