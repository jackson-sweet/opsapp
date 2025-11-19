# TODO - November 19.1, 2025
## Form Sheet Consistency & Styling Fixes

**Created**: November 19, 2025
**Priority**: CRITICAL
**Status**: Not Started

---

## Overview

**CRITICAL REQUIREMENT**: Create Client Sheet, Create Task Sheet, and Create Project Sheet **MUST** be styled identically with their sections formatted the same way.

**Reference Template**: The Create Project Sheet (accessed from floating action button) should dictate how Task and Client sheets are formatted.

---

## General Requirements for ALL Form Sheets

### Common Styling Standards
- All section borders must have same opacity and styling
- All input fields must be styled identically:
  - Blue border ONLY when focused
  - NO opacity modifier on blue focused border
  - NO background color (transparent background)
  - Input titles above each field
- Sheet should NOT dismiss when user swipes down
- Navigation bar buttons: UPPERCASE text ("CANCEL", "CREATE", "SAVE")
- Consistent spacing between sections and elements

---

## 1. CREATE PROJECT SHEET FIXES

**Access**: Floating action button → Create Project
**File**: `OPS/Views/JobBoard/ProjectFormSheet.swift`

### 1.1 Section Border Opacity
**Issue**: Section borders are too dark
**Fix**: Reduce border opacity to match design system
**Current**: Unknown opacity
**Target**: 0.15 or lighter

### 1.2 Copy From Project Button
**Issue**: Button is too prominent
**Requirements**:
- Move to the side (not full-width)
- Add border to button
- Make less visually prominent (secondary styling)

### 1.3 Description and Notes Sections - Save/Cancel Buttons
**Issue**: Description and notes sections still have no save buttons or cancel buttons
**Requirements**:
- Add "Save" button to description section
- Add "Cancel" button to description section
- Add "Save" button to notes section
- Add "Cancel" button to notes section
- Buttons should appear when field is focused/edited

### 1.4 Address Input Border Styling
**Issue**: Address input is always blue bordered. It should only have blue border if focused. Its border should have no opacity modifier when focused either.
**Requirements**:
- Default state: Gray border (white with opacity)
- Focused state: Blue border with NO opacity modifier (solid blue)
- Use standard focus state handling

### 1.5 Disable Swipe-to-Dismiss
**Issue**: Should not dismiss sheet when user swipes down
**Requirements**:
- Add `.interactiveDismissDisabled()` modifier to sheet
- User must tap "Cancel" or "Create" to dismiss

### 1.6 Task Creation Sheet Inconsistency
**Issue**: Tapping "Create Task" from project sheet does not open the same task creation sheet as tapping create task from floating action button. It looks like the one from floating action button is the most up to date.
**Requirements**:
- Use the same TaskFormSheet component in both places
- Ensure latest redesigned version is used everywhere
- Verify consistent styling and functionality

### 1.7 Navigation Bar Button Text
**Issue**: Cancel button and create button in nav bar need to be uppercased
**Current**: "Cancel", "Create"
**Target**: "CANCEL", "CREATE"

---

## 2. CREATE TASK SHEET FIXES

**Access**: Floating action button → Create Task
**File**: `OPS/Views/JobBoard/TaskFormSheet.swift`

### 2.1 Update Preview to Match Universal Job Card
**Issue**: Preview card doesn't match UniversalJobBoardCard for tasks
**Requirements**:
- Study `UniversalJobBoardCard.swift` task layout
- Match preview card styling exactly:
  - Same colored left border (4pt)
  - Same text hierarchy
  - Same avatar display
  - Same spacing and padding
  - Same status badge position

### 2.2 Put All Inputs in Section
**Issue**: Inputs are not grouped in sections like Create Project Sheet
**Requirements**:
- Add section container with border
- Follow Create Project Sheet section styling exactly
- Group related inputs together
- Add section titles if needed

### 2.3 "Tap to Schedule" Button Not Working
**Issue**: "Tap to schedule" button has no effect
**Requirements**:
- Debug button action
- Ensure date picker opens when tapped
- Verify dates are saved correctly
- Test with both start and end dates

### 2.4 Apply General Input Styling
**Requirements** (from general notes):
- Blue border when focused
- No background color
- Input titles above each field
- No opacity modifier on focused border

### 2.5 Navigation Bar Buttons
**Requirements**:
- "CANCEL" (uppercase)
- "CREATE" or "SAVE" (uppercase)

### 2.6 Disable Swipe-to-Dismiss
**Requirements**:
- Add `.interactiveDismissDisabled()` modifier

---

## 3. CREATE CLIENT SHEET FIXES

**Access**: Floating action button → Create Client (or from client list)
**File**: `OPS/Views/JobBoard/ClientFormSheet.swift`

### 3.1 Remove "PREVIEW" Section Title
**Issue**: Preview should not have a section title (remove "preview")
**Requirements**:
- Remove "PREVIEW" text above preview card
- Preview card should be standalone at top

### 3.2 Put All Inputs Inside Section
**Issue**: Inputs need to be grouped in a section, like in Create Project Sheet
**Requirements**:
- Add section container with border
- Follow Create Project Sheet section styling exactly
- Match border opacity and styling
- Consistent padding and spacing

### 3.3 Add Input Titles
**Issue**: Inputs should have titles above them
**Requirements**:
- Add title above each input field:
  - "CLIENT NAME"
  - "EMAIL"
  - "PHONE"
  - "ADDRESS"
  - "NOTES"
- Use `OPSStyle.Typography.captionBold`
- Use `OPSStyle.Colors.secondaryText`
- 8-12pt spacing between title and input

### 3.4 Email Input Placeholder Color
**Issue**: The placeholder in email input is blue for some reason
**Requirements**:
- Change placeholder color to `OPSStyle.Colors.tertiaryText`
- Should match all other input placeholders
- Check all inputs for consistent placeholder styling

### 3.5 Input Styling Consistency
**CRITICAL**: All inputs should be styled IDENTICALLY to the inputs in Create Project view
**Requirements**:
- Blue border when focused (no opacity modifier)
- Gray border when not focused (white with opacity)
- No background color (transparent)
- Same padding: `.padding(.vertical, 12).padding(.horizontal, 16)`
- Same corner radius
- Same font and text color

### 3.6 Navigation Bar Buttons
**Requirements**:
- "CANCEL" (uppercase)
- "CREATE" or "SAVE" (uppercase)

### 3.7 Disable Swipe-to-Dismiss
**Requirements**:
- Add `.interactiveDismissDisabled()` modifier

---

## Implementation Priority

### Phase 1 - Critical Consistency (Do First)
1. **Input Field Styling** - Make ALL inputs identical across all three sheets
   - Blue focused border (no opacity)
   - Transparent background
   - Consistent padding and sizing
2. **Section Styling** - Make ALL sections identical
   - Same border opacity
   - Same padding
   - Same corner radius
3. **Navigation Buttons** - Uppercase all nav bar buttons

### Phase 2 - Functional Fixes
1. Fix "Tap to Schedule" button in Task Sheet
2. Add Save/Cancel buttons to Description and Notes in Project Sheet
3. Fix task editing not saving changes (Section 7 issue)

### Phase 3 - Polish
1. Update preview cards to match UniversalJobBoardCard
2. Adjust Copy From Project button styling
3. Disable swipe-to-dismiss on all sheets

---

## Success Criteria

**All three form sheets must**:
- ✅ Use identical input field styling
- ✅ Use identical section styling
- ✅ Have uppercase navigation buttons
- ✅ Not dismiss on swipe down
- ✅ Show blue border ONLY on focused inputs (no opacity)
- ✅ Have transparent input backgrounds
- ✅ Display input titles above fields
- ✅ Save changes correctly

**Visual Test**: Place screenshots of all three sheets side-by-side - they should look like they belong to the same design system with consistent styling throughout.

---

## Notes

The user was VERY EXPLICIT that these three sheets must be styled identically. Any deviation from the reference template (Create Project Sheet from floating action button) is unacceptable.

This is a critical consistency issue that affects the entire user experience of the form creation workflows.

---

**End of TODO_NOV_19.1.md**
