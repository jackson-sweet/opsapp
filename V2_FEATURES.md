# OPS App - V2 Features Roadmap

This document tracks features that have been identified for V2 implementation (post-MVP).

## UI Enhancements

### Custom Components
- **Custom Progress/Loading Indicator**
  - Replace current loading views with custom branded animations
  - Follow OPS brand colors and style
  - Consider field-appropriate animations (not too flashy)

- **Custom Toggle Switches**
  - Replace standard iOS toggles throughout the app
  - Maintain OPS brand consistency
  - Ensure accessibility standards are met

### Advanced Features

- **Client Project History**
  - Show list of projects belonging to a client on their detail sheet
  - Filter by status, date range
  - Quick stats (total projects, completion rate)

- **Team Member Project Assignment View**
  - Show list of projects that team members are assigned to
  - Only show projects where the viewing user is also assigned
  - Filter by active/completed status

## Storage & Sync Enhancements

- **Smart Caching**
  - Predictive caching based on usage patterns
  - Automatic cleanup of old cached data
  - Bandwidth-aware sync strategies

## Communication Features

- **In-App Messaging**
  - Direct messaging between team members
  - Project-specific chat threads
  - Push notification support

- **Enhanced Contact Actions**
  - WhatsApp integration
  - Multiple phone number support
  - Contact notes/preferences

## Map Features

- **Team Member Live Locations**
  - Real-time location sharing during work hours
  - Location history for the day
  - Proximity alerts

## Reporting & Analytics

- **Project Analytics**
  - Time tracking reports
  - Completion trends
  - Team productivity metrics

- **Client Reports**
  - Automated project status reports
  - PDF export functionality
  - Email scheduling

## Onboarding Enhancements

- **Industry-Specific Customization**
  - Tailored onboarding based on selected industry
  - Industry-specific feature highlights
  - Recommended settings presets

## Data Management

- **Bulk Operations**
  - Multi-select for projects
  - Bulk status updates
  - Batch assignment changes

- **Advanced Search**
  - Full-text search across projects
  - Filter combinations
  - Saved search queries

## Integration Features

- **Calendar Sync**
  - iOS Calendar integration
  - Google Calendar sync
  - Outlook compatibility

- **Accounting Integration**
  - QuickBooks connector
  - Invoice generation
  - Expense tracking

## Performance Optimizations

- **Image Optimization**
  - Server-side image processing
  - Progressive image loading
  - Thumbnail generation

## Accessibility

- **Voice Commands**
  - Siri shortcuts for common actions
  - Voice notes for projects
  - Audio status updates

## Platform Expansion

- **iPad Optimization**
  - Split-view support
  - Landscape layouts
  - Apple Pencil support for annotations

- **Apple Watch Companion**
  - Quick status updates
  - Location check-ins
  - Team notifications

## Auto-Scheduling & Task Management

### Intelligent Project Scheduling
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
  
- **Task Ordering & Management**
  - Manual drag-and-drop reordering with displayOrder/index values
  - Automatic reordering based on dependencies
  - Task templates for common project types
  - Bulk task operations (copy, move, delete)
  
- **Advanced Task Fields**
  - estimatedHours: Track expected time per task
  - actualHours: Compare against estimates
  - percentComplete: Progress tracking beyond status
  - priority: High/Medium/Low for scheduling decisions
  - constraints: Must start on, must finish by, etc.
  
- **Scheduling Algorithms**
  - Forward scheduling from project start date
  - Backward scheduling from required completion date
  - Resource-constrained scheduling
  - Time-constrained scheduling
  
- **Visual Scheduling Tools**
  - Gantt chart view for projects
  - Resource utilization heat map
  - Timeline view with task dependencies
  - Calendar overlay showing all project tasks
  
- **Smart Suggestions**
  - Recommend optimal task sequences
  - Identify scheduling conflicts early
  - Suggest resource reallocation
  - Alert on impossible schedules

### Implementation Notes
*These features build on the Task-based scheduling foundation (V2.0.0)*
- Requires displayOrder field on Task model
- Requires dependencies array field on Task model  
- Requires estimatedHours field on Task model
- Backend must support dependency validation
- Complex UI components needed (Gantt, timeline)
- Consider third-party scheduling library integration

## Advanced Offline Features

- **Conflict Resolution UI**
  - Visual diff for conflicting changes
  - Merge options
  - Conflict history

- **Selective Sync**
  - Choose which projects to keep offline
  - Priority-based sync
  - Manual sync controls

## Security Enhancements

- **Advanced Authentication**
  - SSO support
  - 2FA implementation
  - Session management

- **Enhanced PIN Security Options**
  - PIN requirement modes:
    - Every app open (current implementation)
    - Only on app restart (new option)
  - Biometric authentication integration (Face ID/Touch ID)
  - PIN timeout settings (e.g., require after 5 minutes of inactivity)
  - PIN complexity options (6-digit, alphanumeric)
  - Failed attempt lockout with increasing delays
  - PIN reset via email verification
  - Separate PINs for different security levels (e.g., view vs. edit)

## Notes

Features in this document have been identified during MVP development but deferred to maintain focus on core functionality. Priority order will be determined based on user feedback after MVP launch.