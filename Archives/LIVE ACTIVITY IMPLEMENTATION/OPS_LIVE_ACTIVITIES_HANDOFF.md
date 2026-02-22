# OPS Live Activities & Home Widget - Implementation Handoff

## Document Purpose

Complete direction for implementing Live Activities (lock screen + Dynamic Island) and Home Screen Widgets for the OPS iOS app. Claude Code will handle technical planning and implementation while working in the repo in Xcode.

---

## First Step for Claude Code

**Review the entire codebase before writing any code.** Specifically:

1. Understand the overall architecture and file organization
2. Locate OPSStyle.swift—study colors, fonts, icons, corner radius values
3. Find where project status changes occur (likely in a ViewModel or DataController)
4. Review project and task models for data structure (notes format, photos array, team members, etc.)
5. Understand the role detection system (field crew vs office/admin)
6. Review existing floating action button implementation for State 4 admin actions
7. Identify any existing widget or extension targets

Do not begin implementation until the codebase is fully understood. Ask clarifying questions if architecture is unclear.

---

## Feature Overview

Display active job information and daily schedule on lock screen, Dynamic Island, and home screen widget. Four distinct states based on user context and role.

---

## Four States

| State | Condition | User |
|-------|-----------|------|
| 1 | Project status is "In Progress" | All |
| 2 | Projects scheduled today, none active | Field Crew |
| 3 | Projects scheduled today, none active | Office/Admin |
| 4 | No projects scheduled today | All |

---

## State 1: Active Project

### Lock Screen Layout (Top to Bottom)

**Header**
- Project name (primary text)
- Client name (secondary text)
- Address: street number and street name only (tertiary text)
- Button (top right): opens Project Details view in app

**Notes Preview**
- 2 lines maximum, truncated with ellipsis
- "See all" tap target opens full notes in app
- If no photos exist: expand to 6 lines maximum
- If no notes exist: show "No notes" in muted text

**Photo Carousel**
- Horizontal scrollable row of photo thumbnails
- Tap any photo to expand full screen in app
- If no photos: collapse section entirely, show "No Photos" label, notes section expands
- Auto-advances through photos on home widget

**Quick Action Buttons**
- 4 square buttons in horizontal row
- Filled squares with primaryText background
- Icons in background color (dark)
- Buttons: Add Photo, Route (open Maps), Add Notes, Contact Client
- Use icons from OPSStyle.Icons

**Progress Bar**
- Horizontal bar showing distance to destination
- Left side: current location indicator
- Right side: destination indicator
- Fill: primaryText color for completed portion
- Remaining: dark grey
- Below bar: distance (e.g., "2.7 KM") on left, ETA (e.g., "3:15 PM") on right
- When user arrives (within radius): show "Arrived" text, then collapse entire section after 2 seconds, redistributing space to other elements

### Dynamic Island - Compact (Pill)

- Left: OPS logo
- Right: Time to destination (e.g., "8 min")
- When arrived/at location: show Task Name in task type color instead of TTD

### Dynamic Island - Expanded (Tap and Hold)

Mirror lock screen content:
- Header (project name, client, address, details button)
- Progress bar with ETA
- 4 quick action buttons

---

## State 2: Today's Projects - Field Crew

### Lock Screen Layout

**Header**
- "Today's Projects" or similar
- Count indicator

**Project Tiles**
- Horizontal scrollable row
- Approximately 2.5 tiles visible (third bleeds off edge to indicate scroll)
- Borderless cards with spacing between
- Background: subtle gradient, slightly lighter than live activity background
- Corner radius: use OPSStyle standard

**Tile Content**
- Task type (with task type color indicator)
- Client name
- Address (street number and name)
- Distance and ETA: "2.7 KM   3:15"

**Tile Tap Behavior**
- On tap: two buttons fade in overtop of tile
- "Start Project" button: sets project to In Progress, transitions to State 1
- "Quick View" button: opens Quick View overlay

### Quick View Content

- Project name
- Client name
- Description
- Notes (scrollable if needed)
- Tasks list with current/next task denoted
- Team members assigned
- Photos

### Dynamic Island - Compact

- Left: OPS logo
- Right: "X Projects Today"

### Dynamic Island - Expanded

- Mirror lock screen: scrollable project tiles with tap actions

---

## State 3: Today's Projects - Office/Admin

### Lock Screen Layout

Identical to State 2 except:

**Tile Content Differences**
- Instead of distance/ETA: show team members assigned and total task count
- Example: "3 Team · 8 Tasks"

**Tile Tap Behavior**
- On tap: two buttons fade in overtop of tile
- "Quick View" button: opens Quick View overlay
- "Edit Details" button: opens project edit screen in app

### Dynamic Island

Same as State 2

---

## State 4: No Projects Today

### Lock Screen Layout

**Message**
- "No Projects Today" or similar friendly message

**Action Buttons - Field Crew**
- 2 buttons: Calendar, Job Board
- Opens respective views in app

**Action Buttons - Office/Admin**
- 4 buttons: Create Project, Create Client, Create Task, Create Task Type
- Reuse icons/actions from existing floating action button in app

**Hide Toggle**
- "Hide when no projects?" button/toggle
- Sets preference in app settings to suppress State 4 Live Activity
- Can be re-enabled in Settings later

### Dynamic Island - Compact

- Left: OPS logo
- Right: Random string from pool:
  - "All Clear"
  - "Nothing On Today"
  - "Today's Clear"
  - "Rest Up"
  - (Add more variations)

### Dynamic Island - Expanded

- Mirror lock screen: message + action buttons

---

## Home Screen Widget

### Sizes Supported

- **Medium** (wide rectangle)
- **Large** (tall rectangle)
- No small widget

### Medium Widget Content

Use discretion to fit essentials:
- Header info (project name, client, address)
- Progress bar or status indicator
- Condensed action buttons or key info

### Large Widget Content

Full experience matching lock screen for each state:
- State 1: All elements
- States 2/3: Scrollable project tiles
- State 4: Message + action buttons
- Photo carousel auto-rotates through images

### Widget Tap Behavior

- If active project (State 1): tap opens Project Details view for that project
- If no active project: tap opens app to appropriate screen

---

## Style Guidelines

### Theme

- Use app's dark theme always (do not adapt to system light/dark)
- Tactical/military minimalism aesthetic
- Minimal color usage
- High contrast for outdoor visibility

### Typography

- **Font**: Kosugi for all text (no Bebas Neue or Mohave)
- **Hierarchy**: Reference existing OPSStyle type scales
- Create new font definitions in OPSStyle specifically for Live Activity and Widget, referencing existing styles

### Colors

- **Buttons/Actions**: primaryText
- **Status colors**: Use existing OPSStyle definitions
- **Task type colors**: Use existing OPSStyle definitions
- **Backgrounds**: Dark background as base
- **Lighter backgrounds**: ultraThinMaterial dark
- **Progress bar fill**: primaryText (completed), dark grey (remaining)
- **Tile backgrounds**: Gradient slightly lighter than live activity background

### Buttons (Quick Actions)

- Filled square shape
- Background fill: primaryText
- Icon color: background color (dark)
- Icons: SF Symbols from OPSStyle.Icons

### Progress Bar

- Solid fill style
- Moderate weight (not chunky, not hairline)
- No gradient

### Project Tiles

- Borderless cards
- Space between cards
- Corner radius: OPSStyle standard
- Background: subtle gradient, slightly lighter than surrounding

---

## Technical Notes

### Font Loading

- Attempt custom Kosugi font loading in widget extension
- If not possible, use closest system font approximation

### Location/ETA

- Use Core Location for distance calculation
- Use MapKit for ETA estimation
- Define "arrived" radius threshold (suggest 50-100 meters, configurable)

### State Detection

- Monitor project status changes to trigger State 1
- Query today's scheduled projects for States 2/3
- Detect user role from existing role system
- No projects today triggers State 4

### Settings Integration

- Add "Show Live Activity when no projects" toggle in Settings
- Default: enabled
- State 4 hide button sets this to disabled

### Live Activity Lifecycle

- Start: When project status changes to "In Progress" (State 1) OR when app launches with today's projects (States 2/3/4)
- Update: On location changes, status changes, note additions, photo additions
- End: When State 1 project status changes away from "In Progress" and no other projects for today

---

## Implementation Priority

1. State 1 (Active Project) - highest value for field workers
2. State 2 (Field Crew daily view)
3. Large Home Widget
4. State 3 (Office/Admin daily view)
5. State 4 (No Projects)
6. Medium Home Widget

---

## Code Quality Standards

- Clean, minimal, efficient code
- No redundant code or unnecessary abstractions
- Every line serves a clear purpose
- Prioritize readability, maintainability, performance
- Reuse existing OPSStyle components—do not duplicate
- Follow existing architectural patterns in the codebase
