// OPS/DeckBuilder/Rendering/DeckDimensionLabelPlacement.swift

import CoreGraphics

/// Resolves a dimension label's final world-space drawing geometry.
///
/// Placement deliberately has no viewport input. The label remains attached to
/// its edge while the camera pans or zooms, and the canvas clips both together
/// when they leave the visible region.
struct DeckDimensionLabelPlacement: Equatable {
    let primaryAnchor: CGPoint
    let pillRect: CGRect

    static func resolve(
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        perpendicularOffset: CGVector,
        pillSize: CGSize
    ) -> DeckDimensionLabelPlacement {
        let primaryAnchor = CGPoint(
            x: (edgeStart.x + edgeEnd.x) / 2 + perpendicularOffset.dx,
            y: (edgeStart.y + edgeEnd.y) / 2 + perpendicularOffset.dy
        )

        return DeckDimensionLabelPlacement(
            primaryAnchor: primaryAnchor,
            pillRect: CGRect(
                x: primaryAnchor.x - pillSize.width / 2,
                y: primaryAnchor.y - pillSize.height / 2,
                width: pillSize.width,
                height: pillSize.height
            )
        )
    }

    func secondaryAnchor(verticalOffset: CGFloat) -> CGPoint {
        CGPoint(x: primaryAnchor.x, y: primaryAnchor.y + verticalOffset)
    }
}
