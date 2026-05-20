//
//  PanelSectionHeader.swift
//  OPS
//
//  Standard `// LABEL` mono section header used across the LEADS tab and
//  any future surface that needs a section break. Composes:
//
//      [optional 4pt earth-tone dot]  `// LABEL · NN`           HINT TEXT →
//
//  Optional count, optional trailing hint, optional leading dot. The colored
//  dot is the one place semantic color is permitted on this surface — it
//  carries meaning (urgency bucket, severity). The label and count stay mono
//  text-3 regardless of tone.
//
//  Per ops-design-system DESIGN.md § Voice and mobile/MOBILE.md § Lists.
//

import SwiftUI

struct PanelSectionHeader: View {
    let label: String
    var count: Int? = nil
    var hint: String? = nil

    /// Optional 4pt semantic dot to the left of the `//` prefix. nil = no dot.
    var dotColor: Color? = nil

    /// Optional onTap on the hint side (e.g. `OPEN STAGE BOARD →`).
    var onHintTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let dot = dotColor {
                Circle()
                    .fill(dot)
                    .frame(width: 4, height: 4)
            }

            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(label)
                    .foregroundColor(OPSStyle.Colors.text3)
                if let count {
                    Text("  ·  ")
                        .foregroundColor(OPSStyle.Colors.textMute)
                    Text(String(format: "%02d", count))
                        .foregroundColor(OPSStyle.Colors.text3)
                }
            }
            .font(OPSStyle.Typography.metadata)
            .kerning(1.6)               // 0.16em equivalent
            .textCase(.uppercase)

            Spacer(minLength: 8)

            if let hint {
                Button(action: { onHintTap?() }) {
                    Text(hint)
                        .font(OPSStyle.Typography.metadata)
                        .kerning(1.4)
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .textCase(.uppercase)
                }
                .buttonStyle(PlainButtonStyle())
                .allowsHitTesting(onHintTap != nil)
            }
        }
    }
}

#if DEBUG
#Preview("PanelSectionHeader / variants") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack(spacing: 28) {
            PanelSectionHeader(label: "QUEUE")
            PanelSectionHeader(label: "QUEUE", count: 7)
            PanelSectionHeader(label: "QUEUE", hint: "SORTED — STALE FIRST")
            PanelSectionHeader(
                label: "BY STAGE",
                hint: "OPEN STAGE BOARD →",
                onHintTap: {}
            )
            PanelSectionHeader(
                label: "OVERDUE",
                count: 4,
                dotColor: OPSStyle.Colors.rose
            )
            PanelSectionHeader(
                label: "DUE TODAY",
                count: 3,
                dotColor: OPSStyle.Colors.tan
            )
        }
        .padding(20)
    }
    .preferredColorScheme(.dark)
}
#endif
