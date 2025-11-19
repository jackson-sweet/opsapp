# App Launch and Sync Flow - Complete Trace

**Last Updated:** November 15, 2025
**Purpose:** Complete trace of what happens during app launch, including all sync triggers and their execution order.

## Executive Summary

**Problem:** Multiple overlapping syncs triggered during app launch, causing ~900 records to be processed when only ~296 should be.

**Root Causes:**
1. App launch triggers full sync
2. Connectivity monitor initialization triggers background sync ✅ **FIXED**
3. App becoming active triggers subscription check (no sync, but creates noise)
4. Multiple rapid-fire connectivity state changes during launch ✅ **FIXED**

**Solutions Implemented (Nov 15, 2025):**
- ✅ Debounce sync triggers (2-second minimum interval between syncs)
- ✅ Ignore initial connectivity callback from monitor initialization

---

## Complete App Launch Sequence

### Phase 1: App Initialization (OPSApp.swift)

#### 1.1 SwiftUI Scene Setup (Lines 52-126)
```swift
var body: some Scene {
    WindowGroup {
        ContentView()
            .environmentObject(dataController)
            .environmentObject(notificationManager)
            .environmentObject(subscriptionManager)
            .onAppear { ... }                                          // Trigger #1
            .onReceive(UIApplication.didBecomeActiveNotification) { ... } // Trigger #2
    }
}
```

#### 1.2 onAppear Trigger (Lines 58-106)
**File:** `OPSApp.swift`
**When:** App first appears (every launch)

**Actions:**
1. Fresh install check and auth cleanup (lines 60-67)
2. Set model context in DataController (lines 69-71)
3. Initialize SubscriptionManager (lines 73-74)
4. Check notification status (line 77)
5. **→ Calls `performAppLaunchChecks()`** (lines 80-82) ⚠️ **SYNC TRIGGER**
6. Migrate images (lines 84-106)

### Phase 2: App Launch Health Check

#### 2.1 performAppLaunchChecks() (Lines 152-228)
**File:** `OPSApp.swift`

**Execution Flow:**
```
1. Check authentication (line 162)
   ├─ No userId → Exit, no sync
   └─ Has userId → Continue

2. Load currentUser if null (lines 170-191)
   ├─ Try fetch from SwiftData
   └─ Log if not found

3. Perform health check (line 194)
   ├─ DataHealthManager.performHealthCheck()
   └─ Execute recovery if needed

4. Trigger sync (line 222) ⚠️
   └─ dataController.performAppLaunchSync()

5. Check subscription (lines 225-227)
   └─ subscriptionManager.checkSubscriptionStatus()
```

#### 2.2 DataController.performAppLaunchSync() (Lines 213-239)
**File:** `DataController.swift`

**Execution:**
```swift
func performAppLaunchSync() {
    print("[APP_LAUNCH_SYNC] 🚀 Starting app launch sync")

    Task {
        if isConnected && isAuthenticated {
            if let syncManager = syncManager {
                // THIS TRIGGERS FULL SYNC #1
                await syncManager.triggerBackgroundSync(forceProjectSync: true)
            }

            // Then sync images
            await imageSyncManager.syncPendingImages()
        }
    }
}
```

**Result:** → Calls `CentralizedSyncManager.triggerBackgroundSync(forceProjectSync: true)`

### Phase 3: Connectivity Monitor Initialization

#### 3.1 ConnectivityMonitor Setup (Lines 37-80)
**File:** `ConnectivityMonitor.swift`

**What Happens:**
```swift
init() {
    setupMonitor()  // Sets up NWPathMonitor
}

private func setupMonitor() {
    monitor.pathUpdateHandler = { [weak self] path in
        // Detects connection status
        self.isConnected = path.status == .satisfied

        // Determine connection type (wifi/cellular/ethernet)
        let newConnectionType = ...

        // If connection type changed, notify observers
        if self.connectionType != newConnectionType {
            self.connectionType = newConnectionType

            DispatchQueue.main.async {
                // Execute callback
                self.onConnectionTypeChanged?(newConnectionType)

                // Post notification
                NotificationCenter.default.post(
                    name: ConnectivityMonitor.connectivityChangedNotification,
                    ...
                )
            }
        }
    }

    monitor.start(queue: queue)  // ⚠️ THIS FIRES IMMEDIATELY ON LAUNCH
}
```

**Problem:** When `monitor.start()` is called, `pathUpdateHandler` fires immediately with current network state, even though nothing actually "changed".

#### 3.2 DataController Connectivity Callback (Lines 111-141)
**File:** `DataController.swift`

**Triggered By:** `connectivityMonitor.onConnectionTypeChanged` callback

**Execution:**
```swift
connectivityMonitor.onConnectionTypeChanged = { [weak self] connectionType in
    DispatchQueue.main.async {
        guard let self = self else { return }

        self.isConnected = connectionType != .none
        print("[SYNC] 🔌 Network state changed: \(self.isConnected)")

        if connectionType != .none, self.isAuthenticated {
            Task { @MainActor in
                await self.checkPendingSyncs()

                // THIS TRIGGERS SYNC #2 (and possibly #3, #4)
                self.syncManager?.triggerBackgroundSync()
            }
        }
    }
}
```

**Problem:** This fires during app launch initialization, creating a second concurrent sync.

### Phase 4: App Becoming Active

#### 4.1 didBecomeActiveNotification (Lines 112-117)
**File:** `OPSApp.swift`

**Triggered By:** iOS fires this when app transitions to foreground/active state

**Execution:**
```swift
.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
    Task {
        await performActiveChecks()
    }
}
```

#### 4.2 performActiveChecks() (Lines 130-148)
**File:** `OPSApp.swift`

```swift
private func performActiveChecks() async {
    print("[APP_ACTIVE] 🏥 App became active - checking data health...")

    let healthManager = DataHealthManager(...)
    let hasMinimumData = healthManager.hasMinimumRequiredData()

    if !hasMinimumData {
        return  // Exit early
    }

    // Check subscription (no sync triggered here)
    await subscriptionManager.checkSubscriptionStatus()
}
```

**Note:** This does NOT trigger a sync, only subscription check. But creates console noise.

---

## Sync Execution Paths

### Path A: Full Sync (triggerBackgroundSync with force=true)

**Triggered By:** `dataController.performAppLaunchSync()`

**File:** `CentralizedSyncManager.swift` (Lines 271-298)

```swift
func triggerBackgroundSync(forceProjectSync: Bool = false) {
    guard !syncInProgress, isConnected else { return }

    Task {
        if forceProjectSync {
            try await syncAll()  // ← Full sync
        } else {
            try await syncBackgroundRefresh()
        }
    }
}
```

**Executes:** `syncAll()` (Lines 98-183)

**What syncAll() Does:**
```
1. Company sync           → 1 API call
2. Users sync             → 1 API call (all company users)
3. Clients sync           → 1 API call (all company clients)
4. Task Types sync        → 1 API call (all company task types)
5. Projects sync          → 1 API call (all company projects)
6. Tasks sync             → 1 API call (all company tasks)
   └─ updateProjectTeamsFromTasks() → N API calls (for changed projects)
7. Calendar Events sync   → 1 API call (all company events)
8. Link relationships     → Local operation
```

**Total API Calls:** 7 + N (where N = projects with team changes)

### Path B: Background Refresh (triggerBackgroundSync with force=false)

**Triggered By:** Connectivity monitor callback

**Executes:** `syncBackgroundRefresh()` (Lines 240-267)

**What syncBackgroundRefresh() Does:**
```
1. Projects sync (sinceDate: lastSyncDate)   → 1 API call
2. Tasks sync (sinceDate: lastSyncDate)      → 1 API call
3. Calendar Events sync (sinceDate: lastSyncDate) → 1 API call
```

**Total API Calls:** 3

**Note:** When `lastSyncDate` is null (first launch), it fetches ALL data, same as full sync.

---

## Timeline of Console Output

Based on actual console log from `/Development Tasks/CONSOLE.md`:

```
T+0ms    [SYNC] 📱 Initial connection state: Connected
         ├─ ConnectivityMonitor initialized
         └─ DataController.setupConnectivityMonitoring() runs

T+10ms   [APP_LAUNCH] 🏥 Performing data health check...
         └─ OPSApp.performAppLaunchChecks() triggered

T+15ms   [DATA_HEALTH] ✅ All health checks passed
         └─ Health check completes

T+20ms   [APP_LAUNCH] 🔄 Proceeding with full sync
         └─ dataController.performAppLaunchSync() called

T+25ms   [SUBSCRIPTION] Checking subscription status...
         └─ First subscription check

T+30ms   [APP_LAUNCH_SYNC] ✅ Triggering FULL SYNC (syncAll)
         └─ SYNC #1 STARTS (from app launch)

T+35ms   [SYNC] 🔌 Network state changed: Connected
         └─ ConnectivityMonitor callback fires (initialization)

T+40ms   [SUBSCRIPTION] Checking subscription status...
         └─ Second subscription check

T+45ms   [APP_ACTIVE] 🏥 App became active
         └─ didBecomeActiveNotification fires

T+50ms   [SUBSCRIPTION] Checking subscription status...
         └─ Third subscription check (from active notification)

T+55ms   [TRIGGER_BG_SYNC] 🔵 Background sync triggered (force: true)
         └─ SYNC #1 actually executing

T+60ms   [SYNC] 🔄 Connection active - triggering background sync
         └─ Connectivity callback triggers another sync

T+65ms   [TRIGGER_BG_SYNC] 🔵 Background sync triggered (force: false)
         └─ SYNC #2 STARTS (from connectivity)

T+70ms   [TRIGGER_BG_SYNC] ✅ Starting forced full sync
         └─ Sync #1 begins execution

T+75ms   [SYNC_ALL] 🔄 FULL SYNC STARTED
         └─ syncAll() executing

T+80ms   [TRIGGER_BG_SYNC] ✅ Starting background refresh
         └─ SYNC #2 begins execution (syncBackgroundRefresh)

T+85ms   [SYNC_BG] 🔄 Background refresh...
         └─ Background refresh executing

... (Both syncs run concurrently)

T+200ms  [SYNC_COMPANY] 📊 Syncing company data...
         ├─ Sync #1 fetching company
         └─ Sync #2 also may fetch company (if needed)

T+500ms  [SYNC_PROJECTS] 📋 Syncing projects...
         ├─ Sync #1: Fetches 100 projects
         └─ Sync #2: Also fetches 100 projects (duplicate!)

T+800ms  [SYNC_TASKS] ✅ Syncing tasks...
         ├─ Sync #1: Fetches 100 tasks
         └─ Sync #2: Also fetches 100 tasks (duplicate!)

T+1100ms [SYNC_CALENDAR] 📅 Syncing calendar events...
         ├─ Sync #1: Fetches 100 events
         └─ Sync #2: Also fetches 100 events (duplicate!)

T+2000ms [SYNC_ALL] ✅ FULL SYNC COMPLETED
         [SYNC_BG] ✅ Background refresh complete
```

---

## Problem Analysis

### Issue 1: Multiple Concurrent Syncs

**Count:** 2-4 syncs triggered within 100ms of each other

**Syncs:**
1. **App Launch Sync** (full) - from `performAppLaunchChecks()`
2. **Connectivity Sync** (background refresh) - from monitor initialization
3. **Possibly more** - if connectivity monitor fires multiple rapid updates

**Result:**
- Projects: Fetched 2-3 times (100 → 200-300 records processed)
- Tasks: Fetched 2-3 times (100 → 200-300 records processed)
- Calendar Events: Fetched 2 times (100 → 200 records processed)

**Total Waste:** ~600 extra record processings

### Issue 2: Connectivity Monitor Fires on Initialization

**Location:** `ConnectivityMonitor.swift` line 79

**Problem:**
```swift
monitor.start(queue: queue)  // Immediately fires pathUpdateHandler
```

When `NWPathMonitor.start()` is called, it immediately invokes `pathUpdateHandler` with the current network state, even though the state didn't actually "change".

**Impact:** Triggers a background sync during app launch when no network change occurred.

### Issue 3: No Sync Deduplication

**Problem:** No mechanism to prevent multiple syncs from running concurrently.

**Current Guard:**
```swift
guard !syncInProgress, isConnected else { return }
```

**Issue:** Multiple triggers can pass this guard before `syncInProgress` is set to true, especially on fast devices.

### Issue 4: Subscription Checks Creating Noise

**Count:** 3+ subscription checks during launch

**Why:**
1. From `performAppLaunchChecks()` (line 225-227)
2. From `performActiveChecks()` (line 147)
3. Additional checks from other paths

**Impact:** No sync triggered, but creates console noise and API calls.

---

## File References

### Primary Files

1. **OPSApp.swift**
   - Lines 58-106: `.onAppear` - Main app launch trigger
   - Lines 112-117: `.didBecomeActiveNotification` - Active state trigger
   - Lines 152-228: `performAppLaunchChecks()` - Health check and sync trigger
   - Lines 130-148: `performActiveChecks()` - Active state health check

2. **DataController.swift**
   - Lines 83-142: `setupConnectivityMonitoring()` - Connectivity callback setup
   - Lines 111-141: Connectivity change handler - Triggers background sync
   - Lines 213-239: `performAppLaunchSync()` - App launch sync trigger

3. **CentralizedSyncManager.swift**
   - Lines 271-298: `triggerBackgroundSync()` - Sync dispatcher
   - Lines 98-183: `syncAll()` - Full sync execution
   - Lines 240-267: `syncBackgroundRefresh()` - Background refresh execution

4. **ConnectivityMonitor.swift**
   - Lines 37-80: `setupMonitor()` - Network monitoring setup
   - Lines 42-76: `pathUpdateHandler` - Fires on network changes
   - Line 79: `monitor.start()` - ⚠️ Fires handler immediately

### Supporting Files

5. **DataHealthManager.swift**
   - Health validation and recovery logic
   - Called from `performAppLaunchChecks()`

6. **SubscriptionManager.swift**
   - `checkSubscriptionStatus()` - Called multiple times during launch

---

## Implemented Solutions

### Solution 1: Debounce Sync Triggers ✅ **IMPLEMENTED**

**File:** `CentralizedSyncManager.swift` (Lines 49-51, 278-296)

Prevents multiple syncs within a short time window:

```swift
private var lastSyncTriggerTime: Date?
private let minimumSyncInterval: TimeInterval = 2.0  // 2 seconds

func triggerBackgroundSync(forceProjectSync: Bool = false) {
    // Debounce: Don't trigger if we just triggered recently
    if let lastTrigger = lastSyncTriggerTime,
       Date().timeIntervalSince(lastTrigger) < minimumSyncInterval {
        print("[TRIGGER_BG_SYNC] ⏭️ Skipping - sync triggered \(Date().timeIntervalSince(lastTrigger))s ago")
        return
    }

    lastSyncTriggerTime = Date()

    guard !syncInProgress, isConnected else { return }

    // ... rest of function
}
```

### Solution 2: Ignore Initial Connectivity Event ✅ **IMPLEMENTED**

**File:** `DataController.swift` (Line 36, Lines 116-122)

Ignores the first connectivity callback during monitor initialization:

```swift
// In DataController
private var hasHandledInitialConnection = false

connectivityMonitor.onConnectionTypeChanged = { [weak self] connectionType in
    guard let self = self else { return }

    // Ignore the first callback (initialization)
    if !self.hasHandledInitialConnection {
        self.hasHandledInitialConnection = true
        print("[SYNC] 🔇 Ignoring initial connectivity event")
        return
    }

    // ... rest of handler
}
```

---

## Additional Proposed Solutions (Not Yet Implemented)

### Solution 3: Consolidate Health Checks

**Status:** Proposed, not yet implemented

Move subscription check into `performAppLaunchChecks()` and remove from `performActiveChecks()`:

```swift
// Remove subscription check from performActiveChecks()
private func performActiveChecks() async {
    // Only check minimum data, don't call subscription check
    let healthManager = DataHealthManager(...)
    let hasMinimumData = healthManager.hasMinimumRequiredData()

    if !hasMinimumData {
        print("[APP_ACTIVE] ⚠️ Minimum data requirements not met")
    }
    // Don't check subscription here - already checked in launch
}
```

### Solution 4: Add Sync Queue

**Status:** Proposed, not yet implemented

Replace concurrent syncs with a queue system:

```swift
private var pendingSyncRequest: SyncRequest?

enum SyncRequest {
    case full
    case background
}

func triggerBackgroundSync(forceProjectSync: Bool = false) {
    let request: SyncRequest = forceProjectSync ? .full : .background

    if syncInProgress {
        // Queue for after current sync completes
        pendingSyncRequest = request
        return
    }

    executeSyn(request)
}
```

---

## Expected Behavior After Fixes

With Solutions 1 and 2 implemented, the app launch flow should now:

### Single Sync on Launch
- **Only 1 sync** triggered on app launch (from `performAppLaunchSync()`)
- Connectivity monitor initialization callback is **ignored**
- Any rapid-fire triggers within 2 seconds are **debounced**

### Expected Console Output
```
T+0ms    [SYNC] 📱 Initial connection state: Connected
T+10ms   [APP_LAUNCH] 🏥 Performing data health check...
T+15ms   [DATA_HEALTH] ✅ All health checks passed
T+20ms   [APP_LAUNCH] 🔄 Proceeding with full sync
T+25ms   [SUBSCRIPTION] Checking subscription status...
T+30ms   [APP_LAUNCH_SYNC] ✅ Triggering FULL SYNC (syncAll)
T+35ms   [SYNC] 🔇 Ignoring initial connectivity callback (monitor initialization)  ← NEW
T+40ms   [SUBSCRIPTION] Checking subscription status...
T+45ms   [APP_ACTIVE] 🏥 App became active
T+50ms   [SUBSCRIPTION] Checking subscription status...
T+55ms   [TRIGGER_BG_SYNC] 🔵 Background sync triggered (force: true)
T+70ms   [TRIGGER_BG_SYNC] ✅ Starting forced full sync
T+75ms   [SYNC_ALL] 🔄 FULL SYNC STARTED
... (Single sync executes)
T+2000ms [SYNC_ALL] ✅ FULL SYNC COMPLETED
```

### Performance Improvement
- **Before:** ~900 records processed (3-4 concurrent syncs)
- **After:** ~296 records processed (1 sync)
- **Reduction:** ~67% fewer records processed

### Debouncing in Action
If a connectivity change occurs within 2 seconds of app launch sync:
```
[TRIGGER_BG_SYNC] ⏭️ Skipping - sync triggered 0.5s ago (min: 2.0s)
```

---

## Testing Checklist

To verify sync flow changes:

- [ ] Clean app install - verify single full sync
- [ ] App launch with existing data - verify single background refresh
- [ ] Network disconnect/reconnect - verify single sync triggered
- [ ] App backgrounding/foregrounding - verify no duplicate syncs
- [ ] Console log shows < 30 messages on clean launch
- [ ] Total API calls on launch ≤ 10 (not ~20-30)

---

## Related Documentation

- `CENTRALIZED_SYNC_ARCHITECTURE.md` - Sync architecture overview
- `API_GUIDE.md` - API endpoint documentation
- `SYNC_IMPLEMENTATION.md` - Implementation details
- `DEVELOPMENT_GUIDE.md` - Development best practices
