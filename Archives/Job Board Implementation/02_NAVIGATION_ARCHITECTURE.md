# Navigation Architecture

## Tab Bar Structure

### Tab Order (Left to Right)
1. **Home** - Existing home view
2. **Job Board** - Management dashboard (office/admin only)  
3. **Schedule** - Calendar view
4. **Settings** - App settings

### Tab Configuration

```swift
struct TabConfiguration {
    let title: String
    let icon: String
    let selectedIcon: String
}

let jobBoardTab = TabConfiguration(
    title: "JOB BOARD",
    icon: "hammer",
    selectedIcon: "hammer.fill"
)
```

### Alternative Icon Options
- `wrench.and.hammer`
- `wrench.and.hammer.fill`
- `hammer.circle`
- `hammer.circle.fill`

## Navigation Hierarchy

```
Job Board Tab
├── Dashboard (root)
│   ├── Quick Actions
│   │   ├── Create Project → ProjectFormSheet
│   │   ├── Create Client → ClientFormSheet
│   │   └── Create Task → QuickTaskSheet
│   ├── Attention Required
│   │   ├── Unscheduled → ProjectListView (filtered)
│   │   └── Unassigned → ProjectListView (filtered)
│   ├── View All Projects → ProjectListView
│   │   └── Project Details → ProjectDetailsView
│   │       ├── Edit → ProjectFormSheet
│   │       └── Tasks → TaskListView
│   └── View All Clients → ClientListView
│       └── Client Details → ClientDetailsView
│           ├── Edit → ClientFormSheet
│           └── Projects → ProjectListView (filtered)
```

## View Transitions

### Navigation Styles
- **Push Navigation**: For drilling down (list → detail)
- **Sheet Presentation**: For forms and creation flows
- **Full Screen Cover**: For multi-step wizards
- **Popover**: For quick actions and filters

### Specific Transitions

| From | To | Transition Type |
|------|-----|----------------|
| Dashboard | Project List | Push |
| Dashboard | Client List | Push |
| Dashboard | Create Project | Sheet |
| Dashboard | Create Client | Sheet |
| Dashboard | Create Task | Sheet |
| Project List | Project Details | Push |
| Client List | Client Details | Push |
| Any List | Edit Form | Sheet |
| Delete Confirmation | Reassignment | Sheet |

## Navigation State Management

### Tab Selection
```swift
@Published var selectedTab: Tab = .home {
    didSet {
        if selectedTab == .jobBoard {
            refreshDashboardIfNeeded()
        }
    }
}
```

### Deep Linking Support
```swift
enum DeepLink {
    case project(id: String)
    case client(id: String)
    case createProject
    case createClient
    
    func navigate(from dashboard: JobBoardDashboard) {
        switch self {
        case .project(let id):
            dashboard.navigateToProject(id: id)
        case .client(let id):
            dashboard.navigateToClient(id: id)
        case .createProject:
            dashboard.showProjectCreation = true
        case .createClient:
            dashboard.showClientCreation = true
        }
    }
}
```

## Back Navigation

### Navigation Bar Setup
- Show back button with `OPSStyle.Colors.primaryAccent`
- Title in `OPSStyle.Typography.bodyBold` uppercase
- Right-side actions context-specific

### Gesture Support
- Swipe-from-left-edge for back navigation
- Pull-to-dismiss for sheets
- Long press for context menus

## Tab Badge Notifications

### Badge Scenarios
- Unscheduled projects count
- Unassigned projects count
- Pending approvals count

```swift
var jobBoardBadgeCount: Int {
    let unscheduled = projects.filter { $0.startDate == nil }.count
    let unassigned = projects.filter { $0.teamMembers.isEmpty }.count
    return unscheduled + unassigned
}
```

## Accessibility

### VoiceOver Labels
- Tab: "Job Board, Management Dashboard"
- Badge: "X items need attention"
- Navigation: Clear descriptions of destination

### Dynamic Type Support
- All text respects Dynamic Type settings
- Maintain minimum touch targets of 44pt
- Adjust layout for larger text sizes

## Performance Considerations

### Lazy Loading
- Load dashboard cards on-demand
- Paginate large lists (projects, clients)
- Cache recently viewed details

### Preloading Strategy
```swift
// Preload common navigation paths
func preloadCommonViews() {
    if user.role == .officeCrew || user.role == .admin {
        // Preload empty forms for quick access
        _ = ProjectFormSheet()
        _ = ClientFormSheet()
    }
}
```

## Error States

### Navigation Failures
- Network error: Show local cached data
- Missing data: Show empty state
- Permission denied: Navigate back with alert

### Recovery Actions
- Pull-to-refresh on lists
- Retry button on error views
- Automatic retry with exponential backoff