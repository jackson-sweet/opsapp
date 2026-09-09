//
//  AssignTaskSheet.swift
//  OPS
//
//  Bug a290934f — point a photo at the task it documents, from the viewer.
//
//  The person here is looking at ONE photo and already knows which task it is
//  of. So there is nothing to configure and nothing to confirm: the list is the
//  project's tasks, a tap commits, and the sheet goes away. No Save button —
//  a second tap to confirm a single-choice list is a tax, and the choice is
//  reversible from the same place.
//

import SwiftUI

/// Whether the viewer may offer the TASK action at all.
///
/// Two conditions, and both are about honesty rather than taste:
///
///  * `projects.edit` at scope `all` — the same gate the VISIBLE action uses,
///    and the same rule `project_photos_write_guard` enforces for a non-uploader.
///  * a synced row for this url — the link lives on `project_photos`. A gallery
///    url with no row is a legacy `projects.project_images` CSV entry, and there
///    is nothing on the server to write the link to.
///
/// The uploader half of the server rule is deliberately included: a crew member
/// may always tag their OWN photo, exactly as they may always delete it.
enum AssignTaskAvailability {
    static func canAssign(
        hasSyncedRow: Bool,
        hasProjectTasks: Bool,
        uploader: ProjectPhotoUploaderAttribution,
        currentUserID: String?,
        hasFullProjectEdit: Bool
    ) -> Bool {
        guard hasSyncedRow, hasProjectTasks else { return false }
        if hasFullProjectEdit { return true }
        guard case .known(let uploaderID) = uploader, let currentUserID else { return false }
        return uploaderID == currentUserID
    }
}

struct AssignTaskSheet: View {
    let tasks: [ProjectPhotoTask]
    let selectedTaskID: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .background(OPSStyle.Colors.cardBorder)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(tasks) { task in
                        row(
                            badge: AnyView(
                                TaskBadge(
                                    name: task.title,
                                    color: task.color,
                                    size: .medium,
                                    faded: task.isTerminal
                                )
                            ),
                            chip: task.statusChip,
                            chipColor: task.status.color,
                            isSelected: task.id == selectedTaskID,
                            label: task.title,
                            isLast: false
                        ) {
                            commit(task.id)
                        }
                    }

                    // The absence chip, in the column's own language. A louder
                    // treatment would make "no task" read as the loudest choice
                    // on a screen where every other row is a quiet chip.
                    row(
                        badge: AnyView(
                            StatusBadgePill(
                                text: "NONE",
                                color: OPSStyle.Colors.secondaryText,
                                size: .medium
                            )
                        ),
                        chip: nil,
                        chipColor: nil,
                        isSelected: selectedTaskID == nil,
                        label: "None",
                        isLast: true
                    ) {
                        commit(nil)
                    }
                }
            }
        }
        .background(OPSStyle.Colors.background)
    }

    private var header: some View {
        Text("ASSIGN TO TASK")
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing3)
    }

    @ViewBuilder
    private func row(
        badge: AnyView,
        chip: String?,
        chipColor: Color?,
        isSelected: Bool,
        label: String,
        isLast: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                badge

                if let chip, let chipColor {
                    StatusBadgePill(text: chip, color: chipColor, size: .small)
                }

                Spacer(minLength: 0)

                // The checkmark, not colour, is what says "this one" — colour
                // here already means "which task".
                Image(systemName: OPSStyle.Icons.checkmark)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)

        // Separators sit BETWEEN rows. A hairline under the last one, with
        // empty sheet below it, reads as a list that was cut off.
        if !isLast {
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: OPSStyle.Layout.Border.standard)
                .padding(.leading, OPSStyle.Layout.spacing3)
        }
    }

    private func commit(_ taskID: String?) {
        // Medium impact on commit — the decision landed, and the sheet is about
        // to leave, so the confirmation has to be felt rather than read.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onSelect(taskID)
        dismiss()
    }
}
