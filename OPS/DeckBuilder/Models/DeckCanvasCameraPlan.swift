// OPS/OPS/DeckBuilder/Models/DeckCanvasCameraPlan.swift

import CoreGraphics
import Foundation

/// Which world point the camera should keep in view during a speed-draw walk.
/// Bug 5f285f64.
///
/// The canvas used to answer this one way for every perimeter-entry change:
/// recentre on the ANCHOR. The anchor is where the current segment starts —
/// which is to say, the one place the operator has already been. Committing a
/// length therefore parked the view on the point they had just left, and
/// changing direction moved the camera nowhere useful at all.
///
/// The rule here is "follow the work". At any moment in a walk exactly one
/// point is being placed, and this resolves it:
///
/// - a commit lands on a new vertex and the walk continues from it — follow it;
/// - a direction or length change swings or extends the draft — follow its far
///   end, since that is the end that moves;
/// - a direction chosen with no length yet has only the ghost ray — follow the
///   ray's tip, so the operator can see where the run is about to go;
/// - starting a walk has no "next point" to follow. That transition still wants
///   a recentre so the operator gets their bearings on a freshly planted point,
///   and the view owns that decision, so this reports no focus for it;
/// - a walk that has ended has nothing to follow.
///
/// Pure and viewport-free: the view converts the answer to screen space and
/// hands it to `DeckCanvasFollowPolicy`, which decides how far to actually move.
enum DeckCanvasCameraPlan {

    /// The point to follow after a perimeter-entry transition.
    ///
    /// `ghostLength` is the canvas-space distance from the anchor to the tip of
    /// the direction ghost — the same ray the canvas draws — so the camera
    /// follows exactly what the operator can see.
    ///
    /// `scaleFactor` is the drawing's calibrated canvas points per real-world
    /// inch. Uncalibrated drawings have none and fall back to `fallbackScale`,
    /// the same prescale every edge, snap and dimension already uses.
    static func focus(
        after next: PerimeterEntryMode,
        previous: PerimeterEntryMode,
        ghostLength: CGFloat,
        scaleFactor: Double? = nil,
        fallbackScale: Double = DeckBuilderViewModel.prescaleFallbackScale
    ) -> CGPoint? {
        // Starting a walk is the one transition that earns a recentre instead of
        // a follow; the view handles it, so report nothing here.
        if case .idle = previous { return nil }

        return focus(
            for: next,
            ghostLength: ghostLength,
            scaleFactor: scaleFactor,
            fallbackScale: fallbackScale
        )
    }

    /// The point to follow for a perimeter-entry state, independent of how it
    /// was reached.
    ///
    /// A direction drag that lifts on the direction it was already showing emits
    /// no state change, so the release path has no transition to reason about —
    /// it asks about the state it is in.
    static func focus(
        for mode: PerimeterEntryMode,
        ghostLength: CGFloat,
        scaleFactor: Double? = nil,
        fallbackScale: Double = DeckBuilderViewModel.prescaleFallbackScale
    ) -> CGPoint? {
        switch mode {
        case .idle:
            return nil

        case .choosingDirection(let anchor):
            // The anchor here IS the point in play: either the vertex a commit
            // just created, or the one a step back returned to.
            return sanitized(anchor.position)

        case .enteringLength(let anchor, let direction, let draft):
            guard let start = sanitized(anchor.position) else { return nil }

            guard draft.totalInches > 0 else {
                return ghostEnd(
                    from: start,
                    direction: direction,
                    incomingAngleDegrees: anchor.incomingAngleDegrees,
                    ghostLength: ghostLength
                )
            }

            return sanitized(PerimeterEntryGeometry.endpoint(
                from: start,
                direction: direction,
                lengthInches: draft.totalInches,
                scaleFactor: scaleFactor,
                incomingAngleDegrees: anchor.incomingAngleDegrees,
                fallbackScale: fallbackScale
            ))
        }
    }

    /// Tip of the direction ghost. Falls back to the anchor when the ray length
    /// is unusable — following the anchor is a near-no-op pan, never a jump to
    /// nowhere.
    private static func ghostEnd(
        from start: CGPoint,
        direction: PerimeterDirection,
        incomingAngleDegrees: Double?,
        ghostLength: CGFloat
    ) -> CGPoint? {
        guard ghostLength.isFinite, ghostLength > 0 else { return start }

        let radians = direction.angleDegrees(incomingAngleDegrees: incomingAngleDegrees) * .pi / 180
        return sanitized(CGPoint(
            x: start.x + CGFloat(cos(radians)) * ghostLength,
            y: start.y + CGFloat(sin(radians)) * ghostLength
        ))
    }

    private static func sanitized(_ point: CGPoint) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return point
    }
}
