# OPS App V2 Features

This folder contains implementations of planned features for V2 of the OPS app. These features are not currently integrated into the main codebase but are ready for future implementation.

## 1. Team Member-Specific Notes

Replaces the general project notes with team member-specific notes, allowing unique notes for each team member on a project.

### Files:
- `Models/TeamMemberNote.swift`: SwiftData model for team member-specific notes
- `Components/TeamMemberNotesView.swift`: UI for viewing and editing team member notes

### Implementation Details:
- Notes are associated with both a project and a specific team member
- Uses expandable/collapsible UI for better space management
- Supports proper relationship management with SwiftData

## 2. Team Member Map Locations

Displays team member locations on the map with tappable annotations that allow messaging.

### Files:
- `Components/TeamMemberMapAnnotation.swift`: Custom map annotation for team members
- `Utilities/MessageHelper.swift`: Helper for sending SMS messages to team members

### Implementation Details:
- Custom map markers showing team member locations
- Different colors based on team member role
- Popup interface with contact options
- Direct messaging integration

## 3. Integration Requirements

To integrate these features, the following changes would be needed:

1. Update Project model to include relationship to TeamMemberNote
2. Update User model to include relationship to TeamMemberNote
3. Enhance LocationManager to track team member locations
4. Update ProjectMapView to show team member annotations
5. Update HomeView to handle team member interactions

## 4. Modifications to Existing Components

When implementing V2 features, these components would need updating:

- ProjectDetailsView: Replace general notes with team member-specific notes
- ProjectMapView: Add team member annotations alongside project markers
- LocationManager: Add team location tracking and notifications
- HomeView/HomeContentView: Add support for team member interaction

## 5. Getting Started

To begin implementing these features:

1. Add the TeamMemberNote model to the data schema
2. Update existing models with the proper relationships
3. Add the new UI components to the project
4. Integrate location tracking for team members
5. Update the map views to display team member locations