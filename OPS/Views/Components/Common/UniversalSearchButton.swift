//
//  UniversalSearchButton.swift
//  OPS
//
//  The single source of truth for the search affordance that appears in the
//  top-trailing slot of every tab's header except Home. Rendering it from one
//  component guarantees the icon is byte-for-byte identical — same glyph, size,
//  fill, touch target, haptic and accessibility label — on every surface, so it
//  reads as one universal control rather than a per-screen reimplementation.
//
//  Each header owns its own instance (it slides with that header on a tab
//  switch); the button only standardizes look + feel. The caller supplies the
//  tap behavior, because "search" means the global sheet on most tabs but an
//  expand-in-place field on Settings.
//

import SwiftUI

struct UniversalSearchButton: View {
    /// What tapping search does on this surface. The button itself fires the
    /// light impact haptic before invoking this, so callers must not double it.
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(
                    width: OPSStyle.Layout.touchTargetMin,
                    height: OPSStyle.Layout.touchTargetMin
                )
                .background(OPSStyle.Colors.fillNeutral)
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Search")
    }
}
