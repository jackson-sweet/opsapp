# Remaining Tracks from V1

**Purpose**: Consolidated guide for completing remaining V1 tracks
**Priority Order**: F → C → O → L → M → N

---

## Track F: Icon Migration (85% Complete)

**Status**: IN PROGRESS
**Effort Remaining**: 2-3 hours
**Priority**: P1 - Finish first

### Current State

- ~380 icons migrated across 71 files
- ~60 icons remaining in ViewModels and remaining views
- OPSStyle.Icons has 45 semantic + 60 generic icons

### What's Left

1. Check ViewModels folder for icon usage
2. Check remaining Views/Components files
3. Add any missing icons to OPSStyle.Icons
4. Clean up NOTE comments for added icons

### Grep Commands

```bash
# Find remaining hardcoded icons
grep -r 'systemName: "' OPS/Views OPS/ViewModels --include="*.swift" | \
  grep -v "OPSStyle.Icons" | wc -l

# Should be <20 after completion
```

### Migration Pattern

```swift
// Before
Image(systemName: "folder")

// After - Semantic first
Image(systemName: OPSStyle.Icons.project)

// Or generic if no semantic equivalent
Image(systemName: OPSStyle.Icons.folder)
```

---

## Track C: Notification Consolidation

**Status**: TODO
**Effort**: 4-6 hours
**Priority**: P2
**Reference**: ARCHITECTURAL_DUPLICATION_AUDIT.md Part 1

### Problem

52 files duplicate alert patterns:
```swift
@State private var showingError = false
@State private var errorMessage: String?

.alert("Error", isPresented: $showingError) {
    Button("OK", role: .cancel) {}
} message: {
    Text(errorMessage ?? "An error occurred")
}
```

NotificationBanner exists but is used in 0 files.

### Solution

1. Add notification methods to AppState
2. Migrate 52 files from `.alert()` to NotificationBanner
3. Add success notifications to save operations
4. Remove duplicate @State variables

### Implementation

**Add to AppState.swift**:
```swift
@Published var notificationMessage: String?
@Published var notificationType: NotificationBanner.BannerType = .info
@Published var showNotification = false

func showSuccess(_ message: String) {
    notificationMessage = message
    notificationType = .success
    showNotification = true
}

func showError(_ message: String) {
    notificationMessage = message
    notificationType = .error
    showNotification = true
}

func showInfo(_ message: String) {
    notificationMessage = message
    notificationType = .info
    showNotification = true
}
```

**Add to ContentView or MainTabView**:
```swift
.notificationBanner(
    isPresented: $appState.showNotification,
    message: appState.notificationMessage ?? "",
    type: appState.notificationType
)
```

### Files to Migrate (Partial List)

1. ProjectFormSheet.swift
2. TaskFormSheet.swift
3. ClientSheet.swift
4. TaskTypeSheet.swift
5. SubClientEditSheet.swift
6. LoginView.swift
7. ForgotPasswordView.swift
8. ProfileSettingsView.swift
9. SecuritySettingsView.swift
10. ... +42 more files

### Verification

```bash
# Count alert patterns (should be <5 after migration)
grep -r "\.alert\(" OPS/Views --include="*.swift" | wc -l

# Count NotificationBanner usage (should be 52+)
grep -r "showError\|showSuccess\|showInfo" OPS/Views --include="*.swift" | wc -l
```

---

## Track O: Component Standardization

**Status**: TODO
**Effort**: 12-16 hours
**Priority**: P2
**Reference**: COMPONENT_STANDARDIZATION.md

### Three Phases

#### Phase O1: Fix Self-Violating Components (2-3h)

FormInputs.swift has 7 instances of `.foregroundColor(.white)` → should be `OPSStyle.Colors.primaryText`

ButtonStyles.swift has 3 hardcoded colors → should be OPSStyle

**Files**:
- OPS/Styles/FormInputs.swift
- OPS/Styles/ButtonStyles.swift

#### Phase O2: Create Missing Form Components (3-4h)

Create:
- FormPicker
- FormDatePicker
- FormStepper

Add to FormInputs.swift following FormField pattern.

#### Phase O3: Migrate Files (7-9h)

- ~50 files: raw TextField → FormField
- ~30 files: raw Picker → FormPicker
- ~15 files: raw DatePicker → FormDatePicker
- ~5 files: raw Stepper → FormStepper

### Grep Commands

```bash
# Find raw TextField usage
grep -r "TextField(" OPS/Views --include="*.swift" | grep -v "FormField" | wc -l

# Find raw Picker usage
grep -r "Picker(" OPS/Views --include="*.swift" | grep -v "FormPicker\|DatePicker" | wc -l

# Find raw DatePicker usage
grep -r "DatePicker(" OPS/Views --include="*.swift" | grep -v "FormDatePicker" | wc -l
```

---

## Track L: DataController Refactoring

**Status**: TODO
**Effort**: 8-10 hours
**Priority**: P3 (after J+)
**Reference**: CONSOLIDATION_PLAN.md Phase 6

### Problem

DataController.swift is 3,687 lines in one file.

### Solution

Split into extensions:
- DataController.swift (core, ~200 lines)
- DataController+Auth.swift (~400 lines)
- DataController+Sync.swift (~800 lines)
- DataController+Projects.swift (~500 lines)
- DataController+Tasks.swift (~400 lines)
- DataController+Calendar.swift (~300 lines)
- DataController+Cleanup.swift (~600 lines)
- DataController+Migration.swift (~500 lines)

### Steps

1. Create OPS/Utilities/DataController/ folder
2. Identify sections in current file
3. Create extension files
4. Move code to appropriate extensions
5. Update imports
6. Build and test
7. Delete old single file

---

## Track M: Folder Reorganization

**Status**: TODO
**Effort**: 4-6 hours
**Priority**: P3 (do last)
**Reference**: CONSOLIDATION_PLAN.md Phase 7

### Problem

Views folder has 143 files with inconsistent organization.

### Target Structure

See COMPONENT_HIERARCHY.md for recommended structure:
- Components/Atoms/
- Components/Molecules/
- Components/Organisms/
- Components/Templates/
- Features/ (by feature area)

### Steps

1. Create new folder structure (don't move yet)
2. Update Xcode project
3. Move files by category (Models → Network → Utilities → Components → Features)
4. Update imports after each category
5. Build and test after each category
6. Delete empty old folders

### Risk

This is the **highest risk track** - many files moved, many imports to update. Do this last when codebase is stable.

---

## Track N: Cleanup & Documentation

**Status**: TODO
**Effort**: 6-10 hours
**Priority**: P3 (do last)
**Reference**: CONSOLIDATION_PLAN.md Phases 5, 8, 9

### Phase N1: Remove Print Statements (2-3h)

270 print statements to review:
- Keep: Critical API/sync logging
- Remove: Debug prints

```bash
grep -r "print(" OPS --include="*.swift" | wc -l
```

### Phase N2: Remove Dead Code (2-3h)

- Remove LegacyStatusBadge
- Remove deprecated view modifiers
- Address 7 TODO comments
- Verify/remove unused files

### Phase N3: Update Documentation (2-3h)

- Update DATA_AND_MODELS.md with current state
- Update API_AND_SYNC.md with implementation status
- Update UI_GUIDELINES.md with code quality status
- Update COMPONENTS.md with new components
- Update CLAUDE.md with recent changes

---

## Priority Matrix

| Track | Priority | Effort | Impact | Dependencies |
|-------|----------|--------|--------|--------------|
| F | P1 | 2-3h | High (finish what's started) | None |
| C | P2 | 4-6h | High (52 files, consistent UX) | None |
| O | P2 | 12-16h | High (100+ files) | Track E complete |
| L | P3 | 8-10h | Medium (organization) | Track J+ recommended |
| M | P3 | 4-6h | Low (navigation) | All other tracks |
| N | P3 | 6-10h | Medium (quality) | All other tracks |

---

## Recommended Execution Order

1. **Track F** (2-3h) - Finish icons, clean context
2. **Track J+** (6-8h) - Action-based operations (V2)
3. **Track C** (4-6h) - Notification consolidation
4. **Track W** (4-6h) - Wrapper components (V2)
5. **Track O** (12-16h) - Component standardization
6. **Track T** (3-4h) - Type guards (V2)
7. **Track L** (8-10h) - DataController refactoring
8. **Track M** (4-6h) - Folder reorganization
9. **Track N** (6-10h) - Cleanup and documentation

Total: 52-73 hours

---

## Verification Checklist (All Tracks Complete)

After completing all tracks, verify:

```bash
# Zero hardcoded colors
grep -r "\.foregroundColor(\.\(white\|black\))" OPS/Views --include="*.swift" | wc -l
# Expected: 0

# Zero hardcoded icons
grep -r 'systemName: "' OPS/Views --include="*.swift" | grep -v "OPSStyle.Icons" | wc -l
# Expected: 0

# Zero direct save calls
grep -r "modelContext\.save()" OPS/Views --include="*.swift" | wc -l
# Expected: 0

# Zero local alert patterns
grep -r "@State.*showingError" OPS/Views --include="*.swift" | wc -l
# Expected: 0

# Form components used
grep -r "FormField\|FormPicker\|FormDatePicker" OPS/Views --include="*.swift" | wc -l
# Expected: 100+
```

---

**Last Updated**: November 24, 2025
