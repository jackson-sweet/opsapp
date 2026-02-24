# Template & Component Standardization

**📖 Document Type**: IMPLEMENTATION GUIDE
**🎯 Purpose**: Step-by-step guide for Track B (Sheet Navigation Toolbar)
**👉 Start Here**: [README.md](./README.md) → Track B

---

**Date**: November 18, 2025

## How to Use This Document

**For Track B (Sheet Navigation Toolbar Template)**:
- **READ**: Part 1 (Standardized Sheet Navigation Bar)
- **FOLLOW**: Implementation Plan → Phase 1-2
- **VERIFY**: Expected Impact section

**For Additional Context**:
- Part 2: ExpandableSection component (reference)
- Part 3: Job Detail Card Template (reference)
- Parts 4-6: Full implementation details

**Prerequisites**:
- ✅ None - Track B is independent
- ⚠️ Can run in parallel with any other track
- 🚨 **MUST READ**: [PROJECTFORMSHEET_AUTHORITY.md](./PROJECTFORMSHEET_AUTHORITY.md) - ProjectFormSheet defines the authority navigation bar pattern

**Estimated Effort**: 10-15 hours
**Impact**: 555 lines saved across 37 files
**ROI**: ⭐⭐⭐⭐⭐ Excellent

---

## 🚨 CRITICAL: Ask Before Deleting

**⚠️ MANDATORY RULE**: When migrating the 37 sheets to use `.standardSheetToolbar()`, you will be removing duplicate navigation bar code.

**BEFORE DELETING ANY TOOLBAR CODE**:
1. **COMPARE** the existing toolbar in each file with the ProjectFormSheet authority pattern
2. **IF DIFFERENCES EXIST** (different colors, fonts, button order, etc.):
   - **STOP** - Do not delete
   - **DOCUMENT** the differences
   - **ASK THE USER** which version to keep
   - **WAIT** for confirmation
3. **ONLY AFTER USER CONFIRMS** should you delete the old code

**Example Question**:
```
⚠️ TOOLBAR DIFFERENCE FOUND

FILE: TaskFormSheet.swift lines 145-170

CURRENT CODE:
Button("CANCEL") {
    dismiss()
}
.font(OPSStyle.Typography.bodyBold)
.foregroundColor(OPSStyle.Colors.primaryAccent)  // ← Different from authority!

AUTHORITY (ProjectFormSheet): Uses OPSStyle.Colors.secondaryText

Should I migrate this to match ProjectFormSheet authority (secondaryText)?
```

**Do NOT assume all navigation bars should be identical**. Some may have intentional differences.

---

## Executive Summary

Two critical template patterns are duplicated extensively but can be easily standardized:

1. **Sheet Navigation Bars** - Duplicated across **37 files** with identical structure
2. **ExpandableSection** - Exists in ProjectFormSheet.swift but needs to be extracted for reuse
3. **Job Detail Cards** - Pattern exists in 4 separate card files, needs template wrapper

### Impact

| Template | Current State | Proposed | Lines Saved |
|----------|---------------|----------|-------------|
| Sheet Nav Bars | 37 duplicate implementations | 1 wrapper component | ~555 lines |
| ExpandableSection | 1 local definition in ProjectFormSheet | Shared component | Enable reuse |
| Detail View Cards | 4 separate cards, inconsistent usage | 1 template pattern | Enforce consistency |

---

## Part 1: Standardized Sheet Navigation Bar

### 1.1 Current Duplication

**Found in 37 files**, this exact pattern:

```swift
// ❌ DUPLICATE PATTERN (37 files):
NavigationView {
    // ... content ...
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("CANCEL") {
                dismiss()
            }
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.secondaryText)
        }

        ToolbarItem(placement: .principal) {
            Text("CREATE PROJECT")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button("CREATE") {
                saveAction()
            }
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(isValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
            .disabled(!isValid)
        }
    }
}
```

**Files with this pattern** (partial list):
1. ProjectFormSheet.swift
2. TaskFormSheet.swift
3. ClientFormSheet.swift
4. SubClientEditSheet.swift
5. ClientEditSheet.swift
6. TaskTypeFormSheet.swift
7. TaskTypeEditSheet.swift
8. TaskTypeDeletionSheet.swift
9. ClientDeletionSheet.swift
10. TeamRoleManagementView.swift
11. TeamRoleAssignmentSheet.swift
12. CopyFromProjectSheet.swift
13. TaskListFilterSheet.swift
14. ProjectListFilterSheet.swift
15. CalendarFilterView.swift
16. ProjectSearchFilterView.swift
17. ProjectSearchSheet.swift
... **+20 more files**

**Total duplicate code**: ~15 lines per file × 37 files = **555 lines**

### 1.2 Variations Found

While the structure is identical, there are minor variations:

| Variation | Examples |
|-----------|----------|
| **Cancel text** | "CANCEL", "Cancel", "Done" |
| **Cancel color** | `secondaryText` (most), `primaryAccent` (some) |
| **Title text** | "CREATE PROJECT", "EDIT TASK", "FILTERS", etc. |
| **Action button** | "CREATE", "SAVE", "DELETE", "APPLY", "Done" |
| **Action color** | `primaryAccent` (most), conditional on `isValid` |
| **Action disabled** | Some have `isValid`, some always enabled |

### 1.3 Proposed: StandardSheetToolbar

Create a reusable wrapper component that handles all variations:

**File**: `OPS/Styles/Components/StandardSheetToolbar.swift`

```swift
import SwiftUI

/// Standardized sheet navigation bar with consistent styling
///
/// Provides Cancel (left), Title (center), Action (right) buttons with OPSStyle
///
/// Usage:
/// ```swift
/// NavigationView {
///     content
/// }
/// .standardSheetToolbar(
///     title: "CREATE PROJECT",
///     cancelText: "CANCEL",
///     actionText: "CREATE",
///     isActionEnabled: isValid,
///     onCancel: { dismiss() },
///     onAction: { saveProject() }
/// )
/// ```
struct StandardSheetToolbarModifier: ViewModifier {
    let title: String
    let cancelText: String
    let cancelColor: Color
    let actionText: String
    let actionColor: Color
    let isActionEnabled: Bool
    let onCancel: () -> Void
    let onAction: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(cancelText) {
                        onCancel()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(cancelColor)
                }

                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(actionText) {
                        onAction()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(isActionEnabled ? actionColor : OPSStyle.Colors.tertiaryText)
                    .disabled(!isActionEnabled)
                }
            }
    }
}

extension View {
    /// Apply standardized sheet toolbar with Cancel/Title/Action buttons
    ///
    /// - Parameters:
    ///   - title: Sheet title (automatically uppercased if not already)
    ///   - cancelText: Cancel button text (default: "CANCEL")
    ///   - cancelColor: Cancel button color (default: secondaryText)
    ///   - actionText: Action button text (e.g., "CREATE", "SAVE", "DELETE")
    ///   - actionColor: Action button color when enabled (default: primaryAccent)
    ///   - isActionEnabled: Whether action button is enabled (default: true)
    ///   - onCancel: Action to perform when cancel is tapped
    ///   - onAction: Action to perform when action button is tapped
    func standardSheetToolbar(
        title: String,
        cancelText: String = "CANCEL",
        cancelColor: Color = OPSStyle.Colors.secondaryText,
        actionText: String,
        actionColor: Color = OPSStyle.Colors.primaryAccent,
        isActionEnabled: Bool = true,
        onCancel: @escaping () -> Void,
        onAction: @escaping () -> Void
    ) -> some View {
        modifier(StandardSheetToolbarModifier(
            title: title.uppercased(),  // Enforce uppercase titles
            cancelText: cancelText.uppercased(),  // Enforce uppercase
            cancelColor: cancelColor,
            actionText: actionText.uppercased(),  // Enforce uppercase
            actionColor: actionColor,
            isActionEnabled: isActionEnabled,
            onCancel: onCancel,
            onAction: onAction
        ))
    }
}
```

### 1.4 Migration Examples

**Before** (ProjectFormSheet.swift lines 1308-1332):
```swift
// ❌ OLD: 25 lines of toolbar code
.navigationBarTitleDisplayMode(.inline)
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) {
        Button("CANCEL") {
            dismiss()
        }
        .font(OPSStyle.Typography.bodyBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)
    }

    ToolbarItem(placement: .principal) {
        Text(mode.isCreate ? "CREATE PROJECT" : "EDIT PROJECT")
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
    }

    ToolbarItem(placement: .navigationBarTrailing) {
        Button(mode.isCreate ? "CREATE" : "SAVE") {
            saveProject()
        }
        .font(OPSStyle.Typography.bodyBold)
        .foregroundColor(isValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
        .disabled(!isValid || isSaving)
    }
}
```

**After**:
```swift
// ✅ NEW: 7 lines with standard toolbar
.standardSheetToolbar(
    title: mode.isCreate ? "Create Project" : "Edit Project",
    actionText: mode.isCreate ? "Create" : "Save",
    isActionEnabled: isValid && !isSaving,
    onCancel: { dismiss() },
    onAction: { saveProject() }
)
```

**Savings**: 18 lines per file × 37 files = **666 lines of duplicate code eliminated**

---

## Part 2: Shared ExpandableSection Component

### 2.1 Current State

**ExpandableSection exists** in ProjectFormSheet.swift (lines 1655-1715) as a **local component**.

**Problem**:
- Only usable within ProjectFormSheet
- Can't be reused in TaskFormSheet, ProjectDetailsView, TaskDetailsView
- Already used in TaskFormSheet (so it's duplicated!)

### 2.2 Proposed: Move to Shared Component

**Action**: Extract ExpandableSection to shared component

**File**: `OPS/Styles/Components/ExpandableSection.swift`

```swift
import SwiftUI

/// Expandable section card with header, icon, optional delete button, and collapsible content
///
/// Used for progressive disclosure in forms and detail views
///
/// Usage:
/// ```swift
/// ExpandableSection(
///     title: "PROJECT PHOTOS",
///     icon: "photo",
///     isExpanded: $isPhotosExpanded,
///     onDelete: { deleteAllPhotos() }
/// ) {
///     // Photo grid content
/// }
/// ```
struct ExpandableSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    let onDelete: (() -> Void)?
    @ViewBuilder let content: () -> Content

    /// Create an expandable section
    /// - Parameters:
    ///   - title: Section title (automatically uppercased)
    ///   - icon: SF Symbol icon name (default: "square.grid.2x2")
    ///   - isExpanded: Binding to control expanded/collapsed state
    ///   - onDelete: Optional delete handler (shows delete button when provided)
    ///   - content: Section content (shown when expanded)
    init(
        title: String,
        icon: String = "square.grid.2x2",
        isExpanded: Binding<Bool>,
        onDelete: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self._isExpanded = isExpanded
        self.onDelete = onDelete
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                // Header with icon, title, and optional delete button
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(title.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    // Optional delete button
                    if let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                    }

                    // Chevron indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }

                // Divider between header and content
                if isExpanded {
                    Divider()
                        .background(OPSStyle.Colors.cardBorder)
                }

                // Content area (shown when expanded)
                if isExpanded {
                    VStack(spacing: 0) {
                        content()
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
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

### 2.3 Enhancements to ExpandableSection

**Current version is missing**:
1. ❌ Chevron indicator (up/down arrow)
2. ❌ Tap-to-toggle functionality on header
3. ❌ Smooth expand/collapse animation

**Enhanced version includes**:
1. ✅ Chevron indicator
2. ✅ Tap header to toggle
3. ✅ Spring animation on toggle
4. ✅ Automatic uppercase title
5. ✅ Transition animation for content

### 2.4 Where to Use ExpandableSection

**Current usage**: ProjectFormSheet, TaskFormSheet

**Should also use in**:
1. ProjectDetailsView - for sections (Location, Client Info, Notes, Team, Photos)
2. TaskDetailsView - for sections
3. Settings screens - for grouped options
4. Any form with multiple optional sections

---

## Part 3: Job Detail Card Template Pattern

### 3.1 Existing Reusable Cards

**Already exist** in `OPS/Views/Components/Cards/`:
1. **LocationCard.swift** - Address display with map navigation
2. **ClientInfoCard.swift** - Client contact information
3. **NotesCard.swift** - Expandable notes display/editor
4. **TeamMembersCard.swift** - Team member list with avatars

**Pattern**: All have consistent styling:
- Icon + Title header
- Content area
- Standard padding: `.padding()`
- Background: `OPSStyle.Colors.cardBackground`
- Corner radius: `OPSStyle.Layout.cornerRadius`
- Border: `tertiaryText.opacity(0.2)`

### 3.2 Problem: Inconsistent Usage

**ProjectDetailsView** (2,000+ lines):
- ✅ Uses LocationCard
- ✅ Uses ClientInfoCard
- ✅ Uses NotesCard
- ✅ Uses TeamMembersCard
- ❌ But also has custom card layouts mixed in

**TaskDetailsView**:
- ✅ Uses LocationCard
- ✅ Uses NotesCard
- ✅ Uses TeamMembersCard
- ❌ Doesn't use ClientInfoCard (shows client differently)

### 3.3 Proposed: DetailViewCardTemplate

Create a **base template** that all detail cards follow:

**File**: `OPS/Styles/Components/DetailViewCardTemplate.swift`

```swift
import SwiftUI

/// Base template for detail view cards
///
/// Provides consistent header (icon + title + optional action) and content layout
///
/// Usage:
/// ```swift
/// DetailViewCardTemplate(
///     icon: "mappin.circle",
///     title: "LOCATION",
///     actionIcon: "arrow.triangle.turn.up.right.circle.fill",
///     actionLabel: "Navigate",
///     onAction: { openInMaps() }
/// ) {
///     // Card content
///     Text(address)
/// }
/// ```
struct DetailViewCardTemplate<Content: View>: View {
    let icon: String
    let title: String
    let actionIcon: String?
    let actionLabel: String?
    let onAction: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        icon: String,
        title: String,
        actionIcon: String? = nil,
        actionLabel: String? = nil,
        onAction: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.actionIcon = actionIcon
        self.actionLabel = actionLabel
        self.onAction = onAction
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header (icon + title + optional action button)
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(title.uppercased())
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                // Optional action button (e.g., "Navigate", "Edit", "Call")
                if let actionIcon = actionIcon, let actionLabel = actionLabel, let onAction = onAction {
                    Button(action: onAction) {
                        HStack(spacing: 4) {
                            Image(systemName: actionIcon)
                                .font(.system(size: 16))
                            Text(actionLabel)
                                .font(OPSStyle.Typography.caption)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            .padding(.bottom, 8)

            // Content
            content()
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.tertiaryText.opacity(0.2), lineWidth: 1)
        )
    }
}
```

### 3.4 Refactor Existing Cards to Use Template

**LocationCard.swift** - Refactored:
```swift
struct LocationCard: View {
    let address: String
    let latitude: Double?
    let longitude: Double?

    var body: some View {
        DetailViewCardTemplate(
            icon: "mappin.circle",
            title: "Location",
            actionIcon: latitude != nil ? "arrow.triangle.turn.up.right.circle.fill" : nil,
            actionLabel: latitude != nil ? "Navigate" : nil,
            onAction: latitude != nil ? openInMaps : nil
        ) {
            Text(address)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
    }

    private func openInMaps() {
        // ... existing implementation
    }
}
```

**ClientInfoCard.swift** - Refactored:
```swift
struct ClientInfoCard: View {
    let clientName: String
    let contactName: String?
    let email: String?
    let phone: String?

    var body: some View {
        DetailViewCardTemplate(
            icon: "person.circle",
            title: "Client",
            actionIcon: email != nil || phone != nil ? "phone.circle.fill" : nil,
            actionLabel: email != nil || phone != nil ? "Contact" : nil,
            onAction: email != nil || phone != nil ? showContactOptions : nil
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Client name
                Text(clientName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                // Contact info rows
                if let contactName = contactName {
                    InfoRow(icon: "person", text: contactName)
                }
                if let email = email {
                    InfoRow(icon: "envelope", text: email)
                }
                if let phone = phone {
                    InfoRow(icon: "phone", text: phone)
                }
            }
        }
    }

    // ... helper methods
}
```

### 3.5 Benefits of Template Approach

1. **Consistent Structure**: All cards have icon + title + optional action
2. **Automatic Uppercase**: Title automatically uppercased
3. **Standardized Styling**: Colors, fonts, spacing, borders all consistent
4. **Less Code**: Cards become simpler - just pass data and content
5. **Easy to Extend**: Add new card types by using template

---

## Part 4: Implementation Plan

### Phase 1: Create Shared Components (2-3 hours)

**Tasks**:
1. Create `StandardSheetToolbar.swift` with modifier
2. Extract `ExpandableSection.swift` from ProjectFormSheet
3. Create `DetailViewCardTemplate.swift`
4. Add all three to `COMPONENTS.md` documentation

**Files to create**:
- `OPS/Styles/Components/StandardSheetToolbar.swift`
- `OPS/Styles/Components/ExpandableSection.swift`
- `OPS/Styles/Components/DetailViewCardTemplate.swift`

### Phase 2: Migrate Sheet Toolbars (4-6 hours)

**Tasks**:
1. Replace toolbar code in 37 files with `.standardSheetToolbar()`
2. Remove duplicate NavigationView wrapper patterns
3. Test each sheet to ensure functionality preserved

**Estimated time**: ~10 minutes per file × 37 files = 6 hours

### Phase 3: Migrate ExpandableSection Usage (1-2 hours)

**Tasks**:
1. Remove local ExpandableSection from ProjectFormSheet
2. Import shared ExpandableSection in ProjectFormSheet and TaskFormSheet
3. Add ExpandableSection to ProjectDetailsView and TaskDetailsView sections

**Estimated time**: 2 hours

### Phase 4: Refactor Detail Cards (2-3 hours)

**Tasks**:
1. Refactor LocationCard to use DetailViewCardTemplate
2. Refactor ClientInfoCard to use DetailViewCardTemplate
3. Refactor NotesCard to use DetailViewCardTemplate
4. Refactor TeamMembersCard to use DetailViewCardTemplate
5. Ensure ProjectDetailsView and TaskDetailsView use all cards consistently

**Estimated time**: 30 min per card × 4 cards + 1 hour testing = 3 hours

### Phase 5: Documentation (1 hour)

**Tasks**:
1. Update `COMPONENTS.md` with StandardSheetToolbar usage
2. Update `COMPONENTS.md` with ExpandableSection usage
3. Update `COMPONENTS.md` with DetailViewCardTemplate usage
4. Add "Sheet Patterns" section to UI_GUIDELINES.md

---

## Part 5: Expected Impact

### Before
- **37 files** with 555 lines of duplicate toolbar code
- **ExpandableSection** buried in ProjectFormSheet, can't reuse
- **4 detail cards** with inconsistent internal structure
- **No template** for creating new detail cards
- **Inconsistent usage** of cards across detail views

### After
- **0 duplicate toolbar code** (all use `.standardSheetToolbar()`)
- **ExpandableSection** available as shared component for all forms
- **4 detail cards** all using consistent DetailViewCardTemplate
- **Easy to create** new detail cards (just pass data to template)
- **Enforced consistency** through template usage

### Code Reduction
- **666 lines** of toolbar code eliminated
- **50-100 lines** in detail cards (reduced through template)
- **Easier maintenance** - change template, updates all cards
- **Faster development** - new sheets/cards take minutes

---

## Part 6: Usage Examples

### Creating a New Form Sheet

**Before** (25+ lines):
```swift
struct NewFormSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            // ... content ...
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                // ... more toolbar code ...
            }
        }
    }
}
```

**After** (7 lines):
```swift
struct NewFormSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            // ... content ...
        }
        .standardSheetToolbar(
            title: "Create Item",
            actionText: "Create",
            isActionEnabled: isValid,
            onCancel: { dismiss() },
            onAction: { saveItem() }
        )
    }
}
```

### Creating a New Detail Card

**Before** (40-50 lines of custom styling):
```swift
struct CustomCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star")
                    .font(.system(size: 20))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("CUSTOM SECTION")
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                // ... action button ...
            }
            // ... content ...
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.tertiaryText.opacity(0.2), lineWidth: 1)
        )
    }
}
```

**After** (10 lines with template):
```swift
struct CustomCard: View {
    var body: some View {
        DetailViewCardTemplate(
            icon: "star",
            title: "Custom Section",
            actionIcon: "pencil",
            actionLabel: "Edit",
            onAction: { editContent() }
        ) {
            // Just the content!
            Text("Card content here")
        }
    }
}
```

---

## Conclusion

Three high-impact template opportunities exist:

1. **StandardSheetToolbar** - Eliminates 666 lines across 37 files
2. **ExpandableSection** - Already exists, just needs extraction for reuse
3. **DetailViewCardTemplate** - Enforces consistency across all detail cards

**Total effort**: 10-15 hours
**Total lines saved**: ~700+ lines
**Maintenance benefit**: Massive - change one template, updates entire app

**Recommendation**: Implement **Phase 1-2** (sheet toolbars) immediately as it has the highest ROI and enables faster form development going forward.
