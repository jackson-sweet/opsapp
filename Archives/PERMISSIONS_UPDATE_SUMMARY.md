# Permissions View Update Summary

## Changes Made to Comply with Apple App Store Guidelines (5.1.1)

### Previous Issue
Apple rejected the app because:
- The app had a custom "Allow" button before the system permission request
- Apple requires neutral language like "Continue" or "Next" instead of "Allow"

### Solution Implemented
Updated the PermissionsView to use a two-phase approach:

#### Phase 1: Location Permission
1. Shows explanation of why location access is needed:
   - Show nearby job sites on the map
   - Navigate to work locations
   - Help teammates find you in the field
2. Has a "Continue" button (not "Allow") that triggers the system location permission dialog
3. Includes a tip to select "Always Allow" for the best experience

#### Phase 2: Notifications Permission
1. Shows explanation of why notifications are needed:
   - Job assignments and updates
   - Schedule changes and reminders
   - Important team messages
2. Has a "Continue" button that triggers the system notification permission dialog
3. Notes that notification preferences can be customized later in Settings

### Key Implementation Details
- Added `PermissionPhase` enum with `.location` and `.notifications` states
- Each phase has its own UI with explanatory content
- "Continue" buttons trigger the actual system permission dialogs
- Smooth transitions between phases using `.transition(.opacity)`
- After both permissions are handled, the app proceeds to the field setup step

### Technical Changes
- Added `@State private var currentPhase: PermissionPhase = .location`
- Replaced the consolidated view that showed both permissions at once
- Each phase now has dedicated UI with proper explanations
- System permission requests are triggered by "Continue" buttons, not custom "Allow" buttons

This implementation should satisfy Apple's requirements for permission handling by:
1. Using neutral "Continue" language instead of "Allow"
2. Providing clear explanations before requesting permissions
3. Letting the system dialogs handle the actual permission requests