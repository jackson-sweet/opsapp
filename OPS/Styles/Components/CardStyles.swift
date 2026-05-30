import SwiftUI

/// Card modifiers — spec v2 (2026-04-17).
///
/// Depth strategy: **glass material + hairline only, no box-shadows on dark**.
/// All cards use `.ultraThinMaterial` layered over the pure `#000000` canvas to approximate
/// the web `.glass-surface` treatment. Border is `glassBorder` (rgba 255,255,255,0.09).
/// Radius is `panelRadius` (10pt) for standard cards, `modalRadius` (12pt) for dense/stacked.
///
/// `Accent` cards expose a full-border hue for cases where a single card genuinely needs
/// to stand apart. Avoid for decoration — per spec, colored-accent borders as ornament is
/// an anti-pattern.
struct OPSCardStyle {

    /// Standard glass card — the default surface for cards, panels, widgets.
    struct Standard: ViewModifier {
        var cornerRadius: CGFloat = OPSStyle.Layout.panelRadius
        var padding: CGFloat = 16

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(OPSStyle.Colors.glassBorder, lineWidth: 1)
                )
        }
    }

    /// Dense glass — for stacked surfaces (modals-over-panels, popovers-over-cards).
    /// Radius is `modalRadius` (12) to match sheets / dialogs.
    struct Elevated: ViewModifier {
        var cornerRadius: CGFloat = OPSStyle.Layout.modalRadius
        var padding: CGFloat = 16

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(OPSStyle.Colors.glassBorder, lineWidth: 1)
                )
        }
    }

    /// Interactive card — glass with `surface-hover` tint on press.
    struct Interactive: ViewModifier {
        @State private var isPressed: Bool = false
        var cornerRadius: CGFloat = OPSStyle.Layout.panelRadius
        var padding: CGFloat = 16
        var action: () -> Void

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isPressed ? OPSStyle.Colors.surfaceHover : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(OPSStyle.Colors.glassBorder, lineWidth: 1)
                )
                .animation(OPSStyle.Animation.hover, value: isPressed)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isPressed = true }
                        .onEnded { _ in
                            isPressed = false
                            action()
                        }
                )
        }
    }

    /// Accent card — full-border hue treatment for singular emphasis.
    /// Per spec, use sparingly. Do not use `opsAccent` here unless this IS the screen's
    /// single primary focal element — prefer status-colored borders for category emphasis.
    struct Accent: ViewModifier {
        var accentColor: Color = OPSStyle.Colors.opsAccent
        var cornerRadius: CGFloat = OPSStyle.Layout.panelRadius
        var padding: CGFloat = 16

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(accentColor, lineWidth: 1)
                )
        }
    }
}

// MARK: - View extensions

extension View {
    /// Glass card — the default surface.
    func opsCardStyle(cornerRadius: CGFloat = OPSStyle.Layout.panelRadius, padding: CGFloat = 16) -> some View {
        self.modifier(OPSCardStyle.Standard(cornerRadius: cornerRadius, padding: padding))
    }

    /// Dense glass — for stacked / elevated contexts.
    func opsElevatedCardStyle(cornerRadius: CGFloat = OPSStyle.Layout.modalRadius, padding: CGFloat = 16) -> some View {
        self.modifier(OPSCardStyle.Elevated(cornerRadius: cornerRadius, padding: padding))
    }

    /// Interactive glass card with press feedback.
    func opsInteractiveCardStyle(cornerRadius: CGFloat = OPSStyle.Layout.panelRadius, padding: CGFloat = 16, action: @escaping () -> Void) -> some View {
        self.modifier(OPSCardStyle.Interactive(cornerRadius: cornerRadius, padding: padding, action: action))
    }

    /// Accent-bordered card. Use sparingly — prefer status hues over `opsAccent`.
    func opsAccentCardStyle(accentColor: Color = OPSStyle.Colors.opsAccent, cornerRadius: CGFloat = OPSStyle.Layout.panelRadius, padding: CGFloat = 16) -> some View {
        self.modifier(OPSCardStyle.Accent(accentColor: accentColor, cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Prebuilt wrappers

struct OPSCard: View {
    let content: AnyView
    init<Content: View>(@ViewBuilder content: () -> Content) { self.content = AnyView(content()) }
    var body: some View { content.opsCardStyle() }
}

struct OPSElevatedCard: View {
    let content: AnyView
    init<Content: View>(@ViewBuilder content: () -> Content) { self.content = AnyView(content()) }
    var body: some View { content.opsElevatedCardStyle() }
}

struct OPSInteractiveCard: View {
    var action: () -> Void
    let content: AnyView
    init<Content: View>(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = AnyView(content())
    }
    var body: some View { content.opsInteractiveCardStyle(action: action) }
}

struct OPSAccentCard: View {
    var accentColor: Color = OPSStyle.Colors.opsAccent
    let content: AnyView
    init<Content: View>(accentColor: Color = OPSStyle.Colors.opsAccent, @ViewBuilder content: () -> Content) {
        self.accentColor = accentColor
        self.content = AnyView(content())
    }
    var body: some View { content.opsAccentCardStyle(accentColor: accentColor) }
}

// MARK: - Previews

struct CardStyles_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("CARD STYLES")
                    .font(OPSStyle.Typography.pageTitle)
                    .foregroundColor(OPSStyle.Colors.text)
                    .padding(.top, 16)

                OPSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Standard Card")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.text)
                        Text("Glass surface, hairline border, no shadow.")
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.text2)
                    }
                }

                OPSElevatedCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Elevated (Dense Glass)")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.text)
                        Text("Stacked-surface treatment for modals and popovers.")
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.text2)
                    }
                }

                OPSInteractiveCard(action: {}) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interactive Card")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.text)
                        Text("Press to trigger.")
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.text2)
                    }
                }

                HStack(spacing: 16) {
                    OPSAccentCard(accentColor: OPSStyle.Colors.olive) {
                        VStack {
                            Image(OPSStyle.Icons.checkmarkCircleFill)
                                .foregroundColor(OPSStyle.Colors.olive)
                            Text("Complete")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.text)
                        }
                    }
                    OPSAccentCard(accentColor: OPSStyle.Colors.rose) {
                        VStack {
                            Image(OPSStyle.Icons.exclamationmarkCircleFill)
                                .foregroundColor(OPSStyle.Colors.rose)
                            Text("Error")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.text)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .background(OPSStyle.Colors.background)
        .previewLayout(.sizeThatFits)
    }
}
