//
//  VinylOrderFilter.swift
//  OPS
//
//  Job Board "vinyl procurement" filter (bug c6e90385): surface the projects
//  that carry a vinyl task, show each one's ordered state, and let the operator
//  mark vinyl ordered in one tap — reusing the synced projects.vinyl_order_*
//  marker the Vinyl Order sheet already writes. No new schema.
//

import SwiftData
import SwiftUI

/// Pure detection logic, kept free of SwiftData so it is unit-testable.
enum VinylTaskFilter {
    /// Task-type ids whose display name reads as vinyl work. Substring match so
    /// "Vinyl", "Vinyl Install", "Vinyl Membrane" all qualify. Case-insensitive.
    static func vinylTaskTypeIds(displaysById: [String: String]) -> Set<String> {
        Set(
            displaysById
                .filter { $0.value.lowercased().contains("vinyl") }
                .map(\.key)
        )
    }

    /// A project carries vinyl work when any of its live (non-deleted) tasks is a
    /// vinyl-type task.
    static func hasVinylTask(taskTypeIds: [String], vinylTaskTypeIds: Set<String>) -> Bool {
        guard !vinylTaskTypeIds.isEmpty else { return false }
        return taskTypeIds.contains { vinylTaskTypeIds.contains($0) }
    }
}

/// Per-card vinyl status + one-tap "mark ordered". Rendered under a project card
/// only while the vinyl filter is active — vinyl procurement is a mode, so the
/// strip never clutters the normal board.
struct VinylOrderStrip: View {
    let project: Project
    let marker: ProjectVinylOrderMarker?
    /// Whether the operator may change ordered state. Gated on projects.edit —
    /// crew without edit rights see the status read-only.
    let canMark: Bool
    let blocker: String?
    let onMarkOrdered: () -> Void

    private var isOrdered: Bool { marker?.status == .ordered }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Circle()
                    .fill(isOrdered ? OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus)
                    .frame(
                        width: OPSStyle.Layout.spacing2,
                        height: OPSStyle.Layout.spacing2
                    )

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("VINYL")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .tracking(0.8)
                    Text(statusLabel)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(isOrdered ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryText)
                }

                Spacer(minLength: 0)

                if isOrdered {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.successStatus)
                } else if canMark {
                    Button(action: onMarkOrdered) {
                        Text("MARK ORDERED")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                            .background(OPSStyle.Colors.surfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let blocker {
                Text(blocker)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .tracking(0.8)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var statusLabel: String {
        guard isOrdered else { return "NOT ORDERED" }
        if let orderedAt = marker?.orderedAt {
            return "ORDERED \(DateHelper.simpleDateString(from: orderedAt).uppercased())"
        }
        return "ORDERED"
    }
}
