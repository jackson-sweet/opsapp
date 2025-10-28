# Bubble Field Mappings - Complete Reference

This document contains the exact field names and types for all Bubble.io data objects used in the OPS app.

**IMPORTANT UPDATES**: All Bubble fields have been updated to use camelCase naming conventions.
- Built-in Bubble fields CANNOT be changed: `_id`, `Creator`, `Modified Date`, `Created Date`, `Slug`
- Option Set `Display` attribute is built-in and CANNOT be changed (must remain capitalized)
- All other fields now use camelCase

## Company

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| accountHolder | User | accountHolder | Changed from "AccountHolder" |
| activeProjects | List of Projects | activeProjects | Changed from "Active Projects" |
| admin | List of Users | admin | Already lowercase |
| billingPeriodEnd | date | billingPeriodEnd | Already camelCase |
| calendarEventsList | List of CalendarEvents | calendarEventsList | Changed from "Calendar.EventsList" |
| clients | List of Clients | clients | Changed from "Client" |
| closeHour | text | closeHour | Changed from "Close Hour" |
| companyDescription | text | companyDescription | Changed from "Company Description" |
| companyId | text | companyId | Changed from "company id" - unique code for employees to join |
| companyName | text | companyName | Changed from "Company Name" |
| companyAge | text | companyAge | Changed from "company_age" |
| companySize | text | companySize | Changed from "company_size" |
| completedProjects | List of Projects | completedProjects | Changed from "Completed Projects" |
| dataSetupCompleted | yes/no | dataSetupCompleted | Already camelCase |
| dataSetupPurchased | yes/no | dataSetupPurchased | Already camelCase |
| dataSetupScheduledDate | date | dataSetupScheduledDate | Already camelCase |
| defaultProjectColor | text | defaultProjectColor | Already camelCase - Hex color |
| employees | List of Users | employees | Already lowercase |
| estimates | List of Estimates | estimates | Changed from "Estimates" |
| hasPrioritySupport | yes/no | hasPrioritySupport | Already camelCase |
| hasWebsite | yes/no | hasWebsite | Already camelCase |
| industry | List of Industries | industry | Already lowercase |
| invoices | List of Invoices | invoices | Changed from "Invoice" |
| lateProjects | List of Projects | lateProjects | Changed from "Late Projects" |
| location | geographic address | location | Already lowercase |
| logo | image | logo | Already lowercase |
| maxSeats | number | maxSeats | Already camelCase - Default: 0 |
| officeEmail | text | officeEmail | Changed from "Office Email" |
| openHour | text | openHour | Changed from "Open Hour" - Default: 08:00:00 |
| phone | text | phone | Keep as-is |
| prioritySupportPurchDate | date | prioritySupportPurchaseDate | Already camelCase |
| projects | List of Projects | projects | Already lowercase |
| qbConnected | yes/no | qbConnected | Changed from "QB Connected" - Default: no |
| qbAccessToken | text | qbAccessToken | Changed from "qb.accesstoken" |
| qbAuthBasic | text | qbAuthBasic | Changed from "qb.authbasic" |
| qbCode | text | qbCode | Changed from "qb.code" |
| qbCompanyId | text | qbCompanyId | Changed from "qb.companyid" |
| qbIdToken | text | qbIdToken | Changed from "qb.idtoken" |
| qbRefreshToken | text | qbRefreshToken | Changed from "qb.refreshtoken" |
| reactivatedSubscription | yes/no | reactivatedSubscription | Already camelCase - Default: no |
| receivables | number | receivables | Already lowercase |
| referralMethod | Referral Method | referralMethod | Changed from "Referral Method" |
| referralMethodOther | text | referralMethodOther | Changed from "Referral Method Other" |
| registered | number | registered | Already lowercase - Default: 0 |
| seatedEmployees | List of Users | seatedEmployees | Keep as-is |
| seatGraceEndDate | date | seatGraceEndDate | Already camelCase |
| seatGraceStartDate | date | seatGraceStartDate | Already camelCase |
| securityClearances | List of Security Clearances | securityClearances | Changed from "Security Clearances" |
| stripeCustomerId | text | stripeCustomerId | Already camelCase |
| subscriptionEnd | date | subscriptionEnd | Already camelCase |
| subscriptionEndls | List of subscriptionEndls | subscriptionEndls | Already camelCase |
| subscriptionPeriod | PaymentSchedule | subscriptionPeriod | Already camelCase - Options: Monthly, Annual |
| subscriptionPlan | SubscriptionPlan | subscriptionPlan | Already camelCase - Options: trial, starter, team, business |
| subscriptionStatus | SubscriptionStatus | subscriptionStatus | Already camelCase - Options: trial, active, grace, expired, cancelled |
| taskTypes | List of TaskTypes | taskTypes | Changed from "Task Types" |
| teams | List of Teams | teams | Already lowercase |
| trialEndDate | date | trialEndDate | Already camelCase |
| trialStartDate | date | trialStartDate | Already camelCase |
| visit | number | visit | Already lowercase - Default: 1 |
| website | text | website | Keep as-is |
| Creator | User | creator | Built-in field - CANNOT CHANGE |
| Modified Date | date | modifiedDate | Built-in field - CANNOT CHANGE |
| Created Date | date | createdDate | Built-in field - CANNOT CHANGE |
| Slug | text | slug | Built-in field - CANNOT CHANGE |

## Project

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| address | geographic address | address | Already lowercase |
| allDay | yes/no | allDay | Changed from "All Day" |
| balance | number | balance | Already lowercase |
| client | Client | client | Already lowercase - Reference to Client object |
| clientEmail | text | clientEmail | Changed from "Client Email" - Deprecated - use Client reference |
| clientName | text | clientName | Changed from "Client Name" - Deprecated - use Client reference |
| clientPhone | text | clientPhone | Changed from "Client Phone" - Deprecated - use Client reference |
| company | Company | company | Already lowercase - Reference |
| completion | date | completion | Already lowercase - End date |
| description | text | description | Already lowercase |
| duration | number | duration | Already lowercase - Days |
| eventType | CalendarEventType | eventType | Already camelCase - Options: task, project |
| projectGrossCost | number | projectGrossCost | Changed from "Project Gross Cost" |
| projectImages | List of images | projectImages | Changed from "Project Images" |
| projectName | text | projectName | Changed from "Project Name" |
| projectValue | number | projectValue | Changed from "Project Value" |
| slug | text | slug | Already lowercase |
| startDate | date | startDate | Changed from "Start Date" |
| status | JobStatus | status | Already lowercase - Option set |
| teamMembers | List of Users | teamMembers | Changed from "Team Members" |
| teamNotes | text | teamNotes | Changed from "Team Notes" |
| thumbnail | image | thumbnail | Already lowercase |
| tasks | List of Tasks | tasks | Already lowercase |
| Creator | User | creator | Built-in field - CANNOT CHANGE |
| Modified Date | date | modifiedDate | Built-in field - CANNOT CHANGE |
| Created Date | date | createdDate | Built-in field - CANNOT CHANGE |

## User

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| address | text | address | Already lowercase |
| avatar | image | avatar | Already lowercase - Profile image |
| city | text | city | Already lowercase |
| company | Company | company | Already lowercase - Reference |
| companyDescription | text | companyDescription | Changed from "Company Description" |
| companyName | text | companyName | Changed from "Company Name" |
| companyID | text | companyID | Already camelCase |
| country | text | country | Already lowercase |
| dateAdded | date | dateAdded | Already camelCase |
| email | text | email | Already lowercase - User's email (built-in) |
| employeeType | EmployeeType | employeeType | Changed from "Employee Type" - determines role |
| nameFirst | text | nameFirst | Changed from "First Name" |
| fullName | text | fullName | Changed from "Full Name" |
| hasProfileImageUploaded | yes/no | hasProfileImageUploaded | Already camelCase |
| homeAddress | geographic address | homeAddress | Changed from "Home Address" |
| isPlanHolder | yes/no | isPlanHolder | Already camelCase |
| isProfileCompleted | yes/no | isProfileCompleted | Already camelCase |
| nameLast | text | nameLast | Changed from "Last Name" |
| phone | text | phone | Keep as-is |
| profileCompletedDate | date | profileCompletedDate | NOT BUBBLE FIELD - local only |
| referredBy | text | referredBy | Already camelCase |
| registered | number | registered | Already lowercase |
| requiresPIN | yes/no | requiresPIN | Already camelCase |
| role | text | role | NOT BUBBLE FIELD - local only |
| state | text | state | NOT BUBBLE FIELD - local only |
| userPin | text | userPin | NOT BUBBLE FIELD - local only |
| userType | UserType | userType | Changed from "User Type" |
| userColor | text | userColor | Changed from "User Color" |
| devPermission | yes/no | devPermission | Changed from "Dev Permission" |
| zip | text | zip | NOT BUBBLE FIELD - local only |
| Creator | User | creator | Built-in field - CANNOT CHANGE |
| Modified Date | date | modifiedDate | Built-in field - CANNOT CHANGE |
| Created Date | date | createdDate | Built-in field - CANNOT CHANGE |
| Slug | text | slug | Built-in field - CANNOT CHANGE |

## CalendarEvent

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| color | text | color | Changed from "Color" - Hex color value |
| companyId | Company | companyId | Keep as-is - lowercase 'c' |
| duration | number | duration | Changed from "Duration" - Duration in days |
| endDate | date | endDate | Changed from "End Date" |
| projectId | Project | projectId | Keep as-is - lowercase 'p' |
| startDate | date | startDate | Changed from "Start Date" |
| taskId | Task | taskId | Keep as-is - lowercase 't' |
| teamMembers | List of Users | teamMembers | Changed from "Team Members" |
| title | text | title | Changed from "Title" - Event title |
| eventType | CalendarEventType | eventType | Changed from "Type" to "eventType" - Options: task, project |
| Creator | User | creator | Built-in field - CANNOT CHANGE |
| Modified Date | date | modifiedDate | Built-in field - CANNOT CHANGE |
| Created Date | date | createdDate | Built-in field - CANNOT CHANGE |

## Task

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| calendarEventId | CalendarEvent | calendarEventId | Already camelCase - Reference |
| companyId | Company | companyId | Already camelCase - Reference |
| completionDate | date | completionDate | Already camelCase |
| projectId | Project | projectId | Changed from "projectID" - now lowercase 'd' |
| scheduledDate | date | scheduledDate | Already camelCase |
| status | TaskStatus | status | Already lowercase - Option set |
| taskColor | text | taskColor | Already camelCase - Hex color |
| taskIndex | number | taskIndex | Already camelCase - Display order |
| taskNotes | text | taskNotes | Already camelCase |
| teamMembers | List of Users | teamMembers | Changed from "Team Members" |
| type | TaskType | type | Already lowercase - Reference to TaskType |
| Creator | User | creator | Built-in field - CANNOT CHANGE |
| Modified Date | date | modifiedDate | Built-in field - CANNOT CHANGE |
| Created Date | date | createdDate | Built-in field - CANNOT CHANGE |

## Client

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| address | geographic address | address | Changed from "Address" |
| balance | text | balance | Changed from "Balance" |
| clientIdNo | text | clientIdNo | Changed from "Client ID No" |
| emailAddress | text | emailAddress | Changed from "Email Address" |
| estimates | List of Estimates | estimates | Changed from "Estimates List" to "estimates" (NOT estimatesList) |
| invoices | List of Invoices | invoices | Changed from "Invoices" |
| isCompany | yes/no | isCompany | Changed from "Is Company" - Default: no |
| name | text | name | Changed from "Name" |
| parentCompany | Company | parentCompany | Changed from "Parent Company" |
| phoneNumber | text | phoneNumber | Changed from "Phone Number" |
| projectsList | List of Projects | projectsList | Changed from "Projects List" |
| status | ClientStatus | status | Changed from "Status" - Default: No Balance |
| avatar | image | avatar | Changed from "Thumbnail" to "avatar" (NOT thumbnail) |
| unit | number | unit | Changed from "Unit" - Default: 1 |
| userId | User | userId | Changed from "User ID" - Associated user |
| subClients | List of Clients | subClients | Changed from "Clients List" and "Sub Clients" |
| Creator | User | creator | Built-in field - CANNOT CHANGE |
| Modified Date | date | modifiedDate | Built-in field - CANNOT CHANGE |
| Created Date | date | createdDate | Built-in field - CANNOT CHANGE |
| Slug | text | slug | Built-in field - CANNOT CHANGE |

## TaskType (Data Type)

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| color | text | color | Changed from "Color" - Hex color value |
| display | text | display | Changed from "Display" - Display name |
| isDefault | yes/no | isDefault | Already camelCase - Default: no |
| Creator | User | creator | Built-in field - CANNOT CHANGE |
| Modified Date | date | modifiedDate | Built-in field - CANNOT CHANGE |
| Created Date | date | createdDate | Built-in field - CANNOT CHANGE |

## Option Sets

**IMPORTANT**: Option Set names have been changed to remove spaces and capitalize all words (e.g., "Task Status" → "TaskStatus").
The `Display` attribute is a built-in Bubble field and CANNOT be changed - it must remain capitalized.
**Option Set Display VALUES remain unchanged** (e.g., "In Progress", "RFQ", "Scheduled").

### SubscriptionPlan
**Attributes:**
- annualPrice (number)
- features (List of texts) - Changed from "Features"
- maxSeats (number)
- monthlyPrice (number)
- onetimePrice (number)
- priceId.annual (text)
- priceId.monthly (text)
- priceId.once (text)
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (using camelCase):**
- trial
- starter
- team
- business
- priority
- setup

### SubscriptionStatus
**Attributes:**
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Trial
- Active
- Expired
- Cancelled
- Grace

### OpsContacts
**Attributes:**
- email (text) - Changed from "Email"
- name (text) - Changed from "Name"
- phone (text) - Changed from "Phone"
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options:**
- jack
- prioritySupport
- dataSetup
- generalSupport
- webAppAutoSend

### TaskStatus
**Attributes:**
- color (text) - Changed from "Color"
- index (number) - Changed from "Index"
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Scheduled
- In Progress
- Completed
- Cancelled

### TaskType (Option Set)
**Attributes:**
- color (text) - Changed from "Color"
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Quote
- Work
- Service Call
- Inspection
- Follow Up

### CalendarEventType
**Attributes:**
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Task
- Project

### JobStatus
**Attributes:**
- color (text) - Changed from "Color" - hex
- index (number) - Changed from "Index"
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- RFQ
- Estimated
- Accepted
- In Progress
- Completed
- Closed
- Archived

### PaymentSchedule
**Attributes:**
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Monthly
- Annual

### EmployeeType
**Attributes:**
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Foreman
- Crew
- Admin
- Office

### CompanySize
**Attributes:**
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
(Options use Display attribute)

### CompanyAge
**Attributes:**
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
(Options use Display attribute)

### UserType
**Attributes:**
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Company
- Employee
- Client
- Admin

### ReferralMethod
**Attributes:**
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Google Search
- Social Media
- Word of Mouth
- Trade Show
- Other

## Important Field Naming Changes

**ALL BUBBLE FIELDS NOW USE camelCase** (except built-in fields which CANNOT be changed)

1. **Built-in Fields (CANNOT CHANGE)**:
   - `_id` - Object's unique ID
   - `Creator` - User reference
   - `Modified Date` - Timestamp (with space)
   - `Created Date` - Timestamp (with space)
   - `Slug` - Text (lowercase)

2. **Option Set Changes**:
   - Option Set names: Remove spaces, capitalize words (e.g., "Task Status" → "TaskStatus")
   - Option Set attributes: Now use camelCase (except `Display` which is built-in)
   - Option Set Display values: **UNCHANGED** - remain capitalized (e.g., "In Progress", "RFQ")

3. **Special Field Renames**:
   - CalendarEvent: `Type` → `eventType` (not just `type`)
   - Client: `Estimates List` → `estimates` (not `estimatesList`)
   - Client: `Thumbnail` → `avatar` (not `thumbnail`)
   - Client: `Clients List` / `Sub Clients` → `subClients`
   - Task: `projectID` → `projectId` (lowercase 'd')

4. **Reference Fields**: All use camelCase:
   - `companyId` (not `CompanyId`)
   - `projectId` (not `ProjectId`)
   - `taskId` (not `TaskId`)

## Critical Points

1. **Task.projectId**: Now uses lowercase 'd' (changed from `projectID`)
2. **Built-in fields**: CANNOT be changed - keep original format
3. **Option Set Display**: Built-in attribute - must stay capitalized
4. **All other fields**: Now use camelCase consistently

## API Endpoint Patterns

- Data API: `/api/1.1/obj/{type}/{id}`
- Workflow API: `/api/1.1/wf/{workflow_name}`
- List queries: Support constraints, sorting, and pagination
- Single object: Returns wrapped in `response` object
- Lists: Return in `response.results` array with cursor info
