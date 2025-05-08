# OPS App V2 Features

This directory contains features planned for the next major version of the OPS app. These features are work in progress and not included in the current release build.

## Certifications & Training

The `CertificationsSettingsView.swift` contains the UI for managing user certifications and training records. This feature has been moved to V2 to simplify the initial app deployment.

### Implementation Notes

To re-enable this feature in the future:

1. Move the file back to the `/Views/Settings/` directory
2. Update `SettingsView.swift` to include the certifications section:
   - Add `certifications` back to the `SettingsSection` enum
   - Add the icon and description for this section
   - Add the case in the navigation destination switch

### Database Models

The feature will require new database models:

- `Certification` model with fields for name, issuer, dates, status, etc.
- `Training` model with fields for course name, provider, completion date, etc.

These models will need to be included in the SwiftData schema and properly related to the User model.

### API Integration

API endpoints will need to be created in the Bubble backend to support:

- Fetching user certifications and training records
- Creating new certification/training entries
- Updating existing records
- Uploading supporting documents (certificates, completion records)

## Other V2 Features

Additional V2 features will be added to this directory as they are developed.