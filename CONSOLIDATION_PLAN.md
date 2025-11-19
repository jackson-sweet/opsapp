# OPS Codebase Consolidation & Cleanup Plan

**Purpose**: Agent-executable plan for consolidating duplicate code, migrating hardcoded values to OPSStyle, reorganizing folder structure, and removing waste.

**Last Updated**: November 18, 2025

**Execution Order**: Tasks must be executed in the order listed to avoid breaking dependencies.

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

### Task 2.2: Migrate Hardcoded Colors - File by File

**Execute for each file below:**

#### File: `OPS/Views/Components/Common/PushInMessage.swift`

**Find**:
```swift
Color(hex: "#FF6B6B")
Color(red: 0.95, green: 0.95, blue: 0.97)
```

**Replace**:
```swift
OPSStyle.Colors.errorStatus
OPSStyle.Colors.cardBackground
```

---

#### File: `OPS/Views/JobBoard/ProjectManagementSheets.swift`

**Find**: All instances of `Color(hex:`, `.opacity()` on backgrounds

**Replace**: With appropriate OPSStyle.Colors constants

**Pattern**:
- `Color.white.opacity(0.1)` → `OPSStyle.Colors.cardBorder`
- `Color.black.opacity(0.8)` → `OPSStyle.Colors.cardBackgroundDark`
- Any hex colors → find closest OPSStyle color

---

#### Files with Hardcoded Colors (20 total):

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

**For each file**:
1. Read the file
2. Identify all hardcoded colors (hex, RGB, opacity)
3. Replace with appropriate OPSStyle.Colors constant
4. Verify no background uses .opacity() - use solid colors

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

**⚠️ CRITICAL UPDATE**: Comprehensive audit reveals **498 icon instances** across **122 files**, not 207 instances. See `HARDCODED_VALUES_AUDIT.md` for complete breakdown.

**Actual scope**:
- Total `systemName:` usage: **498 instances**
- OPSStyle.Icons defined: **~60 icons**
- **Hardcoded violations**: **~438 instances** (88% violation rate)
- **Estimated effort**: 20-25 hours (requires adding ~200 icons to OPSStyle first)

### Task 4.1: Update OPSStyle.Icons with Missing Icons

**File**: `OPS/Styles/OPSStyle.swift`

**Action**: Add to Icons struct any SF Symbols found in code but not defined. Search codebase for `Image(systemName: "` and catalog all unique icons.

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

### Task 4.2: Migrate Icon Strings - High Frequency Files (207 instances)

**Strategy**: Use find-and-replace with regex for each file

**Pattern**:
```swift
// FIND:
Image(systemName: "person.circle")

// REPLACE WITH:
Image(systemName: OPSStyle.Icons.personCircle)
```

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
