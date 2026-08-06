//
//  SiteVisitChecklistGuideView.swift
//  OPS
//
//  One-time pointer from Site Visit to checklist administration.
//

import SwiftUI

struct SiteVisitChecklistGuideView: View {
    let onOpenSettings: () -> Void
    let onNotNow: () -> Void
    let onNeverShowAgain: () -> Void

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text("// CHECKLISTS")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text("CHECKLISTS")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Site visit checklists are company-wide. Edit fields or build a new visit type in Settings.")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    guideButton(
                        title: "OPEN SETTINGS",
                        foreground: OPSStyle.Colors.invertedText,
                        background: OPSStyle.Colors.primaryAccent,
                        action: onOpenSettings
                    )
                    guideButton(
                        title: "NOT NOW",
                        foreground: OPSStyle.Colors.primaryText,
                        background: OPSStyle.Colors.surfaceInput,
                        action: onNotNow
                    )
                    Button(action: onNeverShowAgain) {
                        Text("NEVER SHOW AGAIN")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: OPSStyle.Layout.touchTargetMin
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(OPSStyle.Layout.spacing4)
        }
        .preferredColorScheme(.dark)
    }

    private func guideButton(
        title: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(foreground)
                .frame(
                    maxWidth: .infinity,
                    minHeight: OPSStyle.Layout.touchTargetStandard
                )
                .background(
                    RoundedRectangle(
                        cornerRadius: OPSStyle.Layout.buttonRadius,
                        style: .continuous
                    )
                    .fill(background)
                )
        }
        .buttonStyle(.plain)
    }
}
