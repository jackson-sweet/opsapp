# OPS App - V2 Features Updated Roadmap

This document tracks features that have been identified for V2 implementation (post-MVP), updated with current project notes and completion status.

## Calendar & Scheduling Features

### Calendar Request System
- **Long press on calendar date to make requests**
  - Day off/vacation requests
  - Schedule preference changes (early/late start)
  - Availability updates
  - Capacity changes (more/fewer jobs)

- **Advanced Schedule Management**
  - Allow employees to build full schedule with assigned jobs and propose to CO for approval
  - Request Management with status tracking (pending/approved/denied)
  - Manager notification and approval workflow
  - Conflict detection between requests
  - Calendar visualization of pending requests
  - Request history and patterns dashboard

- **Visual Enhancements**
  - Calendar projects can have multiple colors, denoting team members assigned
  - For office crew: add filter to schedule page to filter projects by team member

## Weather & Location Features

### Weather Integration
- Add API to weather apps (user can choose the source in settings)
- Mark jobs as weather dependent, give warnings if forecast includes rain

### Map Features
- ✅ **Team Member Live Locations** (mentioned as already planned in existing docs)
  - Real-time location sharing during work hours
  - Location history for the day
  - Proximity alerts

## Time Tracking & Analytics

### Automatic Time Tracking
- Geofence-triggered time clock (auto-start when arriving at job site)
- Smart detection for job site exit (auto-stop when leaving)
- Use time tracking to help create analytics for trends of days worked, hours worked, jobs completed per hours worked

### Performance Analytics & Insights
- **Business Insights Dashboard**:
  - Average invoice total
  - Number of hours onsite
  - Number of invoices
  - Personalized metrics showing trends over time
  - Jobs completed per hour (efficiency metric)
  - Average time per job type
  - Distance traveled between jobs
  - On-time arrival percentage

- **Data Visualization**:
  - Heat maps showing productive times/locations
  - Timeline views of daily/weekly work patterns
  - Progress toward personal or team goals
  - Mobility patterns between job sites
  - Weather impact on productivity

- **Reporting**
  - Create reports at end of every week and send to user (settings allow user to set report frequency)

## Project Management Features

### Project Enhancements
- Add functionality for multiple visits to a project (new data type: "visit")
- Take multiple photos in app, upload to a project
- Scan receipts functionality
- Rank job importance
- Copy project feature
- Add action items to project

### Client & Contact Management
- Show client contact info on project details, add new Settings object with preferences like "Show Team Client Contact Info"
- Allow users to update teammates contact info, sending notification to team members for approval

## Communication & Collaboration

### ✅ **In-App Messaging** (mentioned as already planned in existing docs)
- Direct messaging between team members
- Project-specific chat threads
- Push notification support

### Notifications & Updates
- Send notification when project notes are updated by a teammate

### ✅ **Enhanced Contact Actions** (mentioned as already planned in existing docs)
- WhatsApp integration
- Multiple phone number support
- Contact notes/preferences

## Business & Financial Features

### Payment & Expense Management
- Set up payment model
- Detailed expense tracking and submission
- Expense functionality
- Set price, but advertise a code for free access to get action

## AI & Web Features

### AI Integration
- **Web app AI quoting**: upload company price sheets and documentation for company knowledge, and upload project drawings to have AI quote

### Notes & Documentation
- **Web app notes system**: add notes tied to project or client, display note pad on dashboard and admin iOS app
  - Example: add note for Mark Jarrett- order vinyl
  - Create notes categories like "vinyl orders" where order pieces can be added

## User Management & Administration

### Role & Permission Management
- User "role" should show 'admin' if the user is a company admin
- Create "you have been terminated" screen for when user has been terminated from company

### User Experience Features
- Add OPS DEVELOPMENT page where users can see progress of requested features and bug fixes

## UI/UX Enhancements

### ✅ **Custom Components** (some already completed in V1)
- ✅ Custom Progress/Loading Indicator (moved to V1, completed)
- ✅ Custom Toggle Switches (mentioned in existing docs)

### Visual Customization
- Extract colors from company logo for UI

### ✅ **Advanced Features** (mentioned as already planned in existing docs)
- Biometric authentication (Face ID/Touch ID)
- Platform expansion (iPad, Apple Watch)

## Technology Integration

### Platform Integration
- Apple CarPlay
- Voice activated features

### ✅ **Integration Features** (mentioned as already planned in existing docs)
- Calendar sync (iOS Calendar integration, Google Calendar sync, Outlook compatibility)
- QuickBooks connector
- Invoice generation

## Storage & Sync Enhancements

### ✅ **Smart Caching** (mentioned as already planned in existing docs)
- Predictive caching based on usage patterns
- Automatic cleanup of old cached data
- Bandwidth-aware sync strategies

### ✅ **Advanced Offline Features** (mentioned as already planned in existing docs)
- Conflict Resolution UI
- Visual diff for conflicting changes
- Merge options
- Conflict history

## ✅ **Accessibility Features** (mentioned as already planned in existing docs)
- Voice Commands
- Siri shortcuts for common actions
- Voice notes for projects
- Audio status updates

## ✅ **Security Enhancements** (some aspects mentioned in existing docs)
- Advanced Authentication
- SSO support
- 2FA implementation
- Session management

---

## Notes

Features marked with ✅ indicate they were already mentioned in the existing V2 features documentation or have been implemented. New features from our project notes have been integrated into appropriate categories. Priority order will be determined based on user feedback and development resources.