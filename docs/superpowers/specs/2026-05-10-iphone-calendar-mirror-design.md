# iPhone Calendar Mirror — Design Spec

**Date:** 2026-05-10
**Bug:** `68123654-6398-4b65-8cec-5bf37b5a29e4` — "Special events not showing in iOS calendar (time off etc)"
**Status:** Authoritative — self-reviewed against bible + Supabase + codebase + design system
**Deployment target:** iOS 17.6+ (per `OPS.xcodeproj/project.pbxproj`)

---

## 0. Known drift discovered during self-review

These are pre-existing inconsistencies that this spec **must work around** but is not in scope to fix. Flagged here so they aren't silently absorbed.

| Drift | Detail | Spec impact |
|---|---|---|
| **iOS `SiteVisit` model is a stub** | iOS has `assignedTo: String?` only. Supabase has `assignee_ids text[]`, `duration_minutes int NOT NULL`, `client_id`, `project_id`, `activity_id`, `calendar_event_id`, `internal_notes`, `status` enum. There is **no `SiteVisit` DTO, no repository, no sync wiring** in iOS. Production `site_visits` table has 0 rows. | **`SiteVisit` is excluded from this spec's mirror scope.** When iOS SiteVisit sync ships, a follow-up adds it. The bug user-confirmed scope expansion (B: "personal + time off + their scheduled work") still applies to `ProjectTask` — the actual production scheduling primitive. |
| **`site_visits.calendar_event_id text`** | Unused legacy column in Supabase, likely an artifact of the removed `CalendarEvent` entity (bible 10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md line 2294: *"CalendarEvent has been removed — scheduling dates are on ProjectTask directly"*). | Ignore. Spec uses its own iOS-local side-table for mapping; does not touch this column. |
| **`project_tasks.recurrence_id` not modeled on iOS** | Supabase has `recurrence_id uuid`; iOS `ProjectTask` model omits it. Server-managed recurrence; iOS reads finalized rows. | No impact — mirror reads the resolved rows iOS already has. |
| **`CalendarUserEvent.userId` types** | Supabase: `user_id text NOT NULL`. iOS: `userId: String`. Aligned. | None. |
| **OPS deep-link URL scheme already exists** | Info.plist `CFBundleURLTypes` registers the `ops` scheme. `AppDelegate.handleDeepLink` routes `ops://projects/{id}`, `ops://clients/{id}`, `ops://tasks/{...}`, `ops://invoices/{id}`, `ops://estimates/{id}`, `ops://catalog/...`. There is **no `event` entity handler today**. | Spec adds an `event` entity branch to `AppDelegate.handleDeepLink` so tapping an iPhone Calendar OPS event opens the corresponding `CalendarUserEvent`. Project task mirror uses the existing `ops://projects/{projectId}/tasks/{taskId}` form, which is supported. |

---

## 1. Problem

OPS schedules — personal events, time off requests, assigned project tasks, assigned site visits — live only inside the OPS app. Users have asked to see this schedule alongside their personal life in the native iPhone Calendar app. There is currently zero EventKit integration in the codebase.

## 2. Goals

- A user's OPS-relevant events appear in their iPhone Calendar app on their device.
- A dedicated `OPS` calendar in iCloud (so it propagates to their iPad, Mac, Apple Watch automatically).
- Updates in OPS reflect in iPhone Calendar within seconds of the source change (foreground) or by the next app launch (background).
- The user can disable the mirror at any time from Settings without losing their OPS data.
- Logout and company-switch leave no orphaned events in the user's calendar.

## 3. Non-goals (deferred)

- **Two-way sync** — edits in iPhone Calendar do NOT flow back to OPS. Researched in a prior brainstorming pass; scoped as a separate future spec. Trade-off accepted: silent revert on user edits in iPhone Calendar (industry-standard pattern; documented in support docs).
- **`SiteVisit` mirror** — deferred until iOS SiteVisit sync (DTO, repository, save path) ships. Add as a follow-up: `MirrorSource.siteVisit` enum case, `assignee_ids` membership predicate, `Visit — {customer || address}` title, `duration_minutes` for end time. See §0 drift.
- **Mirroring company-wide holidays / blackout dates** — would require a new table; not in scope.
- **watchOS / macOS specific support** — comes free via iCloud propagation.
- **Push from server on mobile when app is suspended** — relies on opportunistic `BGAppRefreshTask` only; we do not promise real-time mirror while OPS is closed.

## 4. Decisions

| Decision | Value | Rationale |
|---|---|---|
| **Scope of mirrored items** | `CalendarUserEvent` (personal + time off, any status); `ProjectTask` where current user ∈ parsed `schedulingTeamMemberIds` (the `Set<String>` accessor over `teamMemberIdsString`). **`SiteVisit` excluded** — iOS model is a stub with no sync wiring (see §0 drift) | Matches user intent: "show me my OPS schedule on my phone". SiteVisit deferred until iOS sync ships. |
| **Sync direction** | One-way (OPS → device) | Two-way scoped out as future work |
| **Calendar destination** | Dedicated `OPS` calendar, iCloud source preferred | Clean toggle, clean wipe, propagates across user's devices |
| **Read-only enforcement** | Reconcile-and-revert (no public API enforces calendar read-only) | `EKCalendar.allowsContentModifications` is read-only; cannot be set |
| **Permission API** | `EKEventStore.requestFullAccessToEvents()` (iOS 17+) | Write-only access blocks reading back events we created, breaking reconciliation |
| **Permission UX** | Proactive prompt on first event save + Settings toggle + dismissable banner | Catches the most users at the moment of relevance |
| **Time-off pending behavior** | Mirror on creation; status reflected as title prefix | User wants visibility on "I asked for these days off" |
| **Recurring events** | Mirror each pre-expanded `CalendarUserEvent` row as its own `EKEvent`, no `EKRecurrenceRule` | Matches OPS data model; per-instance status & metadata maps 1:1 |
| **Mirror window** | Past 30 days → future 12 months | Prevents dumping years of history into the user's calendar |
| **Identifier strategy** | Side-table mapping + `EKEvent.url` redundancy anchor | `eventIdentifier` is mostly-stable but can change on server sync; URL gives recovery path |
| **Backend changes** | None | Schema unchanged; iOS-local feature |

## 5. Architecture

```
┌────────────────────────────────────────────────────────┐
│  SwiftData (existing)                                  │
│   CalendarUserEvent, ProjectTask, SiteVisit            │
└────────────────────────────────────────────────────────┘
                 │  observers / repository save hooks
                 ▼
┌────────────────────────────────────────────────────────┐
│  CalendarMirrorService  (NEW — Services/)              │
│   • @MainActor isolated                                │
│   • EKEventStore lifecycle                             │
│   • permission gating                                  │
│   • write queue                                        │
│   • reconcile-and-revert                               │
│   • Combine subscription to .EKEventStoreChanged       │
│   • didBecomeActive re-check                           │
└────────────────────────────────────────────────────────┘
                 │  EventKit writes
                 ▼
┌────────────────────────────────────────────────────────┐
│  EventKit / iOS Calendar  (system)                     │
│   "OPS" calendar (CalDAV iCloud or local source)       │
└────────────────────────────────────────────────────────┘
                 │  side-table for idempotent updates
                 ▼
┌────────────────────────────────────────────────────────┐
│  CalendarMirrorMap (NEW SwiftData @Model)              │
│   opsId → ekEventIdentifier, sourceType, contentHash   │
└────────────────────────────────────────────────────────┘
```

## 6. Components

### 6.1 `CalendarMirrorService` (`OPS/Services/CalendarMirrorService.swift`)

Singleton, owned by `AppState`. `@MainActor` isolated (because `EKEventStore` is not `Sendable` in Swift 6 and `EventStore` operations should run on a stable actor).

**Public surface:**

```swift
@MainActor
final class CalendarMirrorService: ObservableObject {
    static let shared = CalendarMirrorService()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorizationStatus: EKAuthorizationStatus

    func requestAccessIfNeeded() async -> Bool
    func enable() async throws         // toggle on → request access → backfill
    func disable() async               // toggle off → delete OPS calendar
    func mirrorEvent(opsId: String, source: MirrorSource) async
    func unmirrorEvent(opsId: String) async
    func reconcileAll() async          // full sync; called on foreground + after Supabase sync batch
    func handleLogout() async          // wipe OPS calendar entirely + clear map
    func handleCompanySwitch() async   // same as logout
}

enum MirrorSource: String, Codable {
    case calendarUserEvent
    case projectTask
    // siteVisit reserved for future addition once iOS SiteVisit sync ships
}
```

**Internal behavior:**

- `enable()` → `requestAccessIfNeeded()` → on grant, create `OPS` calendar via default-source pattern → store its identifier in UserDefaults → backfill all eligible rows.
- Subscribe to `.EKEventStoreChanged` via Combine; debounce by 1 second; fire `reconcileAll()`.
- Subscribe to `UIApplication.didBecomeActiveNotification`; re-check `authorizationStatus`. If status downgraded from `.fullAccess` to `.denied`/`.notDetermined`, set `isEnabled = false` and surface banner.
- `disable()` deletes the entire `EKCalendar` object (cascades to all events) and clears `CalendarMirrorMap`.
- All writes happen on `@MainActor` to satisfy Swift 6 isolation.

**Calendar creation (correct pattern):**

```swift
let source = store.defaultCalendarForNewEvents?.source
    ?? store.sources.first(where: { $0.sourceType == .calDAV })
    ?? store.sources.first(where: { $0.sourceType == .local })

let cal = EKCalendar(for: .event, eventStore: store)
cal.title = "OPS"
cal.source = source
cal.cgColor = UIColor(OPSStyle.Colors.opsAccent).cgColor  // #6F94B0; iCloud may normalize
try store.saveCalendar(cal, commit: true)
UserDefaults.standard.set(cal.calendarIdentifier, forKey: "ops.calendar.mirror.calendarId")
```

### 6.2 `CalendarMirrorMap` (`OPS/DataModels/CalendarMirrorMap.swift`)

```swift
@Model
final class CalendarMirrorMap {
    @Attribute(.unique) var opsId: String
    var ekEventIdentifier: String
    var sourceType: String     // MirrorSource.rawValue
    var contentHash: String    // SHA256 of canonical "title|start|end|notes|allDay|status"
    var lastMirroredAt: Date

    init(opsId: String, ekEventIdentifier: String, sourceType: MirrorSource, contentHash: String) {
        self.opsId = opsId
        self.ekEventIdentifier = ekEventIdentifier
        self.sourceType = sourceType.rawValue
        self.contentHash = contentHash
        self.lastMirroredAt = Date()
    }
}
```

**Why a side-table:** isolated concern, clean wipe on disable, doesn't contaminate sync-eligible model fields. Registered in `OPSApp.swift` ModelContainer.

### 6.3 Mirror trigger sites

Four places where source changes fan out to the mirror:

| Site | Hook |
|---|---|
| `CalendarUserEventRepository.create/update/delete` | After SwiftData commit, fire `mirrorEvent` / `unmirrorEvent` |
| `ProjectTask` save path (existing ViewModel) | On `startDate`/`endDate`/`teamMemberIdsString` change, fire mirror hook if current user ∈ `schedulingTeamMemberIds` (parsed Set from the stringified field) |
| ~~`SiteVisit` save path~~ | **Excluded** — iOS SiteVisit model is unwired. Re-add as a follow-up. |
| `RealtimeProcessor` (after applying inbound Supabase change for `calendar_user_events` / `project_tasks`) | Same as repository save — applies to remote-originated changes |

All hooks are no-ops when `isEnabled == false` or `authorizationStatus != .fullAccess`.

### 6.4 Reconciliation algorithm

Triggered by: foreground, `.EKEventStoreChanged` (debounced 1s), post-Supabase-sync, `BGAppRefreshTask`.

```
1. Verify OPS calendar still exists (store.calendar(withIdentifier:))
   • nil → recreate calendar, full backfill, return
2. Fetch all CalendarMirrorMap rows for current user
3. Iterate map rows:
   a. Source row exists & is in mirror window & user still eligible
      • Compute current canonical hash
      • Fetch EKEvent by ekEventIdentifier
        - EKEvent nil → user deleted it. Recreate from source, update map.
        - EKEvent present:
          • Compare EKEvent content to source. If drift (user edited) → overwrite with source values.
          • Compare new source hash vs stored hash. If changed → update EKEvent, update hash.
          • Equal → skip.
   b. Source row missing / soft-deleted / out of window / user no longer eligible
      • Delete EKEvent, delete map row.
4. Fetch all eligible source rows. For any without a map entry → create EKEvent + map row.
5. Fetch all events in OPS calendar via predicate. For any with no matching map row:
   • Try to recover by parsing url (ops://event/{opsId}) → if recoverable, rebuild map.
   • Else → orphan from prior version → delete.
```

O(n) per source kind. The hash comparison makes idempotent reconcile near-free.

### 6.5 Event title format

| Source | Title | Notes |
|---|---|---|
| `CalendarUserEvent.personal` | `{title}` | `Dentist` |
| `CalendarUserEvent.timeOff` (`approved`) | `Time Off — {title}` | `Time Off — Cottage` |
| `CalendarUserEvent.timeOff` (`pending`) | `[Pending] {title}` | `[Pending] Cottage` |
| `CalendarUserEvent.timeOff` (`denied`) | `[Denied] {title}` | `[Denied] Cottage` |
| `ProjectTask` | `{customer surname || project name} — {taskType.display}` | `Smith — Plumbing rough-in` |
| ~~`SiteVisit`~~ | **Excluded** | See §0 drift |

**Notes field:** project address (if any) on line 1, user notes (if any) on line 2, footer `// OPS · view in app`.

**URL field:** `ops://event/{opsId}` — both a deep-link tap-through AND a recovery anchor for the reconciler.

**All-day vs timed:**
- `CalendarUserEvent.allDay` honored directly.
- `ProjectTask` is all-day when `duration > 1`; timed for single-day using `startTime`/`endTime` combined with `startDate`.

### 6.6 Permission UX

**(a) First-event-save prompt** — after the user taps Save on their first `CalendarUserEvent` post-update. Shown only once per install. Tracked via `hasShownMirrorPrompt` UserDefault.

```
// MIRROR TO iPHONE CALENDAR

See your OPS schedule alongside your personal calendar.
One-way: edits in OPS, sync to your phone.

[ ENABLE ]    [ NOT NOW ]
```

On Enable → `requestAccessIfNeeded()` → system prompt → on grant, backfill + toast `// SYNCING ${N} EVENTS`.

**(b) Settings toggle** — added to `IntegrationsSettingsView` under a new `CALENDAR` header (above the existing `ACCOUNTING` section). Uses the existing `integrationCard(name:description:iconName:isConnected:onConnect:)` pattern from that file. Card content:

```
iPhone Calendar
Sync OPS events to your iPhone Calendar — time off,
personal events, and your assigned work.
[CONNECT] | [CONNECTED] toggle
```

Icon: `calendar` (SF Symbol). The card's `isConnected` reflects `CalendarMirrorService.shared.isEnabled && authorizationStatus == .fullAccess`. Tapping when not connected runs `enable()`; tapping when connected runs `disable()` after a confirm sheet (`// DISCONNECT iPHONE CALENDAR — Existing mirrored events will be removed from your iPhone Calendar.`).

**(c) Dismissable banner** in Schedule tab (only if `hasShownMirrorPrompt == true && !isEnabled`):

```
// MIRROR DISABLED · TAP TO ENABLE
```

Two dismisses then stays hidden permanently (still recoverable in Settings).

**(d) Denied-in-system path** — if `authorizationStatus == .denied`, tapping Enable shows:

```
// PERMISSION DENIED

OPS can't access your iPhone Calendar.
Open Settings to allow access.

[ OPEN SETTINGS ]    [ NEVER MIND ]
```

All copy goes through `ops-copywriter` skill on implementation (OPS voice: terse, tactical, no exclamation points, sentence-case content + UPPERCASE authority). Permission-prompt sheet animation honors `useReducedMotion` per design system § 6 (`cubic-bezier(0.22, 1, 0.36, 1)` ease, 300ms; fallback opacity-only 150ms when reduced).

### 6.7 Background sync

- `BGAppRefreshTask` registered with identifier `com.ops.calendar.mirror.refresh`.
- Scheduled opportunistically on app background; iOS decides when to fire (Apple budgets ~30s).
- On fire: re-check authorization, run `reconcileAll()`, complete.
- This is best-effort. Not promised in UX. Primary path remains foreground reconcile.

## 7. Edge cases

| Case | Handling |
|---|---|
| User denies permission at system prompt | Set `isEnabled = false`. Show banner (c). Settings toggle stays available. |
| User grants then revokes via Settings.app | Detected on `didBecomeActive` re-check. Set `isEnabled = false`. Show banner. |
| User deletes OPS calendar from iOS Calendar app | Detected on next reconcile (`calendar(withIdentifier:)` returns nil). Recreate silently, re-backfill. |
| User edits an event in iOS Calendar | Reconcile fetches the `EKEvent` and compares its fields (title, start, end, notes, isAllDay) against the OPS source-of-truth on next `.EKEventStoreChanged` fire (typically within seconds, debounced 1s). Any mismatch is silently overwritten with OPS values. Documented behavior. |
| User deletes an event in iOS Calendar | Reconcile detects missing `EKEvent`, recreates from source. Behavior identical to edit. |
| Logout | `handleLogout()` → delete OPS calendar entirely (one EK call cascades). Clear `CalendarMirrorMap`. Reset UserDefaults. |
| Company switch | Same as logout. |
| Time off requested by admin for a crew member | Mirror eligibility on `CalendarUserEvent` is `event.userId == currentUserId || (event.teamMemberIds ?? []).contains(currentUserId)`. Admin who requested it does NOT see it on their own iPhone unless they're in `teamMemberIds`. Each target crew member sees it on their device after sync. |
| Recurring series edit (`thisAndFollowing`) | Iterate all forward `seriesId` rows in OPS, fan out to mirror queue per row. Hash dedup skips no-ops. |
| Project task auto-scheduler reshuffle | Batch mutation; reconcile-with-hashes makes most rows no-op writes. |
| Multi-device | iCloud propagates the OPS calendar to user's iPad/Mac/Watch. We only write on the one device running OPS. |
| App reinstall with iCloud source | Calendar reappears via iCloud. Side-table is gone → reconcile rebuilds map by parsing `EKEvent.url`. |
| App reinstall without iCloud (local source) | Calendar is lost. Full backfill on first launch. |
| Event outside mirror window (more than 30d past or 12mo future) | Excluded on backfill; pruned on reconcile if it ages out. |
| `eventIdentifier` changes (server sync edge case) | Reconcile falls back to URL-parsed `opsId` matching. Map row updated with new identifier. |

## 8. Files touched / created

| File | Action |
|---|---|
| `OPS/Services/CalendarMirrorService.swift` | **NEW** |
| `OPS/DataModels/CalendarMirrorMap.swift` | **NEW** |
| `OPS/OPSApp.swift` | Register `CalendarMirrorMap` in ModelContainer; init `CalendarMirrorService` on launch; register BGAppRefreshTask; trigger reconcile on launch + foreground |
| `OPS/AppState.swift` | Own `CalendarMirrorService` reference; wire `handleLogout()` / `handleCompanySwitch()` |
| `OPS/Network/Supabase/Repositories/CalendarUserEventRepository.swift` | Mirror hook on create/update/delete |
| `OPS/Utilities/DataController.swift` (ProjectTask save path; see line 4683 `paired_from_task_id` write) | Mirror hook on date/team-member change |
| `OPS/Network/Sync/RealtimeProcessor.swift` | Mirror hook after applying remote `calendar_user_events` / `project_tasks` changes |
| `OPS/Views/Calendar Tab/Components/UserEventSheet.swift` | Trigger first-event-save permission prompt (post-save, gated on `hasShownMirrorPrompt` UserDefault) |
| `OPS/Views/ScheduleView.swift` | "Mirror disabled" dismissable banner |
| `OPS/Views/Settings/IntegrationsSettingsView.swift` | Add new `CALENDAR` section with iPhone Calendar integration card |
| `OPS/AppDelegate.swift` | Add `event` branch to `handleDeepLink` — routes `ops://event/{id}` to `CalendarUserEvent` view |
| `OPS/Info.plist` | Add `NSCalendarsFullAccessUsageDescription`; add `BGTaskSchedulerPermittedIdentifiers` array with `com.ops.calendar.mirror.refresh` |
| `OPS/OPS.entitlements` | No change (EventKit + BGTaskScheduler need no entitlements) |
| `ops-software-bible/03_DATA_MODELS.md` | Document `CalendarMirrorMap` (client-local table, iOS only) |
| `ops-software-bible/07_SPECIALIZED_FEATURES.md` | New section "iPhone Calendar Mirror" (after Section 16 "Schedule Tab Redesign"); references §3 "Calendar Event Scheduling" for source-of-truth context |

## 9. Testing

Per OPS CLAUDE.md (`xcodebuild -scheme OPS -destination 'generic/platform=iOS'`, no simulator builds):

- Unit tests on hash computation, title formatter, mirror-eligibility predicate (current-user-in-team-members logic).
- Integration: build verification only. Manual device testing for permission flows, iCloud propagation, drift revert, recurring series fan-out.

## 10. Open risks

1. **iCloud color normalization.** Steel-blue may render slightly off in iOS Calendar. Acceptable; document.
2. **`eventIdentifier` instability on CalDAV server roundtrip.** Mitigated by URL fallback in reconciler.
3. **User edit + immediate close.** If the user edits an OPS event in iOS Calendar and closes the app before `.EKEventStoreChanged` fires, the edit lingers until next reconcile (foreground / BGTask). Acceptable.
4. **First-grant backfill latency** for users with many events (heavy project task assignments). N up to a few hundred typically. Show progress toast.

## 11. References

- Apple TN3153 — Adopting EventKit API changes for iOS 17: https://developer.apple.com/documentation/technotes/tn3153-adopting-api-changes-for-eventkit-in-ios-macos-and-watchos
- Apple — Accessing the event store: https://developer.apple.com/documentation/eventkit/accessing-the-event-store
- Apple — `requestFullAccessToEvents`: https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)
- Apple — `EKCalendar.allowsContentModifications` (read-only): https://developer.apple.com/documentation/eventkit/ekcalendar/allowscontentmodifications?language=objc
- Apple — `EKEventStoreChangedNotification`: https://developer.apple.com/documentation/eventkit/ekeventstorechangednotification
- Apple QA1926 — local calendars and iCloud: https://developer.apple.com/library/archive/qa/qa1926/_index.html
- Apple Developer Forum thread 6636 — identifier stability: https://developer.apple.com/forums/thread/6636
- WWDC23 Session 10052 — Discover Calendar and EventKit: https://developer.apple.com/videos/play/wwdc2023/10052/
- Apple — `BGTaskScheduler`: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler
