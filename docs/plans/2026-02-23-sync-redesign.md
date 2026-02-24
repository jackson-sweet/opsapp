# Sync Architecture Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current sync system with Supabase Realtime-first architecture, merge CalendarEvent into ProjectTask, add an offline SyncQueue with field-level merge, and cover all entities (core, pipeline, accounting).

**Architecture:** Supabase Realtime WebSocket pushes server changes to the device instantly via `RealtimeManager`. Local mutations are optimistically applied to SwiftData and queued in `SyncOperation` entities, then drained by `SyncQueue` with exponential backoff and field-level conflict resolution. `SupabaseSyncManager` becomes a thin coordinator.

**Tech Stack:** SwiftUI, SwiftData, Supabase Swift SDK (Realtime V2), PostgreSQL

**Design Doc:** `docs/plans/2026-02-23-sync-redesign-design.md`

---

## Phase 1: Database Migration (Supabase)

### Task 1: Add scheduling columns to project_tasks and migrate data

**Context:** Currently `project_tasks` has a `calendar_event_id` FK pointing to `calendar_events` which holds `start_date`, `end_date`, `duration`. We're merging these into `project_tasks` directly.

**Step 1: Apply the migration**

Run via Supabase MCP `apply_migration` tool:

```sql
-- Add scheduling columns to project_tasks
ALTER TABLE project_tasks
  ADD COLUMN start_date timestamptz,
  ADD COLUMN end_date timestamptz,
  ADD COLUMN duration integer;

-- Migrate existing calendar_event data into their linked tasks
UPDATE project_tasks pt
SET
  start_date = ce.start_date,
  end_date = ce.end_date,
  duration = ce.duration
FROM calendar_events ce
WHERE pt.calendar_event_id = ce.id;

-- Drop the FK column (no longer needed)
ALTER TABLE project_tasks DROP COLUMN calendar_event_id;

-- Drop the calendar_events table
DROP TABLE calendar_events CASCADE;
```

**Step 2: Verify the migration**

Run via Supabase MCP `execute_sql`:

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'project_tasks'
  AND column_name IN ('start_date', 'end_date', 'duration', 'calendar_event_id')
ORDER BY column_name;
```

Expected: `start_date`, `end_date`, `duration` exist. `calendar_event_id` does NOT exist.

```sql
SELECT count(*) FROM project_tasks WHERE start_date IS NOT NULL;
```

Expected: Count matches the number of tasks that had calendar events.

```sql
SELECT table_name FROM information_schema.tables WHERE table_name = 'calendar_events';
```

Expected: Empty result (table dropped).

---

### Task 2: Enable Supabase Realtime on all sync tables

**Step 1: Enable Realtime publication**

Run via Supabase MCP `apply_migration`:

```sql
-- Core tables
ALTER PUBLICATION supabase_realtime ADD TABLE companies;
ALTER PUBLICATION supabase_realtime ADD TABLE users;
ALTER PUBLICATION supabase_realtime ADD TABLE clients;
ALTER PUBLICATION supabase_realtime ADD TABLE sub_clients;
ALTER PUBLICATION supabase_realtime ADD TABLE task_types;
ALTER PUBLICATION supabase_realtime ADD TABLE projects;
ALTER PUBLICATION supabase_realtime ADD TABLE project_tasks;

-- Pipeline tables
ALTER PUBLICATION supabase_realtime ADD TABLE opportunities;
ALTER PUBLICATION supabase_realtime ADD TABLE pipeline_stage_configs;
ALTER PUBLICATION supabase_realtime ADD TABLE stage_transitions;

-- Accounting tables
ALTER PUBLICATION supabase_realtime ADD TABLE estimates;
ALTER PUBLICATION supabase_realtime ADD TABLE invoices;
ALTER PUBLICATION supabase_realtime ADD TABLE line_items;
ALTER PUBLICATION supabase_realtime ADD TABLE payments;
ALTER PUBLICATION supabase_realtime ADD TABLE payment_milestones;
ALTER PUBLICATION supabase_realtime ADD TABLE products;
ALTER PUBLICATION supabase_realtime ADD TABLE tax_rates;

-- Supporting tables
ALTER PUBLICATION supabase_realtime ADD TABLE activities;
ALTER PUBLICATION supabase_realtime ADD TABLE follow_ups;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE project_photos;
ALTER PUBLICATION supabase_realtime ADD TABLE project_notes;
ALTER PUBLICATION supabase_realtime ADD TABLE site_visits;
```

**Step 2: Enable REPLICA IDENTITY FULL for old record access on UPDATE/DELETE**

Run via Supabase MCP `apply_migration`:

```sql
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

**Step 3: Verify Realtime is enabled**

```sql
SELECT schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
ORDER BY tablename;
```

Expected: All 23 tables listed.

---

## Phase 2: SwiftData Model Updates

### Task 3: Merge scheduling fields into ProjectTask model

**Files:**
- Modify: `OPS/DataModels/ProjectTask.swift`

**Step 1: Add scheduling properties to ProjectTask**

After `var sourceEstimateId: String?` (line 115), add:

```swift
    // MARK: - Scheduling (merged from CalendarEvent)
    var startDate: Date?
    var endDate: Date?
    var duration: Int = 1  // Duration in days
```

**Step 2: Remove calendarEventId and calendarEvent relationship**

Remove these lines:
- Line 105: `var calendarEventId: String?`
- Lines 124-125: `@Relationship(deleteRule: .cascade) var calendarEvent: CalendarEvent?`

**Step 3: Update init to remove calendarEventId**

In the init (line 141-160), remove line 156: `self.calendarEventId = nil`

Add to init body:
```swift
        self.startDate = nil
        self.endDate = nil
        self.duration = 1
```

**Step 4: Replace computed date properties**

Replace the computed properties at lines 204-224 with:

```swift
    // MARK: - Computed Properties for Dates

    /// Get scheduled date (now directly on task)
    var scheduledDate: Date? {
        return startDate
    }

    /// Get completion/end date (now directly on task)
    var completionDate: Date? {
        return endDate
    }

    /// Check if task is overdue
    var isOverdue: Bool {
        guard status != .completed && status != .cancelled,
              let end = endDate else { return false }
        return Date() > end
    }

    /// Check if task is happening today
    var isToday: Bool {
        guard let start = startDate else { return false }
        return Calendar.current.isDateInToday(start)
    }
```

**Step 5: Replace calendar event date methods**

Replace `updateCalendarEventDates` (lines 229-236) with:

```swift
    /// Update scheduling dates
    func updateDates(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
        self.duration = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1
    }
```

Remove `syncWithCalendarEvent()` (lines 239-247) entirely — no longer needed.

**Step 6: Add scheduling helper computed properties (migrated from CalendarEvent)**

Add at end of class before closing brace:

```swift
    // MARK: - Scheduling Display Helpers (migrated from CalendarEvent)

    /// Get SwiftUI Color from hex string
    var swiftUIColor: Color {
        return Color(hex: effectiveColor) ?? Color.blue
    }

    /// Check if task spans multiple days
    var isMultiDay: Bool {
        guard let start = startDate, let end = endDate else { return false }
        return !Calendar.current.isDate(start, inSameDayAs: end)
    }

    /// Get all dates this task spans
    var spannedDates: [Date] {
        guard let start = startDate, let end = endDate else { return [] }
        let calendar = Calendar.current
        if calendar.isDate(start, inSameDayAs: end) {
            return [start]
        }
        var dates: [Date] = []
        var currentDate = start
        while currentDate <= end {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        return dates
    }

    /// Get subtitle for calendar display
    var calendarSubtitle: String {
        if let project = project {
            return project.effectiveClientName
        }
        return ""
    }

    /// Get display icon based on task type
    var displayIcon: String? {
        return taskType?.icon
    }
```

**Step 7: Build and verify**

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5
```

Expected: Build will FAIL with CalendarEvent reference errors. This is expected — we fix those in subsequent tasks.

---

### Task 4: Delete CalendarEvent model and enum

**Files:**
- Delete: `OPS/DataModels/CalendarEvent.swift`
- Delete: `OPS/DataModels/Enums/CalendarEventType.swift`

**Step 1: Delete the files**

Remove both files from the project. Xcode project file will need the references removed too.

**Step 2: Remove CalendarEvent from ModelContainer**

In `OPS/OPSApp.swift`, in the schema array (around line 23-50), remove:
```swift
    CalendarEvent.self,
```

---

### Task 5: Create SyncOperation SwiftData model

**Files:**
- Create: `OPS/DataModels/SyncOperation.swift`

**Step 1: Create the model**

```swift
//
//  SyncOperation.swift
//  OPS
//
//  Queued sync operations for offline-first outbound sync.
//

import Foundation
import SwiftData

/// Represents a queued mutation that needs to be synced to Supabase.
@Model
final class SyncOperation {
    var id: UUID
    var entityType: String        // "project", "task", "client", etc.
    var entityId: String          // UUID of the entity
    var operationType: String     // "create", "update", "delete"
    var payload: Data             // JSON-encoded entity fields
    var changedFields: String     // Comma-separated field names that were locally modified
    var createdAt: Date
    var retryCount: Int = 0
    var status: String = "pending" // pending | inProgress | failed | completed
    var lastError: String?

    init(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: Data,
        changedFields: [String]
    ) {
        self.id = UUID()
        self.entityType = entityType
        self.entityId = entityId
        self.operationType = operationType
        self.payload = payload
        self.changedFields = changedFields.joined(separator: ",")
        self.createdAt = Date()
        self.retryCount = 0
        self.status = "pending"
        self.lastError = nil
    }

    // MARK: - Helpers

    func getChangedFields() -> [String] {
        changedFields.isEmpty ? [] : changedFields.components(separatedBy: ",")
    }

    var isPending: Bool { status == "pending" }
    var isInProgress: Bool { status == "inProgress" }
    var isFailed: Bool { status == "failed" }
    var isCompleted: Bool { status == "completed" }
    var canRetry: Bool { retryCount < 5 }
}
```

**Step 2: Add to ModelContainer**

In `OPS/OPSApp.swift`, add to the schema array:
```swift
    SyncOperation.self,
```

---

### Task 6: Update Project computed dates

**Files:**
- Modify: `OPS/DataModels/Project.swift` (lines 384-398)

**Step 1: Replace computed date properties**

Replace `computedStartDate` (lines 384-389) with:
```swift
    var computedStartDate: Date? {
        let taskDates = tasks.compactMap { $0.startDate }
        return taskDates.min()
    }
```

Replace `computedEndDate` (lines 393-398) with:
```swift
    var computedEndDate: Date? {
        let taskDates = tasks.compactMap { $0.endDate }
        return taskDates.max()
    }
```

---

## Phase 3: DTO & Repository Updates

### Task 7: Update ProjectTaskDTO and remove CalendarEventDTO

**Files:**
- Modify: `OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift`
- Modify: `OPS/Network/Supabase/DTOs/CoreEntityConverters.swift`

**Step 1: Update SupabaseProjectTaskDTO**

Replace the struct at lines 230-263 with:

```swift
struct SupabaseProjectTaskDTO: Codable, Identifiable {
    let id: String
    let bubbleId: String?
    let companyId: String
    let projectId: String
    let taskTypeId: String?
    let customTitle: String?
    let taskNotes: String?
    let status: String
    let taskColor: String?
    let displayOrder: Int?
    let teamMemberIds: [String]?
    let sourceLineItemId: String?
    let sourceEstimateId: String?
    // Scheduling fields (merged from calendar_events)
    let startDate: String?
    let endDate: String?
    let duration: Int?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, duration
        case bubbleId         = "bubble_id"
        case companyId        = "company_id"
        case projectId        = "project_id"
        case taskTypeId       = "task_type_id"
        case customTitle      = "custom_title"
        case taskNotes        = "task_notes"
        case taskColor        = "task_color"
        case displayOrder     = "display_order"
        case teamMemberIds    = "team_member_ids"
        case sourceLineItemId = "source_line_item_id"
        case sourceEstimateId = "source_estimate_id"
        case startDate        = "start_date"
        case endDate          = "end_date"
        case deletedAt        = "deleted_at"
    }
}
```

**Step 2: Remove SupabaseCalendarEventDTO**

Delete the entire `SupabaseCalendarEventDTO` struct (lines 265-293 approximately).

**Step 3: Update ProjectTask converter**

In `CoreEntityConverters.swift`, replace the `SupabaseProjectTaskDTO.toModel()` (lines 205-237) with:

```swift
extension SupabaseProjectTaskDTO {
    func toModel() -> ProjectTask {
        let resolvedStatus = TaskStatus(rawValue: status) ?? .booked
        let task = ProjectTask(
            id: id,
            projectId: projectId,
            taskTypeId: taskTypeId ?? "",
            companyId: companyId,
            status: resolvedStatus,
            taskColor: taskColor ?? "#59779F"
        )
        task.customTitle = customTitle
        task.taskNotes = taskNotes
        task.displayOrder = displayOrder ?? 0
        task.teamMemberIdsString = (teamMemberIds ?? []).joined(separator: ",")
        task.sourceLineItemId = sourceLineItemId
        task.sourceEstimateId = sourceEstimateId
        // Scheduling fields (merged from calendar_events)
        task.startDate = startDate.flatMap { SupabaseDate.parse($0) }
        task.endDate = endDate.flatMap { SupabaseDate.parse($0) }
        task.duration = duration ?? 1
        task.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return task
    }
}
```

**Step 4: Remove CalendarEvent converter**

Delete the entire `SupabaseCalendarEventDTO.toModel()` extension (lines 239-271).

---

### Task 8: Remove CalendarEventRepository

**Files:**
- Delete: `OPS/Network/Supabase/Repositories/CalendarEventRepository.swift`

**Step 1: Delete the file**

Remove from project. All calendar event operations will now go through `TaskRepository`.

**Step 2: Update TaskRepository to handle scheduling fields**

In `OPS/Network/Supabase/Repositories/TaskRepository.swift`, ensure `create` and `update` methods include `start_date`, `end_date`, `duration` fields when writing to Supabase. (Check exact method signatures first before modifying.)

---

## Phase 4: New Sync Infrastructure

### Task 9: Create RealtimeManager

**Files:**
- Create: `OPS/Network/Sync/RealtimeManager.swift`

**Step 1: Create the RealtimeManager**

```swift
//
//  RealtimeManager.swift
//  OPS
//
//  Manages Supabase Realtime WebSocket subscriptions.
//  Listens for INSERT/UPDATE/DELETE on all synced tables
//  and upserts changes into SwiftData.
//

import Foundation
import SwiftData
import Supabase
import Realtime

@MainActor
class RealtimeManager: ObservableObject {
    // MARK: - Dependencies
    private let supabase: SupabaseClient
    private var modelContext: ModelContext?
    private var channel: RealtimeChannelV2?

    @Published var isConnected: Bool = false
    @Published var lastEventAt: Date?

    // Company filter — only receive events for user's company
    private var companyId: String?

    // Track last sync timestamp for catch-up on reconnect
    private var lastSyncTimestamp: Date?

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Setup

    func configure(modelContext: ModelContext, companyId: String) {
        self.modelContext = modelContext
        self.companyId = companyId
    }

    // MARK: - Subscribe

    func startListening() async {
        guard let companyId = companyId else {
            print("[REALTIME] No companyId set, cannot subscribe")
            return
        }

        // Monitor connection status
        Task {
            for await status in supabase.realtimeV2.statusChange {
                await MainActor.run {
                    self.isConnected = (status == .subscribed)
                    print("[REALTIME] Connection status: \(status)")
                }
                if status == .subscribed {
                    // Catch up on missed events since last disconnect
                    await catchUpSync()
                }
            }
        }

        let channel = supabase.realtimeV2.channel("company-\(companyId)")

        // Core tables
        await subscribeToTable(channel: channel, table: "projects", companyId: companyId)
        await subscribeToTable(channel: channel, table: "project_tasks", companyId: companyId)
        await subscribeToTable(channel: channel, table: "users", companyId: companyId)
        await subscribeToTable(channel: channel, table: "clients", companyId: companyId)
        await subscribeToTable(channel: channel, table: "sub_clients", companyId: companyId)
        await subscribeToTable(channel: channel, table: "task_types", companyId: companyId)
        await subscribeToTable(channel: channel, table: "companies", filter: "id=eq.\(companyId)")

        // Pipeline tables
        await subscribeToTable(channel: channel, table: "opportunities", companyId: companyId)
        await subscribeToTable(channel: channel, table: "pipeline_stage_configs", companyId: companyId)
        await subscribeToTable(channel: channel, table: "stage_transitions", companyId: companyId)

        // Accounting tables
        await subscribeToTable(channel: channel, table: "estimates", companyId: companyId)
        await subscribeToTable(channel: channel, table: "invoices", companyId: companyId)
        await subscribeToTable(channel: channel, table: "line_items", companyId: companyId)
        await subscribeToTable(channel: channel, table: "payments", companyId: companyId)
        await subscribeToTable(channel: channel, table: "payment_milestones", companyId: companyId)
        await subscribeToTable(channel: channel, table: "products", companyId: companyId)
        await subscribeToTable(channel: channel, table: "tax_rates", companyId: companyId)

        // Supporting tables
        await subscribeToTable(channel: channel, table: "activities", companyId: companyId)
        await subscribeToTable(channel: channel, table: "follow_ups", companyId: companyId)
        await subscribeToTable(channel: channel, table: "notifications", companyId: companyId)
        await subscribeToTable(channel: channel, table: "project_photos", companyId: companyId)
        await subscribeToTable(channel: channel, table: "project_notes", companyId: companyId)
        await subscribeToTable(channel: channel, table: "site_visits", companyId: companyId)

        do {
            try await channel.subscribe()
            self.channel = channel
            print("[REALTIME] Subscribed to all channels")
        } catch {
            print("[REALTIME] Subscribe error: \(error)")
        }
    }

    func stopListening() async {
        if let channel = channel {
            await channel.unsubscribe()
            self.channel = nil
        }
        isConnected = false
        print("[REALTIME] Unsubscribed from all channels")
    }

    // MARK: - Table Subscription Helper

    private func subscribeToTable(channel: RealtimeChannelV2, table: String, companyId: String) async {
        await subscribeToTable(channel: channel, table: table, filter: "company_id=eq.\(companyId)")
    }

    private func subscribeToTable(channel: RealtimeChannelV2, table: String, filter: String) async {
        // NOTE: The exact Supabase Swift SDK API for Realtime V2 subscriptions
        // may differ from this template. Consult the SDK docs and adjust.
        // The pattern is:
        //   channel.onPostgresChange(AnyAction.self, schema: "public", table: table, filter: filter)
        // or the async for-await pattern:
        //   for await change in channel.postgresChange(AnyAction.self, table: table, filter: filter)
        //
        // Implementation will handle INSERT/UPDATE/DELETE and route to the
        // appropriate upsert/delete handler based on table name.
        //
        // Each handler decodes the record JSON into the appropriate DTO,
        // calls toModel(), and upserts into SwiftData.

        Task {
            let changes = channel.postgresChange(AnyAction.self, schema: "public", table: table, filter: filter)
            for await change in changes {
                await handleChange(table: table, change: change)
            }
        }
    }

    // MARK: - Change Handlers

    private func handleChange(table: String, change: AnyAction) async {
        lastEventAt = Date()
        lastSyncTimestamp = Date()

        switch change {
        case .insert(let action):
            print("[REALTIME] INSERT on \(table)")
            await handleUpsert(table: table, record: action.record)
        case .update(let action):
            print("[REALTIME] UPDATE on \(table)")
            await handleUpsert(table: table, record: action.record)
        case .delete(let action):
            print("[REALTIME] DELETE on \(table)")
            await handleDelete(table: table, oldRecord: action.oldRecord)
        }
    }

    private func handleUpsert(table: String, record: [String: AnyJSON]) async {
        guard let context = modelContext else { return }

        // Decode the record JSON into the appropriate DTO and upsert
        // Each table routes to its specific handler.
        // Implementation pattern:
        //   1. Encode record dict to JSON Data
        //   2. Decode to appropriate DTO type
        //   3. Call dto.toModel() to get SwiftData object
        //   4. Fetch existing by ID or insert new
        //   5. Update all fields on existing, or insert new

        // TODO: Implement per-table upsert handlers
        // This is the core work — each table needs a handler that:
        // - Decodes the Realtime JSON payload into the correct DTO
        // - Fetches existing entity by ID from SwiftData
        // - Updates fields if exists, or inserts if new
        // - Saves context
    }

    private func handleDelete(table: String, oldRecord: [String: AnyJSON]) async {
        guard let context = modelContext else { return }

        // Soft-delete: set deletedAt on the entity
        // TODO: Implement per-table soft delete handlers
    }

    // MARK: - Catch-Up Sync

    /// After WebSocket reconnect, fetch all changes since last known timestamp
    private func catchUpSync() async {
        guard let timestamp = lastSyncTimestamp else {
            print("[REALTIME] No last sync timestamp, performing full sync")
            // Delegate to SupabaseSyncManager for full sync
            return
        }
        print("[REALTIME] Catching up since \(timestamp)")
        // TODO: Incremental fetch from each table where updated_at > timestamp
    }
}
```

**Note:** The `handleUpsert` and `handleDelete` methods need per-table implementations. These are large but follow a repetitive pattern. The exact Supabase Swift SDK API should be verified against the SDK version in the project's Package.swift.

---

### Task 10: Create SyncQueue

**Files:**
- Create: `OPS/Network/Sync/SyncQueue.swift`

**Step 1: Create the queue manager**

```swift
//
//  SyncQueue.swift
//  OPS
//
//  Centralized outbound sync queue.
//  Manages SyncOperation entities in SwiftData.
//  Drains FIFO with exponential backoff.
//

import Foundation
import SwiftData
import Combine

@MainActor
class SyncQueue: ObservableObject {
    private var modelContext: ModelContext?
    private var connectivityMonitor: ConnectivityMonitor
    private var drainTask: Task<Void, Never>?
    private var isProcessing = false

    @Published var pendingCount: Int = 0
    @Published var failedCount: Int = 0

    init(connectivityMonitor: ConnectivityMonitor) {
        self.connectivityMonitor = connectivityMonitor
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshCounts()
    }

    // MARK: - Enqueue

    /// Queue a new sync operation
    func enqueue(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: Data,
        changedFields: [String]
    ) {
        guard let context = modelContext else { return }

        // Check for existing pending operation on same entity — coalesce if update
        if operationType == "update" {
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate<SyncOperation> {
                    $0.entityId == entityId &&
                    $0.entityType == entityType &&
                    $0.status == "pending" &&
                    $0.operationType == "update"
                }
            )
            if let existing = try? context.fetch(descriptor).first {
                // Coalesce: merge changed fields and update payload
                let existingFields = Set(existing.getChangedFields())
                let newFields = Set(changedFields)
                let merged = existingFields.union(newFields)
                existing.changedFields = Array(merged).joined(separator: ",")
                existing.payload = payload
                print("[SYNC_QUEUE] Coalesced update for \(entityType)/\(entityId)")
                refreshCounts()
                return
            }
        }

        let operation = SyncOperation(
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payload: payload,
            changedFields: changedFields
        )
        context.insert(operation)
        try? context.save()

        print("[SYNC_QUEUE] Enqueued \(operationType) for \(entityType)/\(entityId)")
        refreshCounts()

        // Try to drain immediately if connected
        if connectivityMonitor.isConnected {
            drainQueue()
        }
    }

    // MARK: - Drain Queue

    func drainQueue() {
        guard !isProcessing else { return }
        guard connectivityMonitor.isConnected else {
            print("[SYNC_QUEUE] Offline, skipping drain")
            return
        }

        drainTask = Task {
            isProcessing = true
            defer { isProcessing = false }

            while let operation = fetchNextPending() {
                operation.status = "inProgress"
                try? modelContext?.save()

                let success = await processOperation(operation)

                if success {
                    operation.status = "completed"
                    print("[SYNC_QUEUE] Completed \(operation.operationType) for \(operation.entityType)/\(operation.entityId)")
                } else {
                    operation.retryCount += 1
                    if operation.canRetry {
                        operation.status = "pending"
                        // Exponential backoff delay
                        let delay = pow(2.0, Double(operation.retryCount))
                        print("[SYNC_QUEUE] Retry #\(operation.retryCount) in \(delay)s for \(operation.entityType)/\(operation.entityId)")
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    } else {
                        operation.status = "failed"
                        print("[SYNC_QUEUE] Failed permanently: \(operation.entityType)/\(operation.entityId) — \(operation.lastError ?? "unknown")")
                    }
                }

                try? modelContext?.save()
                refreshCounts()
            }

            // Cleanup completed operations older than 1 hour
            cleanupCompleted()
        }
    }

    // MARK: - Process Single Operation

    private func processOperation(_ operation: SyncOperation) async -> Bool {
        // TODO: Route to appropriate repository based on entityType
        // Pattern:
        //   1. Decode operation.payload to the entity's DTO
        //   2. Based on operationType:
        //      - "create": call repository.create()
        //      - "update": call repository.update() with changedFields
        //      - "delete": call repository.softDelete()
        //   3. On conflict: use ConflictResolver
        //   4. Return true on success, false on failure
        //   5. Set operation.lastError on failure

        return false // Placeholder
    }

    // MARK: - Helpers

    private func fetchNextPending() -> SyncOperation? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "pending" },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func refreshCounts() {
        guard let context = modelContext else { return }
        let pendingDescriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "pending" || $0.status == "inProgress" }
        )
        let failedDescriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "failed" }
        )
        pendingCount = (try? context.fetchCount(pendingDescriptor)) ?? 0
        failedCount = (try? context.fetchCount(failedDescriptor)) ?? 0
    }

    private func cleanupCompleted() {
        guard let context = modelContext else { return }
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.status == "completed" && $0.createdAt < oneHourAgo
            }
        )
        if let completed = try? context.fetch(descriptor) {
            for op in completed {
                context.delete(op)
            }
            try? context.save()
        }
    }
}
```

---

### Task 11: Create ConflictResolver

**Files:**
- Create: `OPS/Network/Sync/ConflictResolver.swift`

**Step 1: Create the resolver**

```swift
//
//  ConflictResolver.swift
//  OPS
//
//  Field-level merge for sync conflicts.
//  Compares local changedFields vs server updated_at to decide which fields win.
//

import Foundation

struct ConflictResolver {

    /// Merge local changes with server version.
    ///
    /// - Parameters:
    ///   - localPayload: JSON dict of local entity state
    ///   - serverPayload: JSON dict of server entity state
    ///   - changedFields: Fields the user actually modified locally
    ///   - serverUpdatedAt: Server's updated_at timestamp
    ///   - localChangedAt: When the local change was made
    /// - Returns: Merged JSON dict to push to server
    static func merge(
        localPayload: [String: Any],
        serverPayload: [String: Any],
        changedFields: [String],
        serverUpdatedAt: Date?,
        localChangedAt: Date
    ) -> [String: Any] {
        var merged = serverPayload

        for field in changedFields {
            guard let localValue = localPayload[field] else { continue }

            // If server hasn't been updated since our change, local wins
            if let serverTime = serverUpdatedAt, localChangedAt > serverTime {
                merged[field] = localValue
            }
            // If server was updated but didn't change this specific field,
            // local still wins (field-level, not record-level)
            else if let serverValue = serverPayload[field],
                    areEqual(localPayload[field], serverPayload[field]) == false {
                // Both changed this field — last-write-wins fallback
                if let serverTime = serverUpdatedAt, localChangedAt > serverTime {
                    merged[field] = localValue
                }
                // else server wins (it's newer)
            } else {
                // Server didn't change this field — local wins
                merged[field] = localValue
            }
        }

        return merged
    }

    private static func areEqual(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        guard let a = a, let b = b else { return false }

        switch (a, b) {
        case (let a as String, let b as String): return a == b
        case (let a as Int, let b as Int): return a == b
        case (let a as Double, let b as Double): return a == b
        case (let a as Bool, let b as Bool): return a == b
        default: return false
        }
    }
}
```

---

## Phase 5: Rewrite Sync Coordinator

### Task 12: Rewrite SupabaseSyncManager as thin coordinator

**Files:**
- Rewrite: `OPS/Network/Sync/SupabaseSyncManager.swift`

**Context:** The current 1451-line file handles everything: sync orchestration, entity CRUD, upsert logic, relationship linking. The new version delegates inbound to RealtimeManager and outbound to SyncQueue. It keeps the initial full-sync capability for first launch and the entity CRUD methods (which now go through SyncQueue).

**This is a large task.** The key changes:

1. Remove all `sync*()` methods that fetch from Supabase (RealtimeManager handles inbound)
2. Keep `upsert*()` helpers (used by RealtimeManager's handlers)
3. Keep entity CRUD methods but have them enqueue to SyncQueue instead of calling repositories directly
4. Keep `linkAllRelationships()` (still needed after initial sync)
5. Add RealtimeManager and SyncQueue as dependencies
6. Add `initialSync()` method for first-time data load

**The exact rewrite is too large for inline code here.** The pattern for each CRUD method becomes:

```swift
// Before (direct API call):
func updateProjectStatus(projectId: String, status: Status) async {
    // 1. Update local SwiftData
    // 2. Call projectRepo.update() directly
}

// After (queue-based):
func updateProjectStatus(projectId: String, status: Status) async {
    // 1. Update local SwiftData (optimistic)
    // 2. Enqueue SyncOperation via syncQueue
    syncQueue.enqueue(
        entityType: "project",
        entityId: projectId,
        operationType: "update",
        payload: encodePayload(["status": status.rawValue]),
        changedFields: ["status"]
    )
}
```

---

### Task 13: Update DataController

**Files:**
- Modify: `OPS/Utilities/DataController.swift`

**Key changes:**
1. Remove `calendarEventsDidChange` published property (line 35)
2. Replace sync initialization to use RealtimeManager + SyncQueue
3. Remove race-condition-prone app launch sync cascade
4. Remove all Bubble API references in comments
5. Simplify `performAppLaunchSync()` to:
   - Call initial sync (fetch all data once)
   - Start RealtimeManager listening
   - Set up SyncQueue with connectivity monitoring

---

## Phase 6: Update All Views (CalendarEvent → ProjectTask)

### Task 14: Update calendar/scheduling views

**Files to modify** (replace CalendarEvent references with ProjectTask):

1. `OPS/ViewModels/CalendarViewModel.swift` — Replace `CalendarEvent` queries with `ProjectTask` queries filtered by `startDate != nil`
2. `OPS/Views/Calendar Tab/Components/CalendarEventCard.swift` — Accept `ProjectTask` instead of `CalendarEvent`
3. `OPS/Views/Calendar Tab/Components/CalendarHeaderView.swift` — Update type references
4. `OPS/Views/Calendar Tab/Components/WeekDayCell.swift` — Update type references
5. `OPS/Views/Calendar Tab/ProjectViews/DayEventsSheet.swift` — Replace CalendarEvent with ProjectTask
6. `OPS/Views/Calendar Tab/ProjectViews/ProjectListView.swift` — Update references

**Pattern for each view:**
- Replace `CalendarEvent` type → `ProjectTask`
- Replace `event.startDate` → `task.startDate` (now direct)
- Replace `event.endDate` → `task.endDate` (now direct)
- Replace `event.color` → `task.effectiveColor`
- Replace `event.title` → `task.displayTitle`
- Replace `event.task?.project` → `task.project`
- Replace `event.spannedDates` → `task.spannedDates`
- Replace `event.isMultiDay` → `task.isMultiDay`
- Replace `event.subtitle` → `task.calendarSubtitle`
- Replace `event.displayIcon` → `task.displayIcon`

---

### Task 15: Update form sheets and detail views

**Files to modify:**

1. `OPS/Views/Components/Scheduling/CalendarSchedulerSheet.swift` — Update to work with ProjectTask dates directly
2. `OPS/Views/Components/Event/EventCarousel.swift` — Replace CalendarEvent with ProjectTask
3. `OPS/Views/Components/Project/TaskDetailsView.swift` — Remove calendarEvent references
4. `OPS/Views/Components/Tasks/TaskListView.swift` — Remove calendarEvent references
5. `OPS/Views/JobBoard/ProjectFormSheet.swift` — Update scheduling to use task dates
6. `OPS/Views/JobBoard/ProjectManagementSheets.swift` — Remove CalendarEvent references
7. `OPS/Views/JobBoard/TaskFormSheet.swift` — Update to set dates directly on task
8. `OPS/Views/JobBoard/UniversalJobBoardCard.swift` — Update date display

---

### Task 16: Update home and map views

**Files to modify:**

1. `OPS/Views/Home/HomeContentView.swift` — Replace CalendarEvent references
2. `OPS/Views/Home/HomeView.swift` — Replace CalendarEvent references
3. `OPS/Map/Views/MapContainer.swift` — Remove CalendarEvent references
4. `OPS/Map/Views/ProjectDetailsCard.swift` — Remove CalendarEvent references
5. `OPS/Map/Views/SafeMapContainer.swift` — Remove CalendarEvent references

---

### Task 17: Update tutorial demo data

**Files to modify:**

1. `OPS/Tutorial/Data/TutorialDemoDataManager.swift` — Replace CalendarEvent creation with setting dates directly on ProjectTask

---

## Phase 7: ImageSyncManager Update

### Task 18: Replace UserDefaults with SwiftData queue

**Files:**
- Modify: `OPS/Network/ImageSyncManager.swift`

**Key changes:**
1. Remove all `UserDefaults` persistence for pending uploads
2. Use `SyncOperation` with `entityType: "image"` for queue persistence
3. Keep S3 upload logic but queue through SyncQueue
4. Remove `loadPendingUploads()` and `cleanupUserDefaultsImageData()` methods

---

## Phase 8: Documentation

### Task 19: Update API_AND_SYNC.md

**Files:**
- Rewrite: `API_AND_SYNC.md`

**Key changes:**
1. Remove all Bubble references
2. Document new architecture: RealtimeManager (inbound) + SyncQueue (outbound)
3. Document all 23 synced tables
4. Document SyncOperation model and queue drain logic
5. Document conflict resolution strategy
6. Document the CalendarEvent → ProjectTask merge

---

## Phase 9: Build & Verify

### Task 20: Build, fix compilation errors, and verify

**Step 1: Full build**

```bash
cd "/Users/jacksonsweet/Desktop/OPS LTD./OPS" && xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | grep -E "error:|BUILD"
```

**Step 2: Fix any remaining CalendarEvent references**

Search exhaustively:
```bash
grep -rn "CalendarEvent" OPS/OPS/ --include="*.swift" | grep -v ".build/"
```

All results should be zero after Phase 6 is complete.

**Step 3: Verify Realtime connection**

Launch app in simulator, check console for:
```
[REALTIME] Subscribed to all channels
[REALTIME] Connection status: subscribed
```

**Step 4: Verify data loading**

Check console for initial sync completing and data appearing in the app.

---

## Dependency Order Summary

```
Task 1 (DB: merge calendar_events) → Task 2 (DB: enable Realtime)
    ↓
Task 3 (ProjectTask model) → Task 4 (Delete CalendarEvent) → Task 5 (SyncOperation model)
    ↓
Task 6 (Project computed dates) → Task 7 (DTOs) → Task 8 (Repositories)
    ↓
Task 9 (RealtimeManager) → Task 10 (SyncQueue) → Task 11 (ConflictResolver)
    ↓
Task 12 (Rewrite SupabaseSyncManager) → Task 13 (Update DataController)
    ↓
Tasks 14-17 (Update all views) — can be parallelized
    ↓
Task 18 (ImageSyncManager) → Task 19 (Documentation) → Task 20 (Build & verify)
```

Tasks 14, 15, 16, 17 are independent and can be done in parallel.
