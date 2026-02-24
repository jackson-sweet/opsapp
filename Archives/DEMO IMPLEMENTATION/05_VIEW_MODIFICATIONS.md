# VIEW MODIFICATIONS

Existing views that need tutorial mode support.

---

## OVERVIEW

Views need minimal changes to support tutorial mode:
1. Accept `@Environment(\.tutorialMode)`
2. Conditionally filter data to show only demo data
3. Disable certain interactions when in tutorial

---

## 1. JobBoardDashboard.swift

**Path:** `OPS/Views/JobBoard/JobBoardDashboard.swift`

### Changes Required

**Add environment property:**
```swift
@Environment(\.tutorialMode) private var tutorialMode
```

**Filter projects to demo data:**
```swift
// In the computed property or data source
private var filteredProjects: [Project] {
    let allProjects = projects // existing source

    if tutorialMode {
        return allProjects.filter { $0.id.hasPrefix("DEMO_") }
    }
    return allProjects
}
```

**Disable tab bar navigation when in tutorial:**
```swift
// In parent view or via environment
if tutorialMode {
    // Hide or disable tab bar
}
```

**Keep enabled:**
- Status column swiping
- Long-press drag gestures
- Card interactions

---

## 2. ProjectFormSheet.swift

**Path:** `OPS/Views/JobBoard/ProjectFormSheet.swift`

### Changes Required

**Add environment property:**
```swift
@Environment(\.tutorialMode) private var tutorialMode
```

**Filter clients to demo clients only:**
```swift
private var availableClients: [Client] {
    if tutorialMode {
        return allClients.filter { $0.id.hasPrefix("DEMO_") }
    }
    return allClients
}
```

**Filter team members to demo users only:**
```swift
private var availableTeamMembers: [User] {
    if tutorialMode {
        return allUsers.filter { $0.id.hasPrefix("DEMO_") }
    }
    return allUsers
}
```

**Keep enabled:**
- All form fields
- Client picker
- Task creation
- Save/Complete button

---

## 3. TaskFormSheet.swift

**Path:** `OPS/Views/JobBoard/TaskFormSheet.swift`

### Changes Required

**Add environment property:**
```swift
@Environment(\.tutorialMode) private var tutorialMode
```

**Filter task types to demo types:**
```swift
private var availableTaskTypes: [TaskType] {
    if tutorialMode {
        return allTaskTypes.filter { $0.id.hasPrefix("DEMO_") }
    }
    return allTaskTypes
}
```

**Filter team members:**
```swift
private var availableTeamMembers: [User] {
    if tutorialMode {
        return allUsers.filter { $0.id.hasPrefix("DEMO_") }
    }
    return allUsers
}
```

**Keep enabled:**
- Task type picker
- Team member picker
- Date picker
- Done/Save button

---

## 4. FloatingActionMenu.swift

**Path:** `OPS/Views/Components/FloatingActionMenu.swift`

### Changes Required

**Add environment property:**
```swift
@Environment(\.tutorialMode) private var tutorialMode
```

**Disable non-project actions in tutorial:**
```swift
// In the action menu
VStack {
    // Create Client - disabled in tutorial
    if !tutorialMode {
        createClientButton
    }

    // Create Project - always enabled
    createProjectButton

    // Create Task - disabled in tutorial (or conditional)
    if !tutorialMode {
        createTaskButton
    }

    // Task Type - disabled in tutorial
    if !tutorialMode {
        createTaskTypeButton
    }
}
```

OR use opacity/disabled:
```swift
createClientButton
    .opacity(tutorialMode ? 0.4 : 1.0)
    .allowsHitTesting(!tutorialMode)
```

---

## 5. JobBoardProjectListView.swift

**Path:** `OPS/Views/JobBoard/JobBoardProjectListView.swift`

### Changes Required

**Add environment property:**
```swift
@Environment(\.tutorialMode) private var tutorialMode
```

**Filter to demo projects:**
```swift
private var displayedProjects: [Project] {
    if tutorialMode {
        return projects.filter { $0.id.hasPrefix("DEMO_") }
    }
    return projects
}
```

**Keep enabled:**
- Swipe-to-change-status gestures
- Project tap interactions

---

## 6. HomeView.swift

**Path:** `OPS/Views/Home/HomeView.swift`

### Changes Required

**Add environment property:**
```swift
@Environment(\.tutorialMode) private var tutorialMode
```

**Filter to demo projects assigned to user:**
```swift
private var todayProjects: [Project] {
    let projects = fetchTodayProjects()

    if tutorialMode {
        return projects.filter { $0.id.hasPrefix("DEMO_") }
    }
    return projects
}
```

**Note:** For employee tutorial, current user should be assigned to demo tasks via `TutorialDemoDataManager.assignCurrentUserToTasks()`

**Keep enabled:**
- Project card carousel
- Tap interactions
- Long-press for details

---

## 7. Calendar Views

**Path:** `OPS/Views/Calendar Tab/` (multiple files)

### MonthGridView.swift Changes

**Add environment property:**
```swift
@Environment(\.tutorialMode) private var tutorialMode
```

**Filter events to demo events:**
```swift
private var displayedEvents: [CalendarEvent] {
    if tutorialMode {
        return events.filter { $0.id.hasPrefix("DEMO_") }
    }
    return events
}
```

**Disable certain controls:**
```swift
// Filter button
filterButton
    .opacity(tutorialMode ? 0.4 : 1.0)
    .allowsHitTesting(!tutorialMode)

// Search button
searchButton
    .opacity(tutorialMode ? 0.4 : 1.0)
    .allowsHitTesting(!tutorialMode)

// Refresh button
refreshButton
    .opacity(tutorialMode ? 0.4 : 1.0)
    .allowsHitTesting(!tutorialMode)
```

**Keep enabled:**
- Week/Month segment picker
- Day selection
- Scrolling/navigation
- Pinch gestures (if applicable)
- Task/event tapping

---

## 8. ProjectDetailsView.swift

**Path:** `OPS/Views/Components/Project/ProjectDetailsView.swift`

### Changes Required

**Add environment property:**
```swift
@Environment(\.tutorialMode) private var tutorialMode
```

**No data filtering needed** - view shows single project passed in

**Keep all interactions enabled:**
- Add note
- Add photo
- Complete/status buttons
- Navigation

---

## 9. UniversalJobBoardCard.swift

**Path:** `OPS/Views/JobBoard/UniversalJobBoardCard.swift`

### Changes Required

**Add environment property:**
```swift
@Environment(\.tutorialMode) private var tutorialMode
```

**No changes to swipe gestures** - should work as-is

**Keep enabled:**
- Swipe-to-change-status
- Tap interactions
- Long-press

---

## SUMMARY TABLE

| View | Environment | Data Filter | Disable Controls | Swipe/Gesture |
|------|-------------|-------------|------------------|---------------|
| JobBoardDashboard | YES | DEMO_ projects | Tab bar | Keep enabled |
| ProjectFormSheet | YES | DEMO_ clients, users | None | N/A |
| TaskFormSheet | YES | DEMO_ task types, users | None | N/A |
| FloatingActionMenu | YES | N/A | Non-project actions | N/A |
| JobBoardProjectListView | YES | DEMO_ projects | None | Keep enabled |
| HomeView | YES | DEMO_ projects | Tab bar | Keep enabled |
| MonthGridView | YES | DEMO_ events | Filter, Search, Refresh | Keep enabled |
| ProjectDetailsView | YES | N/A | None | N/A |
| UniversalJobBoardCard | YES | N/A | None | Keep enabled |

---

## IMPLEMENTATION NOTES

### Pattern for Data Filtering
```swift
// Always use this pattern
private var filteredData: [SomeModel] {
    if tutorialMode {
        return sourceData.filter { $0.id.hasPrefix("DEMO_") }
    }
    return sourceData
}
```

### Pattern for Disabling Controls
```swift
// Visual + functional disable
someControl
    .opacity(tutorialMode ? 0.4 : 1.0)
    .allowsHitTesting(!tutorialMode)
```

### Do NOT Disable
- Primary gestures (swipe, drag, long-press)
- Form inputs
- Primary action buttons
- Navigation within tutorial flow

### Testing Checklist
For each modified view:
- [ ] Verify environment property compiles
- [ ] Verify data filtering works
- [ ] Verify disabled controls are visually dimmed
- [ ] Verify enabled controls still function
- [ ] Verify gestures work correctly
- [ ] Verify view looks correct with demo data only
