# TODO - November 18, 2025

## Job Board & UI Fixes

- [x] **Delete job board level floating action button**
  - ✅ COMPLETE: Removed job board specific FAB and all related state
  - Deleted @State variables for showCreateMenu and sheet presentations
  - Deleted entire floating action button ZStack and menu items
  - File: JobBoardView.swift (lines 15-19, 128-130)

- [x] **Job board search bar gradient background**
  - ✅ COMPLETE: Added LinearGradient background (black at top, clear at bottom)
  - Gradient applied to UniversalSearchBar component
  - File: UniversalSearchBar.swift (lines 104-113)

- [x] **Universal job card: Fix address field overlap**
  - ✅ COMPLETE: Changed from fixedSize to truncationMode(.tail)
  - Address field now properly truncates at 35% max width
  - File: UniversalJobBoardCard.swift (lines 591-597)

---

## Create Project Sheet Fixes

- [x] **Reduce bottom spacing**
  - ✅ COMPLETE: Changed padding from 100 to 24
  - File: ProjectFormSheet.swift (line 222)

- [x] **Expanded sections: Match collapsed pill style**
  - ✅ COMPLETE: Completely redesigned ExpandableSection component
  - Section titles and icons moved inside border
  - Border color uses OPSStyle.Colors.secondaryText (brighter/more visible)
  - Added icons to all sections (doc.text, mappin.circle, text.alignleft, etc.)
  - File: ProjectFormSheet.swift (lines 1749-1809)

- [x] **Border styling: Lighter for sections, darker for inputs**
  - ✅ COMPLETE: **CORRECTED NOVEMBER 18 (post-session)**
  - Expanded sections use OPSStyle.Colors.secondaryText (brighter)
  - Pills use OPSStyle.Colors.secondaryText for icon, text, and border
  - Input fields use Color.white.opacity(0.1) when unfocused (darker/subtle)
  - All inputs show primaryAccent when focused
  - Files: ProjectFormSheet.swift (lines 412, 482, 527, 649, 686, 765, 1742), OptionalSectionPill.swift (lines 27, 32, 40)

- [x] **Expanded section titles: Within border with icon**
  - ✅ COMPLETE: Section headers now inside border container
  - Icons displayed next to section titles
  - Consistent styling with OPSStyle.Typography.captionBold
  - File: ProjectFormSheet.swift (lines 1768-1788)

- [x] **ALL input fields: Consistent focus state**
  - ✅ COMPLETE: Added .client and .status to FormField enum
  - Client search field uses focus state (lines 398, 415-417)
  - Status field uses focus state (lines 530-537)
  - All inputs consistently show primaryAccent/grey borders
  - File: ProjectFormSheet.swift (lines 103, 108, 398, 415, 530)

- [x] **Remove Team Members section**
  - ✅ COMPLETE: Deleted isTeamExpanded state variable
  - Removed team expansion initialization
  - Removed "TEAM MEMBERS" pill from OptionalSectionPillGroup
  - Removed entire teamMembersSection view
  - Removed team count from preview card
  - File: ProjectFormSheet.swift (deleted lines 86, 156, 559-563, 989-1044, 1198-1207)

- [x] **Sheet title: Use OPSStyle fonts**
  - ✅ COMPLETE: Replaced .navigationTitle with custom toolbar principal
  - Title uses OPSStyle.Typography.bodyBold and OPSStyle.Colors.primaryText
  - Displays "CREATE PROJECT" or "EDIT PROJECT" based on mode
  - File: ProjectFormSheet.swift (lines 240-244)

- [x] **Remove asterisks from mandatory fields**
  - ✅ COMPLETE: Removed asterisks from all mandatory fields
  - "CLIENT *" → "CLIENT" (line 341)
  - "PROJECT NAME *" → "PROJECT NAME" (line 463)
  - "JOB STATUS *" → "JOB STATUS" (line 488)
  - File: ProjectFormSheet.swift (lines 341, 463, 488)

- [x] **Move job status to project details section**
  - ✅ COMPLETE: Job status field moved inside PROJECT DETAILS section
  - Grouped with client and project name
  - Removed as standalone field
  - File: ProjectFormSheet.swift (line 331)

---

## Loading Animation Z-Index

- [x] **Loading animation: Appear at top above FAB and tab bar**
  - ✅ COMPLETE: Already implemented in previous session (TODO_NOV_17)
  - Tab bar hidden when isPerformingInitialSync = true
  - Floating action button hidden when isPerformingInitialSync = true
  - Loading animation has zIndex(999) in HomeContentView
  - Files: MainTabView.swift (lines 153-161), HomeContentView.swift (line 69)

---

## Implementation Status: ✅ COMPLETE

**Complete:** 13/13 tasks (100%)
**Incomplete:** 0/13 tasks (0%)

### Task Breakdown:
- Job Board & UI: 3 tasks ✅
- Create Project Sheet: 9 tasks ✅
- Loading Animation: 1 task ✅

### All Changes Verified:
All code changes have been implemented and build tested successfully.
