# Dashboard Design Specifications

## Overall Layout

### Screen Structure
```
┌─────────────────────────────┐
│      Job Board Header       │
├─────────────────────────────┤
│                             │
│    Quick Actions Card       │
│                             │
├─────────────────────────────┤
│                             │
│  Attention Required Card    │
│                             │
├─────────────────────────────┤
│                             │
│   Today's Schedule Card     │
│                             │
├──────────────┬──────────────┤
│   Projects   │   Clients    │
├──────────────┼──────────────┤
│     Team     │  Analytics   │
├──────────────┴──────────────┤
│                             │
│    Recent Activity Card     │
│                             │
└─────────────────────────────┘
```

### Styling Constants
- Background: `OPSStyle.Colors.background`
- Card Background: `OPSStyle.Colors.cardBackgroundDark`
- Card Border: `Color.white.opacity(0.1)`
- Corner Radius: `OPSStyle.Layout.cornerRadius`
- Card Spacing: 16pt
- Screen Margins: 20pt
- Inner Card Padding: 16pt

## Card Specifications

### 1. Quick Actions Card

**Purpose**: Primary creation actions
**Height**: 80pt
**Layout**: Horizontal stack, equal distribution

```swift
struct QuickActionsCard: View {
    var body: some View {
        HStack(spacing: 12) {
            QuickActionButton(
                icon: "plus.circle",
                label: "PROJECT",
                action: createProject
            )
            
            QuickActionButton(
                icon: "person.badge.plus",
                label: "CLIENT",
                action: createClient
            )
            
            QuickActionButton(
                icon: "checkmark.circle.badge.plus",
                label: "TASK",
                action: createTask
            )
        }
        .padding(16)
        .cardStyle()
    }
}
```

**Button Specifications**:
- Icon size: 24pt
- Label: `OPSStyle.Typography.captionBold`
- Touch target: 60pt minimum
- Color: `OPSStyle.Colors.primaryAccent`

### 2. Attention Required Card

**Purpose**: Surface items needing action
**Height**: Variable (120-200pt)
**Layout**: Vertical list

```swift
struct AttentionRequiredCard: View {
    let unscheduledCount: Int
    let unassignedCount: Int
    let overdueCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "NEEDS ATTENTION")
            
            if unscheduledCount > 0 {
                AttentionRow(
                    icon: "calendar.badge.exclamationmark",
                    title: "Unscheduled Projects",
                    count: unscheduledCount,
                    color: .orange
                )
            }
            
            if unassignedCount > 0 {
                AttentionRow(
                    icon: "person.fill.questionmark",
                    title: "Unassigned Projects",
                    count: unassignedCount,
                    color: .yellow
                )
            }
            
            if overdueCount > 0 {
                AttentionRow(
                    icon: "exclamationmark.triangle",
                    title: "Overdue Tasks",
                    count: overdueCount,
                    color: .red
                )
            }
            
            if allClear {
                Text("All systems operational")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding(16)
        .cardStyle()
    }
}
```

### 3. Today's Schedule Summary

**Purpose**: Quick view of today's activity
**Height**: 140pt
**Layout**: Stats grid + next item

```swift
struct TodayScheduleCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "TODAY")
            
            HStack(spacing: 20) {
                StatItem(
                    value: activeProjectCount,
                    label: "ACTIVE"
                )
                StatItem(
                    value: teamOnSiteCount,
                    label: "ON SITE"
                )
                StatItem(
                    value: tasksDueCount,
                    label: "DUE"
                )
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            if let nextItem = nextScheduledItem {
                NextItemRow(item: nextItem)
            } else {
                Text("No scheduled items today")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(16)
        .cardStyle()
    }
}
```

### 4. Management Grid Cards

**Purpose**: Navigate to management views
**Height**: 100pt each
**Layout**: 2x2 grid

```swift
struct ManagementGrid: View {
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            NavigationCard(
                icon: "folder.fill",
                title: "PROJECTS",
                count: projectCount,
                destination: .projectList
            )
            
            NavigationCard(
                icon: "person.2.fill",
                title: "CLIENTS",
                count: clientCount,
                destination: .clientList
            )
            
            NavigationCard(
                icon: "person.3.fill",
                title: "TEAM",
                count: teamCount,
                destination: .teamOverview
            )
            
            NavigationCard(
                icon: "chart.bar.fill",
                title: "ANALYTICS",
                subtitle: "View Reports",
                destination: .analytics
            )
        }
    }
}
```

### 5. Recent Activity Card

**Purpose**: Show recent changes
**Height**: Variable (max 200pt)
**Layout**: Scrollable list

```swift
struct RecentActivityCard: View {
    let activities: [Activity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "RECENT ACTIVITY")
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activities.prefix(5)) { activity in
                        ActivityRow(activity: activity)
                        
                        if activity != activities.prefix(5).last {
                            Divider()
                                .background(Color.white.opacity(0.05))
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .padding(16)
        .cardStyle()
    }
}
```

## Component Library

### Section Header
```swift
struct SectionHeader: View {
    let title: String
    let action: (() -> Void)?
    
    var body: some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            Spacer()
            
            if let action = action {
                Button(action: action) {
                    Text("SEE ALL")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }
}
```

### Card Style Modifier
```swift
extension View {
    func cardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }
}
```

## Pull to Refresh

```swift
struct JobBoardDashboard: View {
    @State private var isRefreshing = false
    
    var body: some View {
        ScrollView {
            RefreshIndicator(isRefreshing: $isRefreshing)
            
            VStack(spacing: 16) {
                // All dashboard cards
            }
            .padding(20)
        }
        .refreshable {
            await refreshDashboard()
        }
    }
    
    func refreshDashboard() async {
        isRefreshing = true
        await dataController.syncDashboardData()
        isRefreshing = false
    }
}
```

## Loading States

### Initial Load
- Show skeleton cards with shimmer effect
- Maintain layout structure
- Animate content appearance

### Refresh
- Show subtle refresh indicator
- Keep existing content visible
- Update cards individually as data arrives

## Empty States

### No Items Needing Attention
- Checkmark icon
- "All systems operational"
- Green accent color

### No Recent Activity
- Clock icon
- "No recent activity"
- Secondary text color

## Responsive Design

### iPhone SE (Small)
- Stack management cards vertically
- Reduce font sizes by 1pt
- Maintain minimum touch targets

### iPhone Pro Max (Large)
- Expand card spacing to 20pt
- Show more recent activity items
- Larger stat numbers

### iPad
- 3-column grid for management cards
- Side-by-side layout for some cards
- Expanded activity feed