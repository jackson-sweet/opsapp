import SwiftUI

/// # OPS Surface Elevation Ladder — single source of truth
///
/// One ladder, applied everywhere. Depth is carried by **glass + hairlines only —
/// never a box-shadow on dark**. Mirrors `mobile/MOBILE.md` §3 and `DESIGN.md`
/// §5. The canonical *implementation* of every glass level lives in
/// `GlassSurface.swift`; the `OPSCardStyle` wrappers below delegate to it so a
/// card renders identically no matter which call-site name a view reaches for.
///
/// | Level         | Modifier            | Treatment                                                        | Use |
/// |---------------|---------------------|------------------------------------------------------------------|-----|
/// | **L0 Canvas** | `Colors.background` | pure `#000000` (+ optional single `Atmosphere` glow)             | screen base |
/// | **L1 Card**   | `.glassSurface()` / `.opsCardStyle()` | glass 0.58 + `glassBorder` 0.09 + `panelRadius` 10 + top-edge gradient | cards, panels, widgets, list-of-cards items |
/// | **L2 Nested** | `.nestedCard()`     | flat `surfaceInput` 0.04 + `nestedBorder` 0.08 + `cardRadius` 6, **no blur** | KPI/metric tiles, quick-action buttons, inline strips inside L1 or on canvas |
/// | **Dense**     | `.glassDense()` / `.opsElevatedCardStyle()` | glass 0.78 + `glassBorder` 0.09 + `modalRadius` 12 | sheets, popovers, dropdowns, toasts |
/// | **L3 Inline** | `OPSTag`, dots, etc.| inherits the parent surface                                      | tags, badges, status dots, avatars |
///
/// **Lists are not a surface level.** A list container has **no background fill**.
/// Two sanctioned idioms: (a) a `LazyVStack` of L1/L2 cards on transparent ground
/// (the LEADS pattern), or (b) transparent rows inside one L1 card separated by
/// `Colors.line` (0.10) hairlines (the settings pattern). A row never gets its own
/// competing fill.
///
/// **Depth rules.** No box-shadows on dark. Maximum two glass layers
/// (L0 → L1, or L1 → dense). Never nest L2 inside L2.
struct OPSCardStyle {

    /// **L1** standard glass card — the default surface for cards, panels, widgets.
    /// Delegates to `.glassSurface()` so it is pixel-identical to the canonical L1.
    struct Standard: ViewModifier {
        var cornerRadius: CGFloat = OPSStyle.Layout.panelRadius
        var padding: CGFloat = 16

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .glassSurface(cornerRadius: cornerRadius)
        }
    }

    /// **Dense glass** — for stacked surfaces (sheets / popovers / dropdowns over
    /// an L1 card). Delegates to `.glassDense()` (`modalRadius` = 12).
    struct Elevated: ViewModifier {
        var cornerRadius: CGFloat = OPSStyle.Layout.modalRadius
        var padding: CGFloat = 16

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .glassDense(cornerRadius: cornerRadius)
        }
    }

    /// **L1** interactive card — the canonical glass base plus a `surfaceHover`
    /// press tint and a tap action. Behavior layered over `.glassSurface()`.
    struct Interactive: ViewModifier {
        @State private var isPressed: Bool = false
        var cornerRadius: CGFloat = OPSStyle.Layout.panelRadius
        var padding: CGFloat = 16
        var action: () -> Void

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .glassSurface(cornerRadius: cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isPressed ? OPSStyle.Colors.surfaceHover : Color.clear)
                        .allowsHitTesting(false)
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

    /// **L1** accent card — the canonical glass base with a hued edge for singular
    /// emphasis. Per spec, use sparingly; prefer status hues over `opsAccent`, and
    /// only when this IS the screen's single primary focal element.
    struct Accent: ViewModifier {
        var accentColor: Color = OPSStyle.Colors.opsAccent
        var cornerRadius: CGFloat = OPSStyle.Layout.panelRadius
        var padding: CGFloat = 16

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .glassSurface(cornerRadius: cornerRadius, borderColor: accentColor)
        }
    }
}

// MARK: - View extensions

extension View {
    /// **L1** glass card — the default surface. Alias of `.glassSurface()`.
    func opsCardStyle(cornerRadius: CGFloat = OPSStyle.Layout.panelRadius, padding: CGFloat = 16) -> some View {
        self.modifier(OPSCardStyle.Standard(cornerRadius: cornerRadius, padding: padding))
    }

    /// **Dense glass** — for stacked / elevated contexts. Alias of `.glassDense()`.
    func opsElevatedCardStyle(cornerRadius: CGFloat = OPSStyle.Layout.modalRadius, padding: CGFloat = 16) -> some View {
        self.modifier(OPSCardStyle.Elevated(cornerRadius: cornerRadius, padding: padding))
    }

    /// **L1** interactive glass card with press feedback.
    func opsInteractiveCardStyle(cornerRadius: CGFloat = OPSStyle.Layout.panelRadius, padding: CGFloat = 16, action: @escaping () -> Void) -> some View {
        self.modifier(OPSCardStyle.Interactive(cornerRadius: cornerRadius, padding: padding, action: action))
    }

    /// **L1** accent-bordered glass card. Use sparingly — prefer status hues over `opsAccent`.
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
            VStack(spacing: OPSStyle.Layout.spacing4) {
                Text("CARD STYLES")
                    .font(OPSStyle.Typography.pageTitle)
                    .foregroundColor(OPSStyle.Colors.text)
                    .padding(.top, OPSStyle.Layout.spacing3)

                OPSCard {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("L1 — Standard Card")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.text)
                        Text("Glass surface, hairline border, top-edge gradient, no shadow.")
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.text2)
                    }
                }

                OPSElevatedCard {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("Dense Glass")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.text)
                        Text("Stacked-surface treatment for sheets, popovers, dropdowns.")
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.text2)
                    }
                }

                OPSInteractiveCard(action: {}) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("Interactive Card")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.text)
                        Text("Press to trigger.")
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.text2)
                    }
                }

                // L2 nested cards sit inside an L1 surface — the canonical nesting.
                OPSCard {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("// L1 WITH L2 TILES")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.text3)
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(["04", "03", "17"], id: \.self) { value in
                                Text(value)
                                    .font(OPSStyle.Typography.dataValueLg)
                                    .foregroundColor(OPSStyle.Colors.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .nestedCard()
                            }
                        }
                    }
                }

                HStack(spacing: OPSStyle.Layout.spacing3) {
                    OPSAccentCard(accentColor: OPSStyle.Colors.olive) {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(OPSStyle.Colors.olive)
                            Text("Complete")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.text)
                        }
                    }
                    OPSAccentCard(accentColor: OPSStyle.Colors.rose) {
                        VStack {
                            Image(systemName: "exclamationmark.circle.fill")
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
