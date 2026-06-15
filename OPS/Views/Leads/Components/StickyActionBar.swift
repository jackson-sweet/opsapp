//
//  StickyActionBar.swift
//  OPS
//
//  Bottom-anchored commit bar on LeadDetailView. Three buttons:
//
//      [×]    [EDIT]            [MARK WON →]
//
//  - LOST  : 52×48pt rose-soft square (`onMarkLost`)
//  - EDIT  : flex 1, 48pt, neutral outlined (`onEdit`)
//  - WON   : flex 1.5, 48pt, accent-fill, black text (`onMarkWon`)
//
//  Steel-blue accent fill on the WON button is the ONLY accent on the
//  entire LeadDetailView surface — every other chrome element is mono
//  or earth-tone.
//
//  Sits at `bottom + 49pt` above the safe-area inset so the custom tab
//  bar (49pt) has clearance. A solid-floor gradient (.clear → bg.85 → bg)
//  drawn behind the bar masks any scrolling rows leaking through.
//
//  Caller is responsible for hiding this bar when `stage.isTerminal`.
//

import SwiftUI

struct StickyActionBar: View {
    let onMarkLost: () -> Void
    let onEdit:     () -> Void
    let onMarkWon:  () -> Void

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            lostButton
            actionPair
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, 14)
        .background(floorGradient)
    }

    // MARK: - Lost button (fixed 52×48)

    private var lostButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onMarkLost()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(OPSStyle.Colors.roseTextM)
                .frame(width: 52, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(OPSStyle.Colors.roseFillM)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(OPSStyle.Colors.roseLineM, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Mark lost")
    }

    // MARK: - Edit + Won pair (flex 1 : 1.5)

    private var actionPair: some View {
        GeometryReader { geo in
            let available = geo.size.width - 8   // gap between the two
            let unit = available / 2.5
            let editWidth = unit
            let wonWidth  = unit * 1.5
            HStack(spacing: OPSStyle.Layout.spacing2) {
                editButton.frame(width: editWidth, height: 48)
                wonButton.frame(width: wonWidth, height: 48)
            }
        }
        .frame(height: 48)
    }

    private var editButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onEdit()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .regular))
                Text("EDIT")
                    .font(.custom("CakeMono-Light", size: 13.5))
                    .kerning(0.27)
                    .textCase(.uppercase)
            }
            .foregroundColor(OPSStyle.Colors.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Edit")
    }

    private var wonButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onMarkWon()
        } label: {
            HStack(spacing: 6) {
                Text("MARK WON")
                    .font(.custom("CakeMono-Light", size: 13.5))
                    .kerning(0.27)
                    .textCase(.uppercase)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .regular))
            }
            .foregroundColor(OPSStyle.Colors.invertedText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(OPSStyle.Colors.opsAccent)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Mark won and convert to project")
    }

    // MARK: - Floor gradient

    /// Solid-floor gradient behind the bar so scrolling activity rows fade
    /// out below 25% of the bar's height — keeps the bar legible without a
    /// hard top border that would read as a divider.
    private var floorGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.clear,
                OPSStyle.Colors.background.opacity(0.85),
                OPSStyle.Colors.background
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("StickyActionBar") {
    ZStack(alignment: .bottom) {
        OPSStyle.Colors.background.ignoresSafeArea()

        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(0..<20) { _ in
                    Rectangle()
                        .fill(OPSStyle.Colors.surfaceInput)
                        .frame(height: 60)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                }
            }
            .padding(.bottom, 200)
        }

        StickyActionBar(
            onMarkLost: {},
            onEdit: {},
            onMarkWon: {}
        )
        .padding(.bottom, 49)  // tab-bar clearance
    }
    .preferredColorScheme(.dark)
}
#endif
