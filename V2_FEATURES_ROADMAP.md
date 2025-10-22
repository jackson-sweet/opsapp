# OPS App - V2 Features Roadmap

**Last Updated**: October 2025
**Current Version**: 1.2.0

This document tracks features identified for V2 implementation. Features are organized by category and priority, with status updates reflecting the latest implementation progress.

## Implementation Status Summary

### Major Features Implemented in v1.2.0 ✅
- **CalendarEvent-Centric Architecture**: Complete rewrite of calendar system
- **Task-Based Scheduling**: Full ProjectTask and TaskType system implementation
- **Apple Calendar-like Interface**: Continuous scrolling with month snapping
- **Real-time Task Management**: Immediate sync of status and notes changes
- **SwiftData Defensive Patterns**: Prevention of model invalidation crashes
- **Enhanced Team Management**: Individual task assignment and role detection
- **Project Completion Workflow**: Task-based validation with completion checklist
- **Role-Based Permissions**: Comprehensive access control for field crew vs admin/office

### Features Moved from V2 to Production
Several originally planned V2 features were accelerated into v1.2.0 due to architectural foundations being established:
- Task management system (originally planned for V2.1)
- Advanced calendar interface (originally planned for V2.0)
- Real-time sync improvements (originally planned for V2.0)

## Priority 1: Core Enhancements

### Task Management & Auto-Scheduling
*Building on the current task-based scheduling foundation (v1.2.0)*

**✅ IMPLEMENTED IN v1.2.0:**
- Complete ProjectTask model with status workflow
- TaskType system with predefined templates and custom colors
- TaskDetailsView with comprehensive task management
- Real-time task status and notes sync
- Previous/Next task navigation
- Individual team member assignment per task
- **Project completion workflow with task validation**
- **TaskCompletionChecklistSheet** requiring all tasks to be checked off
- **Smart status management** - tasks marked in progress revert completed projects back to in progress
- **Tactical minimalist completion UI** with radio-style selectors and outline buttons

**Future Enhancements:**
- **Task Dependencies**
  - Define prerequisite tasks that must complete before others can start
  - Visual dependency chain in project view
  - Automatic date adjustment when dependencies change
  - Critical path identification
  
- **Auto-Scheduling Engine**
  - Automatically calculate task dates based on:
    - Dependencies between tasks
    - Team member availability
    - Task estimated hours
    - Working days/hours configuration
  - Conflict detection and resolution suggestions
  - Resource leveling across projects
  
- **Advanced Task Fields**
  - estimatedHours: Track expected time per task
  - actualHours: Compare against estimates
  - percentComplete: Progress tracking beyond status
  - priority: High/Medium/Low for scheduling decisions
  - constraints: Must start on, must finish by, etc.

- **Visual Scheduling Tools**
  - Gantt chart view for projects
  - Resource utilization heat map
  - Timeline view with task dependencies
  - Calendar overlay showing all project tasks

### Calendar & Scheduling Features

**✅ FULLY IMPLEMENTED IN v1.2.0:**
- **CalendarEvent-Centric Architecture**
  - CalendarEvents as single source of truth for all calendar display
  - Efficient shouldDisplay filtering with cached projectEventType
  - Support for both project-level and task-level scheduling modes
  - Batch processing to eliminate N+1 queries
- **Apple Calendar-like Experience**
  - Continuous vertical scrolling through months with seamless transitions
  - Smart month snapping when scroll ends
  - Lazy loading for optimal performance
  - Dynamic month picker that updates while scrolling
  - Event caching system for efficient loading
  - Fixed infinite loop issues and eliminated console spam
  - Enhanced visible month tracking with real-time updates
- **Team member filter for office crew on schedule page**
  
- **Calendar Request System** (Not Started)
  - Long press on calendar date to make requests:
    - Day off/vacation requests
    - Schedule preference changes
    - Availability updates
    - Capacity changes
  - Request Management with status tracking (pending/approved/denied)
  - Manager notification and approval workflow
  - Conflict detection between requests
  
- **Visual Enhancements**
  - Multiple colors per project denoting team members assigned (Partially Complete)
  - ✅ Team member filter for office crew on schedule page (COMPLETED)

### Weather Integration
- Weather API integration (configurable source in settings)
- Mark jobs as weather dependent
- Automatic warnings for weather-impacted projects
- Weather impact analytics on productivity

## Priority 2: Business Features

### Time Tracking & Analytics

- **Automatic Time Tracking**
  - Geofence-triggered time clock (auto-start at job site)
  - Smart detection for job site exit
  - Manual override options
  
- **Business Insights Dashboard**
  - Average invoice total
  - Hours onsite tracking
  - Jobs completed per hour (efficiency metric)
  - Average time per job type
  - Distance traveled between jobs
  - On-time arrival percentage
  - Weather impact on productivity
  
- **Automated Reporting**
  - Weekly/monthly reports via email
  - Customizable report frequency in settings
  - Export to PDF/Excel formats

### Client & Project Management

- **Project Enhancements**
  - Multiple visits per project tracking
  - Bulk photo upload capability
  - Receipt scanning functionality
  - Project importance ranking
  - Copy project feature
  - Action items per project
  
- **Client Features**
  - Project history per client
  - Client contact preferences
  - Quick stats (total projects, completion rate)
  - Client portal access

### Financial Features
- **Expense Management**
  - Detailed expense tracking and submission
  - Receipt attachment
  - Mileage tracking
  - Expense categories and reports
  
- **Accounting Integration**
  - QuickBooks connector
  - Invoice generation
  - Payment tracking
  - Financial reporting

## Priority 3: Communication & Collaboration

### In-App Messaging
- Direct messaging between team members
- Project-specific chat threads
- Push notification support
- Message history and search

### Enhanced Contact Features
- WhatsApp integration
- Multiple phone number support per contact
- Contact notes/preferences
- Team member contact approval workflow

### Notification Enhancements
- Project notes update notifications
- Smart notification preferences
- Notification history

## Priority 4: Platform & Integration

### Platform Expansion
- **iPad Optimization**
  - Split-view support
  - Landscape layouts
  - Apple Pencil support for annotations
  
- **Apple Watch Companion**
  - Quick status updates
  - Location check-ins
  - Team notifications
  
- **Apple CarPlay Integration**
  - Navigation to job sites
  - Voice-activated features
  - Status updates while driving

### Calendar Sync
- iOS Calendar integration
- Google Calendar sync
- Outlook compatibility
- Two-way sync options

### Voice & AI Features
- Siri shortcuts for common actions
- Voice notes for projects
- Audio status updates
- AI-powered quoting (web app)
- AI documentation assistant

## Priority 5: Advanced Features

### Map & Location Features
- **Team Member Live Locations**
  - Real-time location sharing during work hours
  - Location history for the day
  - Proximity alerts
  - Privacy controls
  
### Security Enhancements
- **Advanced Authentication**
  - SSO support
  - 2FA implementation
  - Session management
  - Biometric authentication (Face ID/Touch ID)
  
- **Enhanced PIN Security**
  - PIN timeout settings
  - PIN complexity options (6-digit, alphanumeric)
  - Failed attempt lockout
  - Separate PINs for different security levels

### Offline & Sync Features
- **Conflict Resolution UI**
  - Visual diff for conflicting changes
  - Merge options
  - Conflict history
  
- **Selective Sync**
  - Choose which projects to keep offline
  - Priority-based sync
  - Manual sync controls

### UI/UX Enhancements
- Custom progress/loading indicators
- Custom toggle switches
- Extract colors from company logo for theming
- Dark/light mode toggle
- Customizable dashboard layouts

## Priority 6: Administrative Features

### User Management
- **✅ Role-based permissions** (IMPLEMENTED in v1.2.0)
  - Field crew restricted to view and status updates only
  - Admin/office crew have full edit, delete, and reschedule access
  - Context-aware quick action menus based on user role
  - Calendar event permissions integration
- Termination workflow and screens (Not Started)
- User activity tracking (Not Started)
- Audit logs (Not Started)

### Development Transparency
- OPS Development page showing:
  - Progress on requested features
  - Bug fix status
  - Upcoming releases
  - User voting on features

### Web App Integration
- **Notes System**
  - Notes tied to projects or clients
  - Note categories and organization
  - Dashboard notepad display
  - Cross-platform sync

## Implementation Notes

### Technical Requirements
- Requires displayOrder field on Task model
- Requires dependencies array field on Task model
- Requires estimatedHours field on Task model
- Backend must support dependency validation
- Complex UI components needed (Gantt, timeline)
- Consider third-party scheduling library integration

### Current Status
- Task-based scheduling foundation is in development (not yet complete)
- Multiple bugs need resolution before adding advanced features
- Home page implementation pending

### Prioritization Criteria
Features will be prioritized based on:
1. User feedback and requests
2. Technical dependencies
3. Business value
4. Implementation complexity
5. Available resources

---

*Last Updated: August 2025*
*Note: Features in this roadmap are subject to change based on user feedback and business priorities.*