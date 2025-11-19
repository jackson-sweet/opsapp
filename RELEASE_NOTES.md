# OPS Release Notes

## Version: November 13, 2025 Release

### Overview
This release focuses on improving team member management, data synchronization reliability, and visual clarity for completed work. Key improvements include automatic project team synchronization, comprehensive data health checks, and enhanced UI feedback for completed tasks and events.

---

## What's New

### Visual Improvements

#### Completed Task & Event Overlay
- **Calendar Views**: Completed tasks and events now display with a semi-transparent grey overlay and "COMPLETED" badge
- **Project Carousel**: Home screen project cards show completion status at a glance
- **Clear Visual Hierarchy**: Easily distinguish between active and completed work without cluttering the interface
- **Locations**: Week view, month view, project lists, and home screen carousel (does not apply to job board cards)

### Team Management Enhancements

#### Automatic Project Team Synchronization
- **Smart Team Updates**: When team members are added to or removed from tasks, the parent project's team automatically updates
- **Unified Access Control**: Field crew members assigned to any task on a project now automatically see that project
- **Real-Time Sync**: Team changes sync to the cloud in the background while updating the UI immediately
- **Offline-First**: Team member changes save locally first and sync when connection is available

#### Improved Team Editing Experience
- **Responsive UI**: Team member changes reflect immediately in the interface
- **No Delays**: Eliminated UI hang when saving team member changes
- **Edit Mode Stability**: Task details view no longer closes unexpectedly after editing team members
- **Optimistic Updates**: Changes appear instantly while syncing happens in the background

### Data Reliability & Sync Improvements

#### Comprehensive Data Health Management
- **Health Checks on Launch**: App validates user, company, and sync manager state before initializing
- **Automatic Recovery**: Missing sync manager automatically reinitializes to prevent sync errors
- **Onboarding Protection**: Health checks prevent sync errors during organization setup
- **State Validation**: Ensures all critical data is properly configured before sync operations

#### Enhanced Subscription Data Sync
- **Seated Employee Sync**: Fixed missing seated employee data during company synchronization
- **Data Preservation**: Seated employee information no longer lost during sync operations
- **Proper DTO Extraction**: Correctly extracts and processes seated employee IDs from API responses
- **Complete Company Sync**: All company data including billing and employee seats syncs reliably

#### Field Crew Access Control
- **All-Projects Sync**: Field crew users now sync all company projects to local database
- **Task-Based Filtering**: Access control happens at UI level based on task assignments
- **Improved Performance**: Eliminates unnecessary API filtering, relies on local data access patterns
- **Consistent Behavior**: All user roles receive complete project data for better offline support

### Employee Experience Improvements

#### Unseated Employee Support
- **Clear Messaging**: Unseated employees see helpful information about contacting their administrator
- **Contact Actions**: Direct CALL and EMAIL buttons to reach company admin
- **Admin Information**: Shows admin name and contact details in a minimal, tactical design
- **Professional UI**: Matches subscription lockout view design language

#### Subscription & Billing UI
- **Refresh Mechanism**: BillingInfoView now properly updates after subscription changes
- **SwiftUI Updates**: Forced UI refresh ensures subscription data always displays current state
- **Employee Seat Section**: Redesigned to match subscription lockout view for consistency

### Bug Fixes

#### Job Board Improvements
- **Delete Confirmation**: Task cards in job board now show confirmation alert before deletion
- **Accidental Deletion Prevention**: Prevents unintended task removal with confirmation step

#### Calendar & Event Fixes
- **Team Member IDs**: Fixed CalendarEvent team member ID extraction and storage
- **Data Model Consistency**: All models properly implement team member ID getters/setters
- **Sync Reliability**: Calendar events sync team member changes reliably with task updates

---

## Technical Improvements

### Architecture Enhancements
- Created `DataHealthManager` for centralized health validation
- Implemented automatic project team member updates based on task assignments
- Added `syncProjectTeamMembersFromTasks()` method to DataController
- Improved offline-first architecture with `needsSync` flag usage

### Performance Optimizations
- Optimistic UI updates eliminate perceived lag
- Background sync operations don't block user interface
- Reduced API calls by syncing all projects and filtering locally
- Removed expensive team sync from app launch sequence

### Code Quality
- Removed excessive debug logging from hot paths
- Added comprehensive sync logging for troubleshooting
- Improved error handling with graceful degradation
- Better separation of concerns between sync and UI layers

---

## Files Changed

### Core Data & Sync
- `OPS/Utilities/DataController.swift` - Added team sync logic, removed excessive logging
- `OPS/Network/Sync/CentralizedSyncManager.swift` - Fixed project fetching for field crew, added seated employee sync
- `OPS/Utilities/DataHealthManager.swift` - New comprehensive health validation system

### UI Components
- `OPS/Views/Components/Event/EventCarousel.swift` - Added completed overlay to home screen cards
- `OPS/Views/Calendar Tab/Components/CalendarEventCard.swift` - Added completed overlay to calendar cards
- `OPS/Views/Components/User/TaskTeamView.swift` - Implemented optimistic updates and offline-first behavior
- `OPS/Views/Components/Project/TaskDetailsView.swift` - Fixed edit mode state management
- `OPS/Onboarding/Views/Screens/BillingInfoView.swift` - Added refresh mechanism and employee seat UI improvements

### Data Models
- Multiple DTOs updated for proper team member ID handling
- Calendar events, tasks, and projects now consistently manage team member relationships

---

## Migration Notes

### For Administrators
- Existing projects will automatically sync team members from their tasks on next app launch
- No manual intervention required
- Team member changes will now propagate to both task and project levels

### For Field Crews
- Projects assigned via tasks will now appear correctly on first login
- Improved offline access to project data
- No configuration changes needed

---

## Known Issues
- None at this time

---

## Coming Soon
- Enhanced task scheduling features
- Additional calendar view improvements
- Performance optimizations for large project lists

---

**Built by trades, for trades.** Every feature is designed to make your field work easier, not harder.
