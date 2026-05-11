# iPhone Calendar Mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mirror OPS `CalendarUserEvent` (personal + time off) and assigned `ProjectTask` rows into a dedicated `OPS` calendar in the user's iPhone Calendar app, one-way (OPS → device), with reconcile-and-revert drift handling.

**Architecture:** New `CalendarMirrorService` (`@MainActor` singleton) wraps `EKEventStore`. A SwiftData side-table `CalendarMirrorMap` records `opsId → ekEventIdentifier + contentHash`. Repository save paths fan out to `mirrorEvent(opsId:source:)`. Reconcile runs on foreground, `.EKEventStoreChanged` (debounced), Supabase sync completion, and opportunistic `BGAppRefreshTask`. iOS 17+ `requestFullAccessToEvents()` only.

**Tech Stack:** Swift 6 (Swift Concurrency, `@MainActor`), SwiftUI, SwiftData (`@Model`, `Schema(versionedSchema:)`), EventKit (`EKEventStore`, `EKCalendar`, `EKEvent`), BackgroundTasks (`BGTaskScheduler`, `BGAppRefreshTask`), Combine (debounce on `.EKEventStoreChanged`).

**Spec:** `docs/superpowers/specs/2026-05-10-iphone-calendar-mirror-design.md`

---

## Phase 0 — Bookkeeping

### Task 0.1: Working directory + branch check

**Files:** none

- [ ] **Step 1: Confirm working directory**

Run from a shell with cwd `/Users/jacksonsweet/Projects/OPS/ops-ios`:

```bash
pwd
```

Expected: `/Users/jacksonsweet/Projects/OPS/ops-ios`

- [ ] **Step 2: Verify deployment target**

Run:

```bash
grep IPHONEOS_DEPLOYMENT_TARGET OPS.xcodeproj/project.pbxproj | sort -u
```

Expected: `IPHONEOS_DEPLOYMENT_TARGET = 17.6;` and/or `18.2;` — both iOS 17+. Plan assumes iOS 17 APIs only.

- [ ] **Step 3: Verify the iOS app builds clean before changes**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **` at end. If failure unrelated to this plan, surface to user before proceeding.

---

## Phase 1 — Data layer (CalendarMirrorMap)

### Task 1.1: Create `CalendarMirrorMap` SwiftData model

**Files:**
- Create: `OPS/DataModels/CalendarMirrorMap.swift`

- [ ] **Step 1: Write the model file**

```swift
//
//  CalendarMirrorMap.swift
//  OPS
//
//  Side-table mapping OPS event IDs to EKEvent identifiers for the
//  iPhone Calendar Mirror feature. Client-local only — not synced to
//  Supabase. Cleared on logout/company switch/disable.
//

import Foundation
import SwiftData

enum MirrorSource: String, Codable {
    case calendarUserEvent
    case projectTask
    // siteVisit reserved for future addition once iOS SiteVisit sync ships
}

@Model
final class CalendarMirrorMap {
    @Attribute(.unique) var opsId: String
    var ekEventIdentifier: String
    var sourceType: String       // MirrorSource.rawValue
    var contentHash: String      // SHA256 of canonical "title|start|end|notes|allDay|status"
    var lastMirroredAt: Date

    init(opsId: String, ekEventIdentifier: String, sourceType: MirrorSource, contentHash: String) {
        self.opsId = opsId
        self.ekEventIdentifier = ekEventIdentifier
        self.sourceType = sourceType.rawValue
        self.contentHash = contentHash
        self.lastMirroredAt = Date()
    }

    var source: MirrorSource? { MirrorSource(rawValue: sourceType) }
}
```

- [ ] **Step 2: Build to verify model compiles in isolation**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add OPS/DataModels/CalendarMirrorMap.swift
git commit -m "Add CalendarMirrorMap SwiftData side-table for calendar mirror"
```

### Task 1.2: Register `CalendarMirrorMap` in the active schema (V4 stage)

**Files:**
- Read: `OPS/DataModels/Migrations/OPSSchemaCommon.swift`
- Read: `OPS/DataModels/Migrations/OPSSchemaV4.swift`
- Read: `OPS/DataModels/Migrations/OPSMigrationPlan.swift`
- Modify: whichever of those is the active schema declaration

- [ ] **Step 1: Read the migration plan to find the active schema**

Run:

```bash
grep -n "currentSchema\|active\|VersionedSchema\|stages" OPS/DataModels/Migrations/OPSMigrationPlan.swift | head -20
grep -n "static var models" OPS/DataModels/Migrations/OPSSchemaV4.swift OPS/DataModels/Migrations/OPSSchemaV3.swift OPS/DataModels/Migrations/OPSSchemaCommon.swift | head -20
```

Identify the schema that `OPSApp.swift` uses (`OPSSchemaV3` per `OPSApp.swift:44`; verify V4 isn't already active).

- [ ] **Step 2: Add `CalendarMirrorMap.self` to the active schema's `models` array**

Open the file identified in Step 1. Locate the `static var models: [any PersistentModel.Type]` declaration (or equivalent versioned-schema models list). Add `CalendarMirrorMap.self` at the end of that list.

If the schema is V3 and `CalendarMirrorMap` represents a structural addition that requires a new schema stage, instead:
1. Add `CalendarMirrorMap.self` to `OPSSchemaV4.models`.
2. In `OPSMigrationPlan.swift`, ensure V4 is the current stage with a lightweight migration from V3 (additive — no destructive change).
3. Update `OPSApp.swift:44` to `Schema(versionedSchema: OPSSchemaV4.self)`.

If V4 is already the active schema, just add `CalendarMirrorMap.self` to V4's models.

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`. If migration error, the V3→V4 stage may need a `MigrationStage.lightweight(fromVersion: OPSSchemaV3.self, toVersion: OPSSchemaV4.self)` entry in `OPSMigrationPlan.stages`.

- [ ] **Step 4: Commit**

```bash
git add OPS/DataModels/Migrations
git add OPS/OPSApp.swift
git commit -m "Register CalendarMirrorMap in SwiftData schema"
```

### Task 1.3: Register `CalendarMirrorMap` in `DataController.deleteAll` wipe

**Files:**
- Modify: `OPS/Utilities/DataController.swift`

- [ ] **Step 1: Find existing deleteAll calls (line ~1280)**

Run:

```bash
grep -n "deleteAll(FetchDescriptor<" OPS/Utilities/DataController.swift | head -10
```

Confirm the pattern. There is one near line 1280 for `SiteVisit`; we follow that same pattern.

- [ ] **Step 2: Add `CalendarMirrorMap` to the wipe list**

In the same logout-time wipe block (the function that contains `deleteAll(FetchDescriptor<SiteVisit>(), label: "SiteVisit", in: context)`), add immediately after:

```swift
deleteAll(FetchDescriptor<CalendarMirrorMap>(), label: "CalendarMirrorMap", in: context)
```

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add OPS/Utilities/DataController.swift
git commit -m "Wipe CalendarMirrorMap on logout via DataController.deleteAll"
```

---

## Phase 2 — Pure utilities (title formatter, content hash, window predicate)

### Task 2.1: Add `CalendarMirrorContent` (title + hash + body + URL builder)

**Files:**
- Create: `OPS/Services/CalendarMirror/CalendarMirrorContent.swift`

- [ ] **Step 1: Create directory**

Run:

```bash
mkdir -p OPS/Services/CalendarMirror
```

- [ ] **Step 2: Write the content builder**

```swift
//
//  CalendarMirrorContent.swift
//  OPS
//
//  Pure functions: convert CalendarUserEvent / ProjectTask into the
//  title, body, URL, all-day flag, and stable canonical hash used by
//  the mirror writer + reconciler.
//

import Foundation
import CryptoKit

struct MirroredEventPayload: Equatable {
    let opsId: String
    let source: MirrorSource
    let title: String
    let body: String
    let url: URL
    let isAllDay: Bool
    let startDate: Date
    let endDate: Date

    /// Stable hash of all user-visible fields. Used to dedup writes and
    /// to detect drift (user-edited the EKEvent in iOS Calendar).
    var canonicalHash: String {
        let canonical = "\(title)|\(startDate.timeIntervalSince1970)|\(endDate.timeIntervalSince1970)|\(body)|\(isAllDay ? "1" : "0")"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum CalendarMirrorContent {

    // MARK: - CalendarUserEvent

    static func payload(for event: CalendarUserEvent) -> MirroredEventPayload {
        let title = title(for: event)
        let body = body(address: event.address, notes: event.notes)
        let url = URL(string: "ops://event/\(event.id)")!
        return MirroredEventPayload(
            opsId: event.id,
            source: .calendarUserEvent,
            title: title,
            body: body,
            url: url,
            isAllDay: event.allDay,
            startDate: event.startDate,
            endDate: event.endDate
        )
    }

    private static func title(for event: CalendarUserEvent) -> String {
        let raw = event.title.isEmpty ? "(Untitled)" : event.title
        switch event.eventType {
        case .personal:
            return raw
        case .timeOff:
            switch event.eventStatus {
            case .approved, .none:
                return "Time Off — \(raw)"
            case .pending:
                return "[Pending] \(raw)"
            case .denied:
                return "[Denied] \(raw)"
            }
        }
    }

    // MARK: - ProjectTask

    /// `project` and `taskType` are passed in because the iOS model relationships
    /// may not be eagerly loaded. The caller resolves them from the model context.
    static func payload(for task: ProjectTask, projectDisplayName: String, taskTypeDisplay: String, address: String?) -> MirroredEventPayload? {
        guard let start = task.startDate, let end = task.endDate else { return nil }

        let title = "\(projectDisplayName) — \(taskTypeDisplay)"
        let body = body(address: address, notes: task.taskNotes)
        let url = URL(string: "ops://projects/\(task.projectId)/tasks/\(task.id)")!

        let isAllDay = task.duration > 1
        let (resolvedStart, resolvedEnd) = resolveTaskDates(task: task, isAllDay: isAllDay, start: start, end: end)

        return MirroredEventPayload(
            opsId: task.id,
            source: .projectTask,
            title: title,
            body: body,
            url: url,
            isAllDay: isAllDay,
            startDate: resolvedStart,
            endDate: resolvedEnd
        )
    }

    private static func resolveTaskDates(task: ProjectTask, isAllDay: Bool, start: Date, end: Date) -> (Date, Date) {
        if isAllDay { return (start, end) }
        // Single-day task: combine startDate with startTime/endTime
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let dayComps = cal.dateComponents([.year, .month, .day], from: start)
        let startTimeComps = cal.dateComponents([.hour, .minute], from: task.startTime)
        let endTimeComps = cal.dateComponents([.hour, .minute], from: task.endTime)
        var combinedStart = DateComponents()
        combinedStart.year = dayComps.year
        combinedStart.month = dayComps.month
        combinedStart.day = dayComps.day
        combinedStart.hour = startTimeComps.hour
        combinedStart.minute = startTimeComps.minute
        var combinedEnd = combinedStart
        combinedEnd.hour = endTimeComps.hour
        combinedEnd.minute = endTimeComps.minute
        return (cal.date(from: combinedStart) ?? start, cal.date(from: combinedEnd) ?? end)
    }

    // MARK: - Body

    private static func body(address: String?, notes: String?) -> String {
        var lines: [String] = []
        if let a = address, !a.isEmpty { lines.append(a) }
        if let n = notes, !n.isEmpty { lines.append(n) }
        lines.append("// OPS · view in app")
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add OPS/Services/CalendarMirror/CalendarMirrorContent.swift
git commit -m "Add CalendarMirrorContent: payload builder + canonical hash"
```

### Task 2.2: Add window + eligibility predicates

**Files:**
- Create: `OPS/Services/CalendarMirror/CalendarMirrorEligibility.swift`

- [ ] **Step 1: Write the eligibility module**

```swift
//
//  CalendarMirrorEligibility.swift
//  OPS
//
//  Pure predicates for "should this row be in the mirror right now?"
//  Window: past 30 days → future 12 months from a reference date.
//

import Foundation

enum CalendarMirrorEligibility {

    /// The mirror window: [now - 30d, now + 365d].
    static func windowBounds(now: Date = Date()) -> (lower: Date, upper: Date) {
        let cal = Calendar.current
        let lower = cal.date(byAdding: .day, value: -30, to: now) ?? now
        let upper = cal.date(byAdding: .day, value: 365, to: now) ?? now
        return (lower, upper)
    }

    static func isInWindow(start: Date, end: Date, now: Date = Date()) -> Bool {
        let (lower, upper) = windowBounds(now: now)
        return end >= lower && start <= upper
    }

    // MARK: - CalendarUserEvent

    static func isEligible(event: CalendarUserEvent, currentUserId: String, now: Date = Date()) -> Bool {
        guard event.deletedAt == nil else { return false }
        guard isInWindow(start: event.startDate, end: event.endDate, now: now) else { return false }

        let isOwner = event.userId == currentUserId
        let isTarget = (event.teamMemberIds ?? []).contains(currentUserId)
        return isOwner || isTarget
    }

    // MARK: - ProjectTask

    static func isEligible(task: ProjectTask, currentUserId: String, now: Date = Date()) -> Bool {
        guard task.deletedAt == nil else { return false }
        guard let start = task.startDate, let end = task.endDate else { return false }
        guard isInWindow(start: start, end: end, now: now) else { return false }
        return task.schedulingTeamMemberIds.contains(currentUserId)
    }
}
```

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. If `task.deletedAt` is not a property on `ProjectTask`, look it up in `OPS/DataModels/ProjectTask.swift`:

```bash
grep -n "deletedAt" OPS/DataModels/ProjectTask.swift
```

Use whichever soft-delete predicate the model exposes (the spec confirmed `deletedAt` exists on this model at line 165).

- [ ] **Step 3: Commit**

```bash
git add OPS/Services/CalendarMirror/CalendarMirrorEligibility.swift
git commit -m "Add CalendarMirrorEligibility predicates for window + membership"
```

### Task 2.3: Unit tests for content + eligibility

**Files:**
- Create: `OPSTests/CalendarMirror/CalendarMirrorContentTests.swift`
- Create: `OPSTests/CalendarMirror/CalendarMirrorEligibilityTests.swift`

- [ ] **Step 1: Create directory + content tests file**

Run:

```bash
mkdir -p OPSTests/CalendarMirror
```

Write `OPSTests/CalendarMirror/CalendarMirrorContentTests.swift`:

```swift
import XCTest
import SwiftData
@testable import OPS

final class CalendarMirrorContentTests: XCTestCase {

    func test_personalEvent_titleIsRawTitle() throws {
        let e = makeUserEvent(type: .personal, status: .none, title: "Dentist")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.title, "Dentist")
    }

    func test_personalEvent_emptyTitleFallsBack() throws {
        let e = makeUserEvent(type: .personal, status: .none, title: "")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.title, "(Untitled)")
    }

    func test_timeOff_approvedHasTimeOffPrefix() throws {
        let e = makeUserEvent(type: .timeOff, status: .approved, title: "Cottage")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.title, "Time Off — Cottage")
    }

    func test_timeOff_pendingHasPendingPrefix() throws {
        let e = makeUserEvent(type: .timeOff, status: .pending, title: "Cottage")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.title, "[Pending] Cottage")
    }

    func test_timeOff_deniedHasDeniedPrefix() throws {
        let e = makeUserEvent(type: .timeOff, status: .denied, title: "Cottage")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.title, "[Denied] Cottage")
    }

    func test_url_isEventDeepLink() throws {
        let e = makeUserEvent(type: .personal, status: .none, title: "Dentist")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.url, URL(string: "ops://event/\(e.id)"))
    }

    func test_canonicalHash_isStableForSameContent() throws {
        let e1 = makeUserEvent(type: .personal, status: .none, title: "Dentist")
        let e2 = makeUserEvent(type: .personal, status: .none, title: "Dentist", id: e1.id)
        XCTAssertEqual(
            CalendarMirrorContent.payload(for: e1).canonicalHash,
            CalendarMirrorContent.payload(for: e2).canonicalHash
        )
    }

    func test_canonicalHash_changesWhenTitleChanges() throws {
        let e1 = makeUserEvent(type: .personal, status: .none, title: "Dentist")
        let e2 = makeUserEvent(type: .personal, status: .none, title: "Dentist 2", id: e1.id)
        XCTAssertNotEqual(
            CalendarMirrorContent.payload(for: e1).canonicalHash,
            CalendarMirrorContent.payload(for: e2).canonicalHash
        )
    }

    // MARK: - Helpers

    private func makeUserEvent(
        type: CalendarUserEventType,
        status: CalendarUserEventStatus,
        title: String,
        id: String = UUID().uuidString
    ) -> CalendarUserEvent {
        let e = CalendarUserEvent(
            id: id,
            userId: "user-1",
            companyId: "company-1",
            type: type,
            title: title,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_086_400),
            allDay: true
        )
        e.status = status.rawValue
        return e
    }
}
```

- [ ] **Step 2: Write eligibility tests file**

Write `OPSTests/CalendarMirror/CalendarMirrorEligibilityTests.swift`:

```swift
import XCTest
@testable import OPS

final class CalendarMirrorEligibilityTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func test_windowBounds_extend30DaysBack_365DaysForward() {
        let (lower, upper) = CalendarMirrorEligibility.windowBounds(now: now)
        XCTAssertLessThan(lower, now)
        XCTAssertGreaterThan(upper, now)
        XCTAssertEqual(Int(now.timeIntervalSince(lower) / 86_400), 30)
        XCTAssertEqual(Int(upper.timeIntervalSince(now) / 86_400), 365)
    }

    func test_isInWindow_eventInsideWindow_isTrue() {
        let start = now
        let end = now.addingTimeInterval(3600)
        XCTAssertTrue(CalendarMirrorEligibility.isInWindow(start: start, end: end, now: now))
    }

    func test_isInWindow_eventEntirelyTooFarPast_isFalse() {
        let start = now.addingTimeInterval(-200 * 86_400)
        let end = now.addingTimeInterval(-100 * 86_400)
        XCTAssertFalse(CalendarMirrorEligibility.isInWindow(start: start, end: end, now: now))
    }

    func test_isInWindow_eventEntirelyTooFarFuture_isFalse() {
        let start = now.addingTimeInterval(400 * 86_400)
        let end = now.addingTimeInterval(401 * 86_400)
        XCTAssertFalse(CalendarMirrorEligibility.isInWindow(start: start, end: end, now: now))
    }

    func test_userEventEligible_ownerInWindow_isTrue() {
        let e = makeEvent(userId: "u1", teamMemberIds: nil, deletedAt: nil)
        XCTAssertTrue(CalendarMirrorEligibility.isEligible(event: e, currentUserId: "u1", now: now))
    }

    func test_userEventEligible_targetUser_isTrue() {
        let e = makeEvent(userId: "u2", teamMemberIds: ["u1", "u3"], deletedAt: nil)
        XCTAssertTrue(CalendarMirrorEligibility.isEligible(event: e, currentUserId: "u1", now: now))
    }

    func test_userEventEligible_admin_notIn_teamMemberIds_isFalse() {
        let e = makeEvent(userId: "u2", teamMemberIds: ["u3"], deletedAt: nil)
        XCTAssertFalse(CalendarMirrorEligibility.isEligible(event: e, currentUserId: "u1", now: now))
    }

    func test_userEventEligible_softDeleted_isFalse() {
        let e = makeEvent(userId: "u1", teamMemberIds: nil, deletedAt: Date())
        XCTAssertFalse(CalendarMirrorEligibility.isEligible(event: e, currentUserId: "u1", now: now))
    }

    private func makeEvent(userId: String, teamMemberIds: [String]?, deletedAt: Date?) -> CalendarUserEvent {
        let e = CalendarUserEvent(
            id: UUID().uuidString,
            userId: userId,
            companyId: "c1",
            type: .timeOff,
            title: "x",
            startDate: now,
            endDate: now.addingTimeInterval(3600),
            allDay: true,
            teamMemberIds: teamMemberIds
        )
        e.deletedAt = deletedAt
        return e
    }
}
```

- [ ] **Step 3: Build to verify tests compile**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build-for-testing 2>&1 | tail -20
```

Expected: `** TEST BUILD SUCCEEDED **` (or `** BUILD SUCCEEDED **` if the scheme combines).

If failure: fix test signatures to match actual `CalendarUserEvent` initializer (the iOS model has the `teamMemberIds:` init parameter — confirmed in spec).

- [ ] **Step 4: Commit**

```bash
git add OPSTests/CalendarMirror
git commit -m "Add unit tests for CalendarMirror content + eligibility"
```

---

## Phase 3 — CalendarMirrorService skeleton

### Task 3.1: Create the service shell with permission API

**Files:**
- Create: `OPS/Services/CalendarMirrorService.swift`

- [ ] **Step 1: Write the service skeleton**

```swift
//
//  CalendarMirrorService.swift
//  OPS
//
//  One-way mirror from OPS schedule rows to a dedicated "OPS"
//  calendar in the user's iPhone Calendar. iOS 17+.
//

import Foundation
import EventKit
import SwiftData
import Combine
import UIKit

@MainActor
final class CalendarMirrorService: ObservableObject {
    static let shared = CalendarMirrorService()

    // MARK: - State

    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorizationStatus: EKAuthorizationStatus

    private let store: EKEventStore
    private var cancellables = Set<AnyCancellable>()

    private let enabledKey = "ops.calendar.mirror.enabled"
    private let calendarIdKey = "ops.calendar.mirror.calendarId"
    private let hasShownPromptKey = "ops.calendar.mirror.hasShownPrompt"

    // MARK: - Init

    private init() {
        self.store = EKEventStore()
        self.isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        subscribeToEventStoreChanges()
        subscribeToBecomeActive()
    }

    // MARK: - Public surface

    var hasShownPrompt: Bool {
        get { UserDefaults.standard.bool(forKey: hasShownPromptKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasShownPromptKey) }
    }

    func requestAccessIfNeeded() async -> Bool {
        let current = EKEventStore.authorizationStatus(for: .event)
        self.authorizationStatus = current
        if current == .fullAccess { return true }
        if current == .denied || current == .restricted { return false }
        do {
            let granted = try await store.requestFullAccessToEvents()
            self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return false
        }
    }

    func enable() async throws {
        let granted = await requestAccessIfNeeded()
        guard granted else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            self.isEnabled = false
            return
        }
        _ = try ensureCalendar()
        UserDefaults.standard.set(true, forKey: enabledKey)
        self.isEnabled = true
        await reconcileAll()
    }

    func disable() async {
        deleteCalendarIfPresent()
        UserDefaults.standard.set(false, forKey: enabledKey)
        self.isEnabled = false
        clearAllMapRows()
    }

    func mirrorEvent(opsId: String, source: MirrorSource) async {
        // Implemented in Phase 4
    }

    func unmirrorEvent(opsId: String) async {
        // Implemented in Phase 4
    }

    func reconcileAll() async {
        // Implemented in Phase 5
    }

    func handleLogout() async {
        await disable()
        UserDefaults.standard.removeObject(forKey: hasShownPromptKey)
    }

    func handleCompanySwitch() async {
        await handleLogout()
    }

    // MARK: - Internal helpers (Phase 3 scope)

    /// Returns the OPS calendar. Creates it if missing.
    @discardableResult
    func ensureCalendar() throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: calendarIdKey),
           let cal = store.calendar(withIdentifier: id) {
            return cal
        }
        let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
        guard let source else { throw CalendarMirrorError.noUsableSource }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = "OPS"
        cal.source = source
        cal.cgColor = UIColor(OPSStyle.Colors.opsAccent).cgColor
        try store.saveCalendar(cal, commit: true)
        UserDefaults.standard.set(cal.calendarIdentifier, forKey: calendarIdKey)
        return cal
    }

    private func deleteCalendarIfPresent() {
        guard let id = UserDefaults.standard.string(forKey: calendarIdKey),
              let cal = store.calendar(withIdentifier: id) else {
            UserDefaults.standard.removeObject(forKey: calendarIdKey)
            return
        }
        try? store.removeCalendar(cal, commit: true)
        UserDefaults.standard.removeObject(forKey: calendarIdKey)
    }

    private func clearAllMapRows() {
        guard let context = ModelContainerHolder.shared?.mainContext else { return }
        let descriptor = FetchDescriptor<CalendarMirrorMap>()
        if let rows = try? context.fetch(descriptor) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
    }

    // MARK: - Subscriptions

    private func subscribeToEventStoreChanges() {
        NotificationCenter.default
            .publisher(for: .EKEventStoreChanged, object: store)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.reconcileAll()
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToBecomeActive() {
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAuthorizationStatus()
                    if self?.isEnabled == true, self?.authorizationStatus == .fullAccess {
                        await self?.reconcileAll()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func refreshAuthorizationStatus() {
        let s = EKEventStore.authorizationStatus(for: .event)
        self.authorizationStatus = s
        if s != .fullAccess, isEnabled {
            UserDefaults.standard.set(false, forKey: enabledKey)
            self.isEnabled = false
        }
    }
}

enum CalendarMirrorError: Error {
    case noUsableSource
    case calendarMissing
    case notAuthorized
}
```

- [ ] **Step 2: Add a model-container holder helper if one doesn't already exist**

Check first:

```bash
grep -rn "ModelContainerHolder\|sharedModelContext\|mainContext" OPS/Utilities OPS/OPSApp.swift 2>/dev/null | head -10
```

If a global accessor exists (e.g., `DataController.shared.context`), replace the `ModelContainerHolder.shared?.mainContext` reference in the service with that accessor. If not, create a minimal holder:

Create `OPS/Services/CalendarMirror/ModelContainerHolder.swift`:

```swift
import Foundation
import SwiftData

/// Lightweight bridge so non-View, non-injected services can reach the
/// app's main SwiftData ModelContainer. OPSApp.swift sets `shared` after
/// constructing the container.
@MainActor
enum ModelContainerHolder {
    static var shared: ModelContainer?
}

extension ModelContainer {
    var mainContext: ModelContext { ModelContext(self) }
}
```

Note: if `ModelContainer.mainContext` is already a stored property in SwiftData on this iOS version, drop the extension. Build to confirm. If `ModelContext(container)` constructs a per-call context (it does), prefer:

```swift
extension ModelContainerHolder {
    @MainActor static var mainContext: ModelContext? {
        guard let c = shared else { return nil }
        return c.mainContext
    }
}
```

— actually use `container.mainContext` which IS a property on `ModelContainer` in SwiftUI/SwiftData.

- [ ] **Step 3: Wire the holder in `OPSApp.swift`**

In `OPS/OPSApp.swift`, after `sharedModelContainer` is constructed, set the holder. Find the `init()` or the `body` `.task` where container access happens (use line search):

```bash
grep -n "sharedModelContainer\|init(\|@main" OPS/OPSApp.swift | head -10
```

Add in the appropriate spot (likely right after `var sharedModelContainer: ModelContainer = { ... }()`):

```swift
init() {
    // ... existing init body ...
    ModelContainerHolder.shared = sharedModelContainer
}
```

If `OPSApp` has no `init()`, add one. If it has one already, append the assignment.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add OPS/Services/CalendarMirrorService.swift OPS/Services/CalendarMirror/ModelContainerHolder.swift OPS/OPSApp.swift
git commit -m "Add CalendarMirrorService skeleton with EKEventStore + permission API"
```

### Task 3.2: Add `NSCalendarsFullAccessUsageDescription` to Info.plist

**Files:**
- Modify: `OPS/Info.plist`

- [ ] **Step 1: Add the usage description**

Open `OPS/Info.plist`. Find the `<key>NSContactsUsageDescription</key>` block and add immediately after the matching `</string>`:

```xml
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>OPS syncs your scheduled work, time off, and personal events to your iPhone Calendar so you can see them alongside your personal life.</string>
```

- [ ] **Step 2: Add `BGTaskSchedulerPermittedIdentifiers`**

Search Info.plist for an existing `BGTaskSchedulerPermittedIdentifiers` key:

```bash
grep -A3 "BGTaskSchedulerPermittedIdentifiers" OPS/Info.plist
```

If absent, add at top level (sibling of `UIRequiredDeviceCapabilities`):

```xml
	<key>BGTaskSchedulerPermittedIdentifiers</key>
	<array>
		<string>com.ops.calendar.mirror.refresh</string>
	</array>
```

If present, append the string `com.ops.calendar.mirror.refresh` to the existing array.

- [ ] **Step 3: Build to confirm plist is valid**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add OPS/Info.plist
git commit -m "Add NSCalendarsFullAccessUsageDescription + BGTask identifier to Info.plist"
```

---

## Phase 4 — Single-event mirror (mirrorEvent / unmirrorEvent for CalendarUserEvent)

### Task 4.1: Implement `mirrorEvent` and `unmirrorEvent` for `CalendarUserEvent`

**Files:**
- Modify: `OPS/Services/CalendarMirrorService.swift`

- [ ] **Step 1: Add fetch helpers + write logic**

Replace the Phase 3 stub bodies for `mirrorEvent(opsId:source:)` and `unmirrorEvent(opsId:)` with real implementations. Also add the supporting private fetchers.

In `CalendarMirrorService`, append/replace:

```swift
// MARK: - Mirror write path

func mirrorEvent(opsId: String, source: MirrorSource) async {
    guard isEnabled, authorizationStatus == .fullAccess else { return }
    guard let context = ModelContainerHolder.shared?.mainContext else { return }
    let calendar: EKCalendar
    do { calendar = try ensureCalendar() } catch { return }

    guard let payload = buildPayload(opsId: opsId, source: source, context: context),
          let currentUserId = DataController.shared.currentUser?.id else {
        // Source missing or no current user — treat as unmirror
        await unmirrorEvent(opsId: opsId)
        return
    }

    // Eligibility gate
    if !sourceIsEligible(opsId: opsId, source: source, currentUserId: currentUserId, context: context) {
        await unmirrorEvent(opsId: opsId)
        return
    }

    let mapDesc = FetchDescriptor<CalendarMirrorMap>(predicate: #Predicate { $0.opsId == opsId })
    let existing = try? context.fetch(mapDesc).first

    if let row = existing, let ek = store.event(withIdentifier: row.ekEventIdentifier) {
        // Existing — update if hash changed
        if row.contentHash != payload.canonicalHash {
            apply(payload: payload, to: ek, calendar: calendar)
            try? store.save(ek, span: .thisEvent, commit: true)
            row.contentHash = payload.canonicalHash
            row.lastMirroredAt = Date()
            try? context.save()
        }
    } else {
        // Create new
        let ek = EKEvent(eventStore: store)
        ek.calendar = calendar
        apply(payload: payload, to: ek, calendar: calendar)
        do {
            try store.save(ek, span: .thisEvent, commit: true)
            let row = CalendarMirrorMap(
                opsId: payload.opsId,
                ekEventIdentifier: ek.eventIdentifier,
                sourceType: source,
                contentHash: payload.canonicalHash
            )
            context.insert(row)
            try? context.save()
        } catch {
            // Swallow; reconcile retries on next pass.
        }
    }
}

func unmirrorEvent(opsId: String) async {
    guard let context = ModelContainerHolder.shared?.mainContext else { return }
    let mapDesc = FetchDescriptor<CalendarMirrorMap>(predicate: #Predicate { $0.opsId == opsId })
    guard let row = try? context.fetch(mapDesc).first else { return }
    if let ek = store.event(withIdentifier: row.ekEventIdentifier) {
        try? store.remove(ek, span: .thisEvent, commit: true)
    }
    context.delete(row)
    try? context.save()
}

private func apply(payload: MirroredEventPayload, to ek: EKEvent, calendar: EKCalendar) {
    ek.calendar = calendar
    ek.title = payload.title
    ek.notes = payload.body
    ek.url = payload.url
    ek.isAllDay = payload.isAllDay
    ek.startDate = payload.startDate
    ek.endDate = payload.endDate
}

private func buildPayload(opsId: String, source: MirrorSource, context: ModelContext) -> MirroredEventPayload? {
    switch source {
    case .calendarUserEvent:
        let desc = FetchDescriptor<CalendarUserEvent>(predicate: #Predicate { $0.id == opsId })
        guard let event = try? context.fetch(desc).first else { return nil }
        return CalendarMirrorContent.payload(for: event)
    case .projectTask:
        let desc = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == opsId })
        guard let task = try? context.fetch(desc).first else { return nil }
        let projectDisplay = task.project?.clientSurnameOrName ?? task.project?.name ?? "Project"
        let taskTypeDisplay = task.taskType?.display ?? "Task"
        let address = task.project?.fullAddress
        return CalendarMirrorContent.payload(for: task, projectDisplayName: projectDisplay, taskTypeDisplay: taskTypeDisplay, address: address)
    }
}

private func sourceIsEligible(opsId: String, source: MirrorSource, currentUserId: String, context: ModelContext) -> Bool {
    switch source {
    case .calendarUserEvent:
        let desc = FetchDescriptor<CalendarUserEvent>(predicate: #Predicate { $0.id == opsId })
        guard let event = try? context.fetch(desc).first else { return false }
        return CalendarMirrorEligibility.isEligible(event: event, currentUserId: currentUserId)
    case .projectTask:
        let desc = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == opsId })
        guard let task = try? context.fetch(desc).first else { return false }
        return CalendarMirrorEligibility.isEligible(task: task, currentUserId: currentUserId)
    }
}
```

- [ ] **Step 2: Verify the `Project` accessors `clientSurnameOrName`, `name`, `fullAddress` exist**

Run:

```bash
grep -n "clientSurnameOrName\|var name\|fullAddress" OPS/DataModels/Project.swift 2>/dev/null | head -10
```

Adjust the field names to match whatever the actual `Project` model exposes. If `clientSurnameOrName` doesn't exist, fall back to: `task.project?.client?.lastName ?? task.project?.name ?? "Project"`. The point is producing a short, readable label.

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`. Fix any model accessor mismatches.

- [ ] **Step 4: Commit**

```bash
git add OPS/Services/CalendarMirrorService.swift
git commit -m "Implement single-event mirror + unmirror for CalendarUserEvent and ProjectTask"
```

---

## Phase 5 — Reconcile-and-revert

### Task 5.1: Implement `reconcileAll()`

**Files:**
- Modify: `OPS/Services/CalendarMirrorService.swift`

- [ ] **Step 1: Replace `reconcileAll()` stub with full algorithm**

Replace the empty `reconcileAll()` with:

```swift
func reconcileAll() async {
    guard isEnabled, authorizationStatus == .fullAccess else { return }
    guard let context = ModelContainerHolder.shared?.mainContext else { return }
    guard let currentUserId = DataController.shared.currentUser?.id else { return }

    let calendar: EKCalendar
    do { calendar = try ensureCalendar() } catch { return }

    let (lower, upper) = CalendarMirrorEligibility.windowBounds()

    // 1. Iterate map rows; remove stale, refresh drifted.
    let allMap = (try? context.fetch(FetchDescriptor<CalendarMirrorMap>())) ?? []
    var liveOpsIds = Set<String>()

    for row in allMap {
        guard let source = row.source else {
            context.delete(row); continue
        }
        let stillEligible = sourceIsEligible(opsId: row.opsId, source: source, currentUserId: currentUserId, context: context)
        let ek = store.event(withIdentifier: row.ekEventIdentifier)

        if !stillEligible {
            if let ek { try? store.remove(ek, span: .thisEvent, commit: true) }
            context.delete(row)
            continue
        }

        guard let payload = buildPayload(opsId: row.opsId, source: source, context: context) else {
            if let ek { try? store.remove(ek, span: .thisEvent, commit: true) }
            context.delete(row)
            continue
        }

        if let ek {
            // EKEvent present — check drift and hash
            let driftedFields = ek.title != payload.title
                || ek.startDate != payload.startDate
                || ek.endDate != payload.endDate
                || ek.isAllDay != payload.isAllDay
                || (ek.notes ?? "") != payload.body
            let hashChanged = row.contentHash != payload.canonicalHash
            if driftedFields || hashChanged {
                apply(payload: payload, to: ek, calendar: calendar)
                try? store.save(ek, span: .thisEvent, commit: true)
                row.contentHash = payload.canonicalHash
                row.lastMirroredAt = Date()
            }
        } else {
            // EKEvent missing — user deleted in iOS Calendar. Recreate.
            let new = EKEvent(eventStore: store)
            apply(payload: payload, to: new, calendar: calendar)
            do {
                try store.save(new, span: .thisEvent, commit: true)
                row.ekEventIdentifier = new.eventIdentifier
                row.contentHash = payload.canonicalHash
                row.lastMirroredAt = Date()
            } catch {
                context.delete(row)
                continue
            }
        }
        liveOpsIds.insert(row.opsId)
    }

    // 2. Backfill: any eligible source row with no map entry.
    let userEvents = (try? context.fetch(FetchDescriptor<CalendarUserEvent>())) ?? []
    for e in userEvents where CalendarMirrorEligibility.isEligible(event: e, currentUserId: currentUserId) {
        if liveOpsIds.contains(e.id) { continue }
        await mirrorEvent(opsId: e.id, source: .calendarUserEvent)
    }
    let tasks = (try? context.fetch(FetchDescriptor<ProjectTask>())) ?? []
    for t in tasks where CalendarMirrorEligibility.isEligible(task: t, currentUserId: currentUserId) {
        if liveOpsIds.contains(t.id) { continue }
        await mirrorEvent(opsId: t.id, source: .projectTask)
    }

    // 3. Orphan sweep — events in OPS calendar with no map entry.
    let predicate = store.predicateForEvents(withStart: lower, end: upper, calendars: [calendar])
    let events = store.events(matching: predicate)
    let knownIds = Set(((try? context.fetch(FetchDescriptor<CalendarMirrorMap>())) ?? []).map { $0.ekEventIdentifier })
    for ek in events where !knownIds.contains(ek.eventIdentifier) {
        // Try to recover via url; otherwise delete.
        if let url = ek.url, url.scheme == "ops", url.host == "event" {
            let id = String(url.path.dropFirst())
            let desc = FetchDescriptor<CalendarUserEvent>(predicate: #Predicate { $0.id == id })
            if (try? context.fetch(desc).first) != nil {
                let row = CalendarMirrorMap(
                    opsId: id,
                    ekEventIdentifier: ek.eventIdentifier,
                    sourceType: .calendarUserEvent,
                    contentHash: ""  // forces next reconcile to refresh
                )
                context.insert(row)
                continue
            }
        }
        try? store.remove(ek, span: .thisEvent, commit: true)
    }

    try? context.save()
}
```

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`. Fix any `DataController.shared.currentUser` accessor mismatches (verify with `grep -n "currentUser" OPS/Utilities/DataController.swift | head -5`).

- [ ] **Step 3: Commit**

```bash
git add OPS/Services/CalendarMirrorService.swift
git commit -m "Implement reconcile-and-revert in CalendarMirrorService"
```

---

## Phase 6 — Mirror trigger hooks

### Task 6.1: Hook `CalendarUserEventRepository` save/delete paths

**Files:**
- Modify: `OPS/Network/Supabase/Repositories/CalendarUserEventRepository.swift`

- [ ] **Step 1: Read the file to identify save/update/delete sites**

Run:

```bash
grep -n "func " OPS/Network/Supabase/Repositories/CalendarUserEventRepository.swift
```

Look for the methods that:
- Create a new event (e.g. `upsert`, `create`)
- Update an existing event
- Soft-delete an event (set `deleted_at`)

The mirror hook fires *after* a successful Supabase write (so we don't mirror unsaved work).

- [ ] **Step 2: Add post-success mirror calls**

For each create/update method, add after the successful `.execute()`:

```swift
await CalendarMirrorService.shared.mirrorEvent(opsId: event.id, source: .calendarUserEvent)
```

For each delete method, add after success:

```swift
await CalendarMirrorService.shared.unmirrorEvent(opsId: event.id)
```

Where `event.id` is the row's UUID string.

If the repository operates on raw IDs (no model object in scope), use the available id parameter.

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add OPS/Network/Supabase/Repositories/CalendarUserEventRepository.swift
git commit -m "Mirror CalendarUserEvent changes to iPhone Calendar on repo save/delete"
```

### Task 6.2: Hook `DataController.updateTaskSchedule` and `updateTaskTeamMembers`

**Files:**
- Modify: `OPS/Utilities/DataController.swift`

- [ ] **Step 1: Locate hook sites**

Run:

```bash
grep -n "func updateTaskSchedule\|func updateTaskTeamMembers\|func updateTaskStatus" OPS/Utilities/DataController.swift
```

Sites identified (per spec exploration): `updateTaskSchedule` at line ~3751; `updateTaskTeamMembers` at line ~4112.

- [ ] **Step 2: Add mirror call at end of `updateTaskSchedule`**

Find the body of `func updateTaskSchedule(task: ProjectTask, startDate: Date, endDate: Date, manualEdit: Bool = true) async throws`. After `task.needsSync = true` and the SwiftData save (around line ~3770), insert:

```swift
await CalendarMirrorService.shared.mirrorEvent(opsId: task.id, source: .projectTask)
```

- [ ] **Step 3: Add mirror call at end of `updateTaskTeamMembers`**

Find `func updateTaskTeamMembers(task: ProjectTask, memberIds: [String]) async throws`. After `task.needsSync = true` (around line ~4131), insert the same mirror call:

```swift
await CalendarMirrorService.shared.mirrorEvent(opsId: task.id, source: .projectTask)
```

- [ ] **Step 4: Handle soft-delete sites**

Run:

```bash
grep -n "task.deletedAt = \|tasks.deletedAt" OPS/Utilities/DataController.swift | head -10
```

For each soft-delete site, insert after the `deletedAt` assignment:

```swift
await CalendarMirrorService.shared.unmirrorEvent(opsId: task.id)
```

If the soft-delete is in a synchronous method, wrap the call in `Task { @MainActor in ... }` so we don't have to change the method signature.

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add OPS/Utilities/DataController.swift
git commit -m "Mirror ProjectTask schedule/team/delete changes to iPhone Calendar"
```

### Task 6.3: Hook `RealtimeProcessor` for remote-originated changes

**Files:**
- Modify: `OPS/Network/Sync/RealtimeProcessor.swift`

- [ ] **Step 1: Find the per-table apply branches**

Run:

```bash
grep -n "case \"calendar_user_events\"\|case \"project_tasks\"" OPS/Network/Sync/RealtimeProcessor.swift
```

Confirmed sites (per earlier exploration): lines 330, 435, 460, 554, 586 for `calendar_user_events`. Find equivalents for `project_tasks`.

- [ ] **Step 2: Insert mirror calls after each successful apply**

After each branch where a `CalendarUserEvent` or `ProjectTask` row is inserted/updated/soft-deleted from a realtime payload, add (per branch type):

For `INSERT`/`UPDATE`:

```swift
Task { @MainActor in
    await CalendarMirrorService.shared.mirrorEvent(opsId: rowId, source: .calendarUserEvent)
}
```

(or `.projectTask`)

For `DELETE` (or `deleted_at` flip):

```swift
Task { @MainActor in
    await CalendarMirrorService.shared.unmirrorEvent(opsId: rowId)
}
```

Use whichever local variable holds the row's UUID string in each branch.

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add OPS/Network/Sync/RealtimeProcessor.swift
git commit -m "Mirror realtime calendar/task changes to iPhone Calendar"
```

---

## Phase 7 — Permission UX

### Task 7.1: Create the permission prompt sheet view

**Files:**
- Create: `OPS/Views/CalendarMirror/CalendarMirrorPromptSheet.swift`

- [ ] **Step 1: Create directory**

Run:

```bash
mkdir -p OPS/Views/CalendarMirror
```

- [ ] **Step 2: Write the sheet**

```swift
//
//  CalendarMirrorPromptSheet.swift
//  OPS
//
//  First-event-save explainer for the iPhone Calendar Mirror feature.
//  Shown at most once per install; gated on hasShownPrompt UserDefault.
//

import SwiftUI

struct CalendarMirrorPromptSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("// MIRROR TO iPHONE CALENDAR")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.top, 32)

            Text("See your OPS schedule alongside your personal calendar. One-way: edits in OPS, sync to your phone.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    Task { await dismissNotNow() }
                } label: {
                    Text("NOT NOW")
                        .font(OPSStyle.Typography.bodyBold)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(OPSStyle.Colors.divider, lineWidth: 1)
                        )
                }
                .disabled(isWorking)

                Button {
                    Task { await enableMirror() }
                } label: {
                    Text(isWorking ? "WORKING…" : "ENABLE")
                        .font(OPSStyle.Typography.bodyBold)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundColor(.white)
                        .background(OPSStyle.Colors.opsAccent)
                        .cornerRadius(8)
                }
                .disabled(isWorking)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .background(OPSStyle.Colors.backgroundGradient.ignoresSafeArea())
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }

    @MainActor
    private func enableMirror() async {
        isWorking = true
        defer { isWorking = false }
        CalendarMirrorService.shared.hasShownPrompt = true
        do {
            try await CalendarMirrorService.shared.enable()
        } catch {
            // Silent — Settings card surfaces failure state.
        }
        isPresented = false
    }

    @MainActor
    private func dismissNotNow() async {
        CalendarMirrorService.shared.hasShownPrompt = true
        isPresented = false
    }
}
```

- [ ] **Step 3: Verify the OPSStyle tokens used exist**

Run:

```bash
grep -n "captionBold\|backgroundGradient\|opsAccent\|primaryText\|secondaryText\|divider\|bodyBold\|body\b" OPS/Styles/OPSStyle.swift | head -20
```

Adjust references to whichever names actually exist (e.g., `Typography.body` may be `Typography.bodyRegular` — adapt to the real names).

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add OPS/Views/CalendarMirror/CalendarMirrorPromptSheet.swift
git commit -m "Add CalendarMirrorPromptSheet for first-event-save permission ask"
```

### Task 7.2: Trigger the prompt after first `CalendarUserEvent` save

**Files:**
- Modify: `OPS/Views/Calendar Tab/Components/UserEventSheet.swift`

- [ ] **Step 1: Read the save path in UserEventSheet**

Run:

```bash
grep -n "func save\|onTap\|presentation\|dismiss(\|saveEvent\|onSave" OPS/Views/Calendar\ Tab/Components/UserEventSheet.swift | head -20
```

Identify the function that runs after a successful save.

- [ ] **Step 2: Add state + presentation**

In `UserEventSheet`, add a state var:

```swift
@State private var showingMirrorPrompt = false
```

Add this `.sheet` modifier to the outer view container (top-level of the body):

```swift
.sheet(isPresented: $showingMirrorPrompt) {
    CalendarMirrorPromptSheet(isPresented: $showingMirrorPrompt)
}
```

- [ ] **Step 3: Trigger after successful save**

In the save function, after the Supabase + SwiftData save succeeds and BEFORE the sheet dismisses, gate the prompt on the UserDefault:

```swift
if !CalendarMirrorService.shared.hasShownPrompt
    && CalendarMirrorService.shared.authorizationStatus == .notDetermined {
    showingMirrorPrompt = true
} else {
    isPresented = false
}
```

If `showingMirrorPrompt = true` ran instead of dismissing, the sheet view stays open underneath; when the prompt dismisses (`isPresented = false` inside the prompt), the user must still tap close on the event sheet. Acceptable; the prompt is a one-time interruption.

If the existing save path needs to actually dismiss after prompt resolves, you can pass a `onPromptResolved: () -> Void` closure into `CalendarMirrorPromptSheet` and have the parent dismiss in its completion.

- [ ] **Step 4: Build + manual test note**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. Mark this for manual device test (the prompt cannot fire in unit tests).

- [ ] **Step 5: Commit**

```bash
git add OPS/Views/Calendar\ Tab/Components/UserEventSheet.swift
git commit -m "Show CalendarMirrorPromptSheet after first user event save"
```

---

## Phase 8 — Settings + Banner + Deep Link

### Task 8.1: Add `CALENDAR` section to `IntegrationsSettingsView`

**Files:**
- Modify: `OPS/Views/Settings/IntegrationsSettingsView.swift`

- [ ] **Step 1: Read the existing structure**

Run:

```bash
sed -n '1,140p' OPS/Views/Settings/IntegrationsSettingsView.swift
```

Identify `integrationCard(name:description:iconName:isConnected:onConnect:)` and the `ACCOUNTING` header pattern.

- [ ] **Step 2: Add the new section**

Above the `ACCOUNTING` header (find the `VStack(spacing: 24)` body), add a new section block:

```swift
// CALENDAR header
Text("CALENDAR")
    .font(OPSStyle.Typography.captionBold)
    .foregroundColor(OPSStyle.Colors.secondaryText)
    .frame(maxWidth: .infinity, alignment: .leading)

// iPhone Calendar
integrationCard(
    name: "iPhone Calendar",
    description: "Sync OPS events to your iPhone Calendar — time off, personal events, and your assigned work.",
    iconName: "calendar",
    isConnected: mirrorService.isEnabled && mirrorService.authorizationStatus == .fullAccess,
    onConnect: { handleMirrorToggle() }
)
```

Add at the top of the struct:

```swift
@StateObject private var mirrorService = CalendarMirrorService.shared
@State private var showingDisconnectConfirm = false
```

Add a confirmation alert and toggle handler:

```swift
.alert("// DISCONNECT iPHONE CALENDAR", isPresented: $showingDisconnectConfirm) {
    Button("CANCEL", role: .cancel) { }
    Button("DISCONNECT", role: .destructive) {
        Task { await mirrorService.disable() }
    }
} message: {
    Text("Existing mirrored events will be removed from your iPhone Calendar.")
}

private func handleMirrorToggle() {
    if mirrorService.isEnabled {
        showingDisconnectConfirm = true
    } else {
        Task { try? await mirrorService.enable() }
    }
}
```

Position the `.alert` modifier next to the existing modifiers on the outer view container; position the `private func handleMirrorToggle()` outside `body`.

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. If `EKEventStore` import is missing here it's not needed — the service surfaces booleans.

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/Settings/IntegrationsSettingsView.swift
git commit -m "Add Calendar section + iPhone Calendar Mirror toggle to Integrations settings"
```

### Task 8.2: Add the "Mirror disabled" banner to `ScheduleView`

**Files:**
- Modify: `OPS/Views/ScheduleView.swift`

- [ ] **Step 1: Read ScheduleView's top-of-screen structure**

Run:

```bash
sed -n '1,60p' OPS/Views/ScheduleView.swift
grep -n "var body\|VStack\|ZStack" OPS/Views/ScheduleView.swift | head -10
```

Find the first VStack inside `body` — that's where the banner inserts at the top.

- [ ] **Step 2: Add banner state + render**

At struct scope:

```swift
@StateObject private var mirrorService = CalendarMirrorService.shared
@AppStorage("ops.calendar.mirror.bannerDismissCount") private var bannerDismissCount: Int = 0

private var shouldShowMirrorBanner: Bool {
    mirrorService.hasShownPrompt
        && !mirrorService.isEnabled
        && bannerDismissCount < 2
}
```

In the body, at the top of the first VStack (before the existing content):

```swift
if shouldShowMirrorBanner {
    HStack {
        Text("// MIRROR DISABLED · TAP TO ENABLE")
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.secondaryText)
        Spacer()
        Button {
            bannerDismissCount += 1
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(width: 44, height: 44)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(OPSStyle.Colors.cardBackground)
    .contentShape(Rectangle())
    .onTapGesture {
        Task { try? await mirrorService.enable() }
    }
}
```

(Use `OPSStyle.Colors.cardBackground` or whichever banner-surface token actually exists — verify with `grep "card\|surface" OPS/Styles/OPSStyle.swift`.)

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/ScheduleView.swift
git commit -m "Add dismissable Mirror Disabled banner to ScheduleView"
```

### Task 8.3: Add `event` deep-link branch to `AppDelegate.handleDeepLink`

**Files:**
- Modify: `OPS/AppDelegate.swift`

- [ ] **Step 1: Read the existing switch**

Run:

```bash
sed -n '260,310p' OPS/AppDelegate.swift
```

Find the `switch entity` block.

- [ ] **Step 2: Add the `event` case**

Inside the `switch entity` (alongside `projects`, `clients`, `invoices`, `estimates`, `tasks`, `catalog`), add:

```swift
case "event":
    // ops://event/<calendarUserEventId> — open the CalendarUserEvent in app.
    Task { @MainActor in
        NotificationCenter.default.post(
            name: Notification.Name("OpenCalendarUserEvent"),
            object: nil,
            userInfo: ["eventId": id]
        )
    }
    return true
```

- [ ] **Step 3: Wire the notification observer in `MainTabView`**

Run:

```bash
grep -n "publisher(for:.*OpenAppFromWeb\|OpenCatalog\|OpenProjects" OPS/Views/MainTabView.swift | head -10
```

Inside MainTabView's body modifiers (next to the existing `.publisher(for: Notification.Name("OpenAppFromWeb"))`), add an observer:

```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCalendarUserEvent"))) { note in
    guard let eventId = note.userInfo?["eventId"] as? String else { return }
    // Switch to Schedule tab and post a request to surface the event.
    selectedTab = .schedule  // use the existing enum case; verify name below
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        NotificationCenter.default.post(
            name: Notification.Name("ScheduleView_OpenEvent"),
            object: nil,
            userInfo: ["eventId": eventId]
        )
    }
}
```

Verify the tab enum case for Schedule:

```bash
grep -n "case schedule\|TabItem\|enum Tab" OPS/Views/MainTabView.swift | head -10
```

- [ ] **Step 4: Surface the event in ScheduleView (best-effort)**

In `ScheduleView`, add an `.onReceive` for `Notification.Name("ScheduleView_OpenEvent")`. Whatever the view's existing "open this event" entry point is, route the eventId there. If no such entry point exists, leave the observer as a no-op for now — tapping the deep link still opens the app to the Schedule tab, which is the minimum acceptable behavior. Add a `// TODO(Bug-68123654-followup): wire eventId → detail sheet` comment at the no-op observer so this gets a proper follow-up.

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add OPS/AppDelegate.swift OPS/Views/MainTabView.swift OPS/Views/ScheduleView.swift
git commit -m "Add ops://event/<id> deep link routing for iPhone Calendar Mirror"
```

---

## Phase 9 — Background refresh + lifecycle wiring

### Task 9.1: Register `BGAppRefreshTask`

**Files:**
- Modify: `OPS/OPSApp.swift`
- Modify: `OPS/AppDelegate.swift`

- [ ] **Step 1: Add registration in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`**

Run:

```bash
grep -n "didFinishLaunchingWithOptions\|BGTaskScheduler" OPS/AppDelegate.swift OPS/OPSApp.swift | head -10
```

In whichever launch method runs first (AppDelegate or OPSApp.init), add:

```swift
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.ops.calendar.mirror.refresh",
    using: nil
) { task in
    Task { @MainActor in
        await CalendarMirrorService.shared.reconcileAll()
        CalendarMirrorService.shared.scheduleNextRefresh()
        task.setTaskCompleted(success: true)
    }
}
```

Add at the top: `import BackgroundTasks`.

- [ ] **Step 2: Add the scheduler in `CalendarMirrorService`**

In `OPS/Services/CalendarMirrorService.swift`, add:

```swift
import BackgroundTasks

extension CalendarMirrorService {
    func scheduleNextRefresh() {
        guard isEnabled else { return }
        let req = BGAppRefreshTaskRequest(identifier: "com.ops.calendar.mirror.refresh")
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)  // earliest 1h
        try? BGTaskScheduler.shared.submit(req)
    }
}
```

Call `scheduleNextRefresh()` from `enable()` (after successful enable) and from `applicationDidEnterBackground` if such a hook exists in OPSApp. Find a background hook:

```bash
grep -n "scenePhase\|didEnterBackground\|backgroundOnly" OPS/OPSApp.swift OPS/AppDelegate.swift | head -10
```

Use `@Environment(\.scenePhase)` in `OPSApp.body` if available, observing `.background` transitions.

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add OPS/AppDelegate.swift OPS/OPSApp.swift OPS/Services/CalendarMirrorService.swift
git commit -m "Register BGAppRefreshTask for opportunistic mirror reconcile"
```

### Task 9.2: Trigger reconcile on app launch + after Supabase sync batch

**Files:**
- Modify: `OPS/OPSApp.swift`
- Modify: `OPS/Utilities/DataController.swift` (or wherever the sync batch completion is signaled)

- [ ] **Step 1: Launch reconcile**

In `OPSApp.body`'s `.task` modifier on the root view (or in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`), add after auth/session is restored:

```swift
Task { @MainActor in
    await CalendarMirrorService.shared.reconcileAll()
}
```

Gate so it only runs when there's a current user. Look for an existing "session restored" hook:

```bash
grep -n "currentUser\|sessionRestored\|onAppLaunch" OPS/OPSApp.swift | head -10
```

- [ ] **Step 2: Post-sync reconcile**

Run:

```bash
grep -n "fullSyncComplete\|finishedSync\|syncCompleted\|postSync\|InboundProcessor" OPS/Utilities/DataController.swift OPS/Network/Sync 2>/dev/null | head -10
```

Identify the function/closure that fires after a sync batch finishes. Inside it, append:

```swift
await CalendarMirrorService.shared.reconcileAll()
```

If sync completion is not signaled today, skip this hook — the foreground reconcile + `.EKEventStoreChanged` debouncer covers most cases. Add a `// TODO(Bug-68123654-followup): post-Supabase-sync reconcile hook` comment if so.

- [ ] **Step 3: Logout wiring**

Run:

```bash
grep -n "func logout\|signOut\|currentUser = nil" OPS/AppState.swift OPS/Utilities/DataController.swift 2>/dev/null | head -10
```

In the logout path, before clearing user state:

```swift
await CalendarMirrorService.shared.handleLogout()
```

In the company-switch path:

```swift
await CalendarMirrorService.shared.handleCompanySwitch()
```

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add OPS/OPSApp.swift OPS/AppState.swift OPS/Utilities/DataController.swift
git commit -m "Reconcile CalendarMirror on launch, post-sync, and clear on logout"
```

---

## Phase 10 — Bible updates

### Task 10.1: Document `CalendarMirrorMap` in `03_DATA_MODELS.md`

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/03_DATA_MODELS.md`

- [ ] **Step 1: Find the right insertion point**

Run:

```bash
grep -n "^## \|^### " /Users/jacksonsweet/Projects/OPS/ops-software-bible/03_DATA_MODELS.md | head -40
```

Find the section that lists client-local SwiftData models (or add a new subsection "Client-local tables (iOS only)").

- [ ] **Step 2: Add the entry**

Insert:

```markdown
### CalendarMirrorMap (iOS only — client-local)

**Purpose:** Side-table powering the iPhone Calendar Mirror feature. Maps OPS row IDs (`CalendarUserEvent.id`, `ProjectTask.id`) to the EventKit `EKEvent.eventIdentifier` written into the user's iPhone Calendar's dedicated "OPS" calendar.

**Storage:** SwiftData `@Model`, registered in `OPSSchema*`. Never synced to Supabase. Wiped on logout, company switch, or feature disable.

**Fields:**
- `opsId` (String, unique) — `CalendarUserEvent.id` or `ProjectTask.id`
- `ekEventIdentifier` (String) — EventKit's stable identifier for the mirrored event
- `sourceType` (String) — `MirrorSource.rawValue` (`"calendarUserEvent"` or `"projectTask"`)
- `contentHash` (String) — SHA-256 of canonical "title|start|end|notes|allDay" used to detect drift
- `lastMirroredAt` (Date) — last successful write timestamp

**Related:** see `07_SPECIALIZED_FEATURES.md` → "iPhone Calendar Mirror".
```

- [ ] **Step 3: Commit**

```bash
git add /Users/jacksonsweet/Projects/OPS/ops-software-bible/03_DATA_MODELS.md
git commit -m "Bible: document CalendarMirrorMap client-local table"
```

### Task 10.2: Add "iPhone Calendar Mirror" section to `07_SPECIALIZED_FEATURES.md`

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/07_SPECIALIZED_FEATURES.md`

- [ ] **Step 1: Find insertion point (after Section 16 "Schedule Tab Redesign")**

Run:

```bash
grep -n "^## " /Users/jacksonsweet/Projects/OPS/ops-software-bible/07_SPECIALIZED_FEATURES.md | tail -10
```

Identify Section 16's end. Insert a new Section 17.

- [ ] **Step 2: Write the section**

Append:

```markdown
## 17. iPhone Calendar Mirror (iOS)

One-way mirror from OPS schedule rows to a dedicated "OPS" calendar in the user's iPhone Calendar app. Powered by `EventKit` + `BGTaskScheduler` + a SwiftData side-table.

**Scope (current):**
- `CalendarUserEvent` (personal events, time off — any status; title prefix reflects status)
- `ProjectTask` where the current user is in `schedulingTeamMemberIds`

**Excluded:** `SiteVisit` — iOS model is unwired (see `03_DATA_MODELS.md` known-drift notes). Re-add once SiteVisit sync ships.

**Sync direction:** One-way (OPS → device). Edits the user makes inside iPhone Calendar are silently reverted on next reconcile.

**Calendar destination:** Dedicated `OPS` calendar, iCloud (CalDAV) source preferred; falls back to local source when no iCloud account. Calendar is recreated automatically if the user deletes it from iOS Calendar.

**Permission API:** `EKEventStore.requestFullAccessToEvents()` (iOS 17+). Info.plist key: `NSCalendarsFullAccessUsageDescription`. Full access (not write-only) is required so the reconciler can read back its own events.

**Mirror window:** Past 30 days → future 12 months from `Date()`. Prevents history dumps.

**Architecture:** see §3 "Calendar Event Scheduling" and §16 "Schedule Tab Redesign" for the source-of-truth context. Implementation: `OPS/Services/CalendarMirrorService.swift` (`@MainActor`-isolated singleton), `OPS/Services/CalendarMirror/CalendarMirrorContent.swift` (payload + canonical hash), `OPS/Services/CalendarMirror/CalendarMirrorEligibility.swift` (window + membership predicates).

**Triggers:** repository save paths fan out to `mirrorEvent(opsId:source:)`. Reconcile runs on app launch, `UIApplication.didBecomeActiveNotification`, `.EKEventStoreChanged` (debounced 1s via Combine), and opportunistic `BGAppRefreshTask` (`com.ops.calendar.mirror.refresh`, registered in Info.plist `BGTaskSchedulerPermittedIdentifiers`).

**Deep link:** `ops://event/<calendarUserEventId>` opens the event in OPS. Wired in `AppDelegate.handleDeepLink`. Project task mirror uses the existing `ops://projects/<projectId>/tasks/<taskId>` form.

**Permission UX:** Proactive prompt on first `CalendarUserEvent` save (`CalendarMirrorPromptSheet`), Settings toggle in `IntegrationsSettingsView` under a new "CALENDAR" header, and a dismissable banner on `ScheduleView` when the user dismissed the prompt without enabling.

**Logout / company switch:** `CalendarMirrorService.handleLogout()` deletes the entire `OPS` calendar from EventKit (cascades to all mirrored events) and clears `CalendarMirrorMap`.

**Side-table:** `CalendarMirrorMap` (see `03_DATA_MODELS.md`).
```

- [ ] **Step 3: Commit**

```bash
git add /Users/jacksonsweet/Projects/OPS/ops-software-bible/07_SPECIALIZED_FEATURES.md
git commit -m "Bible: document iPhone Calendar Mirror feature (Section 17)"
```

---

## Phase 11 — Build verification + bug closure

### Task 11.1: Full build sweep

**Files:** none

- [ ] **Step 1: Clean build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' clean build 2>&1 | tail -40
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Test build**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build-for-testing 2>&1 | tail -20
```

Expected: `** TEST BUILD SUCCEEDED **` (or BUILD SUCCEEDED).

- [ ] **Step 3: Lint check**

Run a quick search for any new compiler warnings introduced:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | grep -E "warning:|note:" | head -20
```

Address any new warnings in files this plan touched (silence pre-existing warnings only if straightforward; do not chase unrelated issues).

### Task 11.2: Update Supabase bug row to resolved

**Files:** none (runs MCP Supabase tool)

- [ ] **Step 1: Compose fix-notes summary**

A concise summary of what shipped (≤500 chars):

> Implemented `EventKit`-backed one-way mirror to a dedicated "OPS" iPhone Calendar. Scope: `CalendarUserEvent` (personal + time off, any status) and `ProjectTask` (where current user is assigned). iOS 17+ `requestFullAccessToEvents` permission, reconcile-and-revert drift handling, side-table `CalendarMirrorMap`, mirror window past-30d → future-12mo, `BGAppRefreshTask` opportunistic top-up, IntegrationsSettingsView toggle, first-event-save permission prompt, `ops://event/<id>` deep link. SiteVisit deferred (iOS model unwired). Two-way sync deferred. Spec: `docs/superpowers/specs/2026-05-10-iphone-calendar-mirror-design.md`. Plan: `docs/superpowers/plans/2026-05-10-iphone-calendar-mirror.md`.

- [ ] **Step 2: Run the Supabase update**

Use `mcp__plugin_supabase_supabase__execute_sql` against project `ijeekuhbatykdomumfjx`:

```sql
UPDATE bug_reports
SET
  status = 'resolved',
  resolved_at = now(),
  fixed_at = now(),
  fix_notes = $$Implemented EventKit-backed one-way mirror to a dedicated "OPS" iPhone Calendar. Scope: CalendarUserEvent (personal + time off, any status) and ProjectTask (where current user is assigned). iOS 17+ requestFullAccessToEvents permission, reconcile-and-revert drift handling, side-table CalendarMirrorMap, mirror window past-30d → future-12mo, BGAppRefreshTask opportunistic top-up, IntegrationsSettingsView toggle, first-event-save permission prompt, ops://event/<id> deep link. SiteVisit deferred (iOS model unwired). Two-way sync deferred. Spec: docs/superpowers/specs/2026-05-10-iphone-calendar-mirror-design.md. Plan: docs/superpowers/plans/2026-05-10-iphone-calendar-mirror.md.$$
WHERE id = '68123654-6398-4b65-8cec-5bf37b5a29e4'
RETURNING id, status, resolved_at, fixed_at;
```

Expected return: one row with `status='resolved'` and non-null timestamps.

- [ ] **Step 3: No commit needed for this step (DB update only).**

---

## Self-review (run after writing plan)

### Spec coverage check

| Spec section | Plan task(s) |
|---|---|
| §0 known drift — SiteVisit excluded | 1.1 (omits siteVisit enum case in models), 4.1 (omits siteVisit dispatch); doc note in 10.2 |
| §0 — `ops://event` deep link addition | 8.3 |
| §4 Decisions: full access permission | 3.1 (`requestAccessIfNeeded` uses `requestFullAccessToEvents`), 3.2 (Info.plist key) |
| §4 Reconcile-and-revert | 5.1 |
| §4 Mirror window 30d/365d | 2.2, 5.1 |
| §4 Side-table mapping + URL recovery | 1.1, 4.1, 5.1 (orphan sweep recovers via `EKEvent.url`) |
| §6.1 `CalendarMirrorService` surface | 3.1, 4.1, 5.1, 9.1, 9.2 |
| §6.2 `CalendarMirrorMap` | 1.1, 1.2, 1.3 |
| §6.3 Mirror trigger sites | 6.1, 6.2, 6.3 |
| §6.4 Reconciliation algorithm | 5.1 |
| §6.5 Event title format | 2.1 |
| §6.6 Permission UX (prompt + Settings + banner + denied) | 7.1, 7.2, 8.1, 8.2 |
| §6.7 BGAppRefreshTask | 9.1 |
| §7 Edge cases (logout, company switch, calendar deleted, drift revert) | 3.1 (disable/logout), 5.1 (calendar recreation + drift revert), 9.2 (logout) |
| §8 Files touched — Info.plist, bible, deep link | 3.2, 8.3, 10.1, 10.2 |
| §9 Testing — unit tests | 2.3 (content + eligibility unit tests); manual device test noted in 7.2 |

All spec requirements have at least one task. No gaps.

### Placeholder scan

- No "TBD" / "TODO" / "implement later" in the plan body. Two `// TODO(Bug-68123654-followup):` markers in 8.3 step 4 and 9.2 step 2 — these are explicit, scoped, and reference a tracked bug ID rather than vague intent. Acceptable.
- No "Add appropriate error handling" — every error path is concrete (return early, swallow + rely on reconcile, etc.).
- No "Similar to Task N" — code blocks are repeated where needed.
- All code steps include the actual code, all command steps include the actual command + expected output.

### Type consistency

- `MirrorSource` enum: defined in 1.1 with `calendarUserEvent` + `projectTask`. Used consistently in 4.1 (`source: MirrorSource`), 5.1, 6.x.
- `CalendarMirrorMap`: same fields throughout.
- `mirrorEvent(opsId:source:)` / `unmirrorEvent(opsId:)` signatures stable across all callers.
- `CalendarMirrorEligibility.isEligible(event:currentUserId:now:)` / `isEligible(task:currentUserId:now:)` signatures match callers in 4.1 + 5.1.
- `CalendarMirrorContent.payload(for: event)` and `payload(for: task, projectDisplayName:, taskTypeDisplay:, address:)` signatures match the caller in 4.1.
- UserDefaults keys: `ops.calendar.mirror.enabled`, `ops.calendar.mirror.calendarId`, `ops.calendar.mirror.hasShownPrompt`, `ops.calendar.mirror.bannerDismissCount` — distinct, namespaced, no collisions.
- BGTask identifier: `com.ops.calendar.mirror.refresh` — referenced identically in 3.2 (Info.plist), 9.1 (register), 9.1 (scheduleNextRefresh).

No type drift.
