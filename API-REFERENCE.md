# OPS iOS — API Reference

> Base URL: `https://opsapp.co/version-test/api/1.1/`
> Auth: API token `f81e9da85b7a12e996ac53e970a52299` (URL param or Bearer header)
> Data API: `/obj/{type}` for CRUD, `/wf/{name}` for workflows
> Local persistence: SwiftData (offline-first)

---

## 1. Projects

**Endpoints:** `Network/Endpoints/ProjectEndpoints.swift`

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `fetchProjects()` | GET | `/obj/project` | Sync cycle (sorted by startDate desc) |
| `fetchProject(id:)` | GET | `/obj/project/{id}` | Project detail view appear |
| `fetchUserProjects(userId:)` | GET | `/obj/project` | Field crew filtered view (teamMembers contains userId) |
| `fetchProjectsByStatus(status:)` | GET | `/obj/project` | Pipeline/status filtering |
| `fetchUserProjectsByStatus(userId:status:)` | GET | `/obj/project` | Field crew + status combo |
| `fetchProjectsForDate(date:)` | GET | `/obj/project` | Calendar date selection |
| `fetchCompanyProjects(companyId:)` | GET | `/obj/project` | Sync: company constraint + 6-month lookback |
| `createProject(_:)` | POST | `/obj/project` | New project form submit |
| `updateProject(id:updates:)` | PATCH | `/obj/project/{id}` | Edit project form submit |
| `updateProjectStatus(id:status:)` | PATCH | `/obj/project/{id}` | Swipe-to-change-status, dropdown, pipeline drag |
| `updateProjectNotes(id:notes:)` | PATCH | `/obj/project/{id}` | Notes field save |
| `updateProjectDates(id:...)` | PATCH | `/obj/project/{id}` | Date picker save (also updates linked calendar events) |
| `updateProjectTeamMembers(id:...)` | PATCH | `/obj/project/{id}` | Team member picker save (also syncs calendar event members) |
| `deleteProject(id:)` | DELETE | `/obj/project/{id}` | Delete button (hard delete) |
| `completeProject(projectId:status:)` | POST | `/wf/update_job_status` | Status change workflow (completion flow) |
| `startProject(id:)` | POST | `/wf/update_job_status` | "Start Project" button (sets In Progress) |
| `linkProjectToClient(projectId:clientId:)` | PATCH | `/obj/client/{id}` | Project creation (adds to client.projectsList) |
| `linkProjectToCompany(projectId:companyId:)` | POST | `/wf/add-project-to-company` | Project creation workflow |
| `linkCalendarEventToProject(eventId:projectId:)` | PATCH | `/obj/project/{id}` | Task scheduling (links event to project) |

---

## 2. Tasks

**Endpoints:** `Network/Endpoints/TaskEndpoints.swift`

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `fetchProjectTasks(projectId:)` | GET | `/obj/task` | Project detail view appear |
| `fetchCompanyTasks(companyId:)` | GET | `/obj/task` | Sync cycle (paginated 100/page, date-filtered) |
| `fetchUserTasks(userId:)` | GET | `/obj/task` | Field crew task list |
| `fetchTask(id:)` | GET | `/obj/task/{id}` | Task detail view appear |
| `createTask(_:)` | POST | `/obj/task` | New task form submit (auto-links to project) |
| `updateTask(id:updates:)` | PATCH | `/obj/task/{id}` | Edit task form submit |
| `updateTaskStatus(id:status:)` | PATCH | `/obj/task/{id}` | Swipe-to-change-status, dropdown |
| `updateTaskNotes(id:notes:)` | PATCH | `/obj/task/{id}` | Notes field save |
| `updateTaskTeamMembers(id:...)` | PATCH | `/obj/task/{id}` | Team member picker save (also syncs calendar event members) |
| `updateTaskType(id:taskTypeId:...)` | PATCH | `/obj/task/{id}` | Task type dropdown change (also updates color) |
| `deleteTask(id:)` | DELETE | `/obj/task/{id}` | Delete button (hard delete) |
| `fetchTaskStatusOptions(companyId:)` | GET | `/obj/task_status` | Custom status options (if company has custom statuses) |

**Note:** Task status "Scheduled" was migrated to "Booked" (Nov 2025). Valid statuses: Booked, In Progress, Completed, Cancelled.

---

## 3. Calendar Events

**Endpoints:** `Network/Endpoints/CalendarEventEndpoints.swift`

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `fetchCompanyCalendarEvents(companyId:)` | GET | `/obj/calendarevent` | Sync cycle (paginated) |
| `fetchProjectCalendarEvents(projectId:)` | GET | `/obj/calendarevent` | Project detail (linked events) |
| `fetchCalendarEvents(from:to:)` | GET | `/obj/calendarevent` | Calendar view date range |
| `fetchCalendarEvent(id:)` | GET | `/obj/calendarevent/{id}` | Event detail view |
| `createCalendarEvent(_:)` | POST | `/obj/calendarevent` | Low-level creation |
| `createAndLinkCalendarEvent(_:)` | POST | `/obj/calendarevent` | Task scheduling (creates event + links to task + company) |
| `updateCalendarEvent(id:updates:)` | PATCH | `/obj/calendarevent/{id}` | Event edit (date/time change, drag-to-reschedule) |
| `updateCalendarEventTeamMembers(id:...)` | PATCH | `/obj/calendarevent/{id}` | Team assignment change |
| `deleteCalendarEvent(id:)` | DELETE | `/obj/calendarevent/{id}` | Delete button (hard delete) |
| `linkCalendarEventToCompany(eventId:companyId:)` | POST | `/wf/add-calendar-event-to-company` | Event creation workflow |
| `linkCalendarEventToTask(eventId:taskId:)` | PATCH | `/obj/task/{id}` | Sets task.calendarEventId |

**Architecture:** All scheduling is task-based. Calendar events are always linked to tasks. Project dates are computed from their tasks' calendar events (`computedStartDate`, `computedEndDate`).

---

## 4. Clients

**Endpoints:** `Network/Endpoints/ClientEndpoints.swift`

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `fetchCompanyClients(companyId:)` | GET | `/obj/client` | Sync cycle (parentCompany = companyId) |
| `fetchClient(id:)` | GET | `/obj/client/{id}` | Client detail view appear |
| `fetchClientsByIds(clientIds:)` | GET | `/obj/client` | Batch fetch (OR constraint) |
| `fetchSubClientsForClient(clientId:)` | GET | `/obj/sub client` | Client detail (contacts list) |
| `createClient(_:)` | POST | `/obj/client` | New client form submit |
| `updateClient(id:...)` | PATCH | `/obj/client/{id}` | Edit client form submit |
| `deleteClient(id:)` | DELETE | `/obj/client/{id}` | Delete button (hard delete) |
| `linkClientToCompany(clientId:companyId:)` | POST | `/wf/add-client-to-company` | Client creation workflow |

**Sub-client methods (via APIService):**

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `createSubClient(...)` | POST | `/wf/create_sub_client` | Add contact form |
| `editSubClient(...)` | POST | `/wf/edit_sub_client` | Edit contact form |
| `deleteSubClient(...)` | POST | `/wf/delete_sub_client` | Delete contact button |
| `updateClientContact(...)` | POST | `/wf/update_client_contact` | Contact update workflow |

---

## 5. Users / Team

**Endpoints:** `Network/Endpoints/UserEndpoints.swift`

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `fetchCompanyUsers(companyId:)` | GET | `/obj/user` | Sync cycle (company = companyId) |
| `fetchUser(id:)` | GET | `/obj/user/{id}` | User detail / profile view |
| `fetchUsers()` | GET | `/obj/user` | All users (limit 100) |
| `fetchUsersByRole(role:)` | GET | `/obj/user` | Role-filtered list |
| `fetchCompanyUsersByRole(companyId:role:)` | GET | `/obj/user` | Company + role filter |
| `fetchUsersByIds(userIds:)` | GET | `/obj/user` | Batch fetch (OR constraint) |
| `updateUser(id:fields:)` | PATCH | `/obj/user/{id}` | Profile edit, avatar upload, device token |
| `terminateEmployee(userId:)` | POST | `/wf/terminate_employee` | Remove team member |
| `deleteUser(id:)` | POST | `/wf/delete_user` | Delete account |

**Bubble field names (NOT camelCase):**
- `nameFirst`, `nameLast` (not firstName, lastName)
- `employeeType`, `userType`
- `avatar`, `profileImageURL`
- `deviceToken` (APNs push token)
- `hasCompletedAppTutorial`

**Role detection order:** `company.adminIds` FIRST → `employeeType` → default to Field Crew

---

## 6. Companies

**Endpoints:** `Network/Endpoints/CompanyEndpoints.swift`

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `fetchCompany(id:)` | GET | `/obj/company/{id}` | Sync cycle (first entity synced) |
| `fetchCompanies()` | GET | `/obj/company` | Admin view (all companies) |
| `fetchCompanyProjects(companyId:)` | GET | `/obj/project` | Sync: date-filtered project list |
| `updateCompany(id:data:)` | PATCH | `/obj/company/{id}` | Settings form submit |
| `updateCompanySeatedEmployees(id:...)` | PATCH | `/obj/company/{id}` | Add/remove team seats |
| `updateCompanyFields(id:fields:)` | PATCH | `/obj/company/{id}` | Generic field update |
| `linkTaskTypeToCompany(taskTypeId:companyId:)` | PATCH | `/obj/company/{id}` | Add to taskTypes array |

---

## 7. Task Types

**Endpoints:** `Network/Endpoints/TaskTypeEndpoints.swift`

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `fetchCompanyTaskTypes(companyId:)` | GET | `/obj/tasktype` | Sync cycle (from company.taskTypes refs) |
| `fetchTaskType(id:)` | GET | `/obj/tasktype/{id}` | Detail view |
| `fetchTaskTypesByIds(ids:)` | GET | `/obj/tasktype` | Batch fetch (IN constraint) |
| `createTaskType(_:)` | POST | `/obj/tasktype` | New task type form |
| `updateTaskType(id:...)` | PATCH | `/obj/tasktype/{id}` | Edit display name, color |
| `deleteTaskType(id:)` | DELETE | `/obj/tasktype/{id}` | Delete button (hard delete) |

**Default types:** Quote, Installation, Repair, Inspection, Consultation, Follow-up. Icons assigned locally via `TaskType.assignIconsToTaskTypes()`.

---

## 8. Authentication

**Files:** `Network/Auth/AuthManager.swift`, `KeychainManager.swift`, `GoogleSignInManager.swift`, `SimplePINManager.swift`

### Login Methods

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `signIn(username:password:)` | POST | `/wf/generate-api-token` | Login form submit |
| `signInWithGoogle(idToken:...)` | POST | `/wf/login_google` | Google Sign-In button |
| `signInWithApple(identityToken:...)` | POST | `/wf/login_apple` | Apple Sign-In button |
| `authenticate()` | POST | `/wf/login` | Internal token refresh |
| `requestPasswordReset(email:)` | POST | `/wf/reset_password` | Forgot password link |

### Token Management

```
1. Check cached token (valid if > 5 min before expiry)
2. If expired → re-authenticate with stored Keychain credentials
3. Fallback → use hardcoded API token (for public endpoints)
```

**Keychain storage** (service: `co.opsapp.OPS`):
- `username` — email for re-auth
- `password` — stored for auto token refresh
- `token` — current auth token
- `tokenExpiration` — Unix timestamp
- `userId` — current user ID

### PIN (Optional App Lock)

- 4-digit PIN stored in `AppStorage`
- Entry barrier only, not a login replacement
- Methods: `setPIN()`, `validatePIN()`, `removePIN()`
- One-time entry per app session

### Logout

```
1. Clear all Keychain entries (token, credentials, userId)
2. GoogleSignInManager.signOut()
3. SimplePINManager.resetAuthentication()
```

---

## 9. Onboarding

**File:** `Onboarding/Services/OnboardingService.swift`

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `signUpUser(email:password:userType:)` | POST | `/wf/signup` | Registration form submit |
| `joinCompany(code:userId:)` | POST | `/wf/join_company` | Company code entry |
| `updateCompany(companyId:name:...)` | POST | `/wf/update_company` | Company creation/update during setup |
| `sendInvites(emails:companyId:)` | POST | `/wf/send_invite` | Team invite step |

---

## 10. Subscription / Stripe

**Files:** `Utilities/BubbleSubscriptionService.swift`, `Utilities/StripeConfiguration.swift`, `Views/Subscription/PlanSelectionView.swift`

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `createSetupIntent(companyId:priceId:)` | POST | `/wf/create_setup_intent` | Plan selection → payment sheet |
| `completeSubscription(companyId:priceId:setupIntentId:promoCode:)` | POST | `/wf/complete_subscription` | After Stripe payment success |
| `createSubscriptionWithPayment(priceId:companyId:promoCode:)` | POST | `/wf/create_subscription_with_payment` | One-step subscription creation |
| `createSubscriptionWithPayment(...promoCode)` | POST | `/wf/create_subscription_with_payment_with_promo` | With promo code variant |
| `createSubscriptionSetupIntent(priceId:companyId:)` | POST | `/wf/create_subscription_setup` | Alternative setup intent flow |
| `cancelSubscription(userId:companyId:reason:...)` | POST | `/wf/cancel_subscription` | Cancel subscription button |
| `fetchSubscriptionInfo(stripeCustomerId:)` | POST | `/wf/get_subscription_info` | Settings subscription tab |
| `validatePromoCode(code:)` | POST | `/wf/validate_promo_code` | Promo code input field |
| `createCheckoutSession(...)` | POST | `/wf/create_checkout_session` | Web checkout fallback |
| `createStripeSubscription(...)` | POST | `/wf/create_stripe_subscription` | StripeConfiguration variant |

**Stripe config:**
- Publishable key: `pk_live_51QSBKBEooJoYGoIw...` (live mode)
- Merchant ID: `merchant.co.opsapp`
- Payment sheet styled with OPS theme (dark, Mohave font)

---

## 11. Image Upload

**Files:** `Network/ImageSyncManager.swift`, `Network/PresignedURLUploadService.swift`

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `getPresignedUrl(projectId:filename:contentType:)` | POST | `/wf/get_presigned_url` | Project image upload |
| `getPresignedUrlProfile(filename:contentType:)` | POST | `/wf/get_presigned_url_profile` | Profile/logo image upload |
| `registerProjectImages(projectId:imageUrls:)` | POST | `/wf/upload_project_images` | After S3 upload completes |
| PUT to S3 presigned URL | PUT | S3 (presigned) | Direct upload to AWS |

**Upload flow:**
1. Get presigned URL from Bubble workflow
2. Compress image client-side (0.5-0.8 JPEG quality, max 2048x2048)
3. PUT directly to S3 via presigned URL
4. Register URL array with Bubble via `/wf/upload_project_images`

**Offline support:**
- Images saved locally if offline
- `ImageSyncManager.syncPendingImages()` uploads queued images on reconnect
- Pending uploads tracked in UserDefaults

---

## 12. Miscellaneous

**Feature Requests / Bug Reports:**

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `requestFeature(...)` | POST | `/wf/request_feature` | Feature request form, report issue form, what's new feedback |

**App Messages:**

| Method | HTTP | Endpoint | Trigger |
|--------|------|----------|---------|
| `fetchActiveMessage()` | GET | `/obj/AppMessage` | App launch (10s timeout, non-blocking) |

---

## How Syncing Works

### Architecture: Offline-First with CentralizedSyncManager

**File:** `Network/Sync/CentralizedSyncManager.swift` (~2,200 lines)

All data is persisted locally in SwiftData. The app works fully offline. Sync pushes local changes up and pulls remote data down.

### Sync Triggers

| Trigger | Method | Scope | When |
|---------|--------|-------|------|
| **App launch** | `syncAppLaunch()` | Critical entities first | Once on startup |
| **App foreground** | `triggerBackgroundSync()` | Changed data only | Every time app returns to foreground |
| **Manual refresh** | `syncAll()` | All entities | User taps sync button |
| **Background refresh** | `syncBackgroundRefresh()` | Delta since last sync | Periodic (iOS background task) |
| **After mutation** | Individual update methods | Single entity | Immediately after user saves |

### Sync Order (Dependency-Based)

```
1. Company          — base entity, gets adminIds, subscription info, seats
2. Users            — requires companyId, role detection uses company.adminIds
3. Clients          — requires companyId
4. Task Types       — from company.taskTypes reference array
5. Projects         — requires company + users for team member linking
6. Tasks            — requires projects for relationship linking
7. Calendar Events  — requires projects + tasks for bidirectional linking
8. Link Relationships — connect all IDs to actual SwiftData objects
9. Schedule Notifications — set up local notifications for upcoming events
```

### What Gets Synced Per Entity

| Entity | Fetch Constraint | Pagination | Date Filter |
|--------|-----------------|------------|-------------|
| Company | Single by ID | No | No |
| Users | `company = {id}` | No (limit 100) | No |
| Clients | `parentCompany = {id}` | Auto-paginate | No |
| Task Types | From `company.taskTypes` refs | No | No |
| Projects | `company = {id}` | Auto-paginate (100/page) | 6-month lookback (configurable) |
| Tasks | `companyId = {id}` | Auto-paginate (100/page) | 6-month lookback |
| Calendar Events | `companyId = {id}` | Auto-paginate (100/page) | No |

### Historical Data

Configurable via UserDefaults key `historicalDataMonths`:
- Default: 6 months
- Set to -1 for all data
- Only applies to Projects and Tasks

### Conflict Resolution

**Last-write-wins with server authority:**
- Local mutations push to Bubble immediately (if online)
- Sync pulls from Bubble and overwrites local data
- No merge logic — remote always wins on full sync
- Soft deletes: `deletedAt` timestamp set, record retained for 30 days

### Debouncing & Throttling

| Layer | Mechanism | Value |
|-------|-----------|-------|
| API client | Minimum interval between requests | 500ms |
| Sync manager | Re-entrance guard | `syncInProgress` flag prevents concurrent syncs |
| Background sync | Async task scheduling | Natural ~2s debounce via `Task.detached(priority: .background)` |

### Soft Delete Strategy

```
Remote sync: Compare remote IDs with local IDs
  → IDs missing from remote → set local deletedAt = now
  → IDs with deletedAt in remote → set local deletedAt
  → Records deleted >30 days → eligible for hard removal
All queries filter: deletedAt == nil
```

### Mutation → Sync Flow

```
User action (e.g., change task status)
  ↓
Update local SwiftData immediately (optimistic)
  ↓
If online → PATCH to Bubble API
  If success → done
  If failure → mark needsSync = true for retry
  ↓
If offline → mark needsSync = true
  ↓
On next sync or reconnect → retry pending changes
```

---

## Network Layer

### API Client Configuration

**File:** `Network/API/APIService.swift` (~1,036 lines)

| Setting | Value |
|---------|-------|
| Timeout | 30 seconds (request + resource) |
| Rate limit | 500ms minimum between requests |
| Connections per host | 5 |
| HTTP version | HTTP/2 |
| Waits for connectivity | Yes (URLSession waits vs. failing) |
| User-Agent | `OPS-iOS/1.0` |
| JSON decoding | `convertFromSnakeCase` + `iso8601` dates |

### Retry Logic

| Status | Action | Backoff | Max Retries |
|--------|--------|---------|-------------|
| 401/403 | Throw `unauthorized` | None | 0 (immediate fail) |
| 429 | Retry after backoff | 1 second | 3 |
| 5xx | Retry after backoff | 2 seconds | 3 |
| Network error | Fail (handled by sync layer) | N/A | 0 |

### Error Types

**APIError:**
`invalidURL`, `invalidResponse`, `decodingFailed`, `unauthorized`, `rateLimited`, `serverError`, `networkError`, `httpError(statusCode:)`

**AuthError:**
`credentialsNotFound`, `invalidCredentials`, `invalidResponse`, `serverError(Int)`, `networkError(String)`, `decodingFailed`, `invalidURL`

**SyncError:**
`notConnected`, `alreadySyncing`, `missingUserId`, `missingCompanyId`, `dataCorruption`

---

## Connectivity Monitoring

**File:** `Network/ConnectivityMonitor.swift`

Uses `NWPathMonitor` for real-time network status:

| Property | Type | Purpose |
|----------|------|---------|
| `isConnected` | Bool | Network available |
| `connectionType` | `.none/.wifi/.cellular/.wiredEthernet` | Connection type |
| `onConnectionTypeChanged` | Callback | UI updates on change |

**On reconnect:** triggers `syncPendingImages()` + background sync for any `needsSync` data.

---

## Bubble Constraint Format

All GET queries to `/obj/{type}` use URL-encoded JSON constraints:

```json
[
  { "key": "company", "constraint_type": "equals", "value": "abc123" },
  { "key": "deletedAt", "constraint_type": "is_empty" }
]
```

**Constraint types used:** `equals`, `not equal`, `is_empty`, `is_not_empty`, `greater than`, `less than`, `contains`, `in` (for arrays)

**Pagination:** `cursor=0&limit=100`, auto-paginate when `remaining > 0`

**Sorting:** `sort_field={field}&descending=true`

---

## BubbleFields Constants

**File:** `Network/API/BubbleFields.swift`

These field names must be **byte-identical** across iOS, Android, and Web:

```
Types: "Client", "Company", "Project", "User", "Sub Client", "Task", "TaskType", "calendarevent"
JobStatus: "RFQ", "Estimated", "Accepted", "In Progress", "Completed", "Closed", "Archived"
TaskStatus: "Booked", "In Progress", "Completed", "Cancelled"
EmployeeType: "Office Crew", "Field Crew", "Admin"
User fields: nameFirst, nameLast, employeeType, userType, company, avatar, profileImageURL, deviceToken
Company fields: companyName, companyId, logo, logoURL, seatedEmployees, admin, accountHolder
```

---

## Complete Workflow Endpoint Reference

| Endpoint | HTTP | Service | Purpose |
|----------|------|---------|---------|
| `/wf/generate-api-token` | POST | AuthManager | Email/password login |
| `/wf/login` | POST | AuthManager | Legacy token refresh |
| `/wf/login_google` | POST | AuthManager | Google OAuth |
| `/wf/login_apple` | POST | AuthManager | Apple Sign-In |
| `/wf/reset_password` | POST | AuthManager | Password reset email |
| `/wf/signup` | POST | OnboardingService | New user registration |
| `/wf/join_company` | POST | OnboardingService | Join via company code |
| `/wf/update_company` | POST | OnboardingService | Company creation/update |
| `/wf/send_invite` | POST | OnboardingService | Email team invites |
| `/wf/update_job_status` | POST | ProjectEndpoints | Project status workflow |
| `/wf/add-project-to-company` | POST | ProjectEndpoints | Link project → company |
| `/wf/add-client-to-company` | POST | ClientEndpoints | Link client → company |
| `/wf/add-calendar-event-to-company` | POST | CalendarEventEndpoints | Link event → company |
| `/wf/create_sub_client` | POST | APIService | Create sub-client contact |
| `/wf/edit_sub_client` | POST | APIService | Edit sub-client contact |
| `/wf/delete_sub_client` | POST | APIService | Delete sub-client contact |
| `/wf/update_client_contact` | POST | APIService | Update client contact info |
| `/wf/delete_user` | POST | APIService | Delete user account |
| `/wf/terminate_employee` | POST | APIService | Remove employee from company |
| `/wf/get_presigned_url` | POST | PresignedURLUploadService | S3 URL for project images |
| `/wf/get_presigned_url_profile` | POST | PresignedURLUploadService | S3 URL for profile/logo images |
| `/wf/upload_project_images` | POST | ImageSyncManager | Register uploaded image URLs |
| `/wf/create_setup_intent` | POST | BubbleSubscriptionService | Stripe setup intent |
| `/wf/complete_subscription` | POST | BubbleSubscriptionService | Finalize subscription |
| `/wf/create_subscription_with_payment` | POST | BubbleSubscriptionService | One-step subscription |
| `/wf/create_subscription_with_payment_with_promo` | POST | BubbleSubscriptionService | Subscription + promo |
| `/wf/create_subscription_setup` | POST | BubbleSubscriptionService | Alternative setup flow |
| `/wf/cancel_subscription` | POST | BubbleSubscriptionService | Cancel subscription |
| `/wf/get_subscription_info` | POST | BubbleSubscriptionService | Fetch Stripe subscription data |
| `/wf/validate_promo_code` | POST | PlanSelectionView | Validate promo code |
| `/wf/create_checkout_session` | POST | PlanSelectionView | Web checkout session |
| `/wf/create_stripe_subscription` | POST | StripeConfiguration | Direct Stripe subscription |
| `/wf/request_feature` | POST | FeatureRequestView, ReportIssueView | Submit feedback |
