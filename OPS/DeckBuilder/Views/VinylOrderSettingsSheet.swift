//
//  VinylOrderSettingsSheet.swift
//  OPS
//
//  The settings panel that lives at the bottom of the full-screen vinyl ORDER
//  LAYOUT workspace.
//
//  Bug 317da29f: "there are no tools to adjust the order". The full-screen
//  layout was a picture — the direction, pattern, roll width, seam and wrap
//  that DECIDE that picture lived back on the order sheet, so the operator
//  looked, closed, adjusted, reopened. This panel puts them under the drawing.
//
//  It is part of the workspace, not a modal over it: it rests at the 80pt peek
//  (MOBILE.md §6.1) showing the one line of numbers every control moves, pulls
//  up to a half sheet (§6.2) holding the controls and the cut list, and never
//  dismisses. It is drawn in-hierarchy rather than presented as a UIKit sheet
//  precisely because it belongs to the screen — the drawing behind it stays
//  live with no presentation gymnastics, and the whole workspace renders as one
//  view for snapshot proof.
//

import SwiftUI
import UIKit

/// The two heights the panel rests at. There is no third — a taller sheet would
/// bury the drawing the settings are being judged against.
enum VinylOrderPanelDetent: Equatable {
    case peek
    case half
}

struct VinylOrderSettingsPanel: View {
    let plan: VinylCutPlan
    @Binding var settings: VinylOrderSettings
    let onSettingsChanged: () -> Void

    let peekHeight: CGFloat
    let halfHeight: CGFloat
    /// Home-indicator clearance. Padded into the panel's own content so the
    /// summary line never sits under the indicator.
    let bottomInset: CGFloat

    @Binding var detent: VinylOrderPanelDetent
    /// Live drag translation, positive downward. Zero at rest.
    @Binding var dragOffset: CGFloat

    /// The panel's height for a given detent and live drag — clamped to the two
    /// rest heights so a hard flick can never tear it off its rails. Static so
    /// the workspace can position the panel with the identical number.
    static func height(
        detent: VinylOrderPanelDetent,
        dragOffset: CGFloat,
        peekHeight: CGFloat,
        halfHeight: CGFloat
    ) -> CGFloat {
        let ceiling = max(peekHeight, halfHeight)
        let base = detent == .peek ? peekHeight : ceiling
        return min(ceiling, max(peekHeight, base - dragOffset))
    }

    /// Which detent a release at `height` settles to — the nearer of the two.
    static func settledDetent(
        forHeight height: CGFloat,
        peekHeight: CGFloat,
        halfHeight: CGFloat
    ) -> VinylOrderPanelDetent {
        let ceiling = max(peekHeight, halfHeight)
        return height >= (peekHeight + ceiling) / 2 ? .half : .peek
    }

    private var height: CGFloat {
        Self.height(
            detent: detent,
            dragOffset: dragOffset,
            peekHeight: peekHeight,
            halfHeight: halfHeight
        )
    }

    /// The grab strip is the panel at peek, minus the home indicator: handle,
    /// summary line, and the whole thing a ≥44pt target for the drag and tap.
    private var grabHeight: CGFloat {
        max(OPSStyle.Layout.touchTargetMin, peekHeight - max(0, bottomInset))
    }

    private var contentHeight: CGFloat {
        max(0, height - grabHeight - max(0, bottomInset))
    }

    var body: some View {
        VStack(spacing: 0) {
            grabStrip
                .frame(height: grabHeight)
                .contentShape(Rectangle())
                .gesture(resizeGesture)
                .accessibilityElement(children: .combine)
                .accessibilityAction { toggle() }
                .accessibilityLabel(VinylOrderWorkspaceCopy.settingsSheetLabel)
                .accessibilityValue(VinylOrderWorkspaceCopy.summaryLine(for: plan))
                .accessibilityHint(
                    detent == .peek
                        ? VinylOrderWorkspaceCopy.settingsExpandHint
                        : VinylOrderWorkspaceCopy.settingsCollapseHint
                )
                .accessibilityAddTraits(.isButton)

            expandedContent
                .frame(height: contentHeight, alignment: .top)
                .clipped()

            Color.clear
                .frame(height: max(0, bottomInset))
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background { panelSurface }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OPSStyle.Colors.glassBorder)
                .frame(height: OPSStyle.Layout.Border.standard)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: OPSStyle.Layout.modalRadius,
                topTrailingRadius: OPSStyle.Layout.modalRadius,
                style: .continuous
            )
        )
    }

    // MARK: - Grab strip

    private var grabStrip: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Capsule()
                .fill(OPSStyle.Colors.text.opacity(OPSStyle.Layout.Opacity.light))
                .frame(
                    width: OPSStyle.Layout.sheetHandleWidth,
                    height: OPSStyle.Layout.sheetHandleHeight
                )

            Text(VinylOrderWorkspaceCopy.summaryLine(for: plan))
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .top)
        // The peek band is a fixed 80pt (MOBILE.md §6.1) so the drawing above it
        // keeps its room. The summary is one dense mono line; the controls and
        // cut list below scroll and scale all the way up.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                section(title: VinylOrderWorkspaceCopy.settingsSection) {
                    VinylOrderSettingsControls(
                        settings: $settings,
                        onChange: onSettingsChanged
                    )
                }

                section(title: VinylOrderWorkspaceCopy.cutListSection) {
                    cutList
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
            .padding(.bottom, OPSStyle.Layout.spacing4)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var cutList: some View {
        if plan.surfaces.isEmpty {
            Text(VinylOrderWorkspaceCopy.empty)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                ForEach(plan.surfaces) { surface in
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text(surface.displayLabel.uppercased())
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.text3)

                        ForEach(VinylCutGroup.groups(from: surface.cuts)) { group in
                            Text(group.displayLine)
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(
                                    group.isPurchased
                                        ? OPSStyle.Colors.text
                                        : OPSStyle.Colors.tan
                                )
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OPSStyle.Layout.spacing2)
                    .nestedCard()
                }
            }
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// \(title)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(OPSStyle.Typography.trackingStandard)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Surface

    /// MOBILE.md §6.1 — glass-dense over the live drawing, so the layout stays
    /// legible behind the panel rather than being walled off by it.
    private var panelSurface: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(OPSStyle.Colors.glassDenseApprox)
        }
    }

    // MARK: - Resize

    /// One gesture carries both affordances: drag the strip to size the panel,
    /// tap it to toggle. Splitting them into a `DragGesture` plus an
    /// `onTapGesture` puts two recognisers on the same 46pt strip and lets
    /// SwiftUI's precedence decide which one a gloved thumb gets — so the
    /// release classifies itself instead.
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                switch Self.release(forTravel: value.translation.height) {
                case .tap:
                    toggle()
                case .drag:
                    settle(
                        to: Self.settledDetent(
                            forHeight: Self.height(
                                detent: detent,
                                dragOffset: value.translation.height,
                                peekHeight: peekHeight,
                                halfHeight: halfHeight
                            ),
                            peekHeight: peekHeight,
                            halfHeight: halfHeight
                        )
                    )
                }
            }
    }

    /// What a release on the grab strip meant.
    enum Release: Equatable {
        /// The thumb stayed put — toggle between the two detents.
        case tap
        /// The thumb travelled — settle to whichever detent it ended nearer.
        case drag
    }

    /// Classify a release by how far it travelled. One gesture serves both
    /// affordances, so the release decides which it was rather than leaving two
    /// recognisers on one strip to race.
    static func release(forTravel travel: CGFloat) -> Release {
        abs(travel) < tapTravelCeiling ? .tap : .drag
    }

    /// Travel under this is a tap, not a drag — the slop a thumb leaves behind.
    /// `spacing3` (16pt), deliberately above UIKit's own 10pt
    /// `allowableMovement`: this strip gets a gloved thumb in the cold, and a
    /// tap that wobbles 6pt has to still toggle the panel rather than die as a
    /// drag that settles back where it started. It costs nothing at the other
    /// end — reaching the half detent is a ~350pt pull.
    static let tapTravelCeiling = CGFloat(OPSStyle.Layout.spacing3)

    private func toggle() {
        settle(to: detent == .peek ? .half : .peek)
    }

    /// Transition beat — the panel moves with the one OPS curve, and the light
    /// impact fires only when the detent actually changes, never on a settle
    /// back to where it started.
    private func settle(to target: VinylOrderPanelDetent) {
        let changed = target != detent
        withAnimation(OPSStyle.Animation.page) {
            detent = target
            dragOffset = 0
        }
        if changed {
            VinylOrderPanelFeedback.fire()
        }
    }
}

private enum VinylOrderPanelFeedback {
    static func fire() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}
