//
//  StandardSheetToolbar.swift
//  OPS
//
//  Standardized sheet navigation bar with consistent styling
//

import SwiftUI

/// Standardized sheet toolbar modifier with Cancel/Title/Action buttons
///
/// Provides consistent styling and behavior for all sheet navigation bars.
/// Based on ProjectFormSheet authority pattern.
///
/// Usage:
/// ```swift
/// NavigationView {
///     content
/// }
/// .standardSheetToolbar(
///     title: "Create Project",
///     actionText: "Create",
///     isActionEnabled: isValid,
///     isSaving: isSaving,
///     onCancel: { dismiss() },
///     onAction: { saveProject() }
/// )
/// ```
struct StandardSheetToolbarModifier: ViewModifier {
    let title: String
    let cancelText: String
    let cancelColor: Color
    let actionText: String
    let actionColor: Color
    let isActionEnabled: Bool
    let isSaving: Bool
    let showProgressOnSave: Bool
    let onCancel: () -> Void
    let onAction: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(cancelText) {
                        onCancel()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(cancelColor)
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onAction) {
                        if isSaving && showProgressOnSave {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: actionColor))
                                .scaleEffect(0.8)
                        } else {
                            Text(actionText)
                                .font(OPSStyle.Typography.bodyBold)
                        }
                    }
                    .foregroundColor(isActionEnabled ? actionColor : OPSStyle.Colors.tertiaryText)
                    .disabled(!isActionEnabled || isSaving)
                }
            }
    }
}

extension View {
    /// Apply standardized sheet toolbar with Cancel/Title/Action buttons
    ///
    /// Matches ProjectFormSheet authority pattern:
    /// - Cancel: "CANCEL" (secondaryText), disabled when saving
    /// - Title: Center-aligned, primaryText
    /// - Action: primaryAccent when enabled, tertiaryText when disabled, shows progress when saving
    ///
    /// - Parameters:
    ///   - title: Sheet title (e.g., "Create Project", "Edit Task")
    ///   - cancelText: Cancel button text (default: "CANCEL")
    ///   - cancelColor: Cancel button color (default: secondaryText)
    ///   - actionText: Action button text (e.g., "CREATE", "SAVE", "DELETE")
    ///   - actionColor: Action button color when enabled (default: primaryAccent)
    ///   - isActionEnabled: Whether action button is enabled (default: true)
    ///   - isSaving: Whether a save operation is in progress (default: false)
    ///   - showProgressOnSave: Show ProgressView instead of text when saving (default: true)
    ///   - onCancel: Action to perform when cancel is tapped
    ///   - onAction: Action to perform when action button is tapped
    func standardSheetToolbar(
        title: String,
        cancelText: String = "CANCEL",
        cancelColor: Color = OPSStyle.Colors.secondaryText,
        actionText: String,
        actionColor: Color = OPSStyle.Colors.primaryAccent,
        isActionEnabled: Bool = true,
        isSaving: Bool = false,
        showProgressOnSave: Bool = true,
        onCancel: @escaping () -> Void,
        onAction: @escaping () -> Void
    ) -> some View {
        modifier(StandardSheetToolbarModifier(
            title: title.uppercased(),
            cancelText: cancelText.uppercased(),
            cancelColor: cancelColor,
            actionText: actionText.uppercased(),
            actionColor: actionColor,
            isActionEnabled: isActionEnabled,
            isSaving: isSaving,
            showProgressOnSave: showProgressOnSave,
            onCancel: onCancel,
            onAction: onAction
        ))
    }
}
