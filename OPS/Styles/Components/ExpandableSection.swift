//
//  ExpandableSection.swift
//  OPS
//
//  Expandable section card with header, icon, optional delete button, and collapsible content
//

import SwiftUI

/// Expandable section card with progressive disclosure
///
/// Used for collapsible sections in forms and detail views. Provides consistent
/// header styling with icon, title, optional delete button, and chevron indicator.
///
/// Features:
/// - Tap header to toggle expansion
/// - Smooth spring animation
/// - Optional delete button
/// - Chevron indicator shows expanded state
///
/// Usage:
/// ```swift
/// ExpandableSection(
///     title: "PROJECT PHOTOS",
///     icon: OPSStyle.Icons.photo,
///     isExpanded: $isPhotosExpanded,
///     onDelete: { deleteAllPhotos() }
/// ) {
///     // Photo grid content
/// }
/// ```
struct ExpandableSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    let onDelete: (() -> Void)?
    @ViewBuilder let content: () -> Content

    /// Create an expandable section
    ///
    /// - Parameters:
    ///   - title: Section title (will be uppercased)
    ///   - icon: SF Symbol icon name (default: "square.grid.2x2")
    ///   - isExpanded: Binding to control expanded/collapsed state
    ///   - onDelete: Optional delete handler (shows delete button when provided)
    ///   - content: Section content (shown when expanded)
    init(
        title: String,
        icon: String = "square.grid.2x2",
        isExpanded: Binding<Bool>,
        onDelete: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self._isExpanded = isExpanded
        self.onDelete = onDelete
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                // MARK: - Header
                // Tappable header with icon, title, optional delete button, and chevron
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(title.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    // Optional delete button
                    if let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                    }

                    // Chevron indicator (rotates based on state)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())  // Make entire header tappable
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }

                // MARK: - Content
                // Only show divider and content when expanded
                if isExpanded {
                    Divider()
                        .background(OPSStyle.Colors.cardBorder)

                    VStack(spacing: 0) {
                        content()
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
    }
}
