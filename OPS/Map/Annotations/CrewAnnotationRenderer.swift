//
//  CrewAnnotationRenderer.swift
//  OPS
//
//  Renders crew dot annotations as UIImage for Mapbox PointAnnotation.
//  Each image contains a label (first name) above a dot+ring indicator.
//

import UIKit
import CoreLocation

/// Renders crew map dot images with label, ring, and dot.
///
/// Structure (top to bottom):
/// ```
/// [First Name]       <- Kosugi 11pt, white @ 80%
///      gap (4pt)
///   +--ring--+       <- 2px status-color stroke
///   | gap    |       <- 2pt clear space
///   |  dot   |       <- 10pt solid white fill
///   | gap    |
///   +--------+
/// ```
///
/// Total ring diameter = dot(10) + gap(2)*2 + stroke(2)*2 = 18pt
/// Anchor point is at bottom-center (where the dot sits on the coordinate).
enum CrewAnnotationRenderer {

    // MARK: - Layout Constants

    private static let dotDiameter: CGFloat = 10
    private static let gapWidth: CGFloat = 2
    private static let ringStrokeWidth: CGFloat = 2
    /// Total diameter of the outer ring: dot + 2*(gap + stroke)
    private static let totalRingDiameter: CGFloat = dotDiameter + (gapWidth + ringStrokeWidth) * 2  // 18pt
    private static let labelToRingGap: CGFloat = 4
    private static let labelFontSize: CGFloat = 11
    private static let canvasPadding: CGFloat = 2  // Small padding around edges

    // MARK: - Crew Status

    /// Crew status determined from location update data.
    enum CrewStatus {
        case onSite   // Within 100m of a job site
        case enRoute  // Speed > 2 m/s
        case idle     // No update for > 5 min

        var color: UIColor {
            switch self {
            case .onSite:  return UIColor(hex: "#A5B368")  // Green
            case .enRoute: return UIColor(hex: "#C4A868")  // Amber
            case .idle:    return UIColor(hex: "#8E8E93")  // Gray
            }
        }
    }

    // MARK: - Status Resolution

    /// Determine crew status from a location update.
    /// - Parameters:
    ///   - update: The crew member's latest location update.
    ///   - projectCoordinates: Array of (latitude, longitude) tuples for active job sites.
    /// - Returns: The resolved `CrewStatus`.
    static func resolveStatus(
        from update: CrewLocationUpdate,
        projectCoordinates: [(lat: Double, lng: Double)]
    ) -> CrewStatus {
        // Check if within 100m of any job site
        let crewLocation = CLLocation(latitude: update.lat, longitude: update.lng)
        for coord in projectCoordinates {
            let siteLocation = CLLocation(latitude: coord.lat, longitude: coord.lng)
            if crewLocation.distance(from: siteLocation) <= 100 {
                return .onSite
            }
        }

        // Check if moving (speed > 2 m/s)
        if update.speed > 2 {
            return .enRoute
        }

        // Check if stale (> 5 min since last update)
        if Date().timeIntervalSince(update.timestamp) > 300 {
            return .idle
        }

        // Default to idle if not moving and not on-site
        return .idle
    }

    // MARK: - Render

    /// Render a crew dot annotation image.
    /// - Parameters:
    ///   - firstName: The crew member's first name for the label.
    ///   - status: The resolved crew status (determines ring color).
    ///   - isSelected: Whether this crew dot is in the selected state.
    /// - Returns: A rendered `UIImage` for use as a Mapbox PointAnnotation image.
    static func render(firstName: String, status: CrewStatus, isSelected: Bool) -> UIImage {
        // -- Compute label size --
        let labelFont = UIFont(name: "Kosugi-Regular", size: labelFontSize)
            ?? UIFont.systemFont(ofSize: labelFontSize)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: UIColor.white.withAlphaComponent(isSelected ? 1.0 : 0.8)
        ]
        let labelString = NSAttributedString(string: firstName, attributes: labelAttributes)
        let labelSize = labelString.size()

        // -- Canvas dimensions --
        let canvasWidth = max(labelSize.width, totalRingDiameter) + canvasPadding * 2
        let canvasHeight = labelSize.height + labelToRingGap + totalRingDiameter + canvasPadding * 2
        let size = CGSize(width: ceil(canvasWidth), height: ceil(canvasHeight))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            // -- Draw label (centered horizontally, at top) --
            let labelX = (size.width - labelSize.width) / 2
            let labelY = canvasPadding
            labelString.draw(at: CGPoint(x: labelX, y: labelY))

            // -- Ring + Dot center (below label) --
            let ringCenterX = size.width / 2
            let ringCenterY = canvasPadding + labelSize.height + labelToRingGap + totalRingDiameter / 2
            let center = CGPoint(x: ringCenterX, y: ringCenterY)

            let cgContext = context.cgContext

            // -- Draw ring (status color stroke) --
            let ringColor = status.color
            let ringRadius = (totalRingDiameter - ringStrokeWidth) / 2  // Stroke is centered on radius
            cgContext.setStrokeColor(ringColor.withAlphaComponent(isSelected ? 1.0 : 0.7).cgColor)
            cgContext.setLineWidth(ringStrokeWidth)
            cgContext.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cgContext.strokePath()

            // -- Draw dot (solid white fill) --
            let dotRadius = dotDiameter / 2
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.addArc(center: center, radius: dotRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cgContext.fillPath()
        }

        return image
    }
}

