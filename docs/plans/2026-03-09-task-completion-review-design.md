# Task Completion Review — Design Document

## Overview

Tinder-style swipe card stack for reviewing active tasks that are due today or past-due. Reuses the same card stack gesture infrastructure as payment review. Available to all users — full-access users see all company tasks, limited users see only their assigned tasks.

## Swipe Directions

| Direction | Action | Permission | Label | Color | Icon |
|-----------|--------|------------|-------|-------|------|
| Right | Mark complete | All users | COMPLETE | successStatus | checkmark.circle.fill |
| Left | Skip | All users | SKIP | tertiaryText | arrow.right.circle |
| Up | Reschedule | `calendar.edit` | RESCHEDULE | primaryAccent | calendar.badge.clock |
| Down | Cancel task | All users | CANCEL | errorStatus | xmark.circle.fill |

## Entry Points

- **AppHeader** (Job Board) — icon next to payment review button, with badge count
- **FAB** — new "review" section below creation buttons, with both task review and payment review

## Data & Filtering

- **Status**: `.active` only
- **Date**: `startDate` is today or earlier (tasks without `startDate` excluded)
- **Sort**: date ascending (oldest/most urgent at top)
- **Permissions**: `hasFullAccess("tasks.view")` sees all company tasks; everyone else sees only tasks where they are in `teamMemberIdsString`
- **Badge**: total count of matching tasks (today + past-due)
- **Empty state**: "NO TASKS TO REVIEW" with dismiss button (no fallback)

## Swipe Actions

### Right (Complete)
- `task.status = .completed`
- `task.needsSync = true`
- Haptic: success

### Left (Skip)
- No data change
- Haptic: light impact

### Down (Cancel)
- Confirmation alert: "Cancel this task?"
- On confirm: `task.status = .cancelled`, `task.needsSync = true`
- On dismiss: count as reviewed, move on
- Haptic: warning

### Up (Reschedule) — requires `calendar.edit`
- Present sheet with:
  - Push row: +1D, +2D, +3D, +1W (uses `SchedulingEngine.calculateCascade` for dependency-aware pushes)
  - Cascade preview if enabled (`showCascadePreview` AppStorage)
  - "RESCHEDULE" button opens `CalendarSchedulerSheet` for manual date picking
- After reschedule: task leaves stack (now scheduled in future)
- If dismissed without rescheduling: treat as skip

## Card UI

Photo-forward design matching payment review cards:
- Latest project photo as hero (same image loading pipeline)
- Bottom gradient overlay for text readability
- Task name (uppercase), parent project name, client name
- Scheduled date badge: "TODAY" (amber) or "X DAYS AGO" (amber < 7 days, red >= 7 days)
- Task color stripe
- Tap → Task bio sheet

## Task Bio Sheet

Expanded detail view on tap (same "Tinder bio" concept):
- Photo carousel (project photos via PhotoThumbnail)
- Task header: name, status, task color
- Parent project + client
- Timeline: scheduled dates, duration
- Team members (avatars)
- Notes
- Button to open full TaskDetailsView

## SwipeDirection Architecture

Single `SwipeDirection` enum for gesture mechanics. Stamp overlay and hint pills accept configurable label/color/icon instead of hardcoded payment-specific text. Task and payment review each provide their own label configurations.

## New Files

- `Views/Review/TaskSwipeCardView.swift` — Task card (photo, task name, project, client, date badge, color stripe)
- `Views/Review/TaskReviewCardStack.swift` — Card stack with 4-direction gestures, task-specific labels
- `Views/Review/TaskCompletionReviewView.swift` — Full-screen review view
- `Views/Review/TaskBioSheet.swift` — Tap-to-expand detail sheet
- `Views/Review/TaskRescheduleSheet.swift` — Up-swipe action sheet (push buttons + open scheduler)

## Modified Files

- `AppHeader.swift` — Add task review button + badge next to payment review
- `JobBoardView.swift` — Compute reviewable tasks, pass to AppHeader, handle sheet
- `FloatingActionMenu.swift` — Add review section below create buttons
- `SwipeDirection.swift` — Make labels/colors/icons configurable (not hardcoded to payment)
- `SwipeStampOverlay.swift` — Accept configurable label/color instead of reading from SwipeDirection directly
