# OPS App Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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