//
//  ProjectAnnotationRenderer.swift
//  OPS
//
//  Renders project pin annotations as UIImage for Mapbox PointAnnotation.
//  Supports two modes:
//    1. Project mode (ALL/ACTIVE): label = project name, ring = segmented task type colors,
//       center dot = pipeline status color.
//    2. Task mode (TODAY): label = task name (+"+" if multiple), subtitle = project name,
//       ring = segmented task type colors, center dot = first task's type color.
//

import UIKit

/// Renders project / task map pin images with label, segmented ring, and colored dot.
///
/// **Project mode** structure:
/// ```
/// [Project Name]          <- Kosugi 11pt, white @ 80%
///      gap (4pt)
///   +--ring--+            <- 2px segmented task-type-color arcs
///   | gap    |            <- 2pt clear space
///   |  dot   |            <- 12pt solid status-color fill
///   | gap    |
///   +--------+
/// ```
///
/// **Task mode** structure:
/// ```
/// [Task Name +N]          <- Kosugi 11pt, white @ 90%
/// [Project Name]          <- Kosugi 9pt, white @ 50%
///      gap (4pt)
///   +--ring--+            <- 2px segmented task-type-color arcs
///   | gap    |
///   |  dot   |            <- 12pt solid task-type-color fill
///   | gap    |
///   +--------+
/// ```
enum ProjectAnnotationRenderer {

    // MARK: - Layout Constants

    private static let dotDiameter: CGFloat = 12
    private static let gapWidth: CGFloat = 2
    private static let ringStrokeWidth: CGFloat = 2
    /// Total diameter of the outer ring: dot + 2*(gap + stroke)
    private static let totalRingDiameter: CGFloat = dotDiameter + (gapWidth + ringStrokeWidth) * 2  // 20pt
    private static let labelToRingGap: CGFloat = 4
    private static let labelFontSize: CGFloat = 11
    private static let subtitleFontSize: CGFloat = 9
    private static let subtitleGap: CGFloat = 1
    private static let canvasPadding: CGFloat = 2
    /// Small angular gap (radians) between ring segments for visual separation.
    private static let segmentGap: CGFloat = 0.08  // ~4.5 degrees

    // MARK: - Pipeline Status Colors

    /// Pipeline status color hex values matching the design spec.
    static func statusUIColor(for status: Status) -> UIColor {
        switch status {
        case .rfq:        return UIColor(hex: "#BCBCBC")
        case .estimated:  return UIColor(hex: "#B5A381")
        case .accepted:   return UIColor(hex: "#9DB582")
        case .inProgress: return UIColor(hex: "#8195B5")
        case .completed:  return UIColor(hex: "#B58289")
        case .closed:     return UIColor(hex: "#E9E9E9")
        case .archived:   return UIColor(hex: "#A182B5")
        }
    }

    // MARK: - Helpers

    /// Whether the status represents a closed/archived project (dimmed on map).
    private static func isDimmed(_ status: Status) -> Bool {
        status == .closed || status == .archived
    }

    /// Convert hex color strings to UIColors, filtering out invalid ones.
    private static func parseColors(_ hexStrings: [String]) -> [UIColor] {
        hexStrings.compactMap { UIColor(hex: $0) }
    }

    // MARK: - Project Pin (ALL / ACTIVE modes)

    /// Render a project pin with segmented task-type-color ring and status-colored center dot.
    /// - Parameters:
    ///   - name: The project name displayed as the label.
    ///   - status: The project's pipeline status (determines center dot color).
    ///   - taskColorHexes: Hex color strings for each task type (one per task). Segments the ring.
    ///   - isSelected: Whether this pin is in the selected state.
    /// - Returns: A rendered `UIImage` for use as a Mapbox PointAnnotation image.
    static func renderProject(
        name: String,
        status: Status,
        taskColorHexes: [String],
        isSelected: Bool
    ) -> UIImage {
        let dimmed = isDimmed(status)
        let globalAlpha: CGFloat = dimmed ? 0.5 : 1.0

        // -- Label --
        let labelFont = UIFont(name: "Kosugi-Regular", size: labelFontSize)
            ?? UIFont.systemFont(ofSize: labelFontSize)
        let labelAlpha: CGFloat = (isSelected ? 1.0 : 0.8) * globalAlpha
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: UIColor.white.withAlphaComponent(labelAlpha)
        ]
        let labelString = NSAttributedString(string: name, attributes: labelAttributes)
        let labelSize = labelString.size()

        // -- Canvas dimensions --
        let canvasWidth = max(labelSize.width, totalRingDiameter) + canvasPadding * 2
        let canvasHeight = labelSize.height + labelToRingGap + totalRingDiameter + canvasPadding * 2
        let size = CGSize(width: ceil(canvasWidth), height: ceil(canvasHeight))

        // -- Ring colors --
        let taskColors = parseColors(taskColorHexes)
        let statusColor = statusUIColor(for: status)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Draw label
            let labelX = (size.width - labelSize.width) / 2
            labelString.draw(at: CGPoint(x: labelX, y: canvasPadding))

            // Ring + dot center
            let center = CGPoint(
                x: size.width / 2,
                y: canvasPadding + labelSize.height + labelToRingGap + totalRingDiameter / 2
            )

            let cgContext = context.cgContext
            let ringAlpha: CGFloat = (isSelected ? 1.0 : 0.7) * globalAlpha

            // Draw segmented ring
            drawSegmentedRing(
                in: cgContext,
                center: center,
                colors: taskColors.isEmpty ? [statusColor] : taskColors,
                alpha: ringAlpha
            )

            // Draw center dot (status color)
            let dotRadius = dotDiameter / 2
            cgContext.setFillColor(statusColor.withAlphaComponent(globalAlpha).cgColor)
            cgContext.addArc(center: center, radius: dotRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cgContext.fillPath()
        }
    }

    // MARK: - Task Pin (TODAY mode)

    /// Render a task-based pin for TODAY mode.
    /// - Parameters:
    ///   - taskName: Primary label (task name). Appended with " +N" if multiple tasks.
    ///   - projectName: Secondary label (project name, shown smaller below task name).
    ///   - taskColorHexes: Hex color strings for each task's type color. Segments the ring.
    ///   - isSelected: Whether this pin is in the selected state.
    /// - Returns: A rendered `UIImage`.
    static func renderTask(
        taskName: String,
        projectName: String,
        taskColorHexes: [String],
        isSelected: Bool
    ) -> UIImage {
        let taskColors = parseColors(taskColorHexes)
        let primaryColor = taskColors.first ?? UIColor.white

        // -- Title label --
        let titleFont = UIFont(name: "Kosugi-Regular", size: labelFontSize)
            ?? UIFont.systemFont(ofSize: labelFontSize)
        let titleAlpha: CGFloat = isSelected ? 1.0 : 0.9
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.white.withAlphaComponent(titleAlpha)
        ]
        let titleString = NSAttributedString(string: taskName, attributes: titleAttributes)
        let titleSize = titleString.size()

        // -- Subtitle label --
        let subtitleFont = UIFont(name: "Kosugi-Regular", size: subtitleFontSize)
            ?? UIFont.systemFont(ofSize: subtitleFontSize)
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.5)
        ]
        let subtitleString = NSAttributedString(string: projectName, attributes: subtitleAttributes)
        let subtitleSize = subtitleString.size()

        // -- Canvas dimensions --
        let textWidth = max(titleSize.width, subtitleSize.width)
        let textHeight = titleSize.height + subtitleGap + subtitleSize.height
        let canvasWidth = max(textWidth, totalRingDiameter) + canvasPadding * 2
        let canvasHeight = textHeight + labelToRingGap + totalRingDiameter + canvasPadding * 2
        let size = CGSize(width: ceil(canvasWidth), height: ceil(canvasHeight))

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Draw title (centered)
            let titleX = (size.width - titleSize.width) / 2
            titleString.draw(at: CGPoint(x: titleX, y: canvasPadding))

            // Draw subtitle (centered, below title)
            let subtitleX = (size.width - subtitleSize.width) / 2
            let subtitleY = canvasPadding + titleSize.height + subtitleGap
            subtitleString.draw(at: CGPoint(x: subtitleX, y: subtitleY))

            // Ring + dot center
            let center = CGPoint(
                x: size.width / 2,
                y: canvasPadding + textHeight + labelToRingGap + totalRingDiameter / 2
            )

            let cgContext = context.cgContext
            let ringAlpha: CGFloat = isSelected ? 1.0 : 0.7

            // Draw segmented ring
            drawSegmentedRing(
                in: cgContext,
                center: center,
                colors: taskColors.isEmpty ? [UIColor.white] : taskColors,
                alpha: ringAlpha
            )

            // Draw center dot (first task's type color)
            let dotRadius = dotDiameter / 2
            cgContext.setFillColor(primaryColor.withAlphaComponent(1.0).cgColor)
            cgContext.addArc(center: center, radius: dotRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cgContext.fillPath()
        }
    }

    // MARK: - Segmented Ring Drawing

    /// Draw a ring divided into equal arc segments, one per color.
    /// Single-color arrays draw a solid ring (no gaps).
    private static func drawSegmentedRing(
        in cgContext: CGContext,
        center: CGPoint,
        colors: [UIColor],
        alpha: CGFloat
    ) {
        let ringRadius = (totalRingDiameter - ringStrokeWidth) / 2
        cgContext.setLineWidth(ringStrokeWidth)
        cgContext.setLineCap(.butt)

        if colors.count <= 1 {
            // Solid ring
            let color = (colors.first ?? UIColor.white).withAlphaComponent(alpha)
            cgContext.setStrokeColor(color.cgColor)
            cgContext.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cgContext.strokePath()
        } else {
            // Segmented ring
            let totalAngle: CGFloat = .pi * 2
            let totalGap = segmentGap * CGFloat(colors.count)
            let segmentAngle = (totalAngle - totalGap) / CGFloat(colors.count)

            // Start at top (-π/2 so first segment starts at 12 o'clock)
            var startAngle: CGFloat = -.pi / 2

            for color in colors {
                let endAngle = startAngle + segmentAngle
                cgContext.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
                cgContext.addArc(
                    center: center,
                    radius: ringRadius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false
                )
                cgContext.strokePath()
                startAngle = endAngle + segmentGap
            }
        }
    }

    // MARK: - Stacked Project Pin (Multiple projects at same location)

    /// Data needed for each project in a stacked pin.
    struct StackedProjectInfo {
        let name: String
        let status: Status
    }

    /// Render a stacked project pin showing multiple projects at the same location.
    /// Single teardrop colored by first project's status, count badge, and vertically stacked names.
    /// - Parameters:
    ///   - projects: The projects at this location (first project determines pin color).
    ///   - isSelected: Whether this stacked pin is in the selected state.
    /// - Returns: A rendered `UIImage`.
    static func renderStackedProject(
        projects: [StackedProjectInfo],
        isSelected: Bool
    ) -> UIImage {
        guard let first = projects.first else {
            return UIImage()
        }

        let maxLabels = 4
        let labelFont = UIFont(name: "Kosugi-Regular", size: labelFontSize)
            ?? UIFont.systemFont(ofSize: labelFontSize)
        let smallFont = UIFont(name: "Kosugi-Regular", size: subtitleFontSize)
            ?? UIFont.systemFont(ofSize: subtitleFontSize)
        let countFont = UIFont(name: "Kosugi-Regular", size: 9)
            ?? UIFont.boldSystemFont(ofSize: 9)
        let labelAlpha: CGFloat = isSelected ? 1.0 : 0.8

        // Build label lines
        let visibleProjects = Array(projects.prefix(maxLabels))
        let overflow = projects.count - maxLabels

        // Measure label sizes
        var labelStrings: [(NSAttributedString, UIColor)] = []
        var maxLabelWidth: CGFloat = 0

        for proj in visibleProjects {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: UIColor.white.withAlphaComponent(labelAlpha)
            ]
            let str = NSAttributedString(string: proj.name, attributes: attrs)
            maxLabelWidth = max(maxLabelWidth, str.size().width)
            labelStrings.append((str, statusUIColor(for: proj.status)))
        }

        // "+N more" line
        var overflowString: NSAttributedString?
        if overflow > 0 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: smallFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.5)
            ]
            overflowString = NSAttributedString(string: "+\(overflow) more", attributes: attrs)
            maxLabelWidth = max(maxLabelWidth, overflowString!.size().width)
        }

        // Count badge dimensions
        let countText = "\(projects.count)"
        let countAttrs: [NSAttributedString.Key: Any] = [
            .font: countFont,
            .foregroundColor: UIColor.white
        ]
        let countStr = NSAttributedString(string: countText, attributes: countAttrs)
        let countSize = countStr.size()
        let badgeDiameter = max(countSize.width, countSize.height) + 8

        // Canvas dimensions
        let dotSpacing: CGFloat = 6  // dot-to-label gap
        let dotSize: CGFloat = 5
        let lineHeight = labelFont.lineHeight + 2
        let labelsHeight = lineHeight * CGFloat(visibleProjects.count)
            + (overflowString != nil ? smallFont.lineHeight + 2 : 0)

        let labelBlockWidth = dotSize + dotSpacing + maxLabelWidth
        let canvasWidth = max(labelBlockWidth, totalRingDiameter) + canvasPadding * 2 + badgeDiameter
        let canvasHeight = labelsHeight + labelToRingGap + totalRingDiameter + canvasPadding * 2
        let size = CGSize(width: ceil(canvasWidth), height: ceil(canvasHeight))

        let primaryColor = statusUIColor(for: first.status)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cgContext = context.cgContext

            // Draw stacked labels with status dots
            var labelY = canvasPadding
            let labelsStartX = (size.width - labelBlockWidth) / 2

            for (str, color) in labelStrings {
                // Status dot
                let dotY = labelY + (lineHeight - dotSize) / 2
                cgContext.setFillColor(color.withAlphaComponent(labelAlpha).cgColor)
                cgContext.fillEllipse(in: CGRect(x: labelsStartX, y: dotY, width: dotSize, height: dotSize))

                // Label text
                str.draw(at: CGPoint(x: labelsStartX + dotSize + dotSpacing, y: labelY))
                labelY += lineHeight
            }

            // Overflow text
            if let overflow = overflowString {
                overflow.draw(at: CGPoint(x: labelsStartX + dotSize + dotSpacing, y: labelY))
                labelY += smallFont.lineHeight + 2
            }

            // Ring + dot center
            let center = CGPoint(
                x: size.width / 2,
                y: canvasPadding + labelsHeight + labelToRingGap + totalRingDiameter / 2
            )

            // Draw ring (solid, first project's status color)
            drawSegmentedRing(
                in: cgContext,
                center: center,
                colors: [primaryColor],
                alpha: isSelected ? 1.0 : 0.7
            )

            // Draw center dot
            let dotRadius = dotDiameter / 2
            cgContext.setFillColor(primaryColor.withAlphaComponent(1.0).cgColor)
            cgContext.addArc(center: center, radius: dotRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cgContext.fillPath()

            // Count badge (top-right corner)
            let badgeX = size.width - badgeDiameter - canvasPadding
            let badgeY = canvasPadding
            let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeDiameter, height: badgeDiameter)

            cgContext.setFillColor(primaryColor.cgColor)
            cgContext.fillEllipse(in: badgeRect)

            // Count text centered in badge
            let countX = badgeRect.midX - countSize.width / 2
            let countY = badgeRect.midY - countSize.height / 2
            countStr.draw(at: CGPoint(x: countX, y: countY))
        }
    }

    // MARK: - Legacy Render (backward compatibility)

    /// Original render method — wraps `renderProject` with status color as single ring color.
    static func render(name: String, status: Status, isSelected: Bool) -> UIImage {
        renderProject(name: name, status: status, taskColorHexes: [], isSelected: isSelected)
    }
}

// UIColor(hex:) extension is defined in Utilities/UIColor+Hex.swift
