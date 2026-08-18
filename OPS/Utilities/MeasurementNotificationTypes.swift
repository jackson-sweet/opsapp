//
//  MeasurementNotificationTypes.swift
//  OPS
//
//  Rail type constants + the RPC argument carrier for the three LiDAR
//  Dimensioned Photo Capture notifications.
//
//  Copy is NOT rendered here any more. The 2026-07-15 notification-creation
//  hardening revoked app-role INSERT on `public.notifications`, so every rail
//  row is created by a narrow SECURITY DEFINER RPC that derives the actor from
//  the JWT, derives the project title from the project row, and interpolates
//  the client's validated integers into fixed server-held templates:
//
//    notify_measurement_captured           → `// MEASUREMENT SAVED`
//    sync_measurement_pending_notification → `// SYNC QUEUED` (depth 0 clears)
//    notify_measurement_sync_failed        → `// ERROR — SYNC FAILED`
//
//  The spec §6 strings are unchanged — they were relocated verbatim into
//  ops-software-bible/migrations/
//      20260818023254_ios_notification_surface_rpcs.sql
//      20260818023657_measurement_notification_dedupe_keys.sql
//  Assertions on those strings belong against the database, not against this
//  file. The client's remaining contract is the notification `type` strings
//  (the rail reads them) and the mapping from a derived capture summary onto
//  the RPC's argument set.
//
//  `LiveDimensionedNotificationDispatcher` in `DimensionedPhotoSyncManager.swift`
//  is the only caller.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §6
//

import Foundation

enum MeasurementNotificationType {
    /// `// MEASUREMENT SAVED` — server-rendered after a full successful
    /// 3-asset upload.
    static let captured = "measurement_captured"

    /// `// SYNC QUEUED` — server-rendered when the capture has been written
    /// locally but the network is unavailable. Persistent; the server clears
    /// it once the client reports a queue depth of zero.
    static let pendingSync = "measurement_pending_sync"

    /// `// ERROR — SYNC FAILED` — server-rendered after retries are exhausted.
    static let syncFailed = "measurement_sync_failed"
}

/// Argument set for `notify_measurement_captured`. Mirrors the RPC's parameter
/// list one-for-one: `opening` populates the opening fields and leaves the wall
/// fields nil; `wall_section` does the inverse. The server rejects (22023) a
/// kind whose required fields are missing, so the mapper below is the single
/// place that decides which half of the payload is populated.
struct MeasurementCapturedRPCArguments: Equatable {

    /// `p_kind` for a window/door opening — width, height, opening type and
    /// sill are all required server-side.
    static let openingKind = "opening"

    /// `p_kind` for a wall section — width feet/inches and height feet are all
    /// required server-side.
    static let wallSectionKind = "wall_section"

    let kind: String
    let widthInches: Int?
    let heightInches: Int?
    let openingType: String?
    let sillInches: Int?
    let wallWidthFeet: Int?
    let wallWidthInches: Int?
    let wallHeightFeet: Int?
}

/// Namespace for the payload types the measurement notifications carry. It is
/// named for the copy it used to render; the copy now lives server-side (see
/// the file header) and what remains is the summary the capture pipeline
/// derives plus the mapping onto the RPC arguments.
enum MeasurementNotificationCopy {

    /// Map a derived capture summary onto `notify_measurement_captured`'s
    /// argument set. The opening type's raw value (`window` / `door`) is the
    /// wire contract — the server validates `p_opening_type in ('window','door')`
    /// and uppercases it into the body itself.
    static func rpcArguments(
        for summary: CapturedBodySummary
    ) -> MeasurementCapturedRPCArguments {
        switch summary {
        case let .opening(widthInches, heightInches, type, sillInches):
            return MeasurementCapturedRPCArguments(
                kind: MeasurementCapturedRPCArguments.openingKind,
                widthInches: widthInches,
                heightInches: heightInches,
                openingType: type.rawValue,
                sillInches: sillInches,
                wallWidthFeet: nil,
                wallWidthInches: nil,
                wallHeightFeet: nil
            )
        case let .wallSection(widthFeet, widthInches, heightFeet):
            return MeasurementCapturedRPCArguments(
                kind: MeasurementCapturedRPCArguments.wallSectionKind,
                widthInches: nil,
                heightInches: nil,
                openingType: nil,
                sillInches: nil,
                wallWidthFeet: widthFeet,
                wallWidthInches: widthInches,
                wallHeightFeet: heightFeet
            )
        }
    }
}

extension MeasurementNotificationCopy {

    /// Closed enum of body shapes for the `captured` notification. The two
    /// cases match the two examples in spec §6 — window/door and wall section —
    /// and map onto the RPC's two `p_kind` values. Carried from
    /// `DimensionedPhotoSyncManager.capturedBodySummary(from:)` through the
    /// dispatcher to `rpcArguments(for:)`.
    enum CapturedBodySummary: Equatable {
        case opening(widthInches: Int, heightInches: Int, type: OpeningType, sillInches: Int)
        case wallSection(widthFeet: Int, widthInches: Int, heightFeet: Int)

        /// Raw values are the server's accepted `p_opening_type` set.
        enum OpeningType: String {
            case window
            case door
        }
    }
}

// MARK: - Feature flag slug

enum MeasurementFlag {
    /// Slug for the LiDAR Dimensioned Photo Capture rollout flag.
    /// Matches `feature_flags.slug` on Supabase verbatim (spec §10.3).
    static let dimensionedCapture = "feature.measurement.dimensioned_capture"
}
