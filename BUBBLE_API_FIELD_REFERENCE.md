# Bubble API Field Reference

This document contains the exact field names used in Bubble for all data types.

## Task
| Field Name | Type | Notes |
|------------|------|-------|
| _id | String | Bubble's internal ID |
| calendarEventId | CalendarEvent | Reference to associated calendar event |
| companyId | Company | Reference to company |
| completionDate | date | When task was/will be completed |
| projectID | Project | **Note: capital ID** |
| scheduledDate | date | When task is scheduled |
| status | Task Status | Option set value |
| taskColor | text | Hex color value |
| taskIndex | number | Display order |
| taskNotes | text | Task-specific notes |
| Team Members | List of Users | **Note: space in field name** |
| type | Task Type | Reference to task type |
| Creator | User | Built-in field |
| Modified Date | date | Built-in field |
| Created Date | date | Built-in field |
| Slug | text | Built-in field |

## CalendarEvent
| Field Name | Type | Notes |
|------------|------|-------|
| _id | String | Bubble's internal ID |
| Color | text | Hex color value |
| companyId | Company | **lowercase 'c'** |
| Duration | number | Duration in days |
| End Date | date | Event end date |
| projectId | Project | **lowercase 'p'** |
| Start Date | date | Event start date |
| taskId | Task | **lowercase 't'** |
| Team Members | List of Users | **Note: space in field name** |
| Title | text | Event title |
| Type | CalendarEventType | Event type |
| Creator | User | Built-in field |
| Modified Date | date | Built-in field |
| Created Date | date | Built-in field |
| Slug | text | Built-in field |

## TaskType (Data Type)
| Field Name | Type | Notes |
|------------|------|-------|
| _id | String | Bubble's internal ID |
| Color | text | Hex color value |
| Display | text | Display name |
| isDefault | yes/no | Default: no |
| Creator | User | Built-in field |
| Modified Date | date | Built-in field |
| Created Date | date | Built-in field |
| Slug | text | Built-in field |

## Task Type (Option Set)
**Attributes:**
- Color (text)
- Display (text) - Built-in attribute

**Options:**
- Quote
- Work
- Service Call
- Inspection
- Follow Up

## Task Status (Option Set)
**Attributes:**
- Color (text)
- Index (number)
- Display (text) - Built-in attribute

**Options:**
- Scheduled
- In Progress
- Completed
- Cancelled

## Client
| Field Name | Type | Notes |
|------------|------|-------|
| _id | String | Bubble's internal ID |
| Address | geographic address | Client address |
| Balance | text | Account balance |
| Client ID No | text | Client identification number |
| Clients List | List of Clients | Sub-clients |
| Email Address | text | Contact email |
| Estimates List | List of Estimates | Related estimates |
| Invoices | List of Invoices | Related invoices |
| Is Company | yes/no | Default: no |
| Name | text | Client name |
| Parent Company | Company | Parent company reference |
| Phone Number | text | Contact phone |
| Projects List | List of Projects | Related projects |
| Status | Client Status | Default: No Balance |
| Thumbnail | image | Client logo/image |
| Unit | number | Default: 1 |
| User ID | User | Associated user |
| Creator | User | Built-in field |
| Modified Date | date | Built-in field |
| Created Date | date | Built-in field |
| Slug | text | Built-in field |

## API Type Names
When making API calls, use these exact type names:
- `Task` (capital T)
- `calendarevent` (all lowercase)
- `TaskType` (capital T, capital T)
- `Client` (capital C)
- `Company` (capital C)
- `Project` (capital P)
- `User` (capital U)

## Important Field Naming Patterns
1. **Task fields**: Mixed case - `projectID` has capital ID, but `companyId` has lowercase d
2. **CalendarEvent fields**: All reference fields use lowercase first letter (`companyId`, `projectId`, `taskId`)
3. **Fields with spaces**: `Team Members`, `Start Date`, `End Date`, `Modified Date`, `Created Date`
4. **Built-in fields**: Always have spaces in names (e.g., `Modified Date`, not `ModifiedDate`)

## Common Gotchas
- Task uses `projectID` (capital ID) but CalendarEvent uses `projectId` (lowercase p)
- CalendarEvent type name in API is `calendarevent` (all lowercase)
- Many fields with multiple words use spaces (e.g., `Team Members`, not `TeamMembers`)
- Option Sets have built-in `Display` attribute for the display text
- All data types have built-in `Creator`, `Modified Date`, `Created Date`, and `Slug` fields