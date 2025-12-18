# AGENT HANDOVER DOCUMENT
**Last Updated:** Initial Creation
**Current Phase:** Pre-Implementation
**Branch:** `feature/interactive-tutorial-system`

---

## QUICK CONTEXT

**What We're Building:** An interactive onboarding tutorial where users learn OPS by doing in a sandbox populated with Top Gun-themed demo data.

**Two Flows:**
- **Company Creator** (~30 sec): Create project, manage status, browse calendar
- **Employee** (~20 sec): View assignments, add notes/photos, complete work

**Spec Files:**
- `Tutorial_Implementation_Spec.md` - Complete UX flow, visual system, state management
- `TopGun_Demo_Database.md` - 5 team members, 5 clients, 15 projects, 36 tasks

---

## CURRENT STATUS

### Completed
- [x] Branch created: `feature/interactive-tutorial-system`
- [x] Specification files reviewed
- [x] Codebase audit completed
- [x] Technical implementation guides created (6 documents)

### In Progress
- [ ] Nothing currently in progress

### Next Steps (Phase 1 - Foundation)
1. Create `OPS/Tutorial/` folder structure
2. Build `TutorialEnvironment.swift` - Environment keys
3. Build `TutorialPhase.swift` - Phase enum with tooltips
4. Build `TutorialStateManager.swift` - State management
5. Build `DemoIDs.swift` - ID constants
6. Build demo data structs (TeamMembers, Clients, TaskTypes, Projects)

See `06_IMPLEMENTATION_SEQUENCE.md` for complete build order.

---

## CRITICAL NOTES FOR AGENTS

### Status Enums - IMPORTANT
The codebase uses DIFFERENT status enums than the spec:

**Project Status (actual):** `Status` enum in `DataModels/Status.swift`
- `.rfq`, `.estimated`, `.accepted`, `.inProgress`, `.completed`, `.closed`, `.archived`

**Task Status (actual):** `TaskStatus` enum in `DataModels/ProjectTask.swift`
- `.booked`, `.inProgress`, `.completed`, `.cancelled`

**Mapping (SCHEDULED removed):**
- Spec "ACCEPTED" = Code `.accepted`
- Spec "SCHEDULED" = **USE `.accepted`** (not a real status - just means all tasks are future-dated)
- Spec "IN_PROGRESS" = Code `.inProgress`
- Spec "COMPLETED" = Code `.completed`

**Important:** There is NO `.scheduled` status. Projects with all future tasks simply have `.accepted` status.

### TeamMember vs User
- `TeamMember` model is a lightweight display model
- `User` model is the full SwiftData entity used in relationships
- Demo data should create `User` entities, which will be referenced in project/task teamMembers

### Key File Locations
```
OPS/Views/JobBoard/JobBoardDashboard.swift    - Kanban drag-to-status
OPS/Views/JobBoard/ProjectFormSheet.swift     - Create project form
OPS/Views/JobBoard/TaskFormSheet.swift        - Create task form
OPS/Views/Home/HomeView.swift                 - Employee home view
OPS/Views/Components/FloatingActionMenu.swift - FAB with create options
OPS/Views/Calendar Tab/                       - Calendar views
OPS/DataModels/                               - SwiftData models
OPS/Onboarding/Components/TypewriterText.swift - Existing animation component
```

### Existing Gestures
- **Long-press + Drag:** `JobBoardDashboard.swift` lines 298-343 (DirectionalDragCard)
- **Swipe Status:** `UniversalJobBoardCard.swift` has swipeOffset handling
- **Long-press Haptic:** Both files use `UIImpactFeedbackGenerator`

---

## BLOCKERS / DECISIONS NEEDED

### Resolved
1. **Image Assets:** Available in `Assets.xcassets/Images/Demo/`
   - Project images: `flight_deck_before`, `flight_deck_progress`, `hangar_exterior`, etc.
   - Use asset name directly (e.g., `Image("flight_deck_before")`)

2. **Camera/Photo:** Use production photo picker - NOT mocked
   - User should be able to add photos as they normally would
   - Full camera/library access in tutorial

3. **Team Member Avatars:** Available in `Assets.xcassets/Images/Demo/`
   - Named by first name: `pete`, `nick`, `tom`, `mike`, `rick`
   - Use asset name directly (e.g., `Image("pete")`)

4. **"SCHEDULED" Status:** REMOVED from spec
   - Not a real status in the codebase
   - Projects with future tasks use `.accepted` status
   - Status is computed from task dates, not stored

5. **Tutorial Completion Tracking:** New Bubble field `hasCompletedAppTutorial` on User
   - Field will be added to Bubble User table
   - Must add to local `User` SwiftData model
   - Must add to `BubbleFields.User` constants
   - Must add to `UserDTO` for API sync
   - Check this field to determine if tutorial should show
   - Set to `true` on tutorial completion and sync to Bubble

### Technical Notes
- **Calendar View:** Composed of `MonthGridView.swift` + components in `Calendar Tab/Components/`
- **Status Mapping:** ACCEPTED, IN_PROGRESS, COMPLETED only (no SCHEDULED)

### Unresolved
(None - ready to proceed with implementation)

---

## AGENT INSTRUCTIONS

When you start work:
1. Read this document first
2. Check "Current Status" for what's done
3. Check "Next Steps" for what to do
4. Reference other docs in this folder for details
5. Update this document when you complete work

When you finish work:
1. Update "Current Status" - move items from "In Progress" to "Completed"
2. Update "Next Steps" - remove completed items, add any new ones discovered
3. Add any new blockers or decisions to "Blockers / Decisions Needed"
4. Note any important discoveries in "Critical Notes for Agents"

---

## FILE MANIFEST

| File | Purpose |
|------|---------|
| `00_AGENT_HANDOVER.md` | This file - living handover document |
| `01_CODEBASE_AUDIT.md` | Detailed audit of existing views/models/gestures |
| `02_ARCHITECTURE_PLAN.md` | Architecture decisions and patterns |
| `03_DEMO_DATA_IMPLEMENTATION.md` | Demo data seeding/cleanup strategy |
| `04_COMPONENT_INVENTORY.md` | New components to build |
| `05_VIEW_MODIFICATIONS.md` | Existing views needing changes |
| `06_IMPLEMENTATION_SEQUENCE.md` | Ordered build plan |
| `Tutorial_Implementation_Spec.md` | Original UX specification |
| `TopGun_Demo_Database.md` | Demo data content |
