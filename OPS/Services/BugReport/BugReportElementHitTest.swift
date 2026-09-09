//
//  BugReportElementHitTest.swift
//  OPS
//
//  "Point at it" — turning one tap on the captured screenshot into the actual
//  view the operator meant (bug 5aabcc3a).
//
//  Why a snapshot of the hierarchy instead of a live hit-test: the shot is
//  taken the instant the trigger fires, but the tap that files the report lands
//  seconds later, on a screen that may have scrolled, dismissed or navigated
//  away. Hit-testing the LIVE window then would name a view the operator never
//  pointed at. So the hierarchy is flattened alongside the screenshot, and this
//  file resolves the tap against that frozen copy.
//
//  Everything here is pure — no UIKit lookups, no window, no clock — so the
//  mapping is exercised by unit tests rather than by aiming at a simulator.
//

import CoreGraphics
import Foundation

// MARK: - What was on screen

/// One view from the app window's hierarchy at capture time.
struct BugReportElementCandidate: Equatable {
    /// Frame in window coordinates (points), the same space the screenshot was
    /// rendered in.
    let frame: CGRect
    /// Depth below the window. Deeper wins a tie — it is the more specific view.
    let depth: Int
    let label: String?
    let identifier: String?
    /// The view's class name, e.g. `UILabel` or `_TtC7SwiftUI…`.
    let viewType: String

    init(
        frame: CGRect,
        depth: Int,
        label: String? = nil,
        identifier: String? = nil,
        viewType: String
    ) {
        self.frame = frame
        self.depth = depth
        self.label = label
        self.identifier = identifier
        self.viewType = viewType
    }
}

// MARK: - What the operator pointed at

/// The spot the operator marked, plus whatever the app could name there.
///
/// A mark with no `label`, `identifier` or `viewType` is still worth sending:
/// the coordinates alone put a ring on the screenshot for whoever reads the
/// report. Nothing here is invented to fill a blank.
struct BugReportElementMark: Equatable {
    /// Position inside the screenshot, 0…1 on each axis. Drives the ring, and
    /// survives any rendering size.
    let normalized: CGPoint
    /// The same spot in window points — what a developer compares against a
    /// device screenshot.
    let point: CGPoint
    let label: String?
    let identifier: String?
    let viewType: String?
}

// MARK: - The mapping

enum BugReportElementHitTest {

    /// Hard cap on the flattened hierarchy. A deep SwiftUI tree can run to
    /// thousands of layers; past a few hundred the extra depth names private
    /// container classes nobody can act on, and the report grows for nothing.
    static let candidateLimit = 400

    /// Where an aspect-fit image actually sits inside its container.
    /// Returns `.zero` for a degenerate container or image.
    static func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// A tap in container coordinates, expressed as a 0…1 position inside the
    /// image. Nil when the tap landed on the letterbox — the operator pointed
    /// at nothing, and a mark there would be a lie.
    static func normalizedPoint(
        ofTap tap: CGPoint,
        in container: CGSize,
        imageSize: CGSize
    ) -> CGPoint? {
        let rect = fittedRect(imageSize: imageSize, in: container)
        guard rect.width > 0, rect.height > 0, rect.contains(tap) else { return nil }
        return CGPoint(
            x: (tap.x - rect.minX) / rect.width,
            y: (tap.y - rect.minY) / rect.height
        )
    }

    /// Resolve a normalized tap against the frozen hierarchy.
    ///
    /// The deepest view containing the point names the `viewType` — that is the
    /// thing under the operator's finger. The label and identifier are taken
    /// from the deepest ancestor that actually carries one, because the literal
    /// deepest view is usually an unnamed backing layer while the button two
    /// levels up is what a human would call it.
    static func mark(
        atNormalized normalized: CGPoint,
        windowSize: CGSize,
        candidates: [BugReportElementCandidate]
    ) -> BugReportElementMark {
        let point = CGPoint(
            x: normalized.x * windowSize.width,
            y: normalized.y * windowSize.height
        )

        var hits = candidates.filter { $0.frame.contains(point) }
        hits.sort { lhs, rhs in
            if lhs.depth != rhs.depth { return lhs.depth > rhs.depth }
            // Same depth: the tighter frame is the more specific answer.
            let lhsArea = lhs.frame.width * lhs.frame.height
            let rhsArea = rhs.frame.width * rhs.frame.height
            return lhsArea < rhsArea
        }

        let label = hits.compactMap { nonEmpty($0.label) }.first
        let identifier = hits.compactMap { nonEmpty($0.identifier) }.first

        return BugReportElementMark(
            normalized: normalized,
            point: point,
            label: label,
            identifier: identifier,
            viewType: hits.first.map(\.viewType)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
