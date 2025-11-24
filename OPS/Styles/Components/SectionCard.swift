//
//  SectionCard.swift
//  OPS
//
//  Base card component providing consistent styling for all sections throughout the app
//  Used in: detail views, settings, forms, anywhere content needs to be grouped
//

import SwiftUI

/// Base card component with consistent OPS styling
///
/// Provides standardized background, border, corner radius, and padding for all
/// content sections throughout the app. Can be used standalone or as a base for
/// other card components like ExpandableSection.
///
/// Features:
/// - Consistent cardBackgroundDark background
/// - Standard cardBorder with 1pt width
/// - Corner radius from OPSStyle.Layout
/// - Optional header with icon, title, and action button
/// - Configurable content padding
///
/// Usage:
/// ```swift
/// // Simple content card
/// SectionCard {
///     Text("Card content here")
/// }
///
/// // With header
/// SectionCard(
///     icon: "person.circle",
///     title: "Team Members"
/// ) {
///     // Team members list
/// }
///
/// // With header and action button
/// SectionCard(
///     icon: "mappin.circle",
///     title: "Location",
///     actionIcon: "arrow.triangle.turn.up.right.circle.fill",
///     actionLabel: "Navigate",
///     onAction: { openMaps() }
/// ) {
///     Text(address)
/// }
/// ```
struct SectionCard<Content: View>: View {
    let icon: String?
    let title: String?
    let actionIcon: String?
    let actionLabel: String?
    let onAction: (() -> Void)?
    let contentPadding: EdgeInsets
    @ViewBuilder let content: () -> Content

    /// Create a section card with optional header
    ///
    /// - Parameters:
    ///   - icon: Optional SF Symbol icon for header
    ///   - title: Optional title (will be uppercased)
    ///   - actionIcon: Optional action button icon
    ///   - actionLabel: Optional action button label
    ///   - onAction: Optional action button handler
    ///   - contentPadding: Custom content padding (default: 16pt all sides)
    ///   - content: Card content
    init(
        icon: String? = nil,
        title: String? = nil,
        actionIcon: String? = nil,
        actionLabel: String? = nil,
        onAction: (() -> Void)? = nil,
        contentPadding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.actionIcon = actionIcon
        self.actionLabel = actionLabel
        self.onAction = onAction
        self.contentPadding = contentPadding
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Optional header
            if let title = title {
                header

                // Divider between header and content
                Divider()
                    .background(OPSStyle.Colors.cardBorder)
            }

            // Content
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(contentPadding)
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            // Icon
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            // Title
            if let title = title {
                Text(title.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            Spacer()

            // Optional action button
            if let actionIcon = actionIcon,
               let actionLabel = actionLabel,
               let onAction = onAction {
                Button(action: onAction) {
                    HStack(spacing: 4) {
                        Image(systemName: actionIcon)
                            .font(.system(size: 14))
                        Text(actionLabel)
                            .font(OPSStyle.Typography.caption)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

// MARK: - Convenience Variants

extension SectionCard {
    /// Create a simple content-only card without header
    init(
        contentPadding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = nil
        self.title = nil
        self.actionIcon = nil
        self.actionLabel = nil
        self.onAction = nil
        self.contentPadding = contentPadding
        self.content = content
    }
}
