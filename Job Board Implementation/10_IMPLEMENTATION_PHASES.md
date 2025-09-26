# Implementation Phases

## Overview
Step-by-step implementation plan organized into manageable phases, ensuring each phase builds upon the previous while maintaining a working application.

## Phase 1: Foundation (2-3 days)

### Objectives
- Set up tab navigation
- Add role-based visibility
- Prepare data model updates
- Create basic dashboard skeleton

### Tasks

#### 1.1 Update Tab Bar Navigation
```swift
// MainTabView.swift modifications
□ Add JobBoard tab enum case
□ Update tab icon and title configuration
□ Implement role-based tab visibility
□ Test tab switching
```

#### 1.2 Update Data Models
```swift
// CalendarEvent.swift
□ Add 'active' field to CalendarEvent model
□ Add 'shouldDisplay' computed property
□ Update migration logic for existing events

// CalendarEventDTO.swift
□ Add 'active_boolean' field to DTO
□ Update toCalendarEvent() mapping
□ Update fromCalendarEvent() mapping
```

#### 1.3 Create Dashboard Skeleton
```swift
// JobBoardDashboard.swift
□ Create basic dashboard view structure
□ Add navigation stack
□ Implement placeholder cards
□ Add pull-to-refresh support
□ Test basic navigation
```

#### 1.4 Update Sync Logic
```swift
// SyncManager.swift
□ Update calendar event sync to include active field
□ Add migration for existing calendar events
□ Test sync with updated models
```

### Deliverables
- Working tab navigation with Job Board visible to office/admin
- Updated data models with active field
- Basic dashboard that loads without errors

### Success Criteria
- [ ] Office crew users see Job Board tab
- [ ] Field crew users don't see Job Board tab
- [ ] Dashboard loads with placeholder content
- [ ] No build errors or warnings

---

## Phase 2: Client Management (3-4 days)

### Objectives
- Implement complete client CRUD operations
- Add duplicate detection
- Implement deletion with reassignment

### Tasks

#### 2.1 Client List View
```swift
// ClientListView.swift
□ Create list view with search
□ Implement client row component
□ Add navigation to details
□ Add create button
□ Test list performance with many clients
```

#### 2.2 Client Details View
```swift
// ClientDetailsView.swift
□ Reuse ClientInfoCard component
□ Add embedded ProjectListView (filtered)
□ Add sub-clients section
□ Implement edit navigation
□ Add delete button with logic
```

#### 2.3 Client Form Sheet
```swift
// ClientFormSheet.swift
□ Create form with all fields
□ Implement address autocomplete
□ Add duplicate detection logic
□ Implement save functionality
□ Test create and edit modes
```

#### 2.4 Duplicate Detection
```swift
// DuplicateDetection.swift
□ Implement similarity algorithm
□ Create inline warning component
□ Add "use existing" flow
□ Test with various name patterns
```

#### 2.5 Deletion with Reassignment
```swift
// ClientDeletionSheet.swift
□ Create reassignment UI
□ Implement project list display
□ Add client selection per project
□ Add bulk reassignment option
□ Implement deletion logic
```

#### 2.6 API Integration
```swift
□ Create client endpoints in APIService
□ Implement create client API call
□ Implement update client API call
□ Implement delete client API call
□ Add duplicate check endpoint
□ Test all API operations
```

### Deliverables
- Complete client management functionality
- Working duplicate detection
- Deletion with project reassignment

### Success Criteria
- [ ] Can create new clients
- [ ] Duplicate warnings appear correctly
- [ ] Can edit existing clients
- [ ] Can delete clients with reassignment
- [ ] All changes sync to Bubble

---

## Phase 3: Project Management (4-5 days)

### Objectives
- Implement project creation and editing
- Add scheduling mode support
- Implement mode conversion
- Handle calendar event creation

### Tasks

#### 3.1 Project List Enhancement
```swift
// JobBoardProjectListView.swift
□ Extend existing ProjectListView
□ Add management actions (edit, delete)
□ Add scheduling mode badges
□ Implement quick actions menu
□ Test with mixed scheduling modes
```

#### 3.2 Project Creation Form
```swift
// ProjectFormSheet.swift
□ Create comprehensive form
□ Implement client selection with inline creation
□ Add scheduling mode selector
□ Implement team selection
□ Add photo management
□ Create date pickers for project-based mode
```

#### 3.3 Scheduling Mode Logic
```swift
// SchedulingModeManager.swift
□ Implement project-based creation logic
□ Implement task-based creation logic
□ Create calendar event on project creation
□ Handle active/inactive states
□ Test both scheduling modes
```

#### 3.4 Mode Conversion
```swift
// SchedulingModeConversion.swift
□ Create conversion confirmation UI
□ Implement project→task conversion
□ Implement task→project conversion
□ Update calendar event active states
□ Test conversions with existing data
```

#### 3.5 Project Deletion
```swift
// ProjectDeletionConfirmation.swift
□ Create deletion confirmation
□ Handle task deletion cascade
□ Delete associated calendar events
□ Test with various project states
```

#### 3.6 API Integration
```swift
□ Create project endpoints
□ Implement scheduling mode update endpoint
□ Add calendar event creation logic
□ Test all project operations
```

### Deliverables
- Complete project management
- Working scheduling mode conversion
- Proper calendar event synchronization

### Success Criteria
- [ ] Can create projects with both scheduling modes
- [ ] Calendar events created correctly
- [ ] Can convert between scheduling modes
- [ ] Active field updates properly
- [ ] All changes sync to Bubble

---

## Phase 4: Task Management (3-4 days)

### Objectives
- Implement quick task creation
- Add task type management
- Handle calendar events for tasks
- Implement date calculations

### Tasks

#### 4.1 Quick Task Creation
```swift
// QuickTaskSheet.swift
□ Create project selection view
□ Show scheduling mode indicators
□ Implement task details form
□ Add date/time pickers
□ Calculate duration automatically
```

#### 4.2 Task Type Management
```swift
// TaskTypeManagementView.swift
□ Create task type list
□ Separate default vs custom types
□ Implement create form
□ Add color and icon selection
□ Implement edit functionality
```

#### 4.3 Task Type Deletion
```swift
// TaskTypeDeletionSheet.swift
□ Show affected tasks count
□ Implement reassignment UI
□ Allow inline type creation
□ Handle bulk reassignment
```

#### 4.4 Calendar Event Integration
```swift
□ Create calendar event for each task
□ Set active based on project mode
□ Update project dates from task dates
□ Test date calculations
```

#### 4.5 API Integration
```swift
□ Create task endpoints
□ Create task type endpoints
□ Implement deletion with reassignment
□ Test all task operations
```

### Deliverables
- Quick task creation from dashboard
- Task type customization
- Proper calendar synchronization

### Success Criteria
- [ ] Can create tasks quickly
- [ ] Task types can be customized
- [ ] Calendar events created for tasks
- [ ] Project dates update from tasks
- [ ] Deletion with reassignment works

---

## Phase 5: Dashboard & Analytics (2-3 days)

### Objectives
- Implement all dashboard cards
- Add analytics data
- Create activity feed
- Optimize performance

### Tasks

#### 5.1 Dashboard Cards
```swift
// Dashboard Components
□ Implement QuickActionsCard
□ Create AttentionRequiredCard
□ Build TodayScheduleCard
□ Create ManagementGrid
□ Implement RecentActivityCard
```

#### 5.2 Analytics Integration
```swift
// Analytics
□ Create analytics endpoint
□ Fetch dashboard data
□ Implement data aggregation
□ Add caching for performance
□ Test with large datasets
```

#### 5.3 Activity Feed
```swift
// ActivityFeed.swift
□ Track user actions
□ Create activity items
□ Sort by recency
□ Limit to recent items
□ Add activity icons
```

#### 5.4 Performance Optimization
```swift
□ Implement lazy loading
□ Add data caching
□ Optimize refresh logic
□ Test with slow connections
```

### Deliverables
- Complete dashboard with all cards
- Working analytics display
- Optimized performance

### Success Criteria
- [ ] All dashboard cards display data
- [ ] Analytics load quickly
- [ ] Activity feed updates
- [ ] Pull-to-refresh works smoothly
- [ ] Good performance with many items

---

## Phase 6: Polish & Edge Cases (2-3 days)

### Objectives
- Handle error states
- Add loading indicators
- Implement offline support
- Polish UI/UX

### Tasks

#### 6.1 Error Handling
```swift
□ Add error alerts
□ Implement retry logic
□ Create fallback states
□ Test network failures
□ Add user-friendly messages
```

#### 6.2 Loading States
```swift
□ Add shimmer effects
□ Implement progress indicators
□ Create skeleton screens
□ Test slow loading scenarios
```

#### 6.3 Offline Support
```swift
□ Queue operations when offline
□ Show offline indicators
□ Sync when connection returns
□ Test offline scenarios
```

#### 6.4 UI/UX Polish
```swift
□ Add haptic feedback
□ Implement swipe actions
□ Add keyboard shortcuts
□ Polish animations
□ Ensure consistent styling
```

#### 6.5 Accessibility
```swift
□ Add VoiceOver labels
□ Test with VoiceOver
□ Support Dynamic Type
□ Ensure color contrast
□ Test with accessibility settings
```

### Deliverables
- Polished, production-ready feature
- Comprehensive error handling
- Smooth user experience

### Success Criteria
- [ ] All errors handled gracefully
- [ ] Loading states appear correctly
- [ ] Works offline where possible
- [ ] Consistent with OPS design
- [ ] Accessible to all users

---

## Testing Between Phases

### After Each Phase
1. **Build Test**: Ensure no compilation errors
2. **Runtime Test**: Run app and test new features
3. **Integration Test**: Verify sync with Bubble
4. **Regression Test**: Ensure existing features work
5. **Performance Test**: Check for slowdowns

### User Acceptance Criteria
- Office crew can manage entire workflow from mobile
- No dependency on web app for daily operations
- Data syncs reliably with Bubble
- Performance remains smooth
- UI matches OPS design language

---

## Risk Mitigation

### Potential Risks & Solutions

| Risk | Mitigation |
|------|------------|
| API changes needed | Work closely with Bubble developer |
| Performance issues | Implement pagination early |
| Sync conflicts | Clear conflict resolution rules |
| Complex UI | Start with simple, iterate |
| Testing delays | Test continuously, not at end |

---

## Documentation Requirements

### For Each Phase
- Update code comments
- Document API changes
- Update user guides
- Record known issues
- Note performance metrics

---

## Go/No-Go Checkpoints

### Before Moving to Next Phase
- [ ] Current phase features work correctly
- [ ] No critical bugs
- [ ] Performance acceptable
- [ ] Sync working properly
- [ ] Code reviewed and clean

---

## Timeline Summary

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Foundation | 2-3 days | None |
| Phase 2: Client Management | 3-4 days | Phase 1 |
| Phase 3: Project Management | 4-5 days | Phase 2 |
| Phase 4: Task Management | 3-4 days | Phase 3 |
| Phase 5: Dashboard | 2-3 days | Phase 4 |
| Phase 6: Polish | 2-3 days | Phase 5 |
| **Total** | **16-22 days** | - |

---

## Post-Implementation

### After Completion
1. Comprehensive testing with real users
2. Performance profiling
3. Documentation update
4. Training materials creation
5. Deployment planning
6. Monitor initial usage
7. Gather feedback
8. Plan iterations