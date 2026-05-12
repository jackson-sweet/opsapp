//
//  MeasurementNotificationTypes.swift
//  OPS
//
//  Phase G — type constants, body formatters, and DTO factories for the three
//  LiDAR Dimensioned Photo Capture notification types.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §6
//
//  Phase F's `DimensionedPhotoSyncManager` is the call site that fires these
//  notifications via `NotificationRepository.createNotification(_:)`:
//    - success                       → `captured(...)` factory
//    - queued offline (no signal)    → `pendingSync(count:)` factory
//    - retries exhausted             → `syncFailed(projectName:)` factory
//
//  Body strings are spec-verbatim. Tests in
//  `OPSTests/Utilities/MeasurementNotificationTests.swift` assert verbatim
//  matches against this file — do not edit the strings here without updating
//  the spec first.
//

import Foundation

enum MeasurementNotificationType {
    /// `// MEASUREMENT SAVED` — dispatch after a full successful 3-asset upload.
    static let captured = "measurement_captured"

    /// `// SYNC QUEUED` — dispatch when the capture has been written locally
    /// but the network is unavailable. iOS surfaces as persistent banner.
    static let pendingSync = "measurement_pending_sync"

    /// `// ERROR — SYNC FAILED` — dispatch after retries exhausted.
    static let syncFailed = "measurement_sync_failed"
}

enum MeasurementNotificationCopy {

    /// Title for `measurement_captured`. Spec §6.
    static let capturedTitle = "// MEASUREMENT SAVED"

    /// Title for `measurement_pending_sync`. Spec §6.
    static let pendingSyncTitle = "// SYNC QUEUED"

    /// Title for `measurement_sync_failed`. Spec §6.
    static let syncFailedTitle = "// ERROR — SYNC FAILED"

    /// Action label on the captured / queued cards (`VIEW`).
    static let viewLabel = "VIEW"

    /// Action label on the failed card (`RETRY`).
    static let retryLabel = "RETRY"

    // MARK: - Body formatters

    /// Body for `measurement_captured`. Picks the appropriate format based on
    /// the leading measurement's opening type.
    ///
    /// Window / door:   `[PROJECT] · 36″×60″ WINDOW · SILL 28″`
    /// Wall section:    `[PROJECT] · WALL SECTION · 14′6″ × 8′`
    static func capturedBody(
        projectName: String,
        summary: CapturedBodySummary
    ) -> String {
        let projectToken = projectName.uppercased()
        switch summary {
        case let .opening(widthInches, heightInches, openingType, sillInches):
            let widthStr = inchValueString(widthInches)
            let heightStr = inchValueString(heightInches)
            let typeStr = openingType.displayName
            let sillStr = inchValueString(sillInches)
            return "\(projectToken) · \(widthStr)″×\(heightStr)″ \(typeStr) · SILL \(sillStr)″"
        case let .wallSection(widthFeet, widthInches, heightFeet):
            let widthDimension = formatFeetInches(feet: widthFeet, inches: widthInches)
            let heightDimension = "\(heightFeet)′"
            return "\(projectToken) · WALL SECTION · \(widthDimension) × \(heightDimension)"
        }
    }

    /// Body for `measurement_pending_sync`. Singular vs plural matches spec
    /// verbatim — `1 MEASUREMENT` and `N MEASUREMENTS`, no comma in count.
    static func pendingSyncBody(count: Int) -> String {
        let noun = count == 1 ? "MEASUREMENT" : "MEASUREMENTS"
        return "\(count) \(noun) · WILL UPLOAD ON SIGNAL"
    }

    /// Body for `measurement_sync_failed`. Project name uppercased.
    static func syncFailedBody(projectName: String) -> String {
        let projectToken = projectName.uppercased()
        return "\(projectToken) · MEASUREMENT NOT UPLOADED · RETRY"
    }

    // MARK: - Number formatting helpers

    /// Format an inch value as integer when whole, otherwise keep up to one
    /// fractional digit. Numbers are JetBrains Mono in the UI but the body
    /// string is plain text — typography is applied by the rail.
    static func inchValueString(_ inches: Int) -> String {
        return String(inches)
    }

    /// `14′6″` — feet + inches joined with primes. If `inches` is 0, drop the
    /// trailing `0″` and emit `14′`. Spec example `14′6″ × 8′`.
    static func formatFeetInches(feet: Int, inches: Int) -> String {
        if inches == 0 { return "\(feet)′" }
        return "\(feet)′\(inches)″"
    }
}

extension MeasurementNotificationCopy {

    /// Closed enum of body shapes for the `captured` notification. The two
    /// cases match the two examples in spec §6 — window/door and wall section.
    enum CapturedBodySummary: Equatable {
        case opening(widthInches: Int, heightInches: Int, type: OpeningType, sillInches: Int)
        case wallSection(widthFeet: Int, widthInches: Int, heightFeet: Int)

        enum OpeningType: String {
            case window
            case door

            var displayName: String {
                switch self {
                case .window: return "WINDOW"
                case .door:   return "DOOR"
                }
            }
        }
    }
}

// MARK: - DTO factories

extension NotificationRepository.CreateNotificationDTO {

    /// Build the `measurement_captured` insert payload.
    static func measurementCaptured(
        userId: String,
        companyId: String,
        projectId: String,
        projectName: String,
        summary: MeasurementNotificationCopy.CapturedBodySummary,
        photoAnnotationId: String
    ) -> NotificationRepository.CreateNotificationDTO {
        NotificationRepository.CreateNotificationDTO(
            userId: userId,
            companyId: companyId,
            type: MeasurementNotificationType.captured,
            title: MeasurementNotificationCopy.capturedTitle,
            body: MeasurementNotificationCopy.capturedBody(
                projectName: projectName,
                summary: summary
            ),
            projectId: projectId,
            deepLinkType: "projectDetails",
            persistent: false,
            actionUrl: "ops://project/\(projectId)/photos/\(photoAnnotationId)",
            actionLabel: MeasurementNotificationCopy.viewLabel
        )
    }

    /// Build the `measurement_pending_sync` insert payload. Marked persistent
    /// — the rail keeps the banner up until the queue drains, then the iOS
    /// side calls `markAllAsReadByType(...)` to auto-clear.
    static func measurementPendingSync(
        userId: String,
        companyId: String,
        projectId: String?,
        queueDepth: Int
    ) -> NotificationRepository.CreateNotificationDTO {
        NotificationRepository.CreateNotificationDTO(
            userId: userId,
            companyId: companyId,
            type: MeasurementNotificationType.pendingSync,
            title: MeasurementNotificationCopy.pendingSyncTitle,
            body: MeasurementNotificationCopy.pendingSyncBody(count: queueDepth),
            projectId: projectId,
            deepLinkType: nil,
            persistent: true,
            actionUrl: nil,
            actionLabel: nil
        )
    }

    /// Build the `measurement_sync_failed` insert payload.
    static func measurementSyncFailed(
        userId: String,
        companyId: String,
        projectId: String,
        projectName: String,
        photoAnnotationId: String
    ) -> NotificationRepository.CreateNotificationDTO {
        NotificationRepository.CreateNotificationDTO(
            userId: userId,
            companyId: companyId,
            type: MeasurementNotificationType.syncFailed,
            title: MeasurementNotificationCopy.syncFailedTitle,
            body: MeasurementNotificationCopy.syncFailedBody(projectName: projectName),
            projectId: projectId,
            deepLinkType: "projectDetails",
            persistent: false,
            actionUrl: "ops://project/\(projectId)/photos/\(photoAnnotationId)?retry=1",
            actionLabel: MeasurementNotificationCopy.retryLabel
        )
    }
}

// MARK: - Feature flag slug

enum MeasurementFlag {
    /// Slug for the LiDAR Dimensioned Photo Capture rollout flag.
    /// Matches `feature_flags.slug` on Supabase verbatim (spec §10.3).
    static let dimensionedCapture = "feature.measurement.dimensioned_capture"
}
