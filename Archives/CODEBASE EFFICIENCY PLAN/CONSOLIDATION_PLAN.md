# OPS Codebase Consolidation & Cleanup Plan

**📖 Document Type**: COMPREHENSIVE IMPLEMENTATION GUIDE (9 Phases)
**🎯 Purpose**: Tracks A, E, F, L, M, N (OPSStyle Expansion, Styling Migration, Refactoring)
**👉 Start Here**: [README.md](./README.md) → Choose your track

---

**Last Updated**: November 18, 2025

## How to Use This Document

This is the MASTER implementation guide for all styling-related consolidation work.

**For Track A (Expand OPSStyle)** - 🔴 DO THIS FIRST:
- **READ**: OPSSTYLE_GAPS_AND_STANDARDIZATION.md → Part 2
- **FOLLOW**: Phase 1 of this document (Create Reusable Components)
- **Effort**: 4-6 hours, **Impact**: Unblocks all styling migration

**For Track E (Hardcoded Colors Migration)** - Requires Track A:
- **FOLLOW**: Phase 2 of this document
- **Effort**: 15-20 hours, **Impact**: ~815 color violations fixed

**For Track F (Hardcoded Icons Migration)** - Requires Track A:
- **FOLLOW**: Phase 4 of this document
- **Effort**: 20-25 hours, **Impact**: ~438 icon violations fixed

**For Track L (DataController Refactor)**:
- **FOLLOW**: Phase 6 of this document
- **Effort**: 8-10 hours, **Impact**: Better organization

**For Track M (Folder Reorganization)** - ⚠️ DO THIS LAST:
- **FOLLOW**: Phase 7 of this document
- **Effort**: 4-6 hours, **Impact**: Easier navigation

**For Track N (Remaining Migrations)**:
- **FOLLOW**: Phases 3, 5, 8, 9 of this document
- **Effort**: 25-30 hours, **Impact**: Complete OPSStyle adoption

**Prerequisites**:
- Phase 1 (Track A): ✅ None - foundation for all styling work
- Phases 2-9: 🔴 Require Phase 1 completion

**Total Effort**: 60-75 hours
**Total Impact**: ~5,077 styling violations fixed, complete OPSStyle adoption

**Execution Order**: ⚠️ Phases must be executed in order to avoid breaking dependencies.

---

## 🚨 CRITICAL RULES FOR IMPLEMENTATION

### Rule 1: ProjectFormSheet is the Styling Authority

**READ [PROJECTFORMSHEET_AUTHORITY.md](./PROJECTFORMSHEET_AUTHORITY.md) BEFORE starting any track.**

This document defines the AUTHORITATIVE patterns from `ProjectFormSheet.swift` for:
- Section card styling (ExpandableSection)
- Navigation bar styling
- Input field styling (TextField)
- TextEditor styling (with Cancel/Save buttons)

When consolidating UI code:
- 👍 **KEEP** ProjectFormSheet's patterns
- 👎 **MIGRATE** other files to match ProjectFormSheet
- ⚠️ **ASK USER** before deleting any conflicting implementation

### Rule 2: ALWAYS Ask Before Deleting

**⚠️ MANDATORY**: Before deleting ANY duplicate code during consolidation:

1. **STOP** and compare both implementations
2. **DOCUMENT** differences with file paths and line numbers
3. **ASK THE USER** which version to keep
4. **WAIT** for user confirmation
5. **ONLY THEN** delete the rejected version

**Example Question Format**:
```
⚠️ DUPLICATE COLOR USAGE FOUND

FILE: TaskDetailsView.swift line 145

CURRENT: .foregroundColor(.white)
AUTHORITY: OPSStyle.Colors.primaryText

Should I replace this with OPSStyle.Colors.primaryText?
(This might affect UI appearance if there's a reason for .white)
```

**Do NOT assume** all duplicates should be removed. Some may be intentional.

---

### Rule 3: Semantic Colors, Not Generic Colors

**⚠️ CRITICAL PRINCIPLE**: OPSStyle.Colors must use **semantic (context-specific) naming**, not generic color names.

**✅ CORRECT - Semantic naming**:
```swift
static let cardBorder = Color.white.opacity(0.1)        // For card borders
static let secondaryText = Color("TextSecondary")        // For secondary text
static let inputFieldBorder = Color.white.opacity(0.2)  // For input field borders
```

**❌ WRONG - Generic naming**:
```swift
static let lightGray = Color.white.opacity(0.1)  // Too generic - what is it for?
static let gray60 = Color("TextSecondary")        // Color value, not purpose
```

**Key Principle**: Even if two colors have **identical RGB values**, they must be **separate definitions** if they serve different semantic purposes.

**Example**:
```swift
// Both might be Color.white.opacity(0.1), but serve different purposes
static let cardBorder = Color.white.opacity(0.1)        // Card structure
static let disabledOverlay = Color.white.opacity(0.1)  // Disabled state
static let divider = Color.white.opacity(0.1)          // Section dividers
```

This allows each to evolve independently as design requirements change.

**When migrating colors**:
1. **Identify the PURPOSE** of the color, not just its value
2. **Check if a semantic color exists** for that purpose
3. **If NO appropriate semantic color exists**:
   - **STOP** and ask the user: "No semantic color exists for [purpose]. Should I add `OPSStyle.Colors.[semanticName]`?"
   - **WAIT** for approval to add the new color
   - **Add with clear comment** explaining the semantic purpose
4. **Only then** migrate the hardcoded color

**Bad**: Forcing `.white` text on a button to use `cardBorder` just because they're both white
**Good**: Creating `buttonTextOnAccent` if buttons need a specific text color

### Rule 3.1: Consolidate Similar UI Elements to Single Semantic Color

**⚠️ CRITICAL**: When the SAME type of UI element uses SLIGHTLY DIFFERENT opacity values across different files, they should be **consolidated to ONE semantic color**.

**Example - Job/Task Card Borders**:
- File 1: Task card border uses `Color.white.opacity(0.2)`
- File 2: Task card border uses `Color.white.opacity(0.3)`
- File 3: Project card border uses `Color.white.opacity(0.25)`

**❌ WRONG Approach**: Create three separate colors
```swift
static let taskCardBorder02 = Color.white.opacity(0.2)
static let taskCardBorder03 = Color.white.opacity(0.3)
static let projectCardBorder025 = Color.white.opacity(0.25)
```

**✅ CORRECT Approach**: Create ONE semantic color for the shared purpose
```swift
static let jobCardBorder = Color.white.opacity(0.2)  // Used for all project/task card borders
```

**Why**: These small opacity variations (0.2 vs 0.3 vs 0.25) are likely unintentional inconsistencies, not deliberate design choices. Consolidating them:
- Ensures visual consistency across the app
- Reduces the number of semantic colors needed
- Makes future design updates easier (change once, applies everywhere)

**When migrating**:
1. **Identify the SEMANTIC PURPOSE**: "What is this color used for?" (e.g., card border, input field border, divider)
2. **Group by PURPOSE, not by VALUE**: All card borders should use the same semantic color
3. **Choose ONE representative opacity**: Usually the most common value or middle value
4. **If unsure which elements are "the same purpose"**: **ASK THE USER** before consolidating

**Example Question Format**:
```
⚠️ CONSOLIDATION DECISION NEEDED

I found these similar usages:
- ProjectCard.swift:45 - Card border uses Color.white.opacity(0.2)
- TaskCard.swift:89 - Card border uses Color.white.opacity(0.3)
- EventCard.swift:112 - Card border uses Color.white.opacity(0.25)

Should these all use the same semantic color `jobCardBorder`?
If yes, which opacity value should I use? (0.2, 0.25, or 0.3)
```

---

## ⚠️ CRITICAL UPDATE - Comprehensive Audit Completed

**November 18, 2025**: Comprehensive line-by-line audit of all 283 Swift files reveals **significantly larger scope** than initially estimated.

**Key Findings**:
- **5,077 total hardcoded styling instances** (not ~500)
- **1,372 color instances** across 100+ files (not ~50 in 20 files)
- **498 icon instances** across 122 files (not 207)
- **Effort revised**: 60-75 hours (not 25-35 hours)

**See**: `HARDCODED_VALUES_AUDIT.md` for complete breakdown and analysis.

**Impact**: Phases 2 and 4 require 3-5x more effort than originally estimated. All phase effort estimates have been updated below.

---

## Table of Contents
1. [Phase 1: Create Reusable Components](#phase-1-create-reusable-components)
2. [Phase 2: Migrate Hardcoded Colors](#phase-2-migrate-hardcoded-colors)
3. [Phase 3: Migrate Hardcoded Fonts](#phase-3-migrate-hardcoded-fonts)
4. [Phase 4: Migrate Hardcoded Icons](#phase-4-migrate-hardcoded-icons)
5. [Phase 5: Remove Print Statements](#phase-5-remove-print-statements)
6. [Phase 6: Refactor DataController](#phase-6-refactor-datacontroller)
7. [Phase 7: Reorganize Folder Structure](#phase-7-reorganize-folder-structure)
8. [Phase 8: Remove Dead Code](#phase-8-remove-dead-code)
9. [Phase 9: Update Documentation](#phase-9-update-documentation)

---

## Phase 1: Create Reusable Components

### Task 1.1: Create SectionHeader Component

**File**: `OPS/Styles/Components/SectionHeader.swift`

**Action**: Create new file with content:

```swift
import SwiftUI

/// Standardized section header used throughout the app
/// Replaces 25+ duplicate implementations
struct SectionHeader: View {
    let title: String
    var padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16)

    var body: some View {
        Text(title.uppercased())
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(padding)
    }
}
```

**Then update these 25 files** to use SectionHeader:

1. `OPS/Views/Components/Project/ProjectDetailsView.swift` - Replace all section headers
2. `OPS/Views/Components/Tasks/TaskDetailsView.swift` - Replace all section headers
3. `OPS/Views/JobBoard/ClientListView.swift` - Replace section headers
4. `OPS/Views/JobBoard/ProjectFormSheet.swift` - Replace section headers
5. `OPS/Views/JobBoard/TaskFormSheet.swift` - Replace section headers
6. `OPS/Views/JobBoard/ClientFormSheet.swift` - Replace section headers
7. `OPS/Views/Settings/ProfileSettingsView.swift` - Replace section headers
8. `OPS/Views/Settings/OrganizationSettingsView.swift` - Replace section headers
9. `OPS/Views/Settings/AppSettingsView.swift` - Replace section headers
10. `OPS/Views/Settings/NotificationSettingsView.swift` - Replace section headers
11. `OPS/Views/Settings/SecuritySettingsView.swift` - Replace section headers
12. `OPS/Views/Settings/MapSettingsView.swift` - Replace section headers
13. `OPS/Views/Settings/ProjectSettingsView.swift` - Replace section headers
14. `OPS/Views/Settings/TaskSettingsView.swift` - Replace section headers
15. `OPS/Views/Settings/DataStorageSettingsView.swift` - Replace section headers
16. `OPS/Views/Components/Team/ProjectTeamView.swift` - Replace section headers
17. `OPS/Views/Components/Team/TaskTeamView.swift` - Replace section headers
18. `OPS/Views/Components/Team/OrganizationTeamView.swift` - Replace section headers
19. `OPS/Views/Components/Team/CompanyTeamMembersListView.swift` - Replace section headers
20. `OPS/Views/Components/Client/SubClientListView.swift` - Replace section headers
21. `OPS/Views/Components/Images/ProjectImagesSection.swift` - Replace section headers
22. `OPS/Views/Components/Images/ProjectPhotosGrid.swift` - Replace section headers
23. `OPS/Views/JobBoard/TaskTypeDetailSheet.swift` - Replace section headers
24. `OPS/Views/JobBoard/JobBoardProjectListView.swift` - Replace section headers
25. `OPS/Views/JobBoard/JobBoardDashboard.swift` - Replace section headers

**Pattern to find and replace**:
```swift
// FIND:
Text("SECTION NAME")
    .font(OPSStyle.Typography.captionBold)
    .foregroundColor(OPSStyle.Colors.secondaryText)
    .padding(.horizontal, 16)
    .padding(.top, 16)
    // (any variation of padding)

// REPLACE WITH:
SectionHeader(title: "Section Name")
```

---

### Task 1.2: Create InfoRow Component

**File**: `OPS/Styles/Components/InfoRow.swift`

**Action**: Create new file with content:

```swift
import SwiftUI

/// Standardized info row with icon, title, value, and optional chevron
/// Replaces 40+ duplicate implementations
struct InfoRow: View {
    let icon: String  // Use OPSStyle.Icons constants
    let title: String?
    let value: String
    var valueColor: Color = OPSStyle.Colors.primaryText
    var showChevron: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(action != nil ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                if let title = title {
                    Text(title)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Text(value)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(valueColor)
            }

            Spacer()

            if showChevron || action != nil {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            action?()
        }
    }
}
```

**Then update these 40+ files** to use InfoRow - search for pattern:
```swift
HStack(spacing: 12) {
    Image(systemName:
    // ... with VStack containing Text elements
}
```

---

### Task 1.3: Create ContactRow Component

**File**: `OPS/Styles/Components/ContactRow.swift`

**Action**: Create new file:

```swift
import SwiftUI

/// Standardized contact row with tap-to-call/email/navigate functionality
struct ContactRow: View {
    enum ContactType {
        case email(String)
        case phone(String)
        case address(String, lat: Double?, lon: Double?)

        var icon: String {
            switch self {
            case .email: return OPSStyle.Icons.envelope
            case .phone: return OPSStyle.Icons.phone
            case .address: return OPSStyle.Icons.mapPin
            }
        }

        var label: String {
            switch self {
            case .email: return "Email"
            case .phone: return "Phone"
            case .address: return "Address"
            }
        }

        var value: String {
            switch self {
            case .email(let email): return email
            case .phone(let phone): return phone
            case .address(let address, _, _): return address
            }
        }
    }

    let contact: ContactType
    var tappable: Bool = true

    var body: some View {
        InfoRow(
            icon: contact.icon,
            title: contact.label,
            value: contact.value,
            showChevron: tappable,
            action: tappable ? performAction : nil
        )
    }

    private func performAction() {
        switch contact {
        case .email(let email):
            if let url = URL(string: "mailto:\(email)") {
                UIApplication.shared.open(url)
            }
        case .phone(let phone):
            let cleaned = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let url = URL(string: "tel:\(cleaned)") {
                UIApplication.shared.open(url)
            }
        case .address(_, let lat, let lon):
            if let lat = lat, let lon = lon {
                let url = URL(string: "maps://?daddr=\(lat),\(lon)")!
                UIApplication.shared.open(url)
            }
        }
    }
}
```

---

## Phase 2: Migrate Hardcoded Colors

**⚠️ CRITICAL UPDATE**: Comprehensive audit reveals **1,372 color instances** across **100+ files**, not the originally estimated ~50 instances in 20 files. See `HARDCODED_VALUES_AUDIT.md` for complete breakdown.

**Actual scope**:
- Color names (`.white`, `.black`, etc.): **1,015 instances**
- Color initializers (`Color(red:`, `Color(hex:`): **357 instances**
- **True violations**: ~815 instances (excluding legitimate onboarding/picker usage)
- **Estimated effort**: 15-20 hours (not 2-3 hours as originally estimated)

### Task 2.1: Update OPSStyle.Colors (if needed)

**File**: `OPS/Styles/OPSStyle.swift`

**Action**: Verify these colors exist, add if missing:

```swift
// Verify presence:
static let errorStatus = Color(hex: "#931A32")
static let warningStatus = Color(hex: "#C4A868")
static let successStatus = Color(hex: "#A5B368")
```

---

### Task 2.2: Migrate Hardcoded Colors - Batch Pattern Matching

**⚠️ CRITICAL**: Follow Rule 3 (Semantic Colors) - identify the PURPOSE of each color, not just its value.

**Process - Batch Analysis (20 files at a time)**:

1. **Analyze batch of 20 files** to find all hardcoded colors
2. **Group by pattern** across all files:
   - Same color + same element type + same context = one pattern
   - Example: "Color.white.opacity(0.1) on RoundedRectangle borders" appears in 15 files
3. **Categorize patterns**:
   - **Clear patterns** (auto-fix): Common semantic purposes already in OPSStyle
   - **New patterns** (need decision): Same usage across multiple files, but no semantic color exists
   - **Unique cases** (need approval): One-off usages that don't fit patterns
4. **Present pattern summary once**:
   ```
   BATCH 1 (Files 1-20) - Pattern Analysis:

   CLEAR PATTERNS (auto-fix):
   - Text(...).foregroundColor(.white) → primaryText (found in 18/20 files, 45 instances)
   - Color.white.opacity(0.1) on card borders → cardBorder (found in 12/20 files, 28 instances)

   NEW SEMANTIC COLORS NEEDED (ask once):
   - Color.white.opacity(0.15) on Divider() (found in 8/20 files, 15 instances)
     → Should I create OPSStyle.Colors.divider?
   - Color.black.opacity(0.5) on overlay backgrounds (found in 5/20 files, 8 instances)
     → Should I create OPSStyle.Colors.modalOverlay?

   UNIQUE CASES (need approval):
   - Circle().fill(.white) in UniversalJobBoardCard.swift line 442 (1 instance)
     → Purpose unclear, what is this circle for?
   ```
5. **Get approval for all patterns in batch**
6. **Apply across all files at once**

**Benefits of batch approach**:
- Ask once per pattern, not once per file
- Discover cross-file patterns
- More efficient decision-making
- Consistent application

---

#### File: `OPS/Views/Components/Common/PushInMessage.swift`

**Find**:
```swift
Color(hex: "#FF6B6B")
Color(red: 0.95, green: 0.95, blue: 0.97)
```

**Semantic Analysis**:
- `#FF6B6B` → Error/alert color for message background
- `rgb(0.95, 0.95, 0.97)` → Light background for message container

**Replace**:
```swift
OPSStyle.Colors.errorStatus      // Semantic: error message background
OPSStyle.Colors.cardBackground   // Semantic: message container background
```

---

#### File: `OPS/Views/JobBoard/ProjectManagementSheets.swift`

**Find**: All instances of `Color(hex:`, `.opacity()` on backgrounds

**Replace**: With appropriate **semantic** OPSStyle.Colors constants

**Pattern Examples**:
- `Color.white.opacity(0.1)` on card border → `OPSStyle.Colors.cardBorder` ✅ (semantic: card structure)
- `Color.white.opacity(0.1)` on divider → Ask: "Create `OPSStyle.Colors.divider`?" 🤔
- `Color.black.opacity(0.8)` on background → `OPSStyle.Colors.cardBackgroundDark` ✅ (semantic: card background)
- `Text(...).foregroundColor(.white)` → `OPSStyle.Colors.primaryText` ✅ (semantic: primary text)
- `Circle().fill(.white)` → Ask: "What is this circle for? Purpose unclear" 🤔

**If no semantic color exists**:
```
⚠️ NEW SEMANTIC COLOR NEEDED

FILE: ProjectManagementSheets.swift line 245
ELEMENT: Divider line between sections
CURRENT: Color.white.opacity(0.15)
PURPOSE: Section separator/divider

No existing semantic color for dividers.
Should I add: OPSStyle.Colors.divider = Color.white.opacity(0.15) ?

Note: This is semantically different from cardBorder even if the value is similar.
```

---

#### Files with Hardcoded Colors (20 high-priority + 80+ remaining):

**High-Priority (20 files)**:
1. `OPS/Views/Components/Common/PushInMessage.swift`
2. `OPS/Views/JobBoard/ProjectManagementSheets.swift`
3. `OPS/Views/JobBoard/ProjectFormSheet.swift`
4. `OPS/Views/Components/Common/OptionalSectionPill.swift`
5. `OPS/Utilities/UIComponents.swift`
6. `OPS/Views/JobBoard/JobBoardView.swift`
7. `OPS/Views/JobBoard/JobBoardProjectListView.swift`
8. `OPS/Views/JobBoard/UniversalJobBoardCard.swift`
9. `OPS/Views/Components/Tasks/TaskTestView.swift`
10. `OPS/Views/JobBoard/TaskFormSheet.swift`
11. `OPS/Views/JobBoard/ClientFormSheet.swift`
12. `OPS/Views/MainTabView.swift`
13. `OPS/Views/Calendar Tab/MonthGridView.swift`
14. `OPS/Views/Calendar Tab/ProjectViews/ProjectListView.swift`
15. `OPS/Styles/Components/SegmentedControl.swift`
16. `OPS/Views/JobBoard/JobBoardDashboard.swift`
17. `OPS/Views/Calendar Tab/Components/CalendarEventCard.swift`
18. `OPS/Views/Settings/OrganizationSettingsView.swift`
19. `OPS/Views/Debug/RelinkCalendarEventsView.swift`
20. `OPS/Views/Components/Tasks/TaskDetailsView.swift`

**Approach**:
- Start with high-priority files (most color violations)
- Process file-by-file with batch review
- Build semantic color vocabulary as we discover needs
- Then expand to remaining 80+ files with established patterns

---

## Phase 3: Migrate Hardcoded Fonts

### Files with Hardcoded Fonts (5 total):

#### File: `OPS/Views/Components/Common/PushInMessage.swift`

**Find**:
```swift
.font(.custom("Mohave-Bold", size: 28))
.font(.custom("Kosugi", size: 14))
```

**Replace**:
```swift
.font(OPSStyle.Typography.title)
.font(OPSStyle.Typography.caption)
```

---

#### File: `OPS/Views/Components/User/ProfileImageUploader.swift`

**Find**: `.font(.custom(...))` patterns

**Replace**: With appropriate OPSStyle.Typography constants

---

#### File: `OPS/Views/Components/User/CompanyAvatar.swift`

**Find**: Font custom definitions

**Replace**: OPSStyle.Typography

---

#### File: `OPS/Views/Components/User/UserAvatar.swift`

**Find**: Font custom definitions

**Replace**: OPSStyle.Typography

---

#### File: `OPS/Styles/Fonts.swift`

**Action**: NO CHANGES - This file correctly defines custom fonts

---

## Phase 4: Migrate Hardcoded Icons

**🎯 SEMANTIC ICON UPDATE (Nov 19, 2025)**: Track A implemented a semantic icon approach with 45 OPS domain icons + 30 generic symbols. Migration strategy updated to prioritize semantic icons over raw SF Symbol names.

**⚠️ CRITICAL UPDATE**: Comprehensive audit reveals **498 icon instances** across **122 files**, not 207 instances. See `HARDCODED_VALUES_AUDIT.md` for complete breakdown.

**Actual scope**:
- Total `systemName:` usage: **498 instances**
- OPSStyle.Icons defined (original): **~60 icons**
- OPSStyle.Icons defined (after Track A): **~75 icons (45 semantic + 30 generic)**
- **Hardcoded violations**: **~438 instances** (88% violation rate)
- **Estimated effort**: 15-20 hours (reduced due to semantic standardization)

### Task 4.1: Update OPSStyle.Icons with Missing Icons

**File**: `OPS/Styles/OPSStyle.swift`

**✅ COMPLETED in Track A**: OPSStyle.Icons now includes:
- **45 semantic OPS domain icons** - Use these FIRST (e.g., `OPSStyle.Icons.project`, `.task`, `.client`)
- **30 generic SF Symbols** - Use only when semantic icons don't fit

**Migration Priority**:
1. **Use semantic icons** - If the icon represents a core OPS concept (project, task, client, etc.), use the semantic icon
2. **Use generic symbols** - Only for generic UI elements (shapes, navigation)
3. **Add to semantic section** - If a new domain concept needs an icon, add it to the semantic section

**Action**: ~~Add to Icons struct any SF Symbols found in code but not defined.~~ Already completed. Focus on migration to semantic icons.

**Common icons to ensure exist**:
```swift
struct Icons {
    // Existing icons...

    // Add if missing:
    static let personCircle = "person.circle"
    static let personCircleFill = "person.circle.fill"
    static let envelope = "envelope"
    static let envelopeFill = "envelope.fill"
    static let phone = "phone"
    static let phoneFill = "phone.fill"
    static let mapPin = "mappin"
    static let mapPinCircle = "mappin.circle"
    static let calendar = "calendar"
    static let calendarBadgePlus = "calendar.badge.plus"
    static let location = "location"
    static let locationFill = "location.fill"
    static let chevronRight = "chevron.right"
    static let chevronDown = "chevron.down"
    static let chevronUp = "chevron.up"
    static let xmark = "xmark"
    static let xmarkCircle = "xmark.circle"
    static let checkmark = "checkmark"
    static let checkmarkCircle = "checkmark.circle"
    static let plusCircle = "plus.circle"
    static let plusCircleFill = "plus.circle.fill"
    static let trash = "trash"
    static let trashFill = "trash.fill"
    static let pencil = "pencil"
    static let pencilCircle = "pencil.circle"
    static let gearshape = "gearshape"
    static let gearshapeFill = "gearshape.fill"
    static let bell = "bell"
    static let bellFill = "bell.fill"
    static let magnifyingglass = "magnifyingglass"
    static let square3Stack3d = "square.3.stack.3d"
    static let listBullet = "list.bullet"
    static let squareAndPencil = "square.and.pencil"
    static let folderBadgePlus = "folder.badge.plus"
    static let docText = "doc.text"
    static let photoOnRectangle = "photo.on.rectangle"
    static let ellipsis = "ellipsis"
    static let ellipsisCircle = "ellipsis.circle"
    static let arrowClockwise = "arrow.clockwise"
    static let cloudSlash = "cloud.slash"
    static let wifi = "wifi"
    static let wifiSlash = "wifi.slash"
    static let exclamationmarkTriangle = "exclamationmark.triangle"
    static let exclamationmarkTriangleFill = "exclamationmark.triangle.fill"
    static let infoCircle = "info.circle"
    static let infoCircleFill = "info.circle.fill"
}
```

---

### Task 4.2: Migrate Icon Strings - High Frequency Files (438 instances)

**Strategy**: Semantic-first migration - understand the icon's purpose, then use the appropriate semantic icon

**Pattern** (Semantic Approach):
```swift
// FIND (context: client list):
Image(systemName: "person.circle")

// REPLACE WITH (semantic):
Image(systemName: OPSStyle.Icons.client)  // Uses semantic icon, not raw SF Symbol name

// FIND (context: team member):
Image(systemName: "person.fill")

// REPLACE WITH (semantic):
Image(systemName: OPSStyle.Icons.teamMember)  // Semantic clarity

// FIND (generic navigation):
Image(systemName: "chevron.right")

// REPLACE WITH (generic symbol - OK since it's not domain-specific):
Image(systemName: OPSStyle.Icons.forward)  // Or use .chevronUp from generic catalog
```

**Key Principle**: Prefer semantic icons (`OPSStyle.Icons.project`) over generic symbols (`OPSStyle.Icons.folderFill`)

**Files to update (by category)**:

#### Onboarding Views (59 instances):
- `OPS/Onboarding/Views/Screens/*.swift` - All 16 screen files

#### Component Views (45 instances):
- `OPS/Views/Components/**/*.swift` - All component files

#### Settings Views (23 instances):
- `OPS/Views/Settings/*.swift` - All 13 settings files

#### JobBoard Views (18 instances):
- `OPS/Views/JobBoard/*.swift` - All Job Board files

#### Calendar Tab (15 instances):
- `OPS/Views/Calendar Tab/**/*.swift` - All calendar files

#### ContentView (14 instances):
- `OPS/ContentView.swift`
- `OPS/Views/MainTabView.swift`

#### Debug Views (22 instances):
- `OPS/Views/Debug/*.swift` - All debug files (lower priority)

---

## Phase 5: Remove Print Statements

### Task 5.1: Keep Critical Logging, Remove Debug Prints

**Strategy**: Review each print statement, keep API/sync logging, remove debug

**Files with excessive prints (270 total)**:

#### Keep (Critical API/Sync Logging):
- `OPS/Network/API/APIService.swift` - Keep API request/response logging
- `OPS/Network/Sync/CentralizedSyncManager.swift` - Keep sync operation logging
- `OPS/Network/ImageSyncManager.swift` - Keep image sync logging

#### Remove (Debug Prints):

**Onboarding Flow (65 instances)**:
- `OPS/Onboarding/ViewModels/*.swift`
- `OPS/Onboarding/Services/*.swift`
- Pattern: `print("DEBUG:`, `print("[ONBOARDING]`

**Debug Views (47 instances)**:
- `OPS/Views/Debug/*.swift` - Can keep these, they're debug-only

**Utilities (56 instances)**:
- `OPS/Utilities/DataController.swift` - Remove most, keep critical state changes
- `OPS/Utilities/*.swift` - Remove debug prints

**ViewModels (59 instances)**:
- `OPS/ViewModels/*.swift` - Remove all debug prints

**Action for each file**:
1. Read file
2. Find all `print(` statements
3. If debug/development print → remove
4. If critical operation logging → keep or migrate to DebugLogger
5. Save file

---

## Phase 6: Refactor DataController

### Task 6.1: Split DataController into Extensions

**Current**: `OPS/Utilities/DataController.swift` (3,687 lines)

**Target Structure**:

```
OPS/Utilities/DataController/
├── DataController.swift (core state management, ~200 lines)
├── DataController+Auth.swift (~400 lines)
├── DataController+Sync.swift (~800 lines)
├── DataController+Projects.swift (~500 lines)
├── DataController+Tasks.swift (~400 lines)
├── DataController+Calendar.swift (~300 lines)
├── DataController+Cleanup.swift (~600 lines)
└── DataController+Migration.swift (~500 lines)
```

**Step-by-step**:

1. **Create folder**: `OPS/Utilities/DataController/`

2. **Read existing DataController.swift** and identify sections:
   - Auth-related functions
   - Sync coordination
   - Project management
   - Task management
   - Calendar management
   - Data cleanup
   - Migration logic

3. **Create core DataController.swift**:
```swift
import SwiftUI
import SwiftData

@MainActor
final class DataController: ObservableObject {
    // MARK: - Properties
    @Published var currentUser: User?
    @Published var currentCompany: Company?
    @Published var isAuthenticated = false
    @Published var syncInProgress = false

    let modelContainer: ModelContainer
    let modelContext: ModelContext

    // Services
    let apiService: APIService
    let authManager: AuthManager
    let syncManager: CentralizedSyncManager
    let subscriptionManager: SubscriptionManager
    let locationManager: LocationManager
    let notificationManager: NotificationManager
    let connectivityMonitor: ConnectivityMonitor

    // MARK: - Initialization
    init(modelContainer: ModelContainer) {
        // ... initialization code only
    }
}

// Extensions defined in separate files
```

4. **Create DataController+Auth.swift**:
   - Move all authentication functions
   - Login, logout, token management
   - Session handling

5. **Create DataController+Sync.swift**:
   - Move all sync coordination
   - Trigger sync functions
   - Connectivity handling

6. **Create DataController+Projects.swift**:
   - Move project CRUD helpers
   - Project filtering/fetching

7. **Create DataController+Tasks.swift**:
   - Move task CRUD helpers
   - Task filtering/fetching

8. **Create DataController+Calendar.swift**:
   - Move calendar event helpers
   - Date filtering logic

9. **Create DataController+Cleanup.swift**:
   - Move data cleanup functions
   - Cache clearing
   - Logout cleanup

10. **Create DataController+Migration.swift**:
    - Move one-time migration logic
    - Data health checks

11. **Update Xcode project** to include new files

12. **Test** that all functionality still works

---

## Phase 7: Reorganize Folder Structure

### Current Issues:
- Views folder has 143 files with inconsistent organization
- Some components in Views/Components, some scattered
- Utilities has 28 files, some should be in different locations

### Target Structure:

```
OPS/
├── App/
│   ├── OPSApp.swift
│   ├── AppDelegate.swift
│   ├── AppState.swift
│   └── ContentView.swift
│
├── Core/
│   ├── DataController/
│   │   ├── DataController.swift
│   │   ├── DataController+Auth.swift
│   │   ├── DataController+Sync.swift
│   │   ├── DataController+Projects.swift
│   │   ├── DataController+Tasks.swift
│   │   ├── DataController+Calendar.swift
│   │   ├── DataController+Cleanup.swift
│   │   └── DataController+Migration.swift
│   ├── DataHealthManager.swift
│   └── AppConfiguration.swift
│
├── Models/
│   ├── SwiftData/
│   │   ├── Project.swift
│   │   ├── ProjectTask.swift
│   │   ├── CalendarEvent.swift
│   │   ├── User.swift
│   │   ├── Company.swift
│   │   ├── Client.swift
│   │   ├── SubClient.swift
│   │   ├── TaskType.swift
│   │   ├── TaskStatusOption.swift
│   │   ├── TeamMember.swift
│   │   └── OpsContact.swift
│   ├── Enums/
│   │   ├── Status.swift
│   │   ├── UserRole.swift
│   │   ├── SubscriptionEnums.swift
│   │   └── BubbleTypes.swift
│   └── Supporting/
│       └── BubbleImage.swift
│
├── Network/
│   ├── API/
│   │   ├── APIService.swift
│   │   ├── BubbleFields.swift
│   │   └── APIError.swift
│   ├── DTOs/
│   │   └── [all DTO files]
│   ├── Endpoints/
│   │   └── [all endpoint files]
│   ├── Sync/
│   │   ├── CentralizedSyncManager.swift
│   │   ├── ImageSyncManager.swift
│   │   └── BackgroundTaskManager.swift
│   ├── Auth/
│   │   └── [all auth files]
│   ├── Services/
│   │   ├── ConnectivityMonitor.swift
│   │   ├── S3UploadService.swift
│   │   └── PresignedURLUploadService.swift
│   └── Managers/
│       ├── SubscriptionManager.swift
│       ├── BubbleSubscriptionService.swift
│       └── NotificationManager.swift
│
├── Features/
│   ├── Authentication/
│   │   ├── Views/
│   │   │   ├── LoginView.swift
│   │   │   ├── ForgotPasswordView.swift
│   │   │   └── SimplePINEntryView.swift
│   │   └── Onboarding/
│   │       ├── Coordinators/
│   │       ├── Models/
│   │       ├── Services/
│   │       ├── ViewModels/
│   │       └── Views/
│   │
│   ├── Home/
│   │   ├── HomeView.swift
│   │   ├── HomeContentView.swift
│   │   └── Components/
│   │       ├── ProjectCarousel.swift
│   │       └── EventCarousel.swift
│   │
│   ├── Calendar/
│   │   ├── ViewModels/
│   │   │   └── CalendarViewModel.swift
│   │   ├── Views/
│   │   │   ├── MonthGridView.swift
│   │   │   └── ScheduleView.swift
│   │   ├── Components/
│   │   │   ├── CalendarHeaderView.swift
│   │   │   ├── DayCell.swift
│   │   │   ├── WeekDayCell.swift
│   │   │   └── CalendarEventCard.swift
│   │   └── ProjectViews/
│   │       ├── DayEventsSheet.swift
│   │       └── ProjectListView.swift
│   │
│   ├── JobBoard/
│   │   ├── Dashboard/
│   │   │   ├── JobBoardView.swift
│   │   │   ├── JobBoardDashboard.swift
│   │   │   └── JobBoardAnalyticsView.swift
│   │   ├── Projects/
│   │   │   ├── JobBoardProjectListView.swift
│   │   │   ├── ProjectFormSheet.swift
│   │   │   └── ProjectManagementSheets.swift
│   │   ├── Tasks/
│   │   │   ├── TaskFormSheet.swift
│   │   │   └── TaskManagementSheets.swift
│   │   ├── Clients/
│   │   │   ├── ClientListView.swift
│   │   │   ├── ClientFormSheet.swift
│   │   │   └── ClientDeletionSheet.swift
│   │   ├── TaskTypes/
│   │   │   ├── TaskTypeDetailSheet.swift
│   │   │   ├── TaskTypeFormSheet.swift
│   │   │   └── TaskTypeDeletionSheet.swift
│   │   └── Components/
│   │       ├── UniversalJobBoardCard.swift
│   │       └── UniversalSearchBar.swift
│   │
│   ├── Map/
│   │   ├── Core/
│   │   │   ├── MapCoordinator.swift
│   │   │   ├── NavigationEngine.swift
│   │   │   ├── LocationService.swift
│   │   │   └── KalmanHeadingFilter.swift
│   │   └── Views/
│   │       ├── MapView.swift
│   │       ├── MapContainer.swift
│   │       ├── SafeMapContainer.swift
│   │       ├── MapNavigationView.swift
│   │       ├── ProjectMarkerPopup.swift
│   │       └── MapControlsView.swift
│   │
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── ProfileSettingsView.swift
│   │   ├── OrganizationSettingsView.swift
│   │   ├── AppSettingsView.swift
│   │   ├── NotificationSettingsView.swift
│   │   ├── SecuritySettingsView.swift
│   │   ├── MapSettingsView.swift
│   │   ├── ProjectSettingsView.swift
│   │   ├── TaskSettingsView.swift
│   │   ├── DataStorageSettingsView.swift
│   │   ├── WhatsNewView.swift
│   │   ├── ComingSoonView.swift
│   │   └── SettingsSearchSheet.swift
│   │
│   ├── Subscription/
│   │   ├── PlanSelectionView.swift
│   │   ├── PlanSelectionView+CheckoutSession.swift
│   │   ├── SeatManagementView.swift
│   │   ├── GracePeriodBanner.swift
│   │   └── SubscriptionLockoutView.swift
│   │
│   └── Debug/
│       └── [all debug views]
│
├── Components/
│   ├── Common/
│   │   ├── AppHeader.swift
│   │   ├── CustomTabBar.swift
│   │   ├── RefreshIndicator.swift
│   │   ├── NavigationBanner.swift
│   │   ├── NotificationBanner.swift
│   │   ├── SyncStatusIndicator.swift
│   │   ├── NetworkStatusIndicator.swift
│   │   ├── LoadingIndicators/
│   │   │   ├── TacticalLoadingBar.swift
│   │   │   └── ImageSyncProgressView.swift
│   │   └── Alerts/
│   │       ├── CustomAlert.swift
│   │       └── PushInMessage.swift
│   │
│   ├── Cards/
│   │   ├── ClientInfoCard.swift
│   │   ├── LocationCard.swift
│   │   ├── NotesCard.swift
│   │   ├── TeamMembersCard.swift
│   │   └── ProjectCard.swift
│   │
│   ├── Forms/
│   │   ├── AddressAutocompleteField.swift
│   │   ├── AddressSearchField.swift
│   │   ├── ContactPicker.swift
│   │   └── Scheduling/
│   │       └── CalendarSchedulerSheet.swift
│   │
│   ├── Project/
│   │   ├── ProjectDetailsView.swift
│   │   ├── ProjectHeader.swift
│   │   ├── ProjectActionBar.swift
│   │   ├── ProjectSheetContainer.swift
│   │   └── ProjectTeamView.swift
│   │
│   ├── Task/
│   │   ├── TaskDetailsView.swift
│   │   ├── TaskListView.swift
│   │   ├── TaskCompletionChecklistSheet.swift
│   │   └── TaskTeamView.swift
│   │
│   ├── User/
│   │   ├── UserAvatar.swift
│   │   ├── CompanyAvatar.swift
│   │   ├── UserProfileCard.swift
│   │   └── ProfileImageUploader.swift
│   │
│   ├── Team/
│   │   ├── TeamMemberListView.swift
│   │   ├── OrganizationTeamView.swift
│   │   ├── CompanyTeamListView.swift
│   │   ├── CompanyTeamMembersListView.swift
│   │   ├── TeamRoleManagementView.swift
│   │   └── TeamRoleAssignmentSheet.swift
│   │
│   ├── Client/
│   │   ├── ClientSearchField.swift
│   │   ├── ClientEditSheet.swift
│   │   ├── SubClientListView.swift
│   │   └── SubClientEditSheet.swift
│   │
│   ├── Contact/
│   │   ├── ContactDetailView.swift
│   │   ├── ContactDetailSheet.swift
│   │   ├── ContactUpdater.swift
│   │   └── ContactCreatorView.swift
│   │
│   ├── Images/
│   │   ├── ProjectPhotosGrid.swift
│   │   ├── ProjectImagesSection.swift
│   │   ├── ProjectImagesSimple.swift
│   │   ├── ProjectImageView.swift
│   │   ├── ImagePicker.swift
│   │   └── ImagePickerView.swift
│   │
│   └── Map/
│       ├── MiniMapView.swift
│       ├── ProjectMapView.swift
│       ├── ProjectMapAnnotation.swift
│       └── RouteDirectionsView.swift
│
├── Styles/
│   ├── OPSStyle.swift
│   ├── Fonts.swift
│   └── Components/
│       ├── SectionHeader.swift (NEW)
│       ├── InfoRow.swift (NEW)
│       ├── ContactRow.swift (NEW)
│       ├── ButtonStyles.swift
│       ├── CardStyles.swift
│       ├── StatusBadge.swift
│       ├── IconBadge.swift
│       ├── FormInputs.swift
│       ├── FormTextField.swift
│       ├── ListItems.swift
│       ├── CategoryCard.swift
│       ├── ProfileCard.swift
│       ├── SettingsHeader.swift
│       └── SegmentedControl.swift
│
├── Utilities/
│   ├── Helpers/
│   │   ├── DateHelper.swift
│   │   ├── DateFormatter+Bubble.swift
│   │   ├── SwiftDataHelper.swift
│   │   ├── FieldErrorHandler.swift
│   │   ├── ArrayTransformer.swift
│   │   └── String+AddressFormatting.swift
│   ├── Managers/
│   │   ├── LocationManager.swift
│   │   ├── DeviceHeadingManager.swift
│   │   ├── InProgressManager.swift
│   │   └── SimplePINManager.swift
│   ├── Caching/
│   │   ├── ImageCache.swift
│   │   └── ImageFileManager.swift
│   ├── UI/
│   │   ├── UIComponents.swift
│   │   ├── TabBarPadding.swift
│   │   ├── SwipeBackGesture.swift
│   │   ├── SwipeBackGestureModifier.swift
│   │   └── KeyboardDismissalModifier.swift
│   ├── Services/
│   │   └── SimplifiedBubbleService.swift
│   └── Debug/
│       └── DebugLogger.swift
│
├── Extensions/
│   ├── UIKit+Extensions.swift
│   ├── UIImage+Extensions.swift
│   └── UIApplication+Extensions.swift
│
├── Navigation/
│   └── PersistentNavigationHeader.swift
│
├── Resources/
│   ├── Assets.xcassets/
│   ├── Fonts/
│   └── GoogleService-Info.plist
│
└── Tests/
    ├── OPSTests.swift
    ├── OPSUITests.swift
    └── OPSUITestsLaunchTests.swift
```

### Migration Steps:

1. **Create new folder structure** (don't move files yet)
2. **Update Xcode project** to recognize new folders
3. **Move files systematically** by category:
   - Start with Models (least dependencies)
   - Then Network layer
   - Then Utilities
   - Then Components
   - Then Features
   - Finally App files
4. **Update all imports** after each category move
5. **Build and test** after each category
6. **Delete empty old folders**

---

## Phase 8: Remove Dead Code

### Task 8.1: Remove Deprecated Modifiers

**File**: `OPS/Styles/OPSStyle.swift`

**Lines to remove**: 305-327

**Remove these deprecated view extensions**:
```swift
// REMOVE:
func primaryButtonStyle() -> some View
func secondaryButtonStyle() -> some View
func iconButtonStyle() -> some View
func cardStyle() -> some View
```

**Replace usage throughout codebase with**:
```swift
// OLD:
.primaryButtonStyle()

// NEW:
.opsPrimaryButtonStyle()
```

---

### Task 8.2: Remove Legacy StatusBadge

**File**: `OPS/Styles/OPSStyle.swift`

**Line 289**: Remove `LegacyStatusBadge` struct

**Search codebase** for `LegacyStatusBadge` usage, replace with `StatusBadge`

---

### Task 8.3: Address TODOs

**7 TODO comments found:**

1. **PresignedURLUploadService.swift**:
   ```swift
   // TODO: Update this to match your actual Bubble workflow name
   // ACTION: Update workflow name or remove TODO
   ```

2. **StripeConfiguration.swift** (2 instances):
   ```swift
   // TODO: Implement actual API call to Bubble
   // ACTION: Implement or remove placeholder
   ```

3. **CopyFromProjectSheet.swift** (2 instances):
   ```swift
   // TODO: Add when image support is implemented
   // TODO: Image copying not implemented yet
   // ACTION: Implement image copying or remove feature
   ```

4. **JobBoardView.swift** (2 instances):
   ```swift
   // TODO: Navigate to create task type
   // TODO: Add ProjectFormSheet when implemented
   // ACTION: Complete implementation or remove TODO
   ```

---

### Task 8.4: Verify Unused Files

**Check if these are used, remove if not**:

1. **ScheduleView.swift** - Search for imports/references
2. **MapViewAlternative.swift** - Search for imports/references
3. **V2/CertificationsSettingsView.swift** - Future feature, keep or move to separate branch

**For each file**:
- Search entire codebase for filename
- If no references found → delete
- If referenced → keep

---

## Phase 9: Update Documentation

### Task 9.1: Update DATA_AND_MODELS.md

**File**: `/Users/jacksonsweet/Desktop/OPS APP/OPS/DATA_AND_MODELS.md`

**Add section**: "Current Codebase State (Nov 18, 2025)"

**Content to add**:
```markdown
## Current Codebase State (November 18, 2025)

### File Organization
- **Total Swift Files**: 283
- **Data Models**: 16 files in OPS/DataModels/
- **DTOs**: 10 files in OPS/Network/DTOs/
- **Endpoints**: 7 files in OPS/Network/Endpoints/
- **Views**: 143 files organized by feature
- **Utilities**: 28 helper files

### Model Implementation Status
All 8 core models fully implemented with:
- ✅ Soft delete support (deletedAt)
- ✅ Sync tracking (lastSyncedAt, needsSync)
- ✅ SwiftData defensive patterns
- ✅ Proper relationship delete rules
- ✅ Computed properties for derived data

### Recent Architectural Changes
- **Task-Only Scheduling** (Nov 18, 2025): Removed dual-mode scheduling
  - Deleted `project.eventType` field
  - Deleted `CalendarEvent.type` and `active` fields
  - All calendar events now task-based
  - Project dates computed from task dates
```

---

### Task 9.2: Update API_AND_SYNC.md

**File**: `/Users/jacksonsweet/Desktop/OPS APP/OPS/API_AND_SYNC.md`

**Add section**: "Implementation Status"

**Content**:
```markdown
## Implementation Status (November 18, 2025)

### Sync Architecture
- **CentralizedSyncManager**: 100% implemented
- **Triple-layer strategy**: Fully operational
  - Layer 1 (Immediate): ✅ Working
  - Layer 2 (Event-driven): ✅ Working with 2s debouncing
  - Layer 3 (Periodic retry): ✅ Working every 3 minutes

### API Service
- **APIService.swift**: 926 lines, handles all Bubble communication
- **Endpoints**: 7 endpoint files, fully implemented
- **Error Handling**: Retry with exponential backoff
- **Rate Limiting**: 0.5s minimum between requests

### Recent Fixes
- Nov 15, 2025: Added 2-second debouncing to prevent duplicate syncs
- Nov 3, 2025: Fixed role assignment bug (EmployeeType mapping)
```

---

### Task 9.3: Update UI_GUIDELINES.md

**File**: `/Users/jacksonsweet/Desktop/OPS APP/OPS/UI_GUIDELINES.md`

**Add section**: "Code Quality Status"

**Content**:
```markdown
## Code Quality Status (November 18, 2025)

### OPSStyle Adoption
- **Good Adoption**: 80% of files use OPSStyle correctly
- **Needs Migration**: ~20 files with hardcoded colors
- **Needs Migration**: ~5 files with hardcoded fonts
- **Needs Migration**: ~207 instances of hardcoded icon strings

### Common Violations Found
1. Hardcoded hex colors in 20 files
2. Direct Color() construction instead of OPSStyle.Colors
3. .opacity() on backgrounds (should use solid colors)
4. Hardcoded SF Symbol strings instead of OPSStyle.Icons
5. Custom font definitions instead of OPSStyle.Typography

### Cleanup Priorities
- [ ] Migrate hardcoded colors → OPSStyle.Colors
- [ ] Migrate hardcoded fonts → OPSStyle.Typography
- [ ] Migrate icon strings → OPSStyle.Icons
- [ ] Create reusable components (SectionHeader, InfoRow, ContactRow)
```

---

### Task 9.4: Update COMPONENTS.md

**File**: `/Users/jacksonsweet/Desktop/OPS APP/OPS/COMPONENTS.md`

**Add section**: "New Components (Post-Consolidation)"

**Content**:
```markdown
## New Components (Post-Consolidation)

### SectionHeader
**Location**: `OPS/Styles/Components/SectionHeader.swift`
**Replaces**: 25+ duplicate section header implementations
**Usage**: Standardized section headers throughout app

### InfoRow
**Location**: `OPS/Styles/Components/InfoRow.swift`
**Replaces**: 40+ duplicate info row implementations
**Usage**: Display icon + label + value rows

### ContactRow
**Location**: `OPS/Styles/Components/ContactRow.swift`
**Replaces**: 30+ duplicate contact row implementations
**Usage**: Tappable email/phone/address rows
```

---

### Task 9.5: Update CLAUDE.md

**File**: `/Users/jacksonsweet/Desktop/OPS APP/OPS/CLAUDE.md`

**Update "Recent Implementation Updates" section**:

**Replace August 2025 section with**:
```markdown
## Recent Implementation Updates (November 2025)

### Task-Only Scheduling Migration (Nov 18, 2025)
- **Complete**: Removed dual-scheduling complexity
- **CalendarEvents**: All events are now task-based (taskId always set)
- **Project Dates**: Computed from tasks (computedStartDate, computedEndDate)
- **Removed Fields**: eventType, type, active - no longer needed
- **Migration**: One-time cleanup deleted project-level calendar events

### Documentation Consolidation (Nov 18, 2025)
- **93 files → 4 core docs**: DATA_AND_MODELS, API_AND_SYNC, UI_GUIDELINES, COMPONENTS
- **Purpose**: AI-assistant-optimized documentation
- **Result**: Single source of truth for each domain

### Code Quality Improvements (In Progress)
- **Identified**: 20 files with hardcoded colors
- **Identified**: 5 files with hardcoded fonts
- **Identified**: 207 instances of hardcoded icons
- **Identified**: 270 print statements to clean
- **Plan**: CONSOLIDATION_PLAN.md for systematic cleanup
```

---

### Task 9.6: Create CODEBASE_STATUS.md

**File**: `/Users/jacksonsweet/Desktop/OPS APP/OPS/CODEBASE_STATUS.md`

**Create new file**:
```markdown
# OPS Codebase Status Report

**Generated**: November 18, 2025
**Total Files**: 283 Swift files
**Code Health**: 8/10

---

## Executive Summary

The OPS codebase is well-architected with strong foundations. Recent task-based scheduling migration simplified architecture. Main opportunities are in reducing code duplication and migrating legacy code to centralized style system.

**Strengths**:
- ✅ Task-based scheduling successfully implemented
- ✅ Defensive SwiftData patterns throughout
- ✅ Comprehensive OPSStyle system
- ✅ Solid offline-first architecture
- ✅ Clean API abstraction
- ✅ Proper subscription management

**Improvement Areas**:
- 🔧 **1,372 color instances** across **100+ files** need migration to OPSStyle ⚠️
- 🔧 **498 icon instances** across **122 files** need migration to OPSStyle ⚠️
- 🔧 5 files need font migration to OPSStyle
- 🔧 270 print statements to clean
- 🔧 DataController needs refactoring (3,687 lines)
- 🔧 ~500 lines of duplicate UI code
- 🔧 **1,904 padding instances** with hardcoded values
- 🔧 **508 cornerRadius instances** with hardcoded values

**NOTE**: See `HARDCODED_VALUES_AUDIT.md` for complete breakdown of 5,077 total hardcoded styling instances

---

## File Inventory

### By Category
- **App Core**: 4 files
- **Data Models**: 16 files
- **Network**: 32 files (API, DTOs, Endpoints, Auth, Sync, Services)
- **Views**: 143 files (Features, Components, Debug)
- **ViewModels**: 2 files
- **Utilities**: 28 files
- **Styles**: 15 files
- **Extensions**: 5 files
- **Navigation**: 1 file
- **Tests**: 3 files

### Largest Files
1. DataController.swift - 3,687 lines ⚠️
2. APIService.swift - 926 lines
3. Project.swift - 440 lines
4. OPSStyle.swift - 355 lines
5. ProjectTask.swift - 236 lines

---

## Technical Debt

**Minimal** - Only 7 TODO comments, very little dead code

**Deprecated Code**:
- LegacyStatusBadge (line 289 in OPSStyle.swift)
- 4 deprecated view modifiers (lines 305-327 in OPSStyle.swift)

**Potential Unused**:
- ScheduleView.swift
- MapViewAlternative.swift
- V2/CertificationsSettingsView.swift

---

## Consolidation Opportunities

### High Impact
1. **Create SectionHeader component** - Eliminates 25 duplicates
2. **Create InfoRow component** - Eliminates 40 duplicates
3. **Create ContactRow component** - Eliminates 30 duplicates
4. **Refactor DataController** - From 3,687 lines to ~800 core + extensions

### Medium Impact
5. **Migrate colors to OPSStyle** - **100+ files, 1,372 instances** ⚠️ (See HARDCODED_VALUES_AUDIT.md)
6. **Migrate fonts to OPSStyle** - 5 files
7. **Migrate icons to OPSStyle** - **122 files, 498 instances** ⚠️ (See HARDCODED_VALUES_AUDIT.md)
8. **Remove print statements** - 270 instances
9. **Migrate padding to OPSStyle.Layout** - 133+ files, 1,904 instances (if standardization desired)
10. **Migrate cornerRadius to OPSStyle.Layout** - 81 files, 508 instances

### Estimated Impact
- **Lines Saved**: ~500 lines of duplicate code
- **Improved Maintainability**: Centralized styling across all files
- **Reduced Technical Debt**: Minimal remaining after consolidation

---

## Recent Architectural Changes

### Task-Only Scheduling (Nov 18, 2025)
Simplified from dual-mode to unified task-based scheduling:
- Removed `project.eventType`
- Removed `CalendarEvent.type` and `active`
- All calendar events now task-based
- Project dates computed from tasks
- Clean migration with one-time cleanup

### Documentation Consolidation (Nov 18, 2025)
Reduced 93 markdown files to 4 core reference documents optimized for AI assistants.

---

## Next Steps

See **CONSOLIDATION_PLAN.md** for detailed execution plan.

**Priority Order**:
1. Create reusable components (Phase 1)
2. Migrate hardcoded colors (Phase 2)
3. Migrate hardcoded fonts (Phase 3)
4. Migrate hardcoded icons (Phase 4)
5. Remove print statements (Phase 5)
6. Refactor DataController (Phase 6)
7. Reorganize folder structure (Phase 7)
8. Remove dead code (Phase 8)
9. Update documentation (Phase 9)

**Estimated Effort**: 60-75 hours total ⚠️ (Updated after comprehensive audit)

**Breakdown**:
- Phase 1 (Components): 6-8 hours
- Phase 2 (Colors): 15-20 hours ⚠️ (1,372 instances, not 50)
- Phase 3 (Fonts): 1-2 hours
- Phase 4 (Icons): 20-25 hours ⚠️ (498 instances, not 207)
- Phase 5 (Print statements): 2-3 hours
- Phase 6 (DataController): 8-10 hours
- Phase 7 (Folder reorganization): 4-6 hours
- Phase 8 (Dead code): 2-3 hours
- Phase 9 (Documentation): 2-3 hours

See `HARDCODED_VALUES_AUDIT.md` for detailed breakdown
```

---

## Execution Notes for Agent

### Prerequisites Before Starting

1. **Backup**: Create git branch `consolidation-backup`
2. **Testing**: Ensure project builds successfully
3. **Commit**: Commit current state before starting

### During Execution

1. **Work in phases**: Complete one phase before starting next
2. **Build frequently**: Run build after each file modification
3. **Test changes**: Verify functionality after each phase
4. **Commit often**: Commit after each completed phase
5. **Track progress**: Update CONSOLIDATION_PLAN.md with ✅ for completed tasks

### Error Handling

If build fails:
1. Review last changes made
2. Check for missing imports
3. Verify file paths are correct
4. Ensure no circular dependencies introduced
5. Revert to last working state if needed

### Completion Criteria

Each phase is complete when:
- ✅ All tasks in phase executed
- ✅ Project builds without errors
- ✅ No new warnings introduced
- ✅ Functionality verified in simulator
- ✅ Changes committed to git

---

## Post-Consolidation Benefits

### For Development
- Faster onboarding for new developers
- Easier to find code (logical organization)
- Reduced merge conflicts
- Better test coverage possible
- Clearer separation of concerns

### For Maintenance
- Single source of truth for styles
- Reusable components reduce bugs
- Easier to update UI consistently
- Less code to maintain (~500 fewer lines)
- Clearer dependencies

### For AI Assistance
- Better code suggestions
- Faster context understanding
- More accurate refactoring
- Easier to generate consistent code
- Documentation matches actual structure

---

**End of CONSOLIDATION_PLAN.md**

This plan is designed for systematic execution by an AI agent. Follow phases sequentially for best results.
