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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                actionItem(icon: "camera.fill", label: "PHOTO", action: onPhoto)
                actionItem(icon: "note.text", label: "NOTE", action: onNote)
                actionItem(icon: "doc.text.viewfinder", label: "EXPENSE", action: onExpense)

                if selectedTask != nil {
                    let isCompleted = selectedTask?.status == .completed
                    actionItem(
                        icon: isCompleted ? "arrow.uturn.backward" : "checkmark.circle.fill",
                        label: isCompleted ? "REOPEN" : "COMPLETE",
                        action: onComplete
                    )
                    actionItem(
                        icon: "calendar",
                        label: "RESCHEDULE",
                        action: onReschedule
                    )
                }

                if hasClientContact {
                    actionItem(icon: "phone.fill", label: "CONTACT", action: onContact)
                }

                if canEdit {
                    actionItem(icon: "plus", label: "TASK", action: onAddTask)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(Color.black.opacity(0.5))
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private func actionItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.xl))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(label)
                    .font(.custom("Kosugi-Regular", size: 11))
                    .tracking(0.3)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetLarge, minHeight: OPSStyle.Layout.touchTargetLarge)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
