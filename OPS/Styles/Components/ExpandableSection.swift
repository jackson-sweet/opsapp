//
//  ExpandableSection.swift
//  OPS
//
//  Expandable section card with progressive disclosure - built on SectionCard base
//

import SwiftUI

/// Expandable section card with progressive disclosure
///
/// Built on SectionCard base component, adding expand/collapse behavior with
/// chevron indicator and optional delete button. Uses consistent OPS card styling.
///
/// Features:
/// - Tap header to toggle expansion
/// - Smooth spring animation
/// - Optional delete button
/// - Chevron indicator shows expanded state
/// - Consistent styling via SectionCard base
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
    let collapsible: Bool
    @ViewBuilder let content: () -> Content

    /// Create an expandable section
    ///
    /// - Parameters:
    ///   - title: Section title (will be uppercased)
    ///   - icon: SF Symbol icon name (default: "square.grid.2x2")
    ///   - isExpanded: Binding to control expanded/collapsed state
    ///   - onDelete: Optional delete handler (shows delete button when provided)
    ///   - collapsible: Whether the section can be collapsed (default: true)
    ///   - content: Section content (shown when expanded)
    init(
        title: String,
        icon: String = "square.grid.2x2",
        isExpanded: Binding<Bool>,
        onDelete: (() -> Void)? = nil,
        collapsible: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self._isExpanded = isExpanded
        self.onDelete = onDelete
        self.collapsible = collapsible
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header (Tappable)
            HStack(spacing: 12) {
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

                // Chevron indicator (rotates based on state) - hidden when not collapsible
                if collapsible {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())  // Make entire header tappable
            .onTapGesture {
                guard collapsible else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }

            // MARK: - Content (Shown when expanded)
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
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }
}
