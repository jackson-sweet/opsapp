# Component Standardization & Adoption (Track O)

**📖 Document Type**: IMPLEMENTATION GUIDE
**🎯 Purpose**: Fix self-violating components and migrate files to use standardized UI components
**👉 Start Here**: [README.md](./README.md) → Track O

---

**Date**: November 20, 2025

## How to Use This Document

**For Track O (Component Standardization)**:
- **READ**: This entire document (comprehensive guide)
- **FOLLOW**: Three sequential phases below
- **Effort**: 12-16 hours
- **Impact**: 100+ files migrated to use standardized components, self-violations fixed

**Prerequisites**:
- ✅ Track A (OPSStyle Expansion) - **MUST BE COMPLETE**
- ✅ Track E (Color Migration) - **MUST BE COMPLETE** (fixes self-violating components)
- ⚠️ **RECOMMENDED**: Track D (Form/Edit merge) - Reduces files needing migration

**Execution Order**: Phase O1 → O2 → O3 (sequential)

---

## 🚨 CRITICAL: Ask Before Migrating Components

**⚠️ MANDATORY RULE**: When migrating files from raw UI elements (TextField, Picker, etc.) to standardized components (FormField, FormPicker, etc.):

1. **COMPARE** the existing implementation with the standardized component
2. **DOCUMENT** any custom styling or behavior in the existing implementation
3. **ASK THE USER** if the standardized component can replace it
4. **WAIT** for confirmation
5. **ONLY THEN** perform the migration

**Example Question**:
```
⚠️ COMPONENT MIGRATION DECISION NEEDED

FILE: TaskFormSheet.swift lines 234-245

CURRENT IMPLEMENTATION:
TextField("Task name", text: $taskName)
    .font(OPSStyle.Typography.body)
    .foregroundColor(OPSStyle.Colors.primaryText)
    .padding()
    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
    .cornerRadius(OPSStyle.Layout.cornerRadius)
    .overlay(
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .stroke(Color.white.opacity(0.1), lineWidth: 1)
    )

STANDARDIZED COMPONENT:
FormField(title: "TASK NAME", placeholder: "Task name", text: $taskName)

DIFFERENCES:
- Custom implementation has slightly different background opacity (0.6 vs 0.8 in FormField)
- Custom implementation has border overlay (FormField doesn't)

Should I:
1. Migrate to FormField (loses border overlay and uses 0.8 opacity)
2. Update FormField to match this styling first
3. Keep custom implementation
```

---

## Executive Summary

OPS has standardized UI components in `FormInputs.swift`, but they suffer from two critical issues:

1. **Self-Violation**: The component library itself contains hardcoded colors
2. **Low Adoption**: Only ~40% of files use standardized components; ~60% use raw SwiftUI elements

Additionally, several common form components don't have standardized equivalents:
- ❌ No `FormPicker` (30+ files use raw `Picker`)
- ❌ No `FormDatePicker` (15+ files use raw `DatePicker`)
- ❌ No `FormStepper` (5+ files use raw `Stepper`)

### Track O Goals

**Fix self-violating components** so they practice what they preach:
- `FormInputs.swift`: Replace 7 instances of `.white` with `OPSStyle.Colors.primaryText`
- `ButtonStyles.swift`: Replace hardcoded `.white` and `.black` with semantic colors

**Create missing standardized components** to cover all common UI elements:
- `FormPicker` for consistent dropdown selection
- `FormDatePicker` for consistent date selection
- `FormStepper` for consistent number input

**Migrate files to use standardized components**:
- ~50 files: raw `TextField` → `FormField`
- ~30 files: raw `Picker` → `FormPicker`
- ~15 files: raw `DatePicker` → `FormDatePicker`
- ~5 files: raw `Stepper` → `FormStepper`

### Impact

| Category | Before | After | Benefit |
|----------|--------|-------|---------|
| Self-violations | FormInputs.swift has 7 hardcoded colors | 0 hardcoded colors | Components practice OPSStyle |
| Component coverage | 3 form components | 6 form components | All common UI elements covered |
| Adoption rate | ~40% use FormField | ~95% use FormField | Consistent UI across app |
| Total files migrated | N/A | ~100 files | Easier maintenance, consistent UX |

---

## Phase O1: Fix Self-Violating Components (2-3 hours)

**Goal**: Ensure the standardized component library itself uses OPSStyle properly.

**Prerequisites**: Track E (Color Migration) must be complete, so `OPSStyle.Colors.primaryText` exists.

### O1.1: Fix FormInputs.swift

**File**: `OPS/Styles/FormInputs.swift`

**Violations to fix**:

```swift
// Line 32 (FormField component)
.foregroundColor(.white)  // ❌ Should be OPSStyle.Colors.primaryText

// Line 44 (FormField placeholder)
.foregroundColor(.white)  // ❌ Should be OPSStyle.Colors.primaryText

// Line 57 (SecureField in FormField)
.foregroundColor(.white)  // ❌ Should be OPSStyle.Colors.primaryText

// Line 91 (FormTextEditor)
.foregroundColor(.white)  // ❌ Should be OPSStyle.Colors.primaryText

// Line 113 (FormToggle label)
.foregroundColor(.white)  // ❌ Should be OPSStyle.Colors.primaryText

// Line 135 (RadioOption label)
.foregroundColor(.white)  // ❌ Should be OPSStyle.Colors.primaryText

// Line 221 (SearchBar text)
.foregroundColor(.white)  // ❌ Should be OPSStyle.Colors.primaryText
```

**Migration**:
Replace ALL 7 instances of `.foregroundColor(.white)` with `.foregroundColor(OPSStyle.Colors.primaryText)`

### O1.2: Fix ButtonStyles.swift

**File**: `OPS/Styles/ButtonStyles.swift`

**Violations to fix**:

```swift
// Line 11 (Primary button text)
.foregroundColor(.white)  // ❌ Should be OPSStyle.Colors.buttonText

// Line 48 (Destructive button text)
.foregroundColor(.white)  // ❌ Should be OPSStyle.Colors.buttonText

// Line 72 (Secondary button background for inverted style)
.background(Color.black)  // ❌ Should be OPSStyle.Colors.background
```

**Migration**:
- Replace `.foregroundColor(.white)` with `.foregroundColor(OPSStyle.Colors.buttonText)` (2 instances)
- Replace `.background(Color.black)` with `.background(OPSStyle.Colors.background)` (1 instance)

### O1.3: Verify Component Library Clean

**After fixes, verify**:
```bash
# Should return 0 (no hardcoded colors in component library)
grep -E "\.foregroundColor\(\.white\)|\.foregroundColor\(\.black\)|\.background\(Color\.white\)|\.background\(Color\.black\)" \
  OPS/Styles/FormInputs.swift OPS/Styles/ButtonStyles.swift | \
  grep -v "OPSStyle\." | wc -l
```

**Expected output**: `0`

### O1.4: Build & Test

After fixing self-violations:
1. Build project (should succeed)
2. Test FormField, FormTextEditor, FormToggle in any form sheet
3. Test buttons in various views
4. Verify visual appearance unchanged

**Commit**:
```bash
git add OPS/Styles/FormInputs.swift OPS/Styles/ButtonStyles.swift
git commit -m "Track O Phase 1: Fix self-violating components

Replaced hardcoded colors in component library with semantic OPSStyle colors:
- FormInputs.swift: 7 instances of .white → OPSStyle.Colors.primaryText
- ButtonStyles.swift: 2 instances of .white → OPSStyle.Colors.buttonText,
  1 instance of Color.black → OPSStyle.Colors.background

Component library now practices what it preaches - uses OPSStyle throughout."
```

---

## Phase O2: Create Missing Form Components (3-4 hours)

**Goal**: Add standardized wrappers for Picker, DatePicker, and Stepper to match existing FormField pattern.

### O2.1: Create FormPicker Component

**File**: `OPS/Styles/FormInputs.swift` (append to existing file)

**Add this component**:

```swift
/// Standard Picker component with OPSStyle
///
/// Usage:
/// ```
/// FormPicker(
///     title: "PROJECT STATUS",
///     selection: $selectedStatus,
///     options: [
///         ("Request for Quote", Status.rfq),
///         ("Estimated", Status.estimated),
///         ("Accepted", Status.accepted)
///     ]
/// )
/// ```
struct FormPicker<SelectionValue: Hashable>: View {
    var title: String
    @Binding var selection: SelectionValue
    var options: [(label: String, value: SelectionValue)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title
            Text(title.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Picker with standard styling
            Picker("", selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].label).tag(options[index].value)
                }
            }
            .pickerStyle(.menu)
            .tint(OPSStyle.Colors.primaryAccent)
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
    }
}
```

### O2.2: Create FormDatePicker Component

**File**: `OPS/Styles/FormInputs.swift` (append to existing file)

**Add this component**:

```swift
/// Standard DatePicker component with OPSStyle
///
/// Usage:
/// ```
/// FormDatePicker(
///     title: "START DATE",
///     date: $startDate,
///     displayedComponents: [.date, .hourAndMinute]
/// )
/// ```
struct FormDatePicker: View {
    var title: String
    @Binding var date: Date
    var displayedComponents: DatePickerComponents = [.date]
    var dateRange: ClosedRange<Date>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title
            Text(title.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // DatePicker with standard styling
            Group {
                if let range = dateRange {
                    DatePicker("", selection: $date, in: range, displayedComponents: displayedComponents)
                } else {
                    DatePicker("", selection: $date, displayedComponents: displayedComponents)
                }
            }
            .datePickerStyle(.compact)
            .tint(OPSStyle.Colors.primaryAccent)
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
    }
}
```

### O2.3: Create FormStepper Component

**File**: `OPS/Styles/FormInputs.swift` (append to existing file)

**Add this component**:

```swift
/// Standard Stepper component with OPSStyle
///
/// Usage:
/// ```
/// FormStepper(
///     title: "Team Size",
///     value: $teamSize,
///     range: 1...50
/// )
/// ```
struct FormStepper: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1

    var body: some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()

            Text("\(value)")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 40, alignment: .trailing)
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }
}
```

### O2.4: Update COMPONENTS.md Documentation

**File**: `COMPONENTS.md`

Add these three new components to the Form Components section with usage examples.

### O2.5: Build & Test

After adding components:
1. Build project (should succeed)
2. Create a test view using all three new components
3. Verify styling matches FormField
4. Test picker selection, date picker selection, stepper increment/decrement

**Commit**:
```bash
git add OPS/Styles/FormInputs.swift COMPONENTS.md
git commit -m "Track O Phase 2: Add missing form components

Created three new standardized form components following FormField pattern:
- FormPicker: Standardized dropdown selection with OPSStyle
- FormDatePicker: Standardized date/time selection with OPSStyle
- FormStepper: Standardized number input with OPSStyle

All components match FormField styling (card background, border, accent color).
Updated COMPONENTS.md with usage examples.

This completes the standard form component library."
```

---

## Phase O3: Migrate Files to Standardized Components (7-9 hours)

**Goal**: Replace raw SwiftUI elements with standardized components across 100+ files.

**Prerequisites**:
- Phase O1 complete (components fixed)
- Phase O2 complete (missing components created)
- **RECOMMENDED**: Track D complete (reduces files from 6 to 3)

### O3.1: TextField → FormField Migration (~50 files, 3-4 hours)

**Files to migrate** (partial list - use grep to find all):

#### High-Priority Files (migrate first):
1. `OPS/Views/LoginView.swift` - Username and password fields
2. `OPS/Views/ForgotPasswordView.swift` - Email field
3. `OPS/Views/JobBoard/TaskFormSheet.swift` - Task name field
4. `OPS/Views/JobBoard/ClientFormSheet.swift` - Client name, contact fields
5. `OPS/Views/JobBoard/TaskTypeFormSheet.swift` - Task type name field
6. `OPS/Views/Components/Client/SubClientEditSheet.swift` - Sub-client fields
7. `OPS/Views/Settings/ProfileSettingsView.swift` - Profile fields
8. `OPS/Views/Settings/OrganizationSettingsView.swift` - Organization fields
9. Plus ~42 more files

**Migration Pattern**:

```swift
// ❌ BEFORE: Raw TextField (with custom styling)
TextField("Enter task name", text: $taskName)
    .font(OPSStyle.Typography.body)
    .foregroundColor(OPSStyle.Colors.primaryText)
    .padding()
    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
    .cornerRadius(OPSStyle.Layout.cornerRadius)

// ✅ AFTER: FormField (handles all styling)
FormField(title: "TASK NAME", placeholder: "Enter task name", text: $taskName)
```

**Special Cases**:

If TextField has **custom behavior** beyond styling:
```swift
// Example: TextField with onChange handler
TextField("Search", text: $searchText)
    .onChange(of: searchText) { _, newValue in
        performSearch(newValue)
    }

// Migrate to FormField, keep onChange:
FormField(title: "", placeholder: "Search", text: $searchText)
    .onChange(of: searchText) { _, newValue in
        performSearch(newValue)
    }
```

If TextField has **autocapitalization or keyboard type**:
```swift
// Example: Email field with keyboard type
TextField("Email", text: $email)
    .keyboardType(.emailAddress)
    .textInputAutocapitalization(.never)

// FormField doesn't support these - ASK USER:
// Should we add keyboard type parameters to FormField, or keep custom TextField?
```

**Grep Command** to find candidates:
```bash
grep -r "TextField(" --include="*.swift" OPS/Views | \
  grep -v "FormField" | \
  grep -v "UnderlineTextField" | \
  cut -d: -f1 | sort | uniq
```

### O3.2: Picker → FormPicker Migration (~30 files, 2-3 hours)

**Files to migrate** (use grep to find all):

#### High-Priority Files:
1. `OPS/Views/JobBoard/ProjectFormSheet.swift` - Status picker, type picker
2. `OPS/Views/JobBoard/TaskFormSheet.swift` - Task type picker, priority picker
3. `OPS/Views/Settings/ProfileSettingsView.swift` - Role picker
4. `OPS/Views/Settings/OrganizationSettingsView.swift` - Industry picker
5. Plus ~26 more files

**Migration Pattern**:

```swift
// ❌ BEFORE: Raw Picker
Picker("Status", selection: $selectedStatus) {
    ForEach(Status.allCases, id: \.self) { status in
        Text(status.displayName).tag(status)
    }
}
.pickerStyle(.menu)

// ✅ AFTER: FormPicker
FormPicker(
    title: "STATUS",
    selection: $selectedStatus,
    options: Status.allCases.map { ($0.displayName, $0) }
)
```

**Grep Command**:
```bash
grep -r "Picker(" --include="*.swift" OPS/Views | \
  grep -v "FormPicker" | \
  grep -v "DatePicker" | \
  cut -d: -f1 | sort | uniq
```

### O3.3: DatePicker → FormDatePicker Migration (~15 files, 1-2 hours)

**Files to migrate**:

#### High-Priority Files:
1. `OPS/Views/JobBoard/ProjectFormSheet.swift` - Start date, end date pickers
2. `OPS/Views/JobBoard/TaskFormSheet.swift` - Due date picker
3. `OPS/Views/Components/Scheduling/CalendarSchedulerSheet.swift` - Event date picker
4. Plus ~12 more files

**Migration Pattern**:

```swift
// ❌ BEFORE: Raw DatePicker
DatePicker("Start Date", selection: $startDate, displayedComponents: [.date])
    .datePickerStyle(.compact)

// ✅ AFTER: FormDatePicker
FormDatePicker(
    title: "START DATE",
    date: $startDate,
    displayedComponents: [.date]
)
```

**With date range**:
```swift
// ❌ BEFORE: DatePicker with range
DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: [.date])

// ✅ AFTER: FormDatePicker with range
FormDatePicker(
    title: "END DATE",
    date: $endDate,
    displayedComponents: [.date],
    dateRange: startDate...
)
```

**Grep Command**:
```bash
grep -r "DatePicker(" --include="*.swift" OPS/Views | \
  grep -v "FormDatePicker" | \
  cut -d: -f1 | sort | uniq
```

### O3.4: Stepper → FormStepper Migration (~5 files, 30 minutes)

**Files to migrate** (use grep to find all):

**Migration Pattern**:

```swift
// ❌ BEFORE: Raw Stepper
HStack {
    Text("Team Size")
    Spacer()
    Stepper("", value: $teamSize, in: 1...50)
    Text("\(teamSize)")
}

// ✅ AFTER: FormStepper
FormStepper(title: "Team Size", value: $teamSize, range: 1...50)
```

**Grep Command**:
```bash
grep -r "Stepper(" --include="*.swift" OPS/Views | \
  grep -v "FormStepper" | \
  cut -d: -f1 | sort | uniq
```

### O3.5: Migration Workflow

For EACH file being migrated:

1. **Read the file** to understand current usage
2. **Identify all raw UI elements** (TextField, Picker, DatePicker, Stepper)
3. **Check for custom behavior** (onChange, keyboard types, validation, etc.)
4. **If custom behavior exists**: ASK USER if FormComponent can handle it
5. **Migrate to FormComponent** if approved
6. **Test the view** to ensure behavior unchanged
7. **Commit the migration** for that file

**Example Commit**:
```bash
git add OPS/Views/JobBoard/TaskFormSheet.swift
git commit -m "Track O Phase 3: Migrate TaskFormSheet to standardized components

Replaced raw UI elements with standardized components:
- TextField → FormField (task name, description)
- Picker → FormPicker (task type, priority)
- DatePicker → FormDatePicker (due date)

Visual appearance and behavior unchanged. Form now uses consistent styling."
```

### O3.6: Batch Migration Strategy

**Don't migrate all 100 files at once**. Use batches:

#### Batch 1: Job Board Forms (6-8 files, 1 hour)
- ProjectFormSheet, TaskFormSheet, ClientFormSheet
- TaskTypeFormSheet, SubClientEditSheet, ClientEditSheet

#### Batch 2: Settings Views (15 files, 2 hours)
- All views in `OPS/Views/Settings/`

#### Batch 3: Component Views (20 files, 2 hours)
- Views in `OPS/Views/Components/` with forms

#### Batch 4: Remaining Views (50+ files, 3-4 hours)
- Debug views, onboarding views, other views with forms

**Commit after each batch**, build and test.

---

## Verification & Completion

### Final Verification Commands

After completing all three phases:

**1. Verify no hardcoded colors in component library**:
```bash
grep -E "\.foregroundColor\(\.white\)|\.foregroundColor\(\.black\)" \
  OPS/Styles/FormInputs.swift OPS/Styles/ButtonStyles.swift | \
  grep -v "OPSStyle\."
```
Expected: 0 results

**2. Verify all form components exist**:
```bash
grep -E "struct Form(Field|TextEditor|Toggle|Picker|DatePicker|Stepper)" \
  OPS/Styles/FormInputs.swift
```
Expected: 6 components found

**3. Count remaining raw TextField usage**:
```bash
grep -r "TextField(" --include="*.swift" OPS/Views | \
  grep -v "FormField" | \
  grep -v "UnderlineTextField" | \
  wc -l
```
Expected: <10 (legitimate exceptions like search bars with custom behavior)

**4. Count remaining raw Picker usage**:
```bash
grep -r "Picker(" --include="*.swift" OPS/Views | \
  grep -v "FormPicker" | \
  grep -v "DatePicker" | \
  wc -l
```
Expected: <5 (legitimate exceptions)

### Track O Completion Checklist

- [ ] Phase O1: Self-violating components fixed (FormInputs.swift, ButtonStyles.swift)
- [ ] Phase O2: Missing components created (FormPicker, FormDatePicker, FormStepper)
- [ ] Phase O3: Files migrated to standardized components
  - [ ] Batch 1: Job Board Forms (6-8 files)
  - [ ] Batch 2: Settings Views (15 files)
  - [ ] Batch 3: Component Views (20 files)
  - [ ] Batch 4: Remaining Views (50+ files)
- [ ] All verification commands pass
- [ ] Build succeeds
- [ ] Manual testing of migrated views complete
- [ ] COMPONENTS.md updated with new components

---

## Expected Impact

### Before Track O:
- FormInputs.swift: 7 hardcoded colors (self-violation)
- ButtonStyles.swift: 3 hardcoded colors (self-violation)
- Form component coverage: 3 components (Field, TextEditor, Toggle)
- Component adoption: ~40% of files use FormField
- Raw UI elements: ~100 files use raw TextField/Picker/DatePicker

### After Track O:
- Component library: 0 hardcoded colors (practices OPSStyle)
- Form component coverage: 6 components (Field, TextEditor, Toggle, Picker, DatePicker, Stepper)
- Component adoption: ~95% of files use standardized components
- Raw UI elements: <15 files (legitimate exceptions only)

### Benefits:
1. **Consistency**: All forms look and behave the same way
2. **Maintainability**: Update FormField styling once, affects 100+ files
3. **Development Speed**: New forms use standardized components, faster to build
4. **Bug Fixes Propagate**: Fix a bug in FormField, fixes 100+ usages
5. **Self-Documenting**: Component library practices what it preaches

---

## Relationship to Other Tracks

### Track D (Form/Edit Merging) - **Do Before Track O**
If Track D is completed first:
- 6 form files → 3 merged files
- Reduces files needing component migration from ~56 to ~53
- Each merged file gets component migration done once, not twice

**Recommendation**: Complete Track D before Track O Phase 3.

### Track E (Color Migration) - **Required Before Track O Phase 1**
Track O Phase 1 replaces hardcoded colors with semantic colors, which must exist first.

### Track F (Icon Migration) - **Can Run in Parallel**
Independent work, no conflicts.

### Track B (Sheet Toolbars) - **Can Run in Parallel**
Independent work, different files.

---

**Track O Total Effort**: 12-16 hours
**Track O Total Impact**: 100+ files migrated, 0 self-violations, complete component library

**Recommendation**: Execute after Track D and Track E, in parallel with Track F.

---

**Last Updated**: 2025-11-20
**Read Next**: ARCHITECTURAL_DUPLICATION_AUDIT.md for Track C, J, K
