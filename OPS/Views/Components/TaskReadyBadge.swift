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
    var body: some View {
        Text("READY")
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(OPSStyle.Colors.successStatus)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .fill(OPSStyle.Colors.successStatus.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.successStatus, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .accessibilityLabel("Ready to start")
    }
}
