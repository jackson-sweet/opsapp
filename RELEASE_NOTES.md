# OPS Release Notes

**Current Version**: 2.0.3
**Last Updated**: December 4, 2025

---

## Version 2.0.3 (November 28, 2025)

### Overview
Major release featuring Firebase Analytics integration for Google Ads conversion tracking, in-app messaging system, and comprehensive UI consistency improvements across all settings and detail views.

---

### New Features

#### Firebase Analytics & Conversion Tracking
- **Google Ads Integration**: Comprehensive analytics events for conversion tracking
- **User Journey Tracking**: Track key user actions and conversions
- **Marketing Attribution**: Enable data-driven marketing decisions
- **Screen View Tracking**: Manual tracking for all main screens and forms
- **CRUD Event Tracking**: Track task, client, and project create/edit/delete operations
- **Status Change Tracking**: Monitor project and task status transitions
- **Tab Navigation Tracking**: Track user navigation patterns across app tabs
- See [ANALYTICS.md](ANALYTICS.md) for complete event reference

#### In-App Messaging System
- **App Messages**: New system for displaying in-app announcements and updates
- **Message Management**: Admin-controlled messaging from Bubble backend
- **User Experience**: Non-intrusive notifications for important updates

#### Organization Settings Modular Views
- **Redesigned Settings**: Organization settings split into focused, modular views
- **Improved Navigation**: Easier access to specific settings categories
- **Consistent UI**: All settings views now use SectionCard pattern

---

### UI Consistency Improvements

#### SectionCard Migration (Track B)
- **All Settings Views**: Migrated to consistent SectionCard component
  - MapSettingsView
  - NotificationSettingsView
  - DataStorageSettingsView
  - SecuritySettingsView
  - OrganizationSettingsView
  - ProfileSettingsView
- **Detail Views**: ProjectDetailsView, ContactDetailView updated
- **Uniform Spacing**: Consistent padding and layout across all views

#### Loading & Confirmation Patterns (Track K)
- **LoadingOverlay Modifier**: Standardized loading states across all form sheets
- **DeleteConfirmation Modifier**: Consistent delete confirmation dialogs
- **Subscription Lockout**: Improved UX with status display in refresh button

---

### Bug Fixes

#### Team & Sync
- **Project Team Computation**: Fixed team members computed during sync instead of view appearance
- **Onboarding Flow**: Fixed data sync, subscription loading, and loading UI issues

#### QA Fixes
- **Team UI**: Various team management interface fixes
- **Push-in Notifications**: Fixed notification display issues
- **Task List**: Resolved task list rendering problems
- **Settings**: Multiple settings view fixes

---

## Version 2.0.2 (November 18-24, 2025)

### Overview
Architecture simplification release featuring task-only scheduling migration, comprehensive codebase efficiency improvements, and form sheet UI consistency updates.

---

### Architecture Changes

#### Task-Only Scheduling Migration
- **Simplified Architecture**: Removed dual-scheduling system (project-level vs task-level)
- **All Projects Task-Based**: Every project now uses task-based scheduling exclusively
- **Computed Project Dates**: Project start/end dates computed from task calendar events
- **Removed Fields**: Eliminated `eventType`, `type`, `active` fields from models
- **Cleaner Codebase**: Simplified CalendarEvent filtering logic

#### Codebase Efficiency Improvements
- **Track A**: Expanded OPSStyle definitions with semantic colors and icons
- **Track D**: Merged duplicate form/edit sheets (TaskTypeSheet, ClientSheet)
- **Track E**: Complete color migration to semantic OPSStyle colors (235+ files)
- **Track F**: Icon migration to OPSStyle.Icons (54% complete)
- **Track G**: Consolidated filter sheets into generic FilterSheet component
- **Track H**: Consolidated deletion sheets into generic DeletionSheet component

---

### Form Sheet UI Improvements

#### Consistency Updates
- **ProjectFormSheet**: Dynamic section reordering, auto-scroll to opened sections
- **TaskFormSheet**: All inputs grouped into single card section
- **ClientFormSheet**: Unified input card layout with consistent borders
- **Button Placement**: Save/Cancel buttons positioned at bottom consistently
- **Border Consistency**: All form sheets use `Color.white.opacity(0.1)` borders

#### Progressive Disclosure
- **Collapsible Sections**: Sections expand/collapse with smooth animations
- **Smart Ordering**: Active sections move to top of form
- **Reduced Clutter**: Less overwhelming initial form state

---

### Job Board Enhancements

#### Badge Logic Improvements
- **Unscheduled Badge**: Shows if project has no tasks
- **Smart Filtering**: Excludes completed/cancelled tasks from badge calculation
- **Badge Hiding**: Hidden when all tasks are completed/cancelled

#### Field Crew Access
- **Tab Bar Access**: Job Board tab visible to all user roles
- **Role-Based UI**: Section picker hidden for field crew
- **Project Filtering**: Field crew see only assigned projects
- **Status Updates**: Field crew can update project and task statuses

---

### Bug Fixes

#### Critical Fixes
- **Task/Project Linking**: Fixed critical bug in task-project relationships
- **UI Notifications**: Improved notification display and timing
- **Floating Action Menu**: UI improvements and fixes

#### TaskDetailsView
- **Field Crew Permissions**: Dates section visual consistency for all roles
- **Interaction Control**: Uses `.allowsHitTesting()` for permission control
- **Permission Indicators**: Chevron shows only for users who can edit

---

## Version 2.0.1 (November 13, 2025)

### Overview
Focus on team member management, data synchronization reliability, and visual clarity for completed work.

---

### Visual Improvements

#### Completed Task & Event Overlay
- **Calendar Views**: Completed items display with grey overlay and "COMPLETED" badge
- **Project Carousel**: Home screen cards show completion status
- **Clear Visual Hierarchy**: Easy distinction between active and completed work
- **Locations**: Week view, month view, project lists, home carousel

---

### Team Management Enhancements

#### Automatic Project Team Synchronization
- **Smart Team Updates**: Task team changes automatically update parent project
- **Unified Access Control**: Field crew assigned to tasks see parent project
- **Real-Time Sync**: Background sync with immediate UI updates
- **Offline-First**: Local save first, sync when connected

#### Improved Team Editing
- **Responsive UI**: Immediate reflection of team changes
- **No Delays**: Eliminated UI hang on team saves
- **Edit Mode Stability**: Fixed unexpected dismissal after edits
- **Optimistic Updates**: Instant UI with background sync

---

### Data Reliability & Sync

#### Data Health Management
- **Health Checks on Launch**: Validates user, company, sync manager state
- **Automatic Recovery**: Missing sync manager reinitializes automatically
- **Onboarding Protection**: Prevents sync errors during setup
- **State Validation**: Ensures critical data configured before sync

#### Subscription Data Sync
- **Seated Employee Sync**: Fixed missing data during company sync
- **Data Preservation**: Employee info no longer lost during sync
- **Complete Company Sync**: All data including billing syncs reliably

#### Field Crew Access
- **All-Projects Sync**: Field crew syncs all company projects locally
- **Task-Based Filtering**: UI-level access control based on assignments
- **Improved Performance**: Local data filtering instead of API filtering

---

### Employee Experience

#### Unseated Employee Support
- **Clear Messaging**: Helpful info about contacting administrator
- **Contact Actions**: Direct CALL and EMAIL buttons
- **Admin Information**: Shows admin contact details
- **Professional UI**: Matches subscription lockout design

#### Subscription & Billing UI
- **Refresh Mechanism**: BillingInfoView updates after changes
- **Employee Seat Section**: Redesigned for consistency

---

### Bug Fixes

- **Delete Confirmation**: Task cards show confirmation before deletion
- **Team Member IDs**: Fixed CalendarEvent team member handling
- **Data Model Consistency**: All models implement team member getters/setters
- **Sync Reliability**: Calendar events sync team changes with tasks

---

## Technical Summary

### Architecture
- Task-only scheduling (removed dual-mode)
- SectionCard component for consistent UI
- LoadingOverlay and DeleteConfirmation modifiers
- Semantic OPSStyle colors and icons
- Generic FilterSheet and DeletionSheet components

### Key Files
- `CentralizedSyncManager.swift` - Triple-layer sync strategy
- `OPSStyle.swift` - Centralized design system
- `DataHealthManager.swift` - Health validation
- `DataController.swift` - Data management and team sync

---

## Known Issues
- None at this time

---

## Coming Soon
- Enhanced analytics dashboard
- Additional calendar view improvements
- Performance optimizations for large project lists
- Continued icon migration (Track F)

---

**Built by trades, for trades.** Every feature is designed to make your field work easier, not harder.
