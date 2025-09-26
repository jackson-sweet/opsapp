# Job Board Implementation Guide

## Overview
The Job Board is a comprehensive management system for office crew and admin users in the OPS iOS app. This feature enables complete project and client management from mobile devices, eliminating dependency on the web app for daily operations.

## Documentation Structure

This implementation guide is organized into the following sections:

1. **[User Roles & Permissions](01_USER_ROLES_PERMISSIONS.md)** - Access levels and capabilities by role
2. **[Navigation Architecture](02_NAVIGATION_ARCHITECTURE.md)** - Tab structure and navigation flow  
3. **[Dashboard Design](03_DASHBOARD_DESIGN.md)** - Dashboard layout and card specifications
4. **[Client Management](04_CLIENT_MANAGEMENT.md)** - Client CRUD operations and UI flows
5. **[Project Management](05_PROJECT_MANAGEMENT.md)** - Project creation, editing, and scheduling modes
6. **[Task Management](06_TASK_MANAGEMENT.md)** - Task creation and task type management
7. **[Calendar Synchronization](07_CALENDAR_SYNC.md)** - Calendar event management and date calculations
8. **[API Endpoints](08_API_ENDPOINTS.md)** - Required Bubble backend endpoints
9. **[Component Architecture](09_COMPONENT_ARCHITECTURE.md)** - Reusable components and style guidelines
10. **[Implementation Phases](10_IMPLEMENTATION_PHASES.md)** - Step-by-step build order
11. **[Testing Checklist](11_TESTING_CHECKLIST.md)** - Comprehensive testing requirements

## Quick Start

### Who Has Access?
- **Admin**: Full access to all Job Board features plus billing
- **Office Crew**: Full access except billing and team termination
- **Field Crew**: No access (tab hidden)

### Key Features
- Create and manage clients
- Create and manage projects  
- Switch between project-based and task-based scheduling
- Create and assign tasks
- Manage custom task types
- View analytics and reports
- Handle reassignments when deleting entities

### Design Principles
- **Military/Tactical Minimalism**: Clean, functional interface
- **OPSStyle Consistency**: All colors, fonts, and spacing from OPSStyle
- **Mobile-First**: Optimized for field conditions
- **Offline Capability**: Critical features work without connectivity
- **Speed**: Quick actions and minimal taps to complete tasks

## Implementation Status

- [ ] Phase 1: Foundation
- [ ] Phase 2: Client Management
- [ ] Phase 3: Project Management
- [ ] Phase 4: Task Management
- [ ] Phase 5: Dashboard & Analytics
- [ ] Phase 6: Polish & Edge Cases

## Key Decisions

1. **Tab Position**: Job Board is the second tab (Home - Job Board - Schedule - Settings)
2. **No Soft Delete**: Clients are permanently deleted (with project reassignment)
3. **Immediate Sync**: Date calculations happen on device, then sync to Bubble
4. **Active Field**: CalendarEvents use `active` boolean to control visibility
5. **Duplicate Detection**: 80% name similarity triggers duplicate warning

## Success Metrics

The implementation succeeds when:
- Office crew can fully manage operations from mobile
- All data syncs correctly with Bubble
- UI maintains tactical aesthetic throughout
- Navigation feels intuitive and predictable
- Performance remains smooth with large datasets

## Next Steps

Begin with [Phase 1: Foundation](10_IMPLEMENTATION_PHASES.md#phase-1-foundation) in the implementation guide.