# Bubble API Field Reference

This document contains the exact field names used in Bubble for all data types.

**IMPORTANT**: Built-in Bubble fields that CANNOT be changed:
- `_id` (object's unique ID)
- `Creator` (User reference)
- `Modified Date` (timestamp)
- `Created Date` (timestamp)
- `Slug` (text)

**Note on Option Sets**: The `Display` attribute is a built-in Bubble field and must remain capitalized.

## Company

| Field Name | Type | Notes |
|------------|------|-------|
| _id | String | Bubble's internal ID |
| companyName | text | Changed from "Company Name" |
| companyId | text | Changed from "company id" - unique code for employees to join |
| companyDescription | text | Changed from "Company Description" |
| location | geographic address | Already lowercase |
| logo | image | Already lowercase |
| projects | List of Projects | Already lowercase |
| teams | List of Teams | Already lowercase |
| openHour | text | Changed from "Open Hour" |
| closeHour | text | Changed from "Close Hour" |
| phone | text | Keep as-is |
| officeEmail | text | Changed from "Office Email" |
| industry | List of Industries | Already lowercase |
| companySize | text | Changed from "company_size" |
| companyAge | text | Changed from "company_age" |
| employees | List of Users | Already lowercase |
| admin | List of Users | Already lowercase |
| website | text | Keep as-is |
| activeProjects | List of Projects | Changed from "Active Projects" |
| completedProjects | List of Projects | Changed from "Completed Projects" |
| lateProjects | List of Projects | Changed from "Late Projects" |
| calendarEventsList | List of CalendarEvents | Changed from "Calendar.EventsList" |
| taskTypes | List of TaskTypes | Changed from "Task Types" |
| clients | List of Clients | Changed from "Client" |
| estimates | List of Estimates | Changed from "Estimates" |
| invoices | List of Invoices | Changed from "Invoice" |
| receivables | number | Already lowercase |
| qbConnected | yes/no | Changed from "QB Connected" |
| qbAccessToken | text | Changed from "qb.accesstoken" |
| qbAuthBasic | text | Changed from "qb.authbasic" |
| qbCode | text | Changed from "qb.code" |
| qbCompanyId | text | Changed from "qb.companyid" |
| qbIdToken | text | Changed from "qb.idtoken" |
| qbRefreshToken | text | Changed from "qb.refreshtoken" |
| securityClearances | List of Security Clearances | Changed from "Security Clearances" |
| referralMethod | Referral Method | Changed from "Referral Method" |
| referralMethodOther | text | Changed from "Referral Method Other" |
| accountHolder | User | Changed from "AccountHolder" |
| registered | number | Already lowercase |
| visit | number | Already lowercase |
| seatedEmployees | List of Users | Keep as-is |
| Creator | User | Built-in field - CANNOT CHANGE |
| Modified Date | date | Built-in field - CANNOT CHANGE |
| Created Date | date | Built-in field - CANNOT CHANGE |
| Slug | text | Built-in field - CANNOT CHANGE |

## Project

| Field Name | Type | Notes |
|------------|------|-------|
| _id | String | Bubble's internal ID |
| address | geographic address | Already lowercase |
| allDay | yes/no | Changed from "All Day" |
| balance | number | Already lowercase |
| client | Client | Already lowercase |
| clientEmail | text | Changed from "Client Email" |
| clientName | text | Changed from "Client Name" |
| clientPhone | text | Changed from "Client Phone" |
| company | Company | Already lowercase |
| completion | date | Already lowercase |
| description | text | Already lowercase |
| duration | number | Already lowercase |
| projectGrossCost | number | Changed from "Project Gross Cost" |
| projectImages | List of images | Changed from "Project Images" |
| projectName | text | Changed from "Project Name" |
| projectValue | number | Changed from "Project Value" |
| slug | text | Already lowercase |
| startDate | date | Changed from "Start Date" |
| status | Job Status | Already lowercase |
| teamMembers | List of Users | Changed from "Team Members" |
| teamNotes | text | Changed from "Team Notes" |
| thumbnail | image | Already lowercase |
| tasks | List of Tasks | Already lowercase |
| Creator | User | Built-in field - CANNOT CHANGE |
| Modified Date | date | Built-in field - CANNOT CHANGE |
| Created Date | date | Built-in field - CANNOT CHANGE |

## User

| Field Name | Type | Notes |
|------------|------|-------|
| _id | String | Bubble's internal ID |
| address | text | Already lowercase |
| avatar | image | Already lowercase |
| city | text | Already lowercase |
| company | Company | Already lowercase |
| companyDescription | text | Changed from "Company Description" |
| companyName | text | Changed from "Company Name" |
| country | text | Already lowercase |
| email | text | Already lowercase |
| employeeType | Employee Type | Changed from "Employee Type" - determines role |
| nameFirst | text | Changed from "Name First" |
| nameLast | text | Changed from "Name Last" |
| fullName | text | Changed from "Full Name" |
| homeAddress | geographic address | Changed from "Home Address" |
| phone | text | Keep as-is |
| registered | number | Already lowercase |
| userType | User Type | Changed from "User Type" |
| userColor | text | Changed from "User Color" |
| devPermission | yes/no | Changed from "Dev Permission" |
| Creator | User | Built-in field - CANNOT CHANGE |
| Modified Date | date | Built-in field - CANNOT CHANGE |
| Created Date | date | Built-in field - CANNOT CHANGE |
| Slug | text | Built-in field - CANNOT CHANGE |

**Note**: The following are NOT Bubble fields (local app-only):
- profileCompletedDate
- role
- state
- userPin
- zip

## CalendarEvent

| Field Name | Type | Notes |
|------------|------|-------|
| _id | String | Bubble's internal ID |
| color | text | Changed from "Color" |
| companyId | Company | Keep as-is - lowercase 'c' |
| duration | number | Changed from "Duration" |
| endDate | date | Changed from "End Date" |
| projectId | Project | Keep as-is - lowercase 'p' |
| startDate | date | Changed from "Start Date" |
| taskId | Task | Keep as-is - lowercase 't' |
| teamMembers | List of Users | Changed from "Team Members" |
| title | text | Changed from "Title" |
| eventType | CalendarEventType | Changed from "Type" to "eventType" |
| Creator | User | Built-in field - CANNOT CHANGE |
| Modified Date | date | Built-in field - CANNOT CHANGE |
| Created Date | date | Built-in field - CANNOT CHANGE |

## Task

| Field Name | Type | Notes |
|------------|------|-------|
| _id | String | Bubble's internal ID |
| calendarEventId | CalendarEvent | Reference to associated calendar event |
| companyId | Company | Reference to company |
| completionDate | date | When task was/will be completed |
| projectId | Project | Changed from "projectID" - now lowercase 'd' |
| scheduledDate | date | When task is scheduled |
| status | Task Status | Option set value |
| taskColor | text | Hex color value |
| taskIndex | number | Display order |
| taskNotes | text | Task-specific notes |
| teamMembers | List of Users | Changed from "Team Members" |
| type | Task Type | Reference to task type |
| Creator | User | Built-in field - CANNOT CHANGE |
| Modified Date | date | Built-in field - CANNOT CHANGE |
| Created Date | date | Built-in field - CANNOT CHANGE |

## Client

| Field Name | Type | Notes |
|------------|------|-------|
| _id | String | Bubble's internal ID |
| address | geographic address | Changed from "Address" |
| balance | text | Changed from "Balance" |
| clientIdNo | text | Changed from "Client ID No" |
| emailAddress | text | Changed from "Email Address" |
| estimates | List of Estimates | Changed from "Estimates List" to "estimates" |
| invoices | List of Invoices | Changed from "Invoices" |
| isCompany | yes/no | Changed from "Is Company" |
| name | text | Changed from "Name" |
| parentCompany | Company | Changed from "Parent Company" |
| phoneNumber | text | Changed from "Phone Number" |
| projectsList | List of Projects | Changed from "Projects List" |
| status | Client Status | Changed from "Status" |
| avatar | image | Changed from "Thumbnail" to "avatar" |
| unit | number | Changed from "Unit" |
| userId | User | Changed from "User ID" |
| subClients | List of Clients | Changed from "Sub Clients" and "Clients List" |
| Creator | User | Built-in field - CANNOT CHANGE |
| Modified Date | date | Built-in field - CANNOT CHANGE |
| Created Date | date | Built-in field - CANNOT CHANGE |
| Slug | text | Built-in field - CANNOT CHANGE |

## TaskType (Data Type)

| Field Name | Type | Notes |
|------------|------|-------|
| _id | String | Bubble's internal ID |
| color | text | Changed from "Color" |
| display | text | Changed from "Display" |
| isDefault | yes/no | Default: no |
| Creator | User | Built-in field - CANNOT CHANGE |
| Modified Date | date | Built-in field - CANNOT CHANGE |
| Created Date | date | Built-in field - CANNOT CHANGE |

## Option Sets

### CalendarEventType
**Attributes:**
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Task
- Project

### TaskType
**Attributes:**
- color (text)
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Quote
- Work
- Service Call
- Inspection
- Follow Up

### TaskStatus
**Attributes:**
- color (text)
- index (number)
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Scheduled
- In Progress
- Completed
- Cancelled

### JobStatus
**Attributes:**
- color (text)
- index (number)
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- RFQ
- Estimated
- Accepted
- In Progress
- Completed
- Closed
- Archived

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

### SubscriptionStatus
**Attributes:**
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Trial
- Active
- Grace
- Expired
- Cancelled

### SubscriptionPlan
**Attributes:**
- Display (text) - Built-in attribute - CANNOT CHANGE

**Options (Display values - unchanged):**
- Trial
- Starter
- Team
- Business

## API Type Names

When making API calls, use these exact type names:
- `Task` (capital T)
- `calendarevent` (all lowercase)
- `TaskType` (capital T, capital T)
- `Client` (capital C)
- `Company` (capital C)
- `Project` (capital P)
- `User` (capital U)

## Important Field Naming Changes

1. **All data type fields now use camelCase** (except built-in fields)
2. **Built-in fields unchanged**: `_id`, `Creator`, `Modified Date`, `Created Date`, `Slug`
3. **Special field renames**:
   - CalendarEvent: `Type` → `eventType` (not just `type`)
   - Client: `Estimates List` → `estimates` (not `estimatesList`)
   - Client: `Thumbnail` → `avatar` (not `thumbnail`)
   - Client: `Clients List`/`Sub Clients` → `subClients` (clientsList not used)
   - Task: `projectID` → `projectId` (lowercase 'd')
4. **Option Set changes**:
   - Option Set names: Changed to remove spaces (e.g., "Task Status" → "TaskStatus")
   - Option Set attributes: Changed to camelCase (e.g., "Color" → "color")
   - Option Set Display values: **UNCHANGED** - remain capitalized (e.g., "In Progress", "RFQ")

## Common Gotchas

- Task now uses `projectId` (lowercase 'd') instead of `projectID`
- CalendarEvent type name in API is still `calendarevent` (all lowercase)
- Option Sets have built-in `Display` attribute that CANNOT be changed - must stay capitalized
- All data types have built-in `Creator`, `Modified Date`, `Created Date`, and `Slug` fields that CANNOT be changed
