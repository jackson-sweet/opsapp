//
//  GlassSurface.swift
//  OPS
//
//  Glass + hairline surface modifiers per `ops-design-system/project/DESIGN.md`
//  § Surfaces & Depth and `mobile/MOBILE.md` § Surfaces & Card Hierarchy.
//
//  Three levels of depth on dark canvas:
//
//    • .glassSurface()  — L1 section card  (rgba(18,18,20,0.58) + blur 28pt
//                         + 0.09 hairline + 10pt radius + top-edge gradient)
//    • .glassDense()    — L1 dense surface (rgba(18,18,20,0.78) + blur 28pt
//                         + 0.09 hairline + 12pt radius, no top gradient)
//    • .nestedCard()    — L2 nested card   (rgba(255,255,255,0.04) + 0.08
//                         hairline + 6pt radius, no blur, no top gradient)
//
//  Zero box-shadows on dark backgrounds — depth = glass + hairlines only.
//

import SwiftUI

// MARK: - L1 Section card (.glassSurface)

/// L1 surface — the primary card / panel / widget container. Inherits depth from
/// `.ultraThinMaterial` (system blur) painted over a tinted `glassApprox` fill,
/// stroked with a 1pt hairline at 9% white, and lit from above by a 4% white
/// top-edge gradient.
///
/// Pass `cornerRadius` to override the default (`panelRadius` = 10pt).
struct GlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat = OPSStyle.Layout.panelRadius

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(OPSStyle.Colors.glassApprox)
                    // Top-edge gradient — the only "lit from above" cue
                    LinearGradient(
                        colors: [OPSStyle.Colors.surfaceInput, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.glassBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - L1 Dense surface (.glassDense)

/// L1 dense surface — used for stacked elements over an L1 card (sheets, popovers,
/// dropdowns, toasts). Higher opacity fill, slightly larger default radius, no
/// top-edge gradient (the surface is already busy enough).
///
/// Maximum nesting is L1 → L1-dense. Three glass layers deep is forbidden.
struct GlassDenseModifier: ViewModifier {
    var cornerRadius: CGFloat = OPSStyle.Layout.modalRadius

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(OPSStyle.Colors.glassDenseApprox)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.glassBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - L2 Nested card (.nestedCard)

/// L2 nested card — sits inside an L1 surface OR directly on canvas when grouping
/// small peer elements (KPI tiles, quick-action grids). Flat fill, no blur, no
/// top-edge gradient. 6pt radius is intentionally smaller than L1's 10pt so the
/// nesting reads as nesting.
///
/// L2 inside L2 is forbidden — never nest deeper than L1 → L2.
struct NestedCardModifier: ViewModifier {
    var cornerRadius: CGFloat = OPSStyle.Layout.cardRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.surfaceActive, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - View extension

extension View {
    /// L1 glass section card. Pass `cornerRadius` to override the default 10pt.
    func glassSurface(cornerRadius: CGFloat = OPSStyle.Layout.panelRadius) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius))
    }

    /// L1 dense glass surface for sheets, popovers, and dropdowns. Default 12pt.
    func glassDense(cornerRadius: CGFloat = OPSStyle.Layout.modalRadius) -> some View {
        modifier(GlassDenseModifier(cornerRadius: cornerRadius))
    }

    /// L2 nested card surface. Default 6pt radius.
    func nestedCard(cornerRadius: CGFloat = OPSStyle.Layout.cardRadius) -> some View {
        modifier(NestedCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("GlassSurface / NestedCard hierarchy") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()

        VStack(spacing: OPSStyle.Layout.spacing3_5) {
            // L1 section card with L2 nested cards inside (the canonical pattern)
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                Text("// L1 SECTION")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)

                Text("$184,240")
                    .font(.custom("Mohave-Light", size: 38))
                    .foregroundColor(OPSStyle.Colors.text)

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    nested(label: "OVERDUE", value: "04", tone: OPSStyle.Colors.roseTextM)
                    nested(label: "DUE TODAY", value: "03", tone: OPSStyle.Colors.tanTextM)
                    nested(label: "OPEN", value: "17", tone: OPSStyle.Colors.text3)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()

            // L2 card alone on canvas (KPI tile pattern)
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Text("// L2 SOLO")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                Spacer()
                Text("42")
                    .font(OPSStyle.Typography.dataValueLg)
                    .foregroundColor(OPSStyle.Colors.text)
            }
            .padding(14)
            .nestedCard()

            // L1 dense surface — what bottom sheets sit on
            VStack(alignment: .leading, spacing: 6) {
                Text("// L1 DENSE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                Text("Used for sheets, popovers, dropdowns")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text)
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassDense()

            Spacer()
        }
        .padding(OPSStyle.Layout.spacing3_5)
    }
    .preferredColorScheme(.dark)
}

@ViewBuilder
private func nested(label: String, value: String, tone: Color) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(label)
            .font(OPSStyle.Typography.category)
            .foregroundColor(tone)
        Text(value)
            .font(.custom("Mohave-Light", size: 22))
            .foregroundColor(OPSStyle.Colors.text)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 10)
    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
    .nestedCard()
}
#endif
