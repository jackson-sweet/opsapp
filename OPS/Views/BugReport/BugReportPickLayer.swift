//
//  BugReportPickLayer.swift
//  OPS
//
//  POINT AT IT's pick surface (bug 14e5a792): a transparent layer over the
//  LIVE app, in the bug report's overlay window.
//
//  At rest it is nothing but a glass bar that says what to do and how to get
//  out. A finger down turns it on: the element under the finger is outlined,
//  everything else dims, and a small tag says exactly what will be recorded —
//  so the operator can slide until the tag names the right thing, and lift.
//  The bar gets out of the way while the finger is down, because the element
//  worth reporting is often the one it would be covering: a start that begins
//  anywhere can slide onto the nav bar and still lift there.
//
//  No accent anywhere. The outline is `text` white — this is a pointer, not a
//  call to action. Reduce Motion turns every movement into a crossfade.
//

import SwiftUI
import UIKit

struct BugReportPickLayer: View {
    @ObservedObject var session: BugReportPickSession
    let onCancel: () -> Void
    /// The finger lifted at this point, in the layer's coordinates.
    let onLift: (CGPoint) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasEntered = false

    private static let space = "BugReportPickLayer"

    /// The bar is for the empty moment before a finger lands.
    private var isBarShown: Bool {
        hasEntered && !session.isTracking && !session.isCommitted
    }

    var body: some View {
        // Two readers on purpose. The outer one respects the safe area, so it
        // is the one that knows how tall the status bar is; the inner one
        // spans the whole screen, so its coordinates ARE window coordinates.
        // A single reader that ignores the safe area reports zero insets, and
        // the bar would sit under the Dynamic Island.
        GeometryReader { safe in
            GeometryReader { screen in
                layer(size: screen.size, topInset: safe.safeAreaInsets.top)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(OPSStyle.Animation.panel) { hasEntered = true }
        }
    }

    private func layer(size: CGSize, topInset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            surface

            if let target = session.target {
                focus(target, in: size, topInset: topInset)
                    .transition(.opacity)
            }

            bar(topInset: topInset)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
        .animation(OPSStyle.Animation.hover, value: session.target)
        .animation(OPSStyle.Animation.hover, value: isBarShown)
    }

    // MARK: - Touch surface

    /// Takes every touch, so the app beneath stays exactly as it is while the
    /// operator aims. A zero-distance drag reads a tap and a slide the same way.
    private var surface: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { session.track(at: $0.location) }
                    .onEnded { value in
                        guard !session.isCommitted else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onLift(value.location)
                    }
            )
            .allowsHitTesting(!session.isCommitted)
            .accessibilityElement()
            .accessibilityLabel("Pick the problem")
            .accessibilityHint("Touch the element with the problem, then lift")
            // VoiceOver hands touches straight through, so the same drag works.
            .accessibilityAddTraits(.allowsDirectInteraction)
    }

    // MARK: - Focus

    @ViewBuilder
    private func focus(
        _ target: BugReportPickResolution,
        in size: CGSize,
        topInset: CGFloat
    ) -> some View {
        let rect = session.layerRect(for: target.outlineRect)
        let focus = ZStack(alignment: .topLeading) {
            BugReportPickCutout(rect: rect, cornerRadius: OPSStyle.Layout.buttonRadius)
                .fill(OPSStyle.Colors.overlayMedium, style: FillStyle(eoFill: true))

            BugReportPickOutline(rect: rect, cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(OPSStyle.Colors.text, lineWidth: OPSStyle.Layout.Border.outline)

            BugReportPickTagPlacement(target: rect, topInset: topInset) {
                tag(target.tagText)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)

        if reduceMotion {
            // One element fades out, the next fades in — nothing slides.
            focus
                .id(rect.integral.debugDescription + target.tagText)
                .transition(.opacity)
        } else {
            focus
        }
    }

    /// What will be recorded, before it is recorded.
    private func tag(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.metadata)
            .tracking(OPSStyle.Typography.trackingStandard)
            .foregroundColor(OPSStyle.Colors.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .glassDense(cornerRadius: OPSStyle.Layout.chipRadius)
            .accessibilityHidden(true)
    }

    // MARK: - Bar

    /// `// TAP THE PROBLEM` and the way out. Only CANCEL takes a touch — the
    /// rest of the bar lets a touch through to the surface, so an element
    /// under the bar is still reachable.
    private func bar(topInset: CGFloat) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("TAP THE PROBLEM")
                    .foregroundColor(OPSStyle.Colors.text)
            }
            .font(OPSStyle.Typography.captionBold)
            .tracking(OPSStyle.Typography.trackingStandard)
            .lineLimit(1)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tap the problem")

            Spacer(minLength: 0)

            Button(action: onCancel) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(OPSStyle.Typography.trackingStandard)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel. Back to the report")
        }
        .padding(.leading, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .background(
            Color.clear
                .glassDense()
                .allowsHitTesting(false)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, topInset + OPSStyle.Layout.spacing2)
        .opacity(isBarShown ? 1 : 0)
        .allowsHitTesting(isBarShown)
    }
}

// MARK: - Where the outline goes

extension BugReportPickResolution {
    /// The rect the outline is drawn on, in app-window points. A component's
    /// rect is its own frame, so the outline hugs its edge. Vision's box for a
    /// text line hugs the GLYPHS, so a text pick's outline stands one spacing
    /// step off them instead of cutting through the letters. The recorded
    /// rect stays Vision's box either way.
    var outlineRect: CGRect {
        guard source == .text else { return rect }
        let outset = OPSStyle.Layout.spacing1
        return rect.insetBy(dx: -outset, dy: -outset)
    }
}

// MARK: - Shapes

/// The screen with a hole where the element is — filled even-odd, it dims
/// everything but the element. Animatable, so the hole travels with the
/// outline instead of jumping ahead of it.
struct BugReportPickCutout: Shape {
    var rect: CGRect
    let cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(rect.minX, rect.minY), .init(rect.width, rect.height)) }
        set {
            rect = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in bounds: CGRect) -> Path {
        var path = Path()
        path.addRect(bounds)
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )
        return path
    }
}

/// The element's outline, in the same animatable rect as the cutout.
struct BugReportPickOutline: Shape {
    var rect: CGRect
    let cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(rect.minX, rect.minY), .init(rect.width, rect.height)) }
        set {
            rect = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in bounds: CGRect) -> Path {
        Path(
            roundedRect: rect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )
    }
}

// MARK: - Tag placement

/// Puts the tag beside the element without covering it: above when there is
/// room (the finger is below the point it touches), else below, else — for an
/// element that fills the screen — just inside its top edge. Always inside
/// the screen's side margins.
struct BugReportPickTagPlacement: Layout {
    let target: CGRect
    /// The status-bar inset; the tag never sits under it.
    let topInset: CGFloat

    static let gap = OPSStyle.Layout.spacing2
    static let margin = OPSStyle.Layout.spacing2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let tag = subviews.first else { return }
        let maxWidth = max(0, bounds.width - Self.margin * 2)
        let measured = tag.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        let size = CGSize(width: min(measured.width, maxWidth), height: measured.height)
        let origin = Self.origin(for: size, target: target, bounds: bounds.size, topInset: topInset)
        tag.place(
            at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
            anchor: .topLeading,
            proposal: ProposedViewSize(size)
        )
    }

    static func origin(for size: CGSize, target: CGRect, bounds: CGSize, topInset: CGFloat) -> CGPoint {
        let x = min(max(target.minX, margin), max(margin, bounds.width - margin - size.width))
        let above = target.minY - gap - size.height
        if above >= topInset + gap {
            return CGPoint(x: x, y: above)
        }
        let below = target.maxY + gap
        if below + size.height <= bounds.height - margin {
            return CGPoint(x: x, y: below)
        }
        return CGPoint(x: x, y: max(topInset + gap, target.minY + gap))
    }
}
