//
//  SchedulerFooterBar.swift
//  OPS
//
//  The schedule sheet's single commit point.
//
//  Everything above this bar is exploration — scrolling months, reading
//  conflicts, opening a day. Nothing above it writes. The bar is pinned so the
//  operator always knows where "done" lives, and its label always says what
//  the next tap will do: pick a start, pick an end, or save N days.
//
//  SAVE is the only accent-filled element on the screen. Per the OPS system,
//  steel blue means "the primary action" — so exactly one thing may wear it.
//

import SwiftUI

struct SchedulerFooterBar: View {
    let selection: SchedulerSelection
    let onClear: () -> Void
    let onSave: () -> Void

    private var primaryLabel: String {
        switch selection {
        case .none:
            return "SELECT START DATE"
        case .start:
            return "SELECT END DATE"
        case .range:
            let days = selection.dayCount() ?? 0
            return days == 1 ? "SAVE · 1 DAY" : "SAVE · \(days) DAYS"
        }
    }

    private var isSaveEnabled: Bool { selection.isCommittable }
    private var isClearEnabled: Bool { selection != .none }

    var body: some View {
        GeometryReader { proxy in
            let clearWidth = max(
                0,
                (proxy.size.width - OPSStyle.Layout.spacing2)
                    * OPSStyle.Layout.schedulerFooterSecondaryWidthRatio
            )
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button(action: onClear) {
                    Text("CLEAR")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(
                            isClearEnabled ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.bottomCTAHeight)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .fill(OPSStyle.Colors.surfaceInput)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .contentShape(Rectangle())
                }
                .disabled(!isClearEnabled)
                .frame(width: clearWidth)

                Button(action: onSave) {
                    Text(primaryLabel)
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(
                            isSaveEnabled ? OPSStyle.Colors.invertedText : OPSStyle.Colors.tertiaryText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.bottomCTAHeight)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .fill(
                                    isSaveEnabled
                                        ? OPSStyle.Colors.primaryAccent
                                        : OPSStyle.Colors.surfaceInput
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .strokeBorder(
                                    isSaveEnabled ? Color.clear : OPSStyle.Colors.cardBorder,
                                    lineWidth: OPSStyle.Layout.Border.standard
                                )
                        )
                        .contentShape(Rectangle())
                }
                .disabled(!isSaveEnabled)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: OPSStyle.Layout.bottomCTAHeight)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity)
        // Same recipe as `.glassDense()` (material + dense tint), laid out as a
        // full-bleed band with a top hairline instead of a rounded card — the
        // bar is the screen's floor, not a floating panel.
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(OPSStyle.Colors.glassDenseApprox)
                Rectangle()
                    .fill(OPSStyle.Colors.line)
                    .frame(height: OPSStyle.Layout.Border.standard)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(OPSStyle.Animation.fast, value: isSaveEnabled)
    }
}
