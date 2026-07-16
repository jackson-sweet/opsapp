//
//  PhoneContactRow.swift
//  OPS
//
//  Bug 388663d4 — one row for a device contact that isn't in OPS yet, shared
//  by the create-project client picker (text-only, to match its OPS rows) and
//  the change-client sheet (with an avatar, to match its rows). The "IN
//  CONTACTS" badge is the signal: unbadged rows are already OPS clients;
//  tapping a badged row creates the client in the background.
//

import SwiftUI

struct PhoneContactRow: View {
    let suggestion: PhoneContactSuggestion
    /// Show an initials avatar (change-client sheet) or not (create-form
    /// dropdown, whose OPS rows are text-only).
    var showsAvatar: Bool = false
    var isDisabled: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                if showsAvatar {
                    UserAvatar(firstName: suggestion.firstName, lastName: suggestion.lastName, size: 32)
                }

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(suggestion.displayName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    if let subtitle = suggestion.subtitle {
                        Text(subtitle)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: OPSStyle.Layout.spacing2)

                StatusBadgePill(
                    text: "IN CONTACTS",
                    color: OPSStyle.Colors.secondaryText,
                    size: .small
                )
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
        .accessibilityLabel("\(suggestion.displayName), from your phone contacts")
        .accessibilityHint("Adds this contact to OPS as a client.")
    }
}
