# OPS App Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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