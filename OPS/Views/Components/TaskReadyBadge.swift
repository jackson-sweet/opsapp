//
//  TaskReadyBadge.swift
//  OPS
//
//  "READY" chip shown on a task whose predecessor tasks are all complete —
//  i.e. the work blocking it is done and the crew can start (item ba35b7c0).
//  Drive visibility with `ProjectTask.isReadyToStart`.
//
//  Text-only (no decorative icon) and styled to match the task status /
//  UNSCHEDULED badges: smallCaption, 0.1 fill, hairline stroke. Uses the
//  success/go color because READY means "blockers cleared — go".
//

import SwiftUI

struct TaskReadyBadge: View {
    /// Which L1 fill the badge is riding on — `.listRow` swaps the frosted
    /// material for the row's opaque `surfaceRaised` (see `GlassSurfaceFill`).
    var surface: GlassSurfaceFill = .translucent

    var body: some View {
        let label = Text("READY")
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(OPSStyle.Colors.successStatus)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)

        Group {
            switch surface {
            case .translucent:
                label.frostedBadgeFill(OPSStyle.Colors.successStatus, cornerRadius: OPSStyle.Layout.cardCornerRadius)
            case .listRow:
                label.listRowBadgeFill(OPSStyle.Colors.successStatus, cornerRadius: OPSStyle.Layout.cardCornerRadius)
            }
        }
        .accessibilityLabel("Ready to start")
    }
}
