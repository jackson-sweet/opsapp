//
//  OPSComponents.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-14.
//

import SwiftUI

/// This file serves as a central import point for all OPS UI components
/// Import this single file to access all standardized UI components for the app

// This file serves as documentation for the components system
// Direct implementations are preferred over typealias/imports

/* Component Organization:
 
LAYOUT COMPONENTS:
- CategoryCard (CategoryCard.swift) - For consistent settings UI
- OrganizationProfileCard (CategoryCard.swift) - For organization profile display
- UserProfileCard (ProfileCard.swift) - For user profile display
- SettingsHeader (SettingsHeader.swift) - For settings view headers
- SettingsSectionHeader (SettingsComponents.swift) - For section headers in settings

CARD COMPONENTS:
- OPSCard (CardStyles.swift) - Standard card container
- OPSElevatedCard (CardStyles.swift) - Card with elevation and shadow
- OPSInteractiveCard (CardStyles.swift) - Tappable interactive card
- OPSAccentCard (CardStyles.swift) - Card with accent-colored border
- OPSCardStyle (CardStyles.swift) - Card style modifiers for custom layouts

FORM COMPONENTS:
- FormField (FormInputs.swift) - Text input with label
- FormTextEditor (FormInputs.swift) - Multi-line text input
- FormToggle (FormInputs.swift) - Toggle switch with label
- RadioOption (FormInputs.swift) - Radio button style option
- SearchBar (FormInputs.swift) - Search input field
- EmptyStateView (FormInputs.swift) - Empty state messaging

BUTTON COMPONENTS:
- OPSPrimaryButton (ButtonStyles.swift) - Standardized primary action button
- OPSSecondaryButton (ButtonStyles.swift) - Outlined secondary action button
- OPSDestructiveButton (ButtonStyles.swift) - Danger/destructive action button
- OPSIconButton (ButtonStyles.swift) - Circular icon button
- OPSButtonStyle (ButtonStyles.swift) - Button style modifiers for custom buttons

UTILITY COMPONENTS:
- IconBadge (IconBadge.swift) - Icon with background styling
- ListItem (ListItems.swift) - Standard list item row
- StatusBadge (StatusBadge.swift) - Standardized status indicators

TYPOGRAPHY:
- Font extensions (../Fonts.swift) - Standardized typography system
*/

// Export buttons and other components from existing files
// Note: We're keeping the originals to avoid breaking existing code,
// but future code should use these prefixed versions for consistency

/// Standard primary action button
public struct OPSPrimaryButton: View {
    var title: String
    var icon: String = ""
    var action: () -> Void
    var isDisabled: Bool = false
    
    public var body: some View {
        Button(action: action) {
            HStack {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(OPSStyle.Typography.body)
                }
                
                Text(title)
                    .font(OPSStyle.Typography.button)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isDisabled ? OPSStyle.Colors.primaryAccent.opacity(0.5) : OPSStyle.Colors.primaryAccent)
            .cornerRadius(12)
        }
        .disabled(isDisabled)
    }
}

/// Standard secondary action button
public struct OPSSecondaryButton: View {
    var title: String
    var icon: String = ""
    var action: () -> Void
    
    public var body: some View {
        Button(action: action) {
            HStack {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(OPSStyle.Typography.body)
                }
                
                Text(title)
                    .font(OPSStyle.Typography.button)
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
            )
        }
    }
}

/// Standard destructive action button
public struct OPSDestructiveButton: View {
    var title: String
    var icon: String = ""
    var action: () -> Void
    
    public var body: some View {
        Button(action: action) {
            HStack {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(OPSStyle.Typography.body)
                }
                
                Text(title)
                    .font(OPSStyle.Typography.button)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(OPSStyle.Colors.errorStatus)
            .cornerRadius(12)
        }
    }
}