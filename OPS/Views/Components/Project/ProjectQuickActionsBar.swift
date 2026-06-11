//
//  ProjectQuickActionsBar.swift
//  OPS
//
//  Floating horizontal action bar for project details.
//  Single material pill containing compact icon+label buttons.
//

import SwiftUI

enum ProjectQuickActionPermissionGate {
    static func canShowDeckAction(
        featureEnabled: Bool,
        canCreate: Bool,
        canEdit: Bool
    ) -> Bool {
        featureEnabled && (canCreate || canEdit)
    }
}

struct ProjectQuickActionsBar: View {
    let selectedTask: ProjectTask?
    let hasClientContact: Bool
    let canEdit: Bool
    /// Bug G9 — when true, the user got here via a note mention and should
    /// only be able to post reply notes. All other actions are hidden.
    var isMentionOnly: Bool = false
    let onPhoto: () -> Void
    let onNote: () -> Void
    let onExpense: () -> Void
    let onComplete: () -> Void
    let onReschedule: () -> Void
    let onContact: () -> Void
    let onAddTask: () -> Void
    var onDeckDesign: (() -> Void)? = nil
    /// LiDAR Dimensioned Photo Capture entry (spec §3.1). Optional so the
    /// parent can gate it on `feature.measurement.dimensioned_capture` flag
    /// AND device capability (`CaptureCapability != .noDepth`). Hidden when
    /// nil. Spec: ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.1
    var onMeasure: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    /// Bug 1b7e59f7 — in-app equivalent of the requested Photos → OPS share
    /// extension flow. Tapping opens the Photos library picker for this
    /// project so the user can attach existing library photos without
    /// going through the camera first. The full Share Extension target
    /// requires project.pbxproj edits which are out of scope for this
    /// agent sweep; this covers the core "attach photo from library to
    /// project" user need.
    var onPhotoLibrary: (() -> Void)? = nil
    var allTasksComplete: Bool = false
    var projectIsActive: Bool = true
    var onCompleteProject: (() -> Void)? = nil

    /// Builds the list of actions based on current context
    private var actions: [ActionItem] {
        // Bug G9 — mention-only users: reply-note only.
        if isMentionOnly {
            return [ActionItem(icon: "note.text", label: "NOTE", action: onNote)]
        }

        var items: [ActionItem] = []

        // COMPLETE PROJECT — front of bar, double width, when all tasks are done.
        // Flagged as emphasized so it renders with a bordered success-accent
        // treatment to stand apart from the monochrome quick actions.
        if allTasksComplete && projectIsActive, let onCompleteProject = onCompleteProject {
            items.append(ActionItem(
                icon: "flag.checkered.circle.fill",
                label: "COMPLETE PROJECT",
                isWide: true,
                isEmphasized: true,
                action: onCompleteProject
            ))
        }

        items.append(contentsOf: [
            ActionItem(icon: "camera.fill", label: "PHOTO", action: onPhoto),
        ])

        // Bug 1b7e59f7 — library import button. Shown immediately after
        // the camera capture action so the two photo paths (capture vs
        // attach from library) sit side-by-side.
        if let onPhotoLibrary = onPhotoLibrary {
            items.append(ActionItem(icon: "photo.on.rectangle.angled", label: "LIBRARY", action: onPhotoLibrary))
        }

        items.append(contentsOf: [
            ActionItem(icon: "note.text", label: "NOTE", action: onNote),
            ActionItem(icon: "doc.text.viewfinder", label: "EXPENSE", action: onExpense),
        ])

        if let onDeckDesign = onDeckDesign {
            items.append(ActionItem(icon: "ruler.fill", label: "DECK", action: onDeckDesign))
        }

        // LiDAR Dimensioned Photo Capture — sits next to DECK since both are
        // measurement-related. Parent gates on flag + capability.
        if let onMeasure = onMeasure {
            items.append(ActionItem(icon: "ruler", label: "MEASURE", action: onMeasure))
        }

        if let task = selectedTask {
            let isCompleted = task.status == .completed
            items.append(ActionItem(
                icon: isCompleted ? "arrow.uturn.backward" : "checkmark.circle.fill",
                label: isCompleted ? "REOPEN" : "COMPLETE",
                action: onComplete
            ))
            items.append(ActionItem(
                icon: "calendar",
                label: "RESCHEDULE",
                action: onReschedule
            ))
        }

        if hasClientContact {
            items.append(ActionItem(icon: "phone.fill", label: "CONTACT", action: onContact))
        }

        if canEdit {
            items.append(ActionItem(icon: "plus", label: "TASK", action: onAddTask))
        }

        if let onShare = onShare {
            items.append(ActionItem(icon: "square.and.arrow.up", label: "SHARE", action: onShare))
        }

        return items
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            OPSActionBar {
                HStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                        Group {
                            if item.isEmphasized {
                                emphasizedActionButton(for: item)
                            } else {
                                OPSActionBarButton(
                                    icon: item.icon,
                                    label: item.label,
                                    action: item.action
                                )
                                .frame(minWidth: item.isWide ? 128 : 64)
                            }
                        }
                        .if(item.label == "PHOTO") { view in
                            view.wizardTarget("capture_photo")
                        }

                        // Spacer + divider + spacer — matches the 16pt container edge padding
                        if index < actions.count - 1 {
                            Spacer().frame(width: 16)
                            Rectangle()
                                .fill(OPSStyle.Colors.cardBorderSubtle)
                                .frame(width: 1, height: 32)
                            Spacer().frame(width: 16)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Primary-CTA rendering for emphasized actions (e.g. COMPLETE PROJECT).
    /// Distinct from the monochrome quick actions: success-accent icon and
    /// label inside a bordered pill so the finish-the-project action reads
    /// as the obvious next move without competing with the other buttons.
    private func emphasizedActionButton(for item: ActionItem) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            item.action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.successStatus)

                Text(item.label.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.8)
                    .foregroundColor(OPSStyle.Colors.successStatus)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.successStatus.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.successStatus, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(EmphasizedButtonStyle())
    }
}

private struct EmphasizedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Action Item

/// Lightweight struct to build the action list dynamically
private struct ActionItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    var isWide: Bool = false
    /// Renders with a bordered success-accent treatment instead of the
    /// default monochrome OPSActionBarButton. Used for the primary CTA
    /// (e.g. COMPLETE PROJECT) so it reads as the clear next step.
    var isEmphasized: Bool = false
    let action: () -> Void
}
