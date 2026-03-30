//
//  ProjectQuickActionsBar.swift
//  OPS
//
//  Floating horizontal action bar for project details.
//  Single material pill containing compact icon+label buttons.
//

import SwiftUI

struct ProjectQuickActionsBar: View {
    let selectedTask: ProjectTask?
    let hasClientContact: Bool
    let canEdit: Bool
    let onPhoto: () -> Void
    let onNote: () -> Void
    let onExpense: () -> Void
    let onComplete: () -> Void
    let onReschedule: () -> Void
    let onContact: () -> Void
    let onAddTask: () -> Void

    /// Builds the list of actions based on current context
    private var actions: [ActionItem] {
        var items: [ActionItem] = [
            ActionItem(icon: "camera.fill", label: "PHOTO", action: onPhoto),
            ActionItem(icon: "note.text", label: "NOTE", action: onNote),
            ActionItem(icon: "doc.text.viewfinder", label: "EXPENSE", action: onExpense),
        ]

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

        return items
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            OPSActionBar {
                HStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                        OPSActionBarButton(
                            icon: item.icon,
                            label: item.label,
                            action: item.action
                        )
                        .frame(minWidth: 64)
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
}

// MARK: - Action Item

/// Lightweight struct to build the action list dynamically
private struct ActionItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let action: () -> Void
}
