# OPS App Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - 2025-10-16

### Project Completion & Permissions

#### Completion Workflow
- **Project Completion Button**: Added "MARK PROJECT COMPLETE" button to ProjectDetailsView
- **Task-Based Validation**: TaskCompletionChecklistSheet requires all tasks to be checked off before project completion
- **Smart Status Management**: Task status changes to "in progress" automatically revert completed projects back to in progress
- **Tactical Minimalist UI**: Simplified completion checklist with dividers, radio-style selectors, and accent outline buttons

#### Role-Based Permissions
- **Field Crew Restrictions**: Limited to view and status update operations only
- **Admin/Office Access**: Full edit, delete, reschedule, and team assignment capabilities
- **Context-Aware Menus**: Quick action menus show appropriate options based on user role
- **Calendar Integration**: CalendarEventCard respects role permissions in quick actions

#### UI Components
- **TaskCompletionChecklistSheet**: New modal for task-based project completion validation
- **Outline Button Style**: Primary accent outline buttons for completion actions
- **Radio Selectors**: Minimalist circle indicators instead of checkboxes
- **Divider Separated Lists**: Clean task row separation without card backgrounds

### Job Board Enhancements

#### UI/UX Improvements
- **Smooth Transitions**: Fixed section switching in Job Board (dashboard, clients, projects, tasks) with optimized opacity animations
- **Interactive Feedback**: Enhanced project cards with proper long press haptic feedback and scale-down effect (0.95)
- **Drag-and-Drop Polish**: Updated dashboard project cards with refined timing for drag interactions
- **Swipe Gesture Fixes**: Fixed status card text alignment during swipe-to-change-status confirmation
- **Alphabet Index**: Made alphabet index in ClientListView touch-responsive with scrollable drag gesture and haptic feedback

#### Client Management
- **Visual Status Summary**: Redesigned client cards to show project status counts as colored badges
- **Format**: `CLIENT NAME  [2] [1] [3] [5]` where each number represents active project count by status
- **Performance**: Optimized client project counts using Dictionary grouping (single pass instead of 6 filters)
- **Empty States**: Added "No projects yet. Create one?" message when client has no projects
- **Quick Actions**: Added "ADD +" button in client detail view for admin/office users to create projects

#### Project Management
- **Project Creation Fix**: Fixed project creation to properly add project to client's projects array
- **Predictive Address**: Added predictive address fields using LocationManager for proximity-based suggestions
- **Context Pre-population**: Pre-populate client and address when creating project from client view
- **Sort by Status**: Added status-based sorting with "Status (RFQ to Closed)" and "Status (Closed to RFQ)" filter options

#### Architecture & Performance
- **Tab View Optimization**: Removed `.id(selectedSection)` from MainTabView to prevent HomeView recreation causing hangs
- **Transition System**: Optimized JobBoardView with switch statement using opacity animations
- **OPSStyle Centralization**: Added `OPSStyle.Colors.cardBorder` and `cardBorderSubtle` constants
- **Border Consistency**: Updated all card borders to reference centralized color constants (no more hardcoded values)
- **Performance Investigation**: Identified subscription check causing 0.8s hangs on tab switches

#### Technical Improvements
- **Removed Duplicates**: Removed duplicate AddressLocationProvider class
- **Computed Properties**: Added `sortOrder` to Status and TaskStatus enums for consistent sorting
- **Swipe Direction Storage**: Fixed status card confirmation by storing swipe direction before animation

### Known Performance Issues
- Subscription check on tab switch takes ~0.8s and causes UI hangs (needs optimization)

## [1.2.0] - 2025-09-26

### Major Features Added
- **CalendarEvent-Centric Architecture**: Complete rewrite of calendar system using CalendarEvents as single source of truth
- **Task-Based Scheduling**: Full implementation of ProjectTask model with status workflow (Scheduled → In Progress → Completed → Cancelled)
- **TaskType System**: Predefined task templates (Quote, Work, Service Call, Inspection, Follow Up) with custom colors and SF Symbol icons
- **TaskDetailsView**: Comprehensive task management interface matching ProjectDetailsView structure
- **Apple Calendar-like Interface**: Continuous vertical scrolling through months with seamless transitions and month snapping
- **Real-time Task Updates**: Immediate API synchronization for task status and notes changes
- **Enhanced Team Management**: Individual team member assignment per task with full contact integration
- **Swipe-to-Change-Status**: Horizontal swipe gestures on project and task cards with 40% threshold and haptic feedback
- **Collapsible Sections**: Organized sections for closed/archived projects and cancelled tasks to prevent list flooding
- **Icon Centralization**: All SF Symbol icons centralized in OPSStyle.Icons enum for consistency

### Performance & Stability Improvements
- **Fixed infinite loop issues** in MonthGridView that caused performance problems
- **Eliminated verbose debug logging** that caused console spam
- **Enhanced visible month tracking** with dynamic month picker updates during scrolling
- **SwiftData defensive patterns** to prevent model invalidation crashes
- **Complete data wipe on logout** to prevent cross-user data contamination
- **Company admin detection** with isCompanyAdmin property for proper role-based features

### Calendar & UI Enhancements
- **Visible month tracking**: Month picker now displays currently visible month and updates while scrolling
- **Month snapping**: Calendar automatically snaps to nearest month when scrolling ends
- **Performance optimizations**: Lazy loading of events only for visible months with intelligent caching
- **Today card enhancement**: Always displays today's date with event count regardless of selected month
- **shouldDisplay logic**: Centralized filtering based on project scheduling mode with cached projectEventType
- **Task navigation cards**: Previous/Next task navigation for seamless workflow
- **Haptic feedback**: Status change confirmations with user permission respect
- **Swipe gesture system**: 40% threshold triggers status change with revealed status card behind swiping card
- **Status progression**: Projects (RFQ → Estimated → Accepted → In Progress → Completed → Closed), Tasks (Scheduled → In Progress → Completed)
- **Reactivation support**: Archived projects swipe to Accepted, cancelled tasks swipe to Scheduled
- **Collapsible sections**: Closed/archived projects and cancelled tasks organized in expandable sections with count badges

### API & Sync Improvements
- **Task status sync**: Real-time updates with `updateTaskStatus(id: String, status: String)` endpoint
- **Task notes sync**: Auto-save functionality with `updateTaskNotes(id: String, notes: String)` endpoint
- **Selective TaskType fetching**: Performance optimization by fetching only referenced task types
- **CalendarEvent sync**: Events now sync during project operations for consistency
- **Batch processing**: Optimized calendar loading with project lookup dictionaries to eliminate N+1 queries
- **Removed feature flags**: All companies now have access to task features

### Technical Architecture Updates
- **CalendarEvent shouldDisplay property**: Handles complex visibility logic in one location
- **Project eventType support**: Dual scheduling modes (.project vs .task) fully operational
- **TaskDetailsView components**: LocationCard, ClientInfoCard, NotesCard, TeamMembersCard reusability
- **Memory management**: autoreleasepool blocks for batch operations
- **Background task safety**: Never pass SwiftData models to background contexts
- **Status progression logic**: nextStatus() and previousStatus() methods with canSwipeForward/canSwipeBackward properties
- **Interactive gesture handling**: Directional detection (horizontal vs vertical) to prevent scroll interference
- **Animation coordination**: Multi-phase animations with DispatchQueue timing for smooth status changes
- **OPSStyle.Icons enum**: Centralized 40+ SF Symbol references for consistency across app

### Developer Experience
- **Centralized debug dashboard**: Enhanced developer tools with better organization
- **Comprehensive task debugging**: Detailed logging for task team member relationships
- **Fixed exit functionality**: Developer mode exit button now works correctly
- **Icon system**: Centralized icon references eliminate hardcoded SF Symbol strings
- **Reusable components**: CollapsibleSection generic component for expandable list sections

### Bug Fixes
- **Vertical scrolling**: Fixed DragGesture capturing vertical scrolls by adding directional detection
- **Animation timing**: Eliminated "Invalid sample AnimatablePair" warnings with .interactiveSpring() animation
- **Status confirmation**: Fixed incorrect status display on confirmation by storing target status before animation
- **Gesture thresholds**: Added minimum distance (20pt) to DragGesture for better scroll vs swipe detection

### Known Issues
- Task-based scheduling not fully integrated on home page (planned for v1.2.1)
- Some task display and scheduling logic refinements needed
- CalendarEvent filtering could be further optimized

## [1.1.0] - 2025-01-15

### Added
- Advanced Contact Management with sub-client functionality
- Enhanced Project Search with smart filtering
- Client profile photo support from Bubble's Thumbnail field
- Role-based contact editing permissions (Admin/Office only)
- On-demand project refresh with visual feedback
- Address autocomplete for faster data entry

### Changed
- Fixed completion date logic (day after last work day)
- Single-day project handling when start equals completion date
- "Unscheduled" display for projects without dates
- Consistent card styling with proper borders throughout
- Team members section with unified styling

### Fixed
- UIActivityViewController presentation conflicts
- Keyboard pushing up main content in search sheets
- Preview crashes from missing environment objects
- Project sync to remove unassigned projects

## [Unreleased] - 2025-07-03

### Fixed (Historical)
- User type being cached before signup completion, causing persistence on logout
- Team invite page being skipped for company owners due to duplicate switch case
- Company and project data not loading properly during onboarding
- Back navigation from UserInfoView after account creation allowing re-signup attempts
- Account created screen not showing after successful signup
- Step numbering and total steps incorrect for different user types

### Technical Updates
- Comprehensive codebase analysis and documentation update
- Updated all markdown documentation to reflect current architecture
- Documented complete file structure (220+ Swift files)
- Added detailed service layer documentation with CalendarEvent-centric patterns
- Enhanced security implementation details with SwiftData defensive patterns
- Updated data model documentation with DTO patterns and new models

### Known Issues
- AWS credentials temporarily hardcoded in S3UploadService
- Build number hardcoded in project settings
- Phone verification using simulated SMS

## [1.0.2] - 2025-06-19

### Added
- Enhanced location permission handling with completion callbacks
- Proper handling for denied/restricted permission states with immediate settings prompts
- Info.plist permission description keys for location and notifications
- Smart company code skipping logic for employees who already have a company

### Changed
- LocationManager now supports completion callbacks for permission requests
- OnboardingViewModel permission methods now properly handle denied/restricted states
- Permission views show alerts immediately when permissions are denied
- Back navigation in onboarding now skips company code step for employees with existing companies

### Fixed
- Location permission dialog not appearing due to missing Info.plist keys
- Notification permission dialog not appearing due to missing Info.plist key
- Onboarding flow incorrectly showing company code step for users already in a company
- Back button navigation from permissions page incorrectly going to company code

## [1.0.1] - 2025-06-06

### Added
- Location disabled overlay on map with clear messaging and settings link
- Location status card in map settings matching notification design pattern
- Bug reporting functionality with dedicated ReportIssueView
- Role-based welcome messages in onboarding (different for employees vs crew leads)
- Permission denial alerts in onboarding with direct links to settings

### Changed
- Notification settings now use standardized SettingsToggle component
- Project action bar redesigned with blurred background and icon-based layout
- What's New features moved to centralized AppConfiguration
- Completion view simplified with fade-in animation
- Brand Identity documentation converted from RTF to Markdown

### Removed
- Company logo upload requirement from onboarding flow
- Old documentation files (MVP planning documents)

### Fixed
- Location permission handling during project routing
- Consistency across settings screens

## [1.0.0] - 2025-06-01

### Initial Release
- Authentication & Security System
- Project Management with offline-first sync
- Calendar & Scheduling Views
- Comprehensive Settings Suite (13+ screens)
- Image Management with S3 integration
- Team Management with role-based permissions
- Custom dark theme optimized for field work
- Professional typography system (Mohave/Kosugi)
- Map & Navigation with turn-by-turn directions