//
//  OPSActionBar.swift
//  OPS
//
//  Reusable action bar component — unified material pill with consistent
//  icon+label buttons for all bottom action bars across the app.
//

import SwiftUI
import UIKit

// MARK: - OPSActionBar (Container)

/// A material-backed pill container for action bar buttons.
///
/// Caller controls layout via the `content` ViewBuilder — use HStack, Spacer, dividers, etc.
///
///     OPSActionBar {
///         HStack(spacing: 4) {
///             OPSActionBarButton(icon: "camera.fill", label: "PHOTO") { ... }
///             OPSActionBarButton(icon: "note.text", label: "NOTE") { ... }
///         }
///     }
///
struct OPSActionBar<Content: View>: View {
    let showBackground: Bool
    let horizontalPadding: CGFloat
    let content: Content

    init(
        showBackground: Bool = true,
        horizontalPadding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.showBackground = showBackground
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    private let cornerRadius: CGFloat = OPSStyle.Layout.cornerRadius

    var body: some View {
        if showBackground {
            content
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.black.opacity(0.70))
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                )
        } else {
            content
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 10)
        }
    }
}

// MARK: - OPSActionBarButton

/// A single action bar button — icon on top, optional label below.
///
/// Color states:
/// - Default: white icon, gray label (monochromatic)
/// - Accent: pass `iconColor: .primaryAccent, labelColor: .primaryAccent` for the primary CTA
/// - Disabled: set `isDisabled: true`
/// - Destructive: pass `iconColor: .errorStatus, labelColor: .errorStatus`
///
struct OPSActionBarButton: View {
    let icon: String
    let label: String?
    let iconColor: Color
    let labelColor: Color
    let isDisabled: Bool
    let action: () -> Void

    init(
        icon: String,
        label: String? = nil,
        iconColor: Color = OPSStyle.Colors.primaryText,
        labelColor: Color = OPSStyle.Colors.secondaryText,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.iconColor = iconColor
        self.labelColor = labelColor
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button {
            if !isDisabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : iconColor)

                if let label = label {
                    Text(label.uppercased())
                        .font(OPSStyle.Typography.caption)
                        .tracking(0.8)
                        .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : labelColor)
                }
            }
            .frame(
                minWidth: OPSStyle.Layout.touchTargetStandard,
                minHeight: OPSStyle.Layout.touchTargetStandard
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionBarButtonStyle())
        .opacity(isDisabled ? 0.5 : 1.0)
        .allowsHitTesting(!isDisabled)
    }
}

// MARK: - Button Style (press feedback)

/// Subtle opacity + scale on press — understated, tactile.
private struct ActionBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
