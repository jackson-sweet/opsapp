# Bubble Field Mappings - Complete Reference

This document contains the exact field names and types for all Bubble.io data objects used in the OPS app.

## Company

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| AccountHolder | User | accountHolder | |
| Active Projects | List of Projects | activeProjects | |
| Admin | List of Users | admin | |
| billingPeriodEnd | date | billingPeriodEnd | |
| Calendar EventsList | List of CalendarEvents | calendarEventsList | |
| Client | List of Clients | clients | |
| Close Hour | text | closeHour | |
| Company Description | text | companyDescription | |
| company id | text | companyID | Unique code for employees to join |
| Company Name | text | companyName | |
| company_age | text | companyAge | Note underscore |
| company_size | text | companySize | Note underscore |
| Completed Projects | List of Projects | completedProjects | |
| dataSetupCompleted | yes/no | dataSetupCompleted | |
| dataSetupPurchased | yes/no | dataSetupPurchased | |
| dataSetupScheduledDate | date | dataSetupScheduledDate | |
| defaultProjectColor | text | defaultProjectColor | Hex color |
| Employees | List of Users | employees | |
| Estimates | List of Estimates | estimates | |
| hasPrioritySupport | yes/no | hasPrioritySupport | |
| hasWebsite | yes/no | hasWebsite | |
| Industry | List of Industries | industry | |
| Invoice | List of Invoices | invoices | |
| Late Projects | List of Projects | lateProjects | |
| Location | geographic address | location | |
| Logo | image | logo | |
| maxSeats | number | maxSeats | Default: 0 |
| Office Email | text | officeEmail | |
| Open Hour | text | openHour | Default: 08:00:00 |
| phone | text | phone | Note: lowercase |
| prioritySupportPurchDate | date | prioritySupportPurchaseDate | |
| Projects | List of Projects | projects | |
| QB Connected | yes/no | qbConnected | Default: no |
| qb.accesstoken | text | qbAccessToken | |
| qb.authbasic | text | qbAuthBasic | |
| qb.code | text | qbCode | |
| qb.companyid | text | qbCompanyId | |
| qb.idtoken | text | qbIdToken | |
| qb.refreshtoken | text | qbRefreshToken | |
| reactivatedSubscription | yes/no | reactivatedSubscription | Default: no |
| Receivables | number | receivables | |
| Referral Method | Referral Method | referralMethod | |
| Referral Method Other | text | referralMethodOther | |
| Registered | number | registered | Default: 0 |
| seatedEmployees | List of Users | seatedEmployees | |
| seatGraceEndDate | date | seatGraceEndDate | |
| seatGraceStartDate | date | seatGraceStartDate | |
| Security Clearances | List of Security Clearances | securityClearances | |
| stripeCustomerId | text | stripeCustomerId | |
| subscriptionEnd | date | subscriptionEnd | |
| subscriptionEndls | List of subscriptionEndls | subscriptionEndls | |
| subscriptionPeriod | PaymentSchedule | subscriptionPeriod | Options: Monthly, Annual |
| subscriptionPlan | subscriptionPlan | subscriptionPlan | Options: trial, starter, team, business |
| subscriptionStatus | subscriptionStatus | subscriptionStatus | Options: trial, active, grace, expired, cancelled |
| Task Types | List of Task Types | taskTypes | |
| Teams | List of Teams | teams | |
| trialEndDate | date | trialEndDate | |
| trialStartDate | date | trialStartDate | |
| Visit | number | visit | Default: 1 |
| website | text | website | |
| Creator | User | creator | Built-in field |
| Modified Date | date | modifiedDate | Built-in field |
| Created Date | date | createdDate | Built-in field |
| Slug | text | slug | Built-in field |

## Project

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| Address | geographic address | address | |
| All Day | yes/no | allDay | |
| Balance | number | balance | |
| Client | Client | client | Reference to Client object |
| Client Email | text | clientEmail | Deprecated - use Client reference |
| Client Name | text | clientName | Deprecated - use Client reference |
| Client Phone | text | clientPhone | Deprecated - use Client reference |
| Company | Company | company | Reference |
| Completion | date | completion | End date |
| Description | text | description | |
| Duration | number | duration | Days |
| eventType | CalendarEventType | eventType | Options: task, project |
| Project Gross Cost | number | projectGrossCost | |
| Project Images | List of images | projectImages | |
| Project Name | text | projectName | |
| Project Value | number | projectValue | |
| Slug | text | slug | |
| Start Date | date | startDate | |
| Status | Job Status | status | Option set |
| Team Members | List of Users | teamMembers | Note space |
| Team Notes | text | teamNotes | |
| Thumbnail | image | thumbnail | |
| Creator | User | creator | Built-in field |
| Modified Date | date | modifiedDate | Built-in field |
| Created Date | date | createdDate | Built-in field |

## User

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| Address | text | address | |
| Avatar | image | avatar | Profile image |
| City | text | city | |
| Company | Company | company | Reference |
| Company Description | text | companyDescription | |
| Company Name | text | companyName | |
| companyID | text | companyID | |
| Country | text | country | |
| dateAdded | date | dateAdded | |
| Email | text | email | User's email (built-in) |
| Employee Type | Employee Type | employeeType | |
| First Name | text | firstName | |
| Full Name | text | fullName | |
| hasProfileImageUploaded | yes/no | hasProfileImageUploaded | |
| Home Address | geographic address | homeAddress | |
| isPlanHolder | yes/no | isPlanHolder | |
| isProfileCompleted | yes/no | isProfileCompleted | |
| Last Name | text | lastName | |
| Phone | text | phone | |
| Profile Completed Date | date | profileCompletedDate | |
| referredBy | text | referredBy | |
| Registered | number | registered | |
| requiresPIN | yes/no | requiresPIN | |
| Role | text | role | Options: Field Crew, Office Crew, Admin |
| State | text | state | |
| user PIN | text | userPIN | |
| Zip | text | zip | |
| Creator | User | creator | Built-in field |
| Modified Date | date | modifiedDate | Built-in field |
| Created Date | date | createdDate | Built-in field |
| Slug | text | slug | Built-in field |

## CalendarEvent

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| Color | text | color | Hex color value |
| companyId | Company | companyId | **lowercase 'c'** |
| Duration | number | duration | Duration in days |
| End Date | date | endDate | |
| projectId | Project | projectId | **lowercase 'p'** |
| Start Date | date | startDate | |
| taskId | Task | taskId | **lowercase 't'** |
| Team Members | List of Users | teamMembers | Note space |
| Title | text | title | Event title |
| Type | CalendarEventType | type | Options: Task, Project |
| Creator | User | creator | Built-in field |
| Modified Date | date | modifiedDate | Built-in field |
| Created Date | date | createdDate | Built-in field |

## Task

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| calendarEventId | CalendarEvent | calendarEventId | Reference |
| companyId | Company | companyId | Reference |
| completionDate | date | completionDate | |
| projectID | Project | projectID | **Note: capital ID** |
| scheduledDate | date | scheduledDate | |
| status | Task Status | status | Option set |
| taskColor | text | taskColor | Hex color |
| taskIndex | number | taskIndex | Display order |
| taskNotes | text | taskNotes | |
| Team Members | List of Users | teamMembers | Note space |
| type | Task Type | type | Reference to TaskType |
| Creator | User | creator | Built-in field |
| Modified Date | date | modifiedDate | Built-in field |
| Created Date | date | createdDate | Built-in field |

## Client

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| Address | geographic address | address | |
| Balance | text | balance | |
| Client ID No | text | clientIdNo | |
| Clients List | List of Clients | clientsList | Sub-clients |
| Email Address | text | emailAddress | |
| Estimates List | List of Estimates | estimatesList | |
| Invoices | List of Invoices | invoices | |
| Is Company | yes/no | isCompany | Default: no |
| Name | text | name | |
| Parent Company | Company | parentCompany | |
| Phone Number | text | phoneNumber | |
| Projects List | List of Projects | projectsList | |
| Status | Client Status | status | Default: No Balance |
| Thumbnail | image | thumbnail | |
| Unit | number | unit | Default: 1 |
| User ID | User | userId | Associated user |
| Creator | User | creator | Built-in field |
| Modified Date | date | modifiedDate | Built-in field |
| Created Date | date | createdDate | Built-in field |

## TaskType (Data Type)

| Bubble Field Name | Type | Swift Property | Notes |
|-------------------|------|----------------|-------|
| _id | text | id | Bubble's internal ID |
| Color | text | color | Hex color value |
| Display | text | display | Display name |
| isDefault | yes/no | isDefault | Default: no |
| Creator | User | creator | Built-in field |
| Modified Date | date | modifiedDate | Built-in field |
| Created Date | date | createdDate | Built-in field |

## Option Sets

### subscriptionPlan
**Attributes:**
- annualPrice (number)
- Features (List of texts)
- maxSeats (number)
- monthlyPrice (number)
- onetimePrice (number)
- priceId.annual (text)
- priceId.monthly (text)
- priceId.once (text)
- Display (text) - Built-in attribute

**Options:**
- trial
- starter
- team
- business
- priority
- setup

### subscriptionStatus
**Attributes:**
- Display (text) - Built-in attribute

**Options:**
- trial
- active
- expired
- cancelled
- grace

### Ops Contacts
**Attributes:**
- Email (text)
- Name (text)
- Phone (text)
- Display (text) - Built-in attribute

**Options:**
- jack
- Priority Support
- Data Setup
- General Support
- Web App Auto Send

### Task Status
**Attributes:**
- Color (text)
- Index (number)
- Display (text) - Built-in attribute

**Options:**
- Scheduled
- In Progress
- Completed
- Cancelled

### Task Type (Option Set)
**Attributes:**
- Color (text)
- Display (text) - Built-in attribute

**Options:**
- Quote
- Work
- Service Call
- Inspection
- Follow Up

### CalendarEventType
**Attributes:**
- Display (text) - Built-in attribute

**Options:**
- Task
- Project

### Job Status
**Options:**
- RFQ
- Estimated
- Accepted
- In Progress
- Completed
- Closed
- Archived

**Attributes:**
- Display (text)
- Index (number)
- Color (text - hex)

### PaymentSchedule
**Options:**
- Monthly
- Annual

### Employee Type
**Options:**
- Foreman
- Crew
- Admin
- Office

### Referral Method
**Options:**
- Google Search
- Social Media
- Word of Mouth
- Trade Show
- Other

## Important Field Naming Patterns

1. **Inconsistent Capitalization**: Some fields use camelCase (`companyId`), others use spaces (`Company Name`), and some use underscores (`company_size`)

2. **Reference Fields in CalendarEvent**: All use lowercase first letter:
   - `companyId` (not `CompanyId`)
   - `projectId` (not `ProjectId`) 
   - `taskId` (not `TaskId`)

3. **Task Exception**: Uses `projectID` with capital ID (not `projectId`)

4. **Fields with Spaces**: Many Bubble fields have spaces that must be exact:
   - `Team Members` (not `TeamMembers`)
   - `Start Date` (not `StartDate`)
   - `End Date` (not `EndDate`)
   - `Seated Employees` (not `seatedEmployees`)
   - `Company Name` (not `CompanyName`)

5. **Lowercase Fields in Company**:
   - `phone` (not `Phone`)
   - `website` (not `Website`)
   - `company_age` (with underscore)
   - `company_size` (with underscore)

6. **Built-in Fields**: Always have specific formats:
   - `Modified Date` (with space)
   - `Created Date` (with space)
   - `Creator` (reference to User)
   - `Slug` (text)

## Critical Issues to Watch

1. **Seated Employees**: The field name is `Seated Employees` with a space, not `seatedEmployees`
2. **Project ID in Task**: Uses `projectID` with capital ID, different from other references
3. **Company Fields**: Mix of naming conventions - some lowercase (`phone`), some with spaces (`Company Name`), some with underscores (`company_size`)
4. **Date Fields**: Most use spaces (`Start Date`, `End Date`, `Modified Date`)

## API Endpoint Patterns

- Data API: `/api/1.1/obj/{type}/{id}`
- Workflow API: `/api/1.1/wf/{workflow_name}`
- List queries: Support constraints, sorting, and pagination
- Single object: Returns wrapped in `response` object
- Lists: Return in `response.results` array with cursor info
