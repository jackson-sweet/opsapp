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
        OPSActionBar {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                OPSActionBarButton(icon: OPSStyle.Icons.mention, label: "@", action: onMention)
                OPSActionBarButton(icon: "camera.fill", label: "PHOTO", action: onPhoto)

                // POST button — accent when content available, disabled otherwise
                OPSActionBarButton(
                    icon: "arrow.up.circle.fill",
                    label: "POST",
                    iconColor: canPost ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText,
                    labelColor: canPost ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText,
                    isDisabled: !canPost,
                    action: onPost
                )
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }
}
