# Project Payment Review — Tinder-Style Swipe Design

**Date:** 2026-03-08
**Status:** Approved
**Approach:** Hybrid — Local detection + swipe UI, backend push notifications

---

## Overview

A Tinder-style card stack UI for reviewing completed projects that are overdue for payment. Users with Project Manage or Full Access permissions swipe through projects to close (paid), skip, send reminders, or write off as bad debt.

---

## 1. Data & Detection

### Overdue Detection Logic
- On app launch + every 6 hours in background, scan all company projects where:
  - `status == .completed`
  - `completedAt` is older than the configured threshold (default 14 days)
  - Not dismissed in current session
- Queue is computed on the fly — no new persisted model needed

### Project Model
- `completedAt: Date?` — set when project transitions to `.completed` (verify if exists, add if not)

### Company Settings (New Fields)
- `overdueReviewThresholdDays: Int` — default 14
- `overdueReminderFrequencyDays: Int` — default 7
- `matchInvoicePaymentTerms: Bool` — future toggle, greyed out without financial access

---

## 2. Swipe UI — The Card Stack

### Card Face
- Full-bleed most recent project photo as background
- Bottom gradient overlay with:
  - Project name + client name (white text)
  - Completion date + "X DAYS AGO" badge
  - Accounting summary (total, owing) — only if user has financial access

### Card Stack Layout
- 3 visible cards with depth/scale offset (back cards slightly smaller + shifted down)
- Top card is interactive — draggable in 4 directions

### Swipe Directions

| Direction | Threshold | Stamp Overlay | Action | Permission |
|-----------|-----------|---------------|--------|------------|
| **Right →** | ~120pt | Green "CLOSED" | Close project (paid) | Project Manage / Full Access |
| **Left ←** | ~120pt | Gray "SKIP" | Skip, keep as completed | Project Manage / Full Access |
| **Up ↑** | ~120pt | Blue "SEND REMINDER" | Send invoice reminder | Accounting/Financial access |
| **Down ↓** | ~120pt | Red "CLOSE & MARK BAD DEBT" | Write off + close | Accounting/Financial access |

- Users without accounting access only see left/right
- Snap back if released before threshold
- Haptic feedback on threshold cross + action commit

### Card Tap → "Bio" Expansion
Tapping the card expands to a condensed project detail view:
- Photo carousel (horizontal scroll)
- Team members (avatar row)
- Recent notes (last 3)
- Project timeline summary
- Invoice/payment status (if financial access)
- "VIEW FULL PROJECT" button → navigates to ProjectDetailsView
- Tap again or swipe down to collapse back to card

### Empty State
- Celebration animation — checkmark + "ALL CAUGHT UP" text

---

## 3. Entry Points & Notifications

### Job Board Header Button
- New button in Job Board header row
- Icon: `rectangle.stack.fill` or similar card-stack icon
- Red badge with overdue project count
- Hidden when count is 0
- Opens swipe review screen as full-screen sheet

### Push Notifications (Backend — OneSignal)
- Backend scheduled job (Supabase edge function / cron) runs daily
- Identifies projects crossing threshold per company
- Sends push to users with Project Manage or Full Access permissions
- Message: "X projects need payment review"
- Tapping notification → opens app → navigates to swipe review screen
- Repeats every `overdueReminderFrequencyDays` until all reviewed

### Local Fallback
- On app launch, recompute overdue count
- If overdue projects exist and user hasn't been prompted in `reminderFrequency` days, show in-app banner on Job Board

### Deep Link
- New notification category: `projectPaymentReview`
- Notification tap → app opens → swipe review screen

---

## 4. Settings UI

### Location: Company Settings

**New Section: "PROJECT REVIEW"**
- **Overdue Threshold** — Stepper/picker: "Flag completed projects after ___ days" (default 14, range 7–90)
- **Reminder Frequency** — Stepper/picker: "Remind every ___ days" (default 7, range 1–30)
- **Match Invoice Payment Terms** — Toggle, greyed out + lock icon without financial access. Subtitle: "Uses invoice payment terms instead of fixed threshold"

### Permissions
- Only Project Manage / Full Access users can see/modify these settings
- Financial toggles additionally require accounting/financial access

---

## 5. Swipe Action Logic

### Right Swipe — Close (Paid)
- `project.status = .closed`
- `project.needsSync = true`
- Syncs via existing pipeline
- If linked invoices exist, marks as `paid` (requires financial access)
- Success haptic, card flies right

### Left Swipe — Skip
- Project remains `.completed`
- Removed from current session only
- Reappears next time queue is computed
- No data changes

### Up Swipe — Send Reminder (Accounting Access Only)
- Triggers invoice reminder notification to client (future: email/SMS)
- Creates project note: "Invoice reminder sent" with timestamp
- Project stays in queue
- Card flies up

### Down Swipe — Close & Mark Bad Debt (Accounting Access Only)
- **Confirmation alert first** (destructive action): "Are you sure? This will close the project and write off the outstanding balance."
- `project.status = .closed`
- Linked invoice marked as `void` / `written_off`
- Creates project note: "Marked as bad debt" with timestamp
- Card flies down

### Post-Review
- Empty stack → "ALL CAUGHT UP" celebration
- Badge count on Job Board header updates in real time

---

## 6. Future Extensions (Not in Scope)
- **Active → Completed review**: Same swipe pattern for projects scheduled in the past but not yet marked complete
- **Match Invoice Payment Terms**: Toggle activates once invoice system is fully connected
- **Email/SMS reminders**: Up swipe sends actual client communication
- **Analytics**: Track average days-to-close, write-off rates
