# TODO - November 18.5, 2025

## Job Board Interaction Issues

- [ ] **Job board project list and task list: Scroll vs tap gesture conflict**
  - Issue: Scroll gesture frequently incorrectly registered as a tap gesture
  - File: JobBoardView.swift, UniversalJobBoardCard.swift

- [ ] **Job board task list: Swipe to change status not smooth**
  - Issue: Swiping cards to change status needs smoother interaction
  - File: UniversalJobBoardCard.swift

## Job Board Card Data Display

- [ ] **Project and task cards: Show icons even when no data**
  - If no date booked: show calendar icon but signify not booked
  - If 0 team members: show team member icon with 0
  - File: UniversalJobBoardCard.swift

- [ ] **Job board cards: Text truncation ellipsis positioning**
  - Issue: When truncating text, ellipsis is currently in middle
  - Required: Position ellipsis at the bottom
  - File: UniversalJobBoardCard.swift

## Create Client Sheet Updates

- [ ] **Match create project sheet styling**
  - Update overall layout to match ProjectFormSheet
  - File: ClientFormSheet.swift (or similar)

- [ ] **Input field styling consistency**
  - Text fields and input fields use same styling as create project sheet
  - File: ClientFormSheet.swift

- [ ] **Add preview card at top**
  - Like create project page, populate with input values
  - File: ClientFormSheet.swift

- [ ] **Add 'Import from contacts' button**
  - In place of 'copy from' button
  - File: ClientFormSheet.swift

- [ ] **Nav bar title: Use OPSStyle fonts**
  - File: ClientFormSheet.swift

## Create Task Sheet Updates

- [ ] **Update create task sheet styling**
  - Match new create project sheet styling
  - File: TaskFormSheet.swift (or similar)

## Push-in Notification Fixes

- [ ] **Position below native status bar**
  - Currently being cut off by camera area on iPhone 16
  - File: PushInMessage.swift

- [ ] **Update icon and font styling**
  - Don't use fill icon
  - Change font to Kosugi
  - File: PushInMessage.swift

## Project Create Sheet - Task List Improvements

- [ ] **Remove checkmark from task list items**
  - We do not need icons there
  - File: ProjectFormSheet.swift

- [ ] **Show date on task line item if picked**
  - Display selected date for each task
  - File: ProjectFormSheet.swift

- [ ] **Show team avatars on task line item if picked**
  - Display team member avatars when assigned
  - File: ProjectFormSheet.swift

---

## Implementation Status

**Complete:** 0/16 tasks (0%)
**Incomplete:** 16/16 tasks (100%)

### Task Breakdown:
- Job Board Interaction: 2 tasks
- Job Board Card Display: 2 tasks
- Create Client Sheet: 5 tasks
- Create Task Sheet: 1 task
- Push-in Notification: 2 tasks
- Project Create Sheet Task List: 3 tasks
