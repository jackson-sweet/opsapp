//
//  DimensionLabelView.swift
//  OPS
//
//  Renders ONE Hover-style external-leader dimension label per spec §3.5:
//
//    • Leader line 1.5 pt solid white with 1 pt black outer stroke
//    • Dark chip background (#0A0A0A at 80% alpha, 4 pt radius)
//    • Chip text JetBrains Mono 14 pt white, ALWAYS HORIZONTAL regardless
//      of leader angle
//    • Dual-unit text (`14′ 6½″ / 4.43 m`)
//    • Endpoint dots 5 pt circles (white with black outer stroke) on the
//      measurement line endpoints
//
//  This view positions itself inside its parent's coordinate space. The
//  parent passes:
//    • image-space endpoints converted to *screen-canvas* coordinates
//    • the placement decided by `LabelPlacer` (chip rect + leader length)
//    • the unit selection
//
//  Sill-fallback hint (spec §3.3) is rendered when `inlineHint` is set —
//  for the "SILL — NO FLOOR REFERENCE" inline note, the parent passes the
//  hint string and we render it as a small grey caption below the chip.
//
//  Animations: optional `traceProgress` (0…1) for the §5.3 row 5
//  auto-measure stroke trace; chip fades in with `labelOpacity` (0…1)
//  driven by the parent.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.5 §3.3 §5.3
//

import SwiftUI

public struct DimensionLabelView: View {

    public let pointA: CGPoint       // screen-canvas pixel
    public let pointB: CGPoint       // screen-canvas pixel
    public let chipRect: CGRect      // screen-canvas pixel
    public let measurementLabel: String
    public let primaryText: String   // e.g. "14′ 6½″"
    public let secondaryText: String // e.g. "4.43 m"
    public let inlineHint: String?   // e.g. "// SILL — NO FLOOR REFERENCE"
    public let accessibilityLabelText: String
    public let maximumLabelWidth: CGFloat?
    public var traceProgress: CGFloat = 1.0  // 0…1, drives `.trim` on the line
    public var labelOpacity: Double = 1.0    // 0…1, drives chip alpha

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var metrics: DimensionLabelMetrics {
        DimensionLabelMetrics(dynamicTypeSize: dynamicTypeSize)
    }

    public init(
        pointA: CGPoint,
        pointB: CGPoint,
        chipRect: CGRect,
        measurementLabel: String,
        primaryText: String,
        secondaryText: String,
        inlineHint: String? = nil,
        accessibilityLabelText: String,
        maximumLabelWidth: CGFloat? = nil,
        traceProgress: CGFloat = 1.0,
        labelOpacity: Double = 1.0
    ) {
        self.pointA = pointA
        self.pointB = pointB
        self.chipRect = chipRect
        self.measurementLabel = measurementLabel
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.inlineHint = inlineHint
        self.accessibilityLabelText = accessibilityLabelText
        self.maximumLabelWidth = maximumLabelWidth
        self.traceProgress = traceProgress
        self.labelOpacity = labelOpacity
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            measurementLine
            leaderLine
            endpointDot(at: pointA)
            endpointDot(at: pointB)
            chip
            if let hint = inlineHint {
                inlineHintCaption(hint)
            }
        }
        .compositingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabelText))
    }

    // MARK: - Measurement line

    private var measurementLine: some View {
        ZStack {
            // Outer black stroke for legibility on any background.
            Path { p in
                p.move(to: pointA); p.addLine(to: pointB)
            }
            .trim(from: 0, to: max(0, min(1, traceProgress)))
            .stroke(Color.black, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            Path { p in
                p.move(to: pointA); p.addLine(to: pointB)
            }
            .trim(from: 0, to: max(0, min(1, traceProgress)))
            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    // MARK: - Leader line (from line midpoint to chip anchor)

    private var leaderLine: some View {
        let midpoint = CGPoint(x: (pointA.x + pointB.x) / 2,
                               y: (pointA.y + pointB.y) / 2)
        let chipCenter = CGPoint(x: chipRect.midX, y: chipRect.midY)
        return ZStack {
            Path { p in
                p.move(to: midpoint); p.addLine(to: chipCenter)
            }
            .stroke(Color.black, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { p in
                p.move(to: midpoint); p.addLine(to: chipCenter)
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .opacity(traceProgress >= 1.0 ? labelOpacity : 0)
    }

    // MARK: - Endpoint dot

    @ViewBuilder
    private func endpointDot(at p: CGPoint) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.black, lineWidth: 1))
            .frame(width: 7, height: 7)
            .position(p)
            .opacity(traceProgress > 0.05 ? 1 : 0)
    }

    // MARK: - Chip

    private var chip: some View {
        VStack(alignment: .center, spacing: 1) {
            Text(primaryText)
                .font(.custom("JetBrainsMono-Regular", size: metrics.primaryFontSize))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
            if !secondaryText.isEmpty && secondaryText != primaryText {
                Text(secondaryText)
                    .font(.custom("JetBrainsMono-Regular", size: metrics.secondaryFontSize))
                    .foregroundColor(Color.white.opacity(0.7))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, metrics.chipHorizontalPadding)
        .padding(.vertical, metrics.chipVerticalPadding)
        .frame(width: chipRect.width, height: chipRect.height)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 10/255, green: 10/255, blue: 10/255).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        .position(x: chipRect.midX, y: chipRect.midY)
        .opacity(labelOpacity)
    }

    // MARK: - Inline hint

    @ViewBuilder
    private func inlineHintCaption(_ hint: String) -> some View {
        let hintSize = metrics.hintSize(inlineHint: hint, maximumWidth: maximumLabelWidth)
        Text(hint)
            .font(.custom("JetBrainsMono-Regular", size: metrics.hintFontSize))
            .foregroundColor(OPSStyle.Colors.text3)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, metrics.hintHorizontalPadding)
            .padding(.vertical, metrics.hintVerticalPadding)
            .frame(width: hintSize.width, height: hintSize.height)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.6))
            )
            .position(x: chipRect.midX, y: chipRect.maxY + 12)
            .opacity(labelOpacity)
    }
}
