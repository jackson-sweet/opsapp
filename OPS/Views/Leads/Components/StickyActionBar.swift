//
//  StickyActionBar.swift
//  OPS
//
//  Bottom-anchored commit bar on LeadDetailView. Two buttons (Leads
//  redesign spec §5.11 — LOST moved into the status menu):
//
//      [✎ EDIT]            [MARK WON →]
//
//  - EDIT  : flex 1, 48pt, neutral outlined (`onEdit`)
//  - WON   : flex 1.5, 48pt, accent-fill, black text (`onMarkWon`)
//
//  Steel-blue accent fill on the WON button is the ONLY accent on the
//  entire LeadDetailView surface — every other chrome element is mono
//  or earth-tone.
//
//  Sits at `bottom + 49pt` above the safe-area inset so the custom tab
//  bar (49pt) has clearance. The buttons float directly over the document
//  using MOBILE.md's single sanctioned floating-CTA elevation token.
//
//  Caller is responsible for hiding this bar when `stage.isTerminal`.
//

import SwiftUI

struct StickyActionBar: View {
    let canEdit: Bool
    let canConvert: Bool
    let onEdit:     () -> Void
    let onMarkWon:  () -> Void

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            if canEdit && canConvert {
                actionPair
            } else if canEdit {
                editButton
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.inputHeight)
            } else if canConvert {
                wonButton
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.inputHeight)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2_5)
        .compositingGroup()
        .shadow(
            color: OPSStyle.Layout.floatingElevation.color,
            radius: OPSStyle.Layout.floatingElevation.radius,
            x: OPSStyle.Layout.floatingElevation.x,
            y: OPSStyle.Layout.floatingElevation.y
        )
    }

    // MARK: - Edit + Won pair (flex 1 : 1.5)

    private var actionPair: some View {
        GeometryReader { geo in
            let available = geo.size.width - OPSStyle.Layout.spacing2
            let unit = available / 2.5
            let editWidth = unit
            let wonWidth  = unit * 1.5
            HStack(spacing: OPSStyle.Layout.spacing2) {
                editButton.frame(width: editWidth, height: OPSStyle.Layout.inputHeight)
                wonButton.frame(width: wonWidth, height: OPSStyle.Layout.inputHeight)
            }
        }
        .frame(height: OPSStyle.Layout.inputHeight)
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
            canEdit: true,
            canConvert: true,
            onEdit: {},
            onMarkWon: {}
        )
        .padding(.bottom, 49)  // tab-bar clearance
    }
    .preferredColorScheme(.dark)
}
#endif
