# Sync Architecture Redesign — Design Document

**Date**: 2026-02-23
**Status**: Approved
**Goal**: Replace current sync system with Supabase Realtime-first architecture, merge CalendarEvent into ProjectTask, add offline queue with field-level merge, and cover all entities (core, pipeline, accounting).

---

## 1. Problem Statement

- No data loading in-app currently (critical bug)
- Current sync has race conditions at app launch (multiple triggers fire simultaneously)
- No conflict resolution (last-write-wins without detection)
- No exponential backoff (fixed 180s retry timer)
- Image sync queue uses UserDefaults (4MB limit risk)
- CalendarEvent and ProjectTask are unnecessarily separate entities
- Only core entities synced — pipeline and accounting data not included
- Documentation (API_AND_SYNC.md) is outdated — still describes Bubble architecture

## 2. Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Sync direction | Supabase Realtime (server-push via WebSocket) | Instant updates, best UX for field crews |
| Offline queue | SwiftData `SyncOperation` entities | Crash-safe, no size limits, consistent with data layer |
| Conflict resolution | Field-level merge with LWW fallback | Preserves non-conflicting offline edits |
| CalendarEvent | Merge into ProjectTask | Simplifies data model, reduces sync entities |
| Scope | All entities (core + pipeline + accounting) | Complete coverage |

## 3. Entities to Sync

### Core (7 tables)
| Table | Realtime | Offline Queue | Notes |
|-------|----------|---------------|-------|
| `companies` | Yes | Yes | Company settings, subscription info |
| `users` | Yes | Yes | Team members, roles |
| `clients` | Yes | Yes | Client contacts |
| `sub_clients` | Yes | Yes | Client sub-contacts |
| `task_types` | Yes | Yes | Task categories/colors |
| `projects` | Yes | Yes | Primary entity |
| `project_tasks` | Yes | Yes | Tasks + scheduling (merged with calendar_events) |

### Pipeline (3 tables)
| Table | Realtime | Offline Queue | Notes |
|-------|----------|---------------|-------|
| `opportunities` | Yes | Yes | Leads/deals in pipeline |
| `pipeline_stage_configs` | Yes | Yes | Stage definitions |
| `stage_transitions` | Yes | Yes | Stage change history |

### Accounting (7 tables)
| Table | Realtime | Offline Queue | Notes |
|-------|----------|---------------|-------|
| `estimates` | Yes | Yes | Quotes/estimates |
| `invoices` | Yes | Yes | Invoices |
| `line_items` | Yes | Yes | Line items for estimates/invoices |
| `payments` | Yes | Yes | Payment records |
| `payment_milestones` | Yes | Yes | Payment schedule |
| `products` | Yes | Yes | Product catalog |
| `tax_rates` | Yes | Yes | Tax rate config |

### Supporting (6 tables)
| Table | Realtime | Offline Queue | Notes |
|-------|----------|---------------|-------|
| `activities` | Yes | Yes | Activity log |
| `follow_ups` | Yes | Yes | Follow-up reminders |
| `notifications` | Yes | No (read-only) | Push notifications |
| `project_photos` | Yes | Yes | Photo metadata (images via Storage) |
| `project_notes` | Yes | Yes | Project notes |
| `site_visits` | Yes | Yes | Site visit records |

### Config/Log (not Realtime)
| Table | Sync Method | Notes |
|-------|-------------|-------|
| `accounting_connections` | Fetch on demand | External service config |
| `accounting_sync_log` | Fetch on demand | Audit log |

**Total: 23 Realtime tables + 2 fetch-on-demand**

## 4. Architecture Components

### New Files

| File | Purpose |
|------|---------|
| `RealtimeManager.swift` | Subscribes to Supabase Realtime on all tables filtered by `company_id`. Handles INSERT/UPDATE/DELETE → SwiftData upsert. |
| `SyncQueue.swift` | Centralized outbound queue. Drains `SyncOperation` entities FIFO with exponential backoff. |
| `SyncOperation.swift` | SwiftData model for queued mutations. |
| `ConflictResolver.swift` | Field-level merge using `changedFields` vs server `updated_at`. |

### Files to Rewrite

| File | Changes |
|------|---------|
| `SupabaseSyncManager.swift` | Thin coordinator delegating to RealtimeManager (inbound) + SyncQueue (outbound). |
| `DataController.swift` | Remove all direct sync logic, race-condition-prone launch cascade, and Bubble references. |
| `ImageSyncManager.swift` | Replace UserDefaults persistence with SwiftData-backed queue. |

### Data Model Changes

| File | Changes |
|------|---------|
| `ProjectTask.swift` | Add `startDate`, `endDate`, `duration`. Remove `calendarEvent` relationship. |
| `CalendarEvent.swift` | **Delete entirely.** All scheduling reads from ProjectTask. |
| `CoreEntityDTOs.swift` | Update `ProjectTaskDTO` with scheduling fields. Remove `CalendarEventDTO`. Add DTOs for pipeline/accounting entities. |
| New repository files | Repositories for any pipeline/accounting entities not yet covered. |

### Files to Keep (Minor Updates)

| File | Changes |
|------|---------|
| `SupabaseService.swift` | Add `realtimeV2` accessor convenience property |
| Existing `*Repository.swift` | Keep for outbound CRUD; add any missing ones |

## 5. Data Flow

### Inbound (Server → Device)

```
1. App Launch → RealtimeManager subscribes to all table channels
2. Initial full sync: fetch all entities where updated_at > lastSyncTimestamp
3. Supabase Realtime pushes INSERT/UPDATE/DELETE via WebSocket
4. RealtimeManager decodes DTO → converts to SwiftData model → upsert
5. SwiftUI views auto-update via @Query
6. On WebSocket disconnect → Supabase SDK auto-reconnects
7. On reconnect → incremental sync (updated_at > lastSyncTimestamp) for missed events
```

### Outbound (Device → Server)

```
1. User action → optimistic SwiftData update (instant UI)
2. Create SyncOperation in SwiftData queue with changedFields list
3. If online → drain queue immediately (FIFO, dependency-ordered)
4. If offline → queue persists in SwiftData until network restores
5. On network restore → drain queue with exponential backoff
6. On conflict → field-level merge using updated_at comparison
7. On permanent failure (5 retries) → mark failed, surface to user
```

### Conflict Resolution (Field-Level Merge)

```
Example: Two users edit the same project

User A (offline): changes { status: "active", notes: "Updated locally" }
User B (online):  changes { status: "completed" }

When User A comes online:
1. Fetch server version of project
2. Compare changedFields from SyncOperation vs server updated_at
3. "notes" → only A changed it → A's version wins
4. "status" → both changed → server updated_at is newer → server wins
5. Final merge: { status: "completed", notes: "Updated locally" }
6. Push merged result to Supabase
```

## 6. SyncOperation SwiftData Model

```swift
@Model
class SyncOperation {
    var id: UUID
    var entityType: String        // "project", "task", "client", "opportunity", etc.
    var entityId: String          // UUID of the entity
    var operationType: String     // "create", "update", "delete"
    var payload: Data             // JSON-encoded full entity
    var changedFields: [String]   // Fields that were locally modified
    var createdAt: Date
    var retryCount: Int = 0
    var status: String = "pending" // pending | inProgress | failed | completed
    var lastError: String?
}
```

Queue drain rules:
- FIFO by `createdAt`
- Dependency-aware: creates before updates, all before deletes
- Exponential backoff: 2s → 4s → 8s → 16s → 32s (max 5 retries)
- Batch coalescing: multiple updates to same entity → merge into single operation

## 7. Supabase Database Migration

```sql
-- Phase 1: Merge calendar_events into project_tasks
ALTER TABLE project_tasks ADD COLUMN start_date timestamptz;
ALTER TABLE project_tasks ADD COLUMN end_date timestamptz;
ALTER TABLE project_tasks ADD COLUMN duration integer;

UPDATE project_tasks pt SET
    start_date = ce.start_date,
    end_date = ce.end_date,
    duration = ce.duration
FROM calendar_events ce
WHERE pt.calendar_event_id = ce.id;

ALTER TABLE project_tasks DROP COLUMN calendar_event_id;
DROP TABLE calendar_events;

-- Phase 2: Enable Realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE
    companies, users, clients, sub_clients, task_types,
    projects, project_tasks,
    opportunities, pipeline_stage_configs, stage_transitions,
    estimates, invoices, line_items, payments, payment_milestones,
    products, tax_rates,
    activities, follow_ups, notifications,
    project_photos, project_notes, site_visits;

-- Phase 3: Enable REPLICA IDENTITY FULL for old record access on UPDATE/DELETE
ALTER TABLE companies REPLICA IDENTITY FULL;
ALTER TABLE users REPLICA IDENTITY FULL;
ALTER TABLE clients REPLICA IDENTITY FULL;
ALTER TABLE sub_clients REPLICA IDENTITY FULL;
ALTER TABLE task_types REPLICA IDENTITY FULL;
ALTER TABLE projects REPLICA IDENTITY FULL;
ALTER TABLE project_tasks REPLICA IDENTITY FULL;
ALTER TABLE opportunities REPLICA IDENTITY FULL;
ALTER TABLE pipeline_stage_configs REPLICA IDENTITY FULL;
ALTER TABLE stage_transitions REPLICA IDENTITY FULL;
ALTER TABLE estimates REPLICA IDENTITY FULL;
ALTER TABLE invoices REPLICA IDENTITY FULL;
ALTER TABLE line_items REPLICA IDENTITY FULL;
ALTER TABLE payments REPLICA IDENTITY FULL;
ALTER TABLE payment_milestones REPLICA IDENTITY FULL;
ALTER TABLE products REPLICA IDENTITY FULL;
ALTER TABLE tax_rates REPLICA IDENTITY FULL;
ALTER TABLE activities REPLICA IDENTITY FULL;
ALTER TABLE follow_ups REPLICA IDENTITY FULL;
ALTER TABLE notifications REPLICA IDENTITY FULL;
ALTER TABLE project_photos REPLICA IDENTITY FULL;
ALTER TABLE project_notes REPLICA IDENTITY FULL;
ALTER TABLE site_visits REPLICA IDENTITY FULL;
```

## 8. Implementation Order

1. **Database migration** — merge calendar_events → project_tasks, enable Realtime
2. **SwiftData model updates** — merge CalendarEvent into ProjectTask, create SyncOperation model
3. **DTOs** — update ProjectTaskDTO, add pipeline/accounting DTOs
4. **Repositories** — add any missing repositories for pipeline/accounting entities
5. **RealtimeManager** — subscribe to all 23 tables, handle inbound events
6. **SyncQueue** — outbound mutations with exponential backoff and coalescing
7. **ConflictResolver** — field-level merge logic
8. **Rewrite SupabaseSyncManager** — thin coordinator
9. **Update DataController** — remove old sync logic and Bubble references
10. **Update all views** — replace CalendarEvent references with ProjectTask scheduling fields
11. **ImageSyncManager** — SwiftData-backed upload queue
12. **Update API_AND_SYNC.md** — accurate documentation reflecting new architecture

## 9. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| WebSocket disconnects in poor field connectivity | Auto-reconnect built into Supabase SDK + incremental catch-up sync |
| Large number of Realtime subscriptions (23 tables) | Single channel with multiple table listeners; Supabase handles multiplexing |
| CalendarEvent merge breaks scheduling views | All scheduling views already read through task relationships; update direct references |
| Field-level merge complexity | Start with LWW fallback; field-merge only for high-conflict entities (projects, tasks) |
| Migration data loss | Run migration on branch first; verify with row counts before/after |
