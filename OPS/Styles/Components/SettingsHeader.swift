//
//  SettingsHeader.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-14.
//

import SwiftUI
import UIKit

/// A reusable header component for consistent styling in settings views
/// NOTE: This is commented out because it conflicts with the existing SettingsHeader defined elsewhere
/// See /OPS/Views/Settings/Components/SettingsComponents.swift
/*
struct SettingsHeader: View {
    var title: String
    var showEditButton: Bool = false
    var isEditing: Bool = false
    var onBackTapped: () -> Void
    var onEditTapped: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            // Back button with consistent styling
            Button(action: {
                onBackTapped()
            }) {
                Image(systemName: "chevron.left")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(12)
            
            // Title with consistent styling - left aligned
            Text(title.uppercased())
                .font(OPSStyle.Typography.title)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
            
            // Edit button or spacer for balance
            if showEditButton {
                Button(action: {
                    onEditTapped?()
                }) {
                    Text(isEditing ? "CANCEL" : "EDIT")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .frame(width: 80, height: 44)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .cornerRadius(12)
            } else {
                // Empty spacer to balance the header
                Spacer()
                    .frame(width: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
*/

// All preview code removed - use the original SettingsHeader from Settings/Components/SettingsComponents.swift instead