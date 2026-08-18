//
//  TaskTypeSelectionPolicy.swift
//  OPS
//
//  Shared eligibility rules for user-facing task type choices.
//

import Foundation

enum TaskTypeSelectionPolicy {
    /// Returns task types that may be offered as a new user choice.
    ///
    /// Soft-deleted rows remain in the local cache so sync and historical
    /// references can resolve them, but they must never appear in a picker or
    /// filter. Callers may omit `companyId` when their input is already scoped.
    /// Input order is preserved so each surface can retain its own sort policy.
    static func selectableTaskTypes(
        from taskTypes: [TaskType],
        companyId: String? = nil
    ) -> [TaskType] {
        taskTypes.filter { taskType in
            guard taskType.deletedAt == nil else { return false }
            guard let companyId else { return true }
            return taskType.companyId == companyId
        }
    }

    // MARK: - Display order

    /// The picker order for task types: like colours cluster. Bug bc9c2e83.
    ///
    /// A task type is recognised by its colour chip long before its name is
    /// read, so every list of choices walks the spectrum from red, grouping
    /// chips into 30° colour families; greys and anything unreadable land at
    /// the end. Inside a family the exact hue leads, then the brighter chip,
    /// then the richer one, and finally the name — so two types sharing one
    /// colour always sit together in a stable alphabetical run.
    static func colorOrdered(_ taskTypes: [TaskType]) -> [TaskType] {
        taskTypes
            .map { (colorSortKey($0.color), $0) }
            .sorted { left, right in
                let leftKey = left.0
                let rightKey = right.0
                if leftKey.family != rightKey.family { return leftKey.family < rightKey.family }
                if leftKey.hue != rightKey.hue { return leftKey.hue < rightKey.hue }
                if leftKey.brightness != rightKey.brightness {
                    return leftKey.brightness > rightKey.brightness
                }
                if leftKey.saturation != rightKey.saturation {
                    return leftKey.saturation > rightKey.saturation
                }
                return left.1.display.localizedCaseInsensitiveCompare(right.1.display)
                    == .orderedAscending
            }
            .map { $0.1 }
    }

    /// Where one chip sits in the spectrum walk.
    private struct ColorSortKey {
        let family: Int
        let hue: Double
        let brightness: Double
        let saturation: Double
    }

    /// Width of a colour family, in degrees of hue.
    private static let colorFamilyWidth: Double = 30
    /// Families 0…11 are chromatic; 12 collects the greys.
    private static let neutralColorFamily = 12
    /// Below this saturation a chip reads as grey, not as its hue.
    private static let neutralSaturationCeiling: Double = 0.12

    private static func colorSortKey(_ hex: String) -> ColorSortKey {
        guard let rgb = rgbComponents(hex) else {
            return ColorSortKey(family: neutralColorFamily, hue: 0, brightness: 0, saturation: 0)
        }

        let highest = max(rgb.red, rgb.green, rgb.blue)
        let lowest = min(rgb.red, rgb.green, rgb.blue)
        let delta = highest - lowest
        let saturation = highest == 0 ? 0 : delta / highest

        var hue: Double = 0
        if delta > 0 {
            if highest == rgb.red {
                hue = 60 * ((rgb.green - rgb.blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if highest == rgb.green {
                hue = 60 * (((rgb.blue - rgb.red) / delta) + 2)
            } else {
                hue = 60 * (((rgb.red - rgb.green) / delta) + 4)
            }
            if hue < 0 { hue += 360 }
        }

        guard saturation >= neutralSaturationCeiling else {
            return ColorSortKey(
                family: neutralColorFamily,
                hue: 0,
                brightness: highest,
                saturation: saturation
            )
        }

        let family = min(Int(hue / colorFamilyWidth), neutralColorFamily - 1)
        return ColorSortKey(
            family: family,
            hue: hue,
            brightness: highest,
            saturation: saturation
        )
    }

    /// Parse "#RRGGBB" / "RRGGBB" / "#RRGGBBAA" into 0…1 components. Alpha is
    /// dropped — it never changes which colour a chip reads as.
    private static func rgbComponents(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        let sanitized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6 || sanitized.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: sanitized).scanHexInt64(&value) else { return nil }
        if sanitized.count == 8 { value >>= 8 }

        return (
            red: Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8) / 255.0,
            blue: Double(value & 0x0000FF) / 255.0
        )
    }

    /// Removes selections that are no longer present in the selectable set.
    static func sanitizedSelection(
        _ selection: Set<String>,
        from taskTypes: [TaskType],
        companyId: String? = nil
    ) -> Set<String> {
        let selectableIds = Set(
            selectableTaskTypes(from: taskTypes, companyId: companyId).map(\.id)
        )
        return selection.intersection(selectableIds)
    }

    /// Resolves a task type that may be persisted on a task row.
    ///
    /// Active same-company types are always valid. A soft-deleted type is only
    /// valid when it is the unchanged original value of an existing task,
    /// preserving historical rows without allowing a tombstone to become a
    /// new or changed selection.
    static func persistableTaskType(
        id: String,
        originalTaskTypeId: String? = nil,
        from taskTypes: [TaskType],
        companyId: String
    ) -> TaskType? {
        if let selectable = selectableTaskTypes(
            from: taskTypes,
            companyId: companyId
        ).first(where: { $0.id == id }) {
            return selectable
        }

        guard originalTaskTypeId == id else { return nil }
        return taskTypes.first {
            $0.id == id && $0.companyId == companyId
        }
    }
}
