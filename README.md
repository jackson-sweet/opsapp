# OPS - Operational Project System

**Built by trades, for trades.**

A field-first iOS project management app designed for trade workers who need technology that "just works" in harsh job site conditions—dirt, gloves, sunlight, poor connectivity.

**Current Version**: 2.0.3 (November 2025)
**Platform**: iOS 17+
**Status**: LAUNCHED ✅

---

## What is OPS?

OPS is an iOS app that helps trade companies manage projects, tasks, teams, and schedules from the field. It's built with an offline-first architecture, dark theme for outdoor visibility, and large touch targets for glove operation.

### Key Features

- **Task-Based Scheduling**: Complete ProjectTask model with customizable TaskTypes
- **Offline-First**: All critical operations work without connectivity
- **Calendar Integration**: Apple Calendar-like continuous scrolling
- **Job Board**: Management dashboard for office crew and admins
- **Team Management**: Role-based permissions (Admin, Office Crew, Field Crew)
- **Real-Time Sync**: Triple-layer sync strategy for reliability
- **Client Management**: Client and sub-client support
- **Image Handling**: Multi-tier caching with S3 integration

---

## Documentation Structure

### Important Note

**These markdown files are designed for Claude (AI assistants) to read and understand the project architecture.** They provide complete context for accurate code generation and debugging without introducing data integrity issues or brand inconsistencies.

### Core Documentation (4 Files)

#### 1. [DATA_AND_MODELS.md](DATA_AND_MODELS.md)
Complete data architecture reference for SwiftData models, Bubble integration, and data handling.

**Contains**:
- SwiftData models and relationships (8 core entities)
- Bubble field mappings (BubbleFields.swift constants)
- DTOs (Data Transfer Objects) and conversion
- Query predicates and soft delete strategy
- Task scheduling system architecture
- SwiftData defensive patterns

**Use when**: Understanding data models, Bubble API integration, query patterns, or data sync logic.

#### 2. [API_AND_SYNC.md](API_AND_SYNC.md)
Complete API endpoint reference and sync architecture documentation.

**Contains**:
- All API endpoints by entity (Projects, Tasks, CalendarEvents, Clients, Users, etc.)
- Sync architecture (triple-layer strategy: immediate, event-driven, periodic)
- CentralizedSyncManager detailed reference
- Image upload and sync implementation
- Error handling and retry logic with exponential backoff
- Network configuration and connectivity monitoring

**Use when**: Implementing API calls, sync logic, offline-first features, or debugging network issues.

#### 3. [UI_GUIDELINES.md](UI_GUIDELINES.md)
Complete UI design standards and OPSStyle system reference.

**Contains**:
- OPSStyle reference (colors, typography, icons, layout)
- Design philosophy and field-first principles
- Component styling patterns (buttons, cards, forms)
- Gesture patterns (swipe-to-change-status, collapsible sections)
- Field-first testing requirements
- Common anti-patterns to avoid

**Use when**: Implementing UI, ensuring brand consistency, or following design standards.

#### 4. [COMPONENTS.md](COMPONENTS.md)
Complete reusable component library reference.

**Contains**:
- Button components (Primary, Secondary, Destructive, Icon)
- Card components (Standard, Elevated, Interactive, Accent, ClientInfo, Location, Notes, TeamMembers)
- Form components (TextField, TextEditor, Toggle, Radio, AddressAutocomplete, SearchBar)
- Job Board components (UniversalJobBoardCard, CollapsibleSection, FilterBadge, ClientProjectBadges, AlphabetIndex)
- Calendar, Navigation, Settings, and Utility components
- Usage examples for each component

**Use when**: Building UI, ensuring component reuse, or maintaining consistency.

### Special Files

- **[CLAUDE.md](CLAUDE.md)** - Instructions for Claude on how to work with this project, brand guidelines
- **[RELEASE_NOTES.md](RELEASE_NOTES.md)** - Consolidated version history and feature releases

---

## Tech Stack

- **Platform**: iOS 17+ (SwiftUI + SwiftData)
- **Backend**: Bubble.io REST API
- **Storage**: AWS S3 (images)
- **Architecture**: MVVM, ~200 Swift files
- **Design**: Custom fonts (Mohave, Kosugi), dark theme, OPSStyle system
- **Authentication**: Multi-method (Standard, Google OAuth, PIN)

---

## Project Structure

```
/OPS
├── Data Models/          # SwiftData models (8 core entities)
├── Network/             # API service, sync manager, DTOs, endpoints
├── Views/               # SwiftUI views organized by feature
├── Styles/              # OPSStyle system and standardized components
├── Documentation/       # Technical docs and implementation guides
├── Development Tasks/   # Active TODO lists and future features
├── Release Notes/       # Version-specific release notes
└── Archives/            # Historical migration guides and completed work
```

---

## Quick Start for Developers

### Prerequisites
- Xcode 15+
- iOS 17+ device or simulator
- Bubble.io account (backend API)
- AWS account (S3 image storage)
- Google Cloud Console account (Google Sign-In)

### Setup
1. Clone the repository
2. Open `OPS.xcodeproj` in Xcode
3. Update configuration in `AppConfiguration.swift`
4. Configure AWS credentials (TODO: move to secure config)
5. Add `GoogleService-Info.plist` for Google Sign-In
6. Build and run

### Understanding the Codebase

**Start here**:
1. **Read [CLAUDE.md](CLAUDE.md)** - Understand how to work with this project
2. **Read [DATA_AND_MODELS.md](DATA_AND_MODELS.md)** - Learn the data architecture
3. **Review [UI_GUIDELINES.md](UI_GUIDELINES.md)** - Understand design standards
4. **Browse [COMPONENTS.md](COMPONENTS.md)** - See available reusable components
5. **Reference [API_AND_SYNC.md](API_AND_SYNC.md)** - When implementing API/sync features

---

## Recent Major Work (November 2025)

### Task-Based Scheduling Migration (Nov 18)
- ✅ Removed dual-scheduling system (project-level vs task-level)
- ✅ All projects now use task-only scheduling
- ✅ Simplified CalendarEvent filtering
- ✅ Removed `eventType`, `type`, `active` fields
- ✅ Project dates computed from task dates

### Documentation Consolidation (Nov 18)
- ✅ Consolidated 93 markdown files into 4 core docs + CLAUDE.md
- ✅ Created AI-assistant-focused documentation
- ✅ Archived historical migration guides
- ✅ Streamlined project documentation for maintainability

### Critical Bug Fixes
- ✅ Manual sync data loss (Nov 3) - Fixed role assignment bug
- ✅ App launch duplicate syncs (Nov 15) - Added 2-second debouncing
- ✅ UI/UX improvements - Inline editing, haptic feedback, animations
- ✅ Team management - Optimistic UI with background sync

---

## Development Guidelines

### Code Standards

```swift
// ✅ CORRECT: Use OPSStyle constants
Text("Title").font(OPSStyle.Typography.title)
    .foregroundColor(OPSStyle.Colors.primaryText)
Image(systemName: OPSStyle.Icons.calendar)
    .foregroundColor(OPSStyle.Colors.primaryAccent)

// ❌ WRONG: Hardcoded values (will be rejected)
Text("Title").font(.title)                    // System font
    .foregroundColor(.white)                  // Hardcoded color
Image(systemName: "calendar")                 // Hardcoded icon string
```

### Key Architectural Principles

1. **Task-Only Scheduling** - Simplified from dual-mode (Nov 2025)
2. **Soft Delete Strategy** - All models have `deletedAt: Date?`
3. **SwiftData Defensive Patterns** - Never pass models to background tasks
4. **OPSStyle System** - Never hardcode colors, fonts, or icons
5. **Field-First Design** - Every decision considers gloves, sunlight, connectivity
6. **Reuse Components** - Use COMPONENTS.md reference, never recreate

### Git Workflow
- Feature branches from main
- Clear, descriptive commit messages
- **No AI attribution** in commits
- Use Sonnet 4 (not Opus 4) for development assistance

---

## Field-First Testing Requirements

**Test with gloves**: All touch targets 44×44pt minimum, 60×60pt preferred

**Test in sunlight**: 7:1 contrast ratio for text, dark theme prevents glare

**Test offline**: All critical features work without connectivity, sync when reconnected

**Test on older devices**: Support 3-year-old hardware, smooth performance on older iPhones

**Test with real conditions**: Battery drain, poor network, bright outdoor lighting

---

## Core Values

1. **Reliability > Features** - Works when other tech fails
2. **Simplicity > Flexibility** - No unnecessary complexity
3. **Clarity > Cleverness** - Get to the point
4. **Field Needs > Office Preferences** - Designed for job sites
5. **Consistency is Paramount** - Same components look identical everywhere
6. **Time Is Money** - Quick actions, minimal taps

---

## Getting Help

**Code Questions**:
- Data/API: [DATA_AND_MODELS.md](DATA_AND_MODELS.md), [API_AND_SYNC.md](API_AND_SYNC.md)
- UI/Components: [UI_GUIDELINES.md](UI_GUIDELINES.md), [COMPONENTS.md](COMPONENTS.md)
- How to work: [CLAUDE.md](CLAUDE.md)

**Feature Implementation**: Check `Development Tasks/` folder for active work

**Version History**: See `Release Notes/` folder for version-specific changes

---

## Support

### Current Features (v2.0.3)
- ✅ Task-based scheduling with ProjectTask model and TaskType system
- ✅ Job Board (Phase 1 & 2 complete)
- ✅ CentralizedSyncManager with triple-layer strategy
- ✅ Complete authentication (Standard, Google OAuth, PIN)
- ✅ Team management with role-based permissions
- ✅ Client and sub-client management
- ✅ Image system with S3 integration and multi-tier caching
- ✅ Calendar with month/week views and continuous scrolling
- ✅ 13+ settings screens with comprehensive configuration
- ✅ Data health validation and recovery
- ✅ Soft delete support across all entities

### Reporting Issues
1. Check existing documentation (4 core files)
2. Test in offline mode
3. Provide device/iOS version
4. Include steps to reproduce
5. Check for SwiftData defensive pattern violations

---

## License

Copyright © 2025 OPS App. All rights reserved.

---

**"Start with the customer experience and work backwards to the technology." - Steve Jobs**

**Built by trades, for trades.** 🔨
