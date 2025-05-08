# OPS App View Structure

This document outlines the organization of views and components in the OPS application.

## Folder Structure

### Main Views
- **Home/** - Home screen components and views
  - **Components/** - Components specific to the Home view
- **Calendar Tab/** - Calendar and scheduling views
  - **Components/** - Small reusable calendar components
  - **ProjectViews/** - Project-specific views used in the calendar
- **Settings/** - Settings and profile screens
  - **Components/** - Components specific to settings screens
- **Permissions/** - Permission-related views

### Shared Components
Components in this directory are organized by functionality and can be used across multiple main views.

- **Components/**
  - **Common/** - Shared UI elements like headers, navigation elements, etc.
  - **Project/** - Project-related components (cards, details, headers)
  - **User/** - User-related components (profile cards, team member lists)
  - **Map/** - Map and location components
  - **Images/** - Image display and manipulation components

## Guidelines for Adding New Components

1. **Determine Component Scope**
   - If a component will be used across multiple main views, add it to the appropriate **Components/** subfolder
   - If a component is only used within one main view, add it to that view's **Components/** subfolder

2. **Import Best Practices**
   - Use relative imports when referencing components from the same module
   - Keep imports organized with SwiftUI and UIKit imports first, followed by custom components

3. **File Naming Conventions**
   - Name files descriptively based on their primary function
   - Use PascalCase for view files (e.g., `ProjectDetailsView.swift`)
   - End view files with "View" suffix for clarity