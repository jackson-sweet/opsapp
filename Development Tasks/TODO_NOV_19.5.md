# TODO - November 19.5, 2025

## ProjectFormSheet

### Photos Picker - Duplication Bug
Each time user presses 'add', system is duplicating the photos to be added.
- Example: User selects two photos, presses ADD once → two photos uploaded ✓
- User presses ADD twice → one copy of both photos uploaded as well as originals
- User presses ADD 4 times → 3 copies of photos added plus originals

### Task Line Item Display
- Should NOT show "2 Members" text
- Should show team members icon and the number
- Refer to UniversalJobCard Task for reference
- Needs to include the schedule/calendar/dates icon
  - Show dash (—) if no dates selected
  - Show start date if picked

### Preview Card Issues
1. **Unscheduled Badge**: Showing "UNSCHEDULED" badge even when the tasks have been scheduled. Must fix this.
2. **Team Members**: Must show team member icon and count (sum of unique team members assigned to the tasks)
3. **Calendar/Dates**: Must show calendar/dates icon and date (or dash if not scheduled)

### Job Status Dropdown
- Needs primaryAccent borders when focused

---

## TaskFormSheet

### Task Preview Card
- Should NOT have "PREVIEW" section title
- Should NOT show avatars — should show team members icon and count
- Status Badge should have font in the status color as well as border
- Should literally be an iteration of UniversalJobCard Task
- Show calendar icon and team members icon even if empty (use dash "—" for calendar, "0" for team members - just like UniversalJobCard)

### Assign Team Section
- Remove "(OPTIONAL)" from section title

### Additional Fixes
- Add task status dropdown picker with functionality to set task status
- Remove fixed height on preview card
- Show unscheduled badge on preview card if date is not picked
- Add cancel and save buttons to notes text editor when focused (refer to ProjectFormSheet implementation)
- Notes text editor needs colored border when focused (imitate ProjectFormSheet)
- "Tap to schedule" text should not be primaryAccent
- Select project input needs to expand to fit selected project with animation (text bleeds over bottom border)

---

## TaskTypeFormSheet

### Navigation Bar Styling
- Update nav bar to match styling of other FormSheets (font, uppercased(), size, etc.)

### Section Layout
- Place all inputs inside an instance of 'ExpandableSection' card
- Should match ClientFormSheet and TaskFormSheet structure

### Task Type Name Field
- Remove asterisk (*) next to TASK TYPE NAME

### Color Display
- Need to display colours in a more compact way
- Open to suggestions

### Preview Card
- Add a preview like in TaskFormSheet and ProjectFormSheet
- Use the same template as TaskFormSheet

---

## ClientFormSheet

### Section Layout
- Place all inputs inside an instance of ExpandableSection from ProjectFormSheet
- Exception: Avatar picker should be positioned above the Client Details section, and below the preview card

### Input Styling
- Update all inputs to match ProjectFormSheet inputs

### Import from Contacts Button
- Move to the bottom
- Style like 'Copy from Project' button in ProjectFormSheet

### Email Input
- Placeholder text is blue — should match other inputs

### Placeholder Text
- Should NOT be sample values (email@example.com, 555 123-4567)
- Should be essentially the title text:
  - Email input placeholder: 'Email Address'
  - Phone input placeholder: 'Phone Number'

### Notes Field
- Needs to have Save and Cancel buttons when focused
- Refer to ProjectFormSheet text editor sections (Description and Notes)

---

# NEW ITEMS - November 19.6, 2025

## ProjectFormSheet

### Auto-scroll to Opened Section
- When pill is pressed and section is opened, scroll to position that section in view

---

## UniversalJobCard (Project)

### Unscheduled Badge Logic
- If project has no tasks, show unscheduled badge
- If a task is status completed or cancelled, it should not be considered for unscheduled calculation

---

## ClientFormSheet

### Avatar Size in Preview Card
- Avatar in preview is way too big
- Should not be taller than the text on the left side

---

## TaskFormSheet

### Task Notes Field
- Need to add task notes field back

---

## Job Board

### Employee Tab
- Create job board tab for employees
