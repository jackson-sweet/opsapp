//
//  AppMessageGate.swift
//  OPS
//
//  Pure decision logic for the Update Gate. Given the active messages, the
//  installed version, the platform, the current time, the user's role, and
//  (optionally) the live App Store version, it decides which single message —
//  if any — should block the app, and which should appear as a dismissable
//  overlay. No network, no UI, no globals: fully unit-testable.
//
//  Version targeting is a half-open range [minimum_version, maximum_version):
//  a message applies to installs with version >= minimum_version AND
//  < maximum_version (either bound may be null). A force-update for "everyone
//  below the fix 3.1.0" sets maximum_version = 3.1.0 — the wall self-resolves
//  the instant a user updates past it.
//

import Foundation

enum AppMessageGate {

    /// Component-wise numeric version comparison. Missing trailing components
    /// are treated as zero, so "3.1" == "3.1.0" and "3.10.0" > "3.9.0"
    /// (a plain string compare would get the double-digit case wrong).
    static func semVerCompare(_ a: String, _ b: String) -> ComparisonResult {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhs.count, rhs.count)
        for i in 0..<count {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    /// Tolerant ISO-8601 parse for Supabase timestamptz values (with or without
    /// fractional seconds). Returns nil for nil/empty/unparseable input.
    static func parseTimestamp(_ string: String?) -> Date? {
        guard let string = string, !string.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// Whether a single message targets the given install/context. Excludes on
    /// platform mismatch, schedule window, version range, and role targeting.
    /// Role is only enforced when known — pre-auth (role == nil) a targeted
    /// message still applies, so a blocking wall is never let through for a
    /// user we can't classify yet.
    static func applies(
        _ message: AppMessageDTO,
        installedVersion: String,
        platform: String,
        now: Date,
        userRole: UserRole?
    ) -> Bool {
        // Platform
        if let p = message.platform, !p.isEmpty,
           p.lowercased() != platform.lowercased() {
            return false
        }

        // Schedule window
        if let start = parseTimestamp(message.startDate), now < start { return false }
        if let end = parseTimestamp(message.endDate), now >= end { return false }

        // Version range [min, max): applies if installed >= min and < max.
        if let minV = message.minimumVersion, !minV.isEmpty,
           semVerCompare(installedVersion, minV) == .orderedAscending {
            return false
        }
        if let maxV = message.maximumVersion, !maxV.isEmpty,
           semVerCompare(installedVersion, maxV) != .orderedAscending {
            return false
        }

        // Role targeting (only when the role is known)
        if let role = userRole,
           let targets = message.targetUserTypes, !targets.isEmpty,
           !targets.contains(role.rawValue) {
            return false
        }

        return true
    }

    struct Resolution {
        let blocking: AppMessageDTO?
        let dismissable: AppMessageDTO?
    }

    /// Resolves the applicable messages into at most one blocking message and
    /// at most one dismissable message. A blocking (non-dismissable) message
    /// always takes the whole screen and suppresses any dismissable one. When
    /// nothing is published but the App Store has a newer build, a synthetic
    /// dismissable "update available" nudge is offered.
    static func resolve(
        messages: [AppMessageDTO],
        installedVersion: String,
        platform: String,
        now: Date,
        userRole: UserRole?,
        storeVersion: String?,
        appStoreURL: String?
    ) -> Resolution {
        let applicable = messages
            .filter { applies($0, installedVersion: installedVersion, platform: platform, now: now, userRole: userRole) }
            .sorted { lhs, rhs in
                let lp = priority(lhs.messageType)
                let rp = priority(rhs.messageType)
                if lp != rp { return lp > rp }
                let lc = parseTimestamp(lhs.createdAt) ?? .distantPast
                let rc = parseTimestamp(rhs.createdAt) ?? .distantPast
                return lc > rc
            }

        if let blocking = applicable.first(where: { !($0.dismissable ?? true) }) {
            return Resolution(blocking: blocking, dismissable: nil)
        }

        if let dismissable = applicable.first(where: { $0.dismissable ?? true }) {
            return Resolution(blocking: nil, dismissable: dismissable)
        }

        // No published message applies — auto-nudge if a newer build exists.
        if let store = storeVersion, !store.isEmpty,
           semVerCompare(installedVersion, store) == .orderedAscending {
            return Resolution(blocking: nil, dismissable: .updateNudge(appStoreURL: appStoreURL))
        }

        return Resolution(blocking: nil, dismissable: nil)
    }

    private static func priority(_ messageType: String?) -> Int {
        guard let raw = messageType, let type = AppMessageType(rawValue: raw) else {
            return AppMessageType.info.priority
        }
        return type.priority
    }
}

// MARK: - Synthetic update nudge

extension AppMessageDTO {
    /// App-generated "update available" nudge shown when the App Store has a
    /// newer build than the install and no admin message covers it.
    static func updateNudge(appStoreURL: String?) -> AppMessageDTO {
        AppMessageDTO(
            id: "auto_update_nudge",
            active: true,
            title: "New version ready",
            body: "A newer version of OPS is on the App Store. Update for the latest fixes.",
            messageType: AppMessageType.optionalUpdate.rawValue,
            dismissable: true,
            targetUserTypes: nil,
            appStoreUrl: appStoreURL,
            createdAt: nil,
            minimumVersion: nil,
            maximumVersion: nil,
            platform: "ios",
            startDate: nil,
            endDate: nil
        )
    }
}
