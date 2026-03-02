//
//  NoteComposeToolbar.swift
//  OPS
//
//  Floating toolbar that replaces ProjectQuickActionsBar when composing a note.
//  Contains: @ (mention), PHOTO (add to note), POST (submit note).
//

import SwiftUI

struct NoteComposeToolbar: View {
    let onMention: () -> Void
    let onPhoto: () -> Void
    let onPost: () -> Void
    let canPost: Bool

    var body: some View {
        HStack(spacing: 0) {
            toolbarItem(icon: OPSStyle.Icons.mention, label: "@", action: onMention)
            toolbarItem(icon: "camera.fill", label: "PHOTO", action: onPhoto)

            // POST button — highlighted when content available
            Button(action: onPost) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                        .foregroundColor(
                            canPost
                                ? OPSStyle.Colors.primaryAccent
                                : OPSStyle.Colors.tertiaryText
                        )
                    Text("POST")
                        .font(.custom("Kosugi-Regular", size: 10))
                        .tracking(0.3)
                        .foregroundColor(
                            canPost
                                ? OPSStyle.Colors.primaryAccent
                                : OPSStyle.Colors.tertiaryText
                        )
                }
                .frame(minWidth: OPSStyle.Layout.touchTargetStandard, minHeight: OPSStyle.Layout.touchTargetStandard)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canPost)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func toolbarItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.lg))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(label)
                    .font(.custom("Kosugi-Regular", size: 10))
                    .tracking(0.3)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetStandard, minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
