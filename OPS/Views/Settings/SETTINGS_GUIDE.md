# OPS App Settings Components

## Overview

This directory contains the settings views and components for the OPS app, focused on providing a consistent, user-friendly settings experience.

## Folder Structure

```
Settings/
├── Components/                 # Reusable UI components for settings
│   ├── SettingsComponents.swift      # Core UI components (header, card, etc.)
│   └── NotificationSettingsControls.swift  # Notification-specific controls
├── EnhancedNotificationSettingsView.swift  # Notification settings with time windows
├── MapSettingsView.swift       # Map customization settings
├── NotificationSettingsView.swift    # Original notification settings
├── OrganizationSettingsView.swift    # Organization settings
├── ProfileSettingsView.swift         # User profile settings
├── ProjectHistorySettingsView.swift  # Project history settings
└── README.md                   # This file
```

## Key Components

### UI Components

- **SettingsHeader**: Header bar with back button and optional edit button
- **SettingsCard**: Container for grouping related settings
- **SettingsSectionHeader**: Section divider with title
- **SettingsToggle**: Toggle control with title and description
- **SettingsButton**: Button with primary/secondary/destructive styles
- **SettingsCategoryButton**: Menu item for navigation to subsections
- **SettingsField**: Text input field with editable/non-editable states

### Notification Components

- **NotificationTimeWindow**: Control for setting notification quiet hours
- **NotificationPrioritySelector**: Allows selecting notification priority levels
- **TemporaryMuteControl**: Temporarily mutes notifications with auto-resume

## Usage Guidelines

1. **Avoid Duplication**: Only create settings views in this directory. Do not duplicate files or create alternative versions with similar names.

2. **Always Use Existing Components**: Use the components in Components/ folder for consistent styling.

3. **Add to Xcode Project**: When adding new files, ensure they're properly added to the Xcode project in the correct group.

4. **Keep Functionality Together**: Related settings should be grouped together in the same file or section.

5. **Update README**: When adding new components, update this file to document them.

## Map Settings Features

The MapSettingsView provides the following customization options:

- **Auto Zoom**: Automatically fit all markers on the map
- **Show Compass**: Display compass for orientation
- **Auto Center/Rotate**: Re-center map when navigating between projects
- **Map Type**: Choose between standard, satellite, or hybrid views
- **3D Buildings**: Toggle 3D building models
- **Traffic Display**: Toggle traffic conditions

## Notification Settings Features

The EnhancedNotificationSettingsView provides:

- **Time Windows**: Set quiet hours for notifications
- **Priority Levels**: Filter notifications by importance
- **Temporary Mute**: Silence notifications for a specific period
- **Project Reminders**: Schedule notifications for specific projects