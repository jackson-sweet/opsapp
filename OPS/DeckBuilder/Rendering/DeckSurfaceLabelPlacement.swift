// OPS/DeckBuilder/Rendering/DeckSurfaceLabelPlacement.swift

import CoreGraphics
import Foundation

/// Largest axis-aligned rectangle inside a surface polygon, and text fitting
/// inside it. Pure and viewport-free so the viewer, the builder and export
/// renderers place surface labels identically.
///
/// Bug f7dd3673 — the viewer used to draw the surface label at a fixed 11pt in
/// CANVAS space at the naive vertex mean. The canvas is then scaled by the fit
/// transform (~0.25-0.5 for a real deck), so the label landed at 3-6pt on
/// screen and the anchor could fall outside a concave surface entirely. The
/// label now fills the biggest rectangle the surface actually offers, clamped
/// to the on-screen legibility floor and the display ceiling.
///
/// Grid-rasterized maximal rectangle over a 64x64 grid of the polygon's
/// bounding box: deterministic, and cheap enough to run inside a `Canvas` draw
/// on every pan/zoom frame. The grid is rasterized one row at a time — the
/// row's edge crossings are computed once and reused across its 64 cells —
/// which is the same even/odd rule `PolygonMath.pointInPolygon` applies, cell
/// for cell, at a fraction of the cost of 4096 independent ray casts.
enum DeckSurfaceLabelPlacement {
    static let gridResolution = 64
    /// DESIGN.md: "11px minimum. No exceptions." — and MOBILE.md puts a mono
    /// metadata label at 10-11px, so this is the label's own scale, not a
    /// concession.
    static let screenFloorPoints: CGFloat = 11
    /// Top of the mobile type scale (MOBILE.md screen title, 28px). A name
    /// written on the drawing never outsizes the screen's own title.
    static let screenCapPoints: CGFloat = 28

    /// The single ellipsis a truncated label ends with. Never "..." — the
    /// glyph keeps the label one character wide at the floor size.
    static let ellipsis = "\u{2026}"

    /// Ceiling for an edge's custom caption, on screen: the top of the mono
    /// data-value range (MOBILE.md, JetBrains Mono 16-20px). Lower than the
    /// surface ceiling on purpose — a caption hangs off a dimension pill and
    /// annotates one run, so it stays quieter than a name that owns a face.
    static let edgeCaptionCapPoints: CGFloat = 20

    /// Share of an edge's on-screen length a caption may occupy. Keeps the
    /// annotation attached to its own run instead of reaching across the
    /// neighbouring geometry.
    static let edgeCaptionEdgeShare: CGFloat = 0.6

    struct Fit: Equatable {
        let text: String        // possibly truncated with the ellipsis
        let fontSize: CGFloat   // canvas units
        let size: CGSize        // measured text size at fontSize (canvas units)
    }

    static func largestInscribedRect(in polygon: [CGPoint]) -> CGRect? {
        guard polygon.count >= 3 else { return nil }
        let xs = polygon.map(\.x)
        let ys = polygon.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(),
              maxX > minX, maxY > minY else { return nil }

        let n = gridResolution
        let cellW = (maxX - minX) / CGFloat(n)
        let cellH = (maxY - minY) / CGFloat(n)

        // inside[r][c] == true when the cell's center is inside the polygon.
        let inside = insideGrid(
            polygon: polygon,
            origin: CGPoint(x: minX, y: minY),
            cellW: cellW,
            cellH: cellH,
            resolution: n
        )

        // Maximal rectangle in a binary matrix via per-row histograms + stack.
        var heights = [Int](repeating: 0, count: n)
        var best = (area: 0, r0: 0, c0: 0, r1: 0, c1: 0)
        for r in 0..<n {
            for c in 0..<n { heights[c] = inside[r][c] ? heights[c] + 1 : 0 }
            var stack: [Int] = []
            for c in 0...n {
                let h = c == n ? 0 : heights[c]
                while let top = stack.last, heights[top] >= h {
                    stack.removeLast()
                    let height = heights[top]
                    let left = stack.last.map { $0 + 1 } ?? 0
                    let width = c - left
                    let area = height * width
                    if area > best.area {
                        best = (area, r - height + 1, left, r, c - 1)
                    }
                }
                stack.append(c)
            }
        }
        guard best.area > 0 else { return nil }

        // Shrink by half a cell on every side so the rectangle is strictly
        // inside the polygon, not merely touching a boundary cell's center.
        let x0 = minX + CGFloat(best.c0) * cellW + cellW / 2
        let y0 = minY + CGFloat(best.r0) * cellH + cellH / 2
        let x1 = minX + CGFloat(best.c1 + 1) * cellW - cellW / 2
        let y1 = minY + CGFloat(best.r1 + 1) * cellH - cellH / 2
        guard x1 > x0, y1 > y0 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Screen-space size for an edge's custom caption.
    ///
    /// The caption used to render at a fixed 11pt through an inverse-scaled
    /// layer, which is legible but invisible next to a long run at fit zoom.
    /// It now fills `edgeCaptionEdgeShare` of the edge's ON-SCREEN length,
    /// clamped to the legibility floor and the caption ceiling. `measure`
    /// returns the caption's size at a given screen font size.
    static func edgeCaptionFontSize(
        edgeScreenLength: CGFloat,
        measure: (CGFloat) -> CGSize
    ) -> CGFloat {
        let available = max(edgeScreenLength, 0) * edgeCaptionEdgeShare
        let referenceWidth = measure(screenFloorPoints).width
        guard available > 0, referenceWidth > 0 else { return screenFloorPoints }
        let scaled = available / referenceWidth * screenFloorPoints
        return min(edgeCaptionCapPoints, max(screenFloorPoints, scaled))
    }

    /// Even/odd rasterization of the bounding-box grid's cell centers.
    ///
    /// Identical, cell for cell, to calling `PolygonMath.pointInPolygon` on
    /// every center — the crossing test, the half-open `>` rule on y and the
    /// strict `<` rule on x are the same, and the intersection is computed with
    /// the same expression — but each row solves its edge crossings once and
    /// then sweeps its cells with a single ascending pointer.
    private static func insideGrid(
        polygon: [CGPoint],
        origin: CGPoint,
        cellW: CGFloat,
        cellH: CGFloat,
        resolution n: Int
    ) -> [[Bool]] {
        var inside = [[Bool]](repeating: [Bool](repeating: false, count: n), count: n)
        let count = polygon.count
        var crossings: [CGFloat] = []
        crossings.reserveCapacity(count)

        for r in 0..<n {
            let y = origin.y + (CGFloat(r) + 0.5) * cellH
            crossings.removeAll(keepingCapacity: true)
            var j = count - 1
            for i in 0..<count {
                let vi = polygon[i]
                let vj = polygon[j]
                if (vi.y > y) != (vj.y > y) {
                    crossings.append(vj.x + (y - vj.y) / (vi.y - vj.y) * (vi.x - vj.x))
                }
                j = i
            }
            guard !crossings.isEmpty else { continue }
            crossings.sort()

            // Cell centers ascend, so one pointer walks the sorted crossings:
            // the crossings still ahead of it are exactly the ones a ray cast
            // to the right would toggle on.
            var passed = 0
            let total = crossings.count
            for c in 0..<n {
                let x = origin.x + (CGFloat(c) + 0.5) * cellW
                while passed < total, !(x < crossings[passed]) { passed += 1 }
                inside[r][c] = (total - passed) % 2 == 1
            }
        }
        return inside
    }

    static func isInside(_ rect: CGRect, polygon: [CGPoint]) -> Bool {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
         CGPoint(x: rect.midX, y: rect.midY)]
            .allSatisfy { PolygonMath.pointInPolygon($0, vertices: polygon) }
    }

    /// Chooses the largest font (canvas units) whose measured single line fits
    /// `rect` inset by `padding`, clamped to the on-screen floor/cap given the
    /// current `canvasScale`. Text metrics scale linearly with font size, so one
    /// reference measurement plus one confirmation measurement is enough.
    ///
    /// When even the floor size overflows the rectangle's width the text is
    /// truncated with an ellipsis rather than drawn across the neighbouring
    /// geometry. The label is never hidden.
    static func fit(
        text: String,
        in rect: CGRect,
        canvasScale: CGFloat,
        padding: CGFloat,
        measure: (String, CGFloat) -> CGSize
    ) -> Fit {
        let scale = max(canvasScale, CGFloat.ulpOfOne.squareRoot())
        let floor = canvasSize(atLeast: screenFloorPoints, scale: scale)
        let cap = canvasSize(atMost: screenCapPoints, scale: scale)
        let availW = max(rect.width - 2 * padding, 0)
        let availH = max(rect.height - 2 * padding, 0)

        let reference: CGFloat = 100
        let ref = measure(text, reference)
        var size = reference
        if ref.width > 0 && ref.height > 0 {
            size = min(availW / ref.width, availH / ref.height) * reference
        }
        size = min(cap, max(floor, size))

        let measured = measure(text, size)
        guard measured.width > availW && size <= floor + 0.01 else {
            return Fit(text: text, fontSize: size, size: measured)
        }
        // The floor cannot fit: truncate rather than overflow the rectangle.
        return fitting(text: text, toWidth: availW, fontSize: size, measure: measure)
    }

    /// Longest prefix of `text` that fits `availableWidth` at a FIXED
    /// `fontSize`, ending in the ellipsis whenever anything was dropped.
    ///
    /// Shared with surfaces whose type size is decided elsewhere (the builder
    /// clamps its label to the zoom band rather than filling the rectangle),
    /// so every OPS surface truncates a deck label the same way. Degrades to
    /// the ellipsis alone when not even one character plus the mark fits: the
    /// label is never hidden and never drawn past the space it was given.
    static func fitting(
        text: String,
        toWidth availableWidth: CGFloat,
        fontSize: CGFloat,
        measure: (String, CGFloat) -> CGSize
    ) -> Fit {
        var candidate = text
        var measured = measure(candidate, fontSize)
        guard measured.width > availableWidth else {
            return Fit(text: candidate, fontSize: fontSize, size: measured)
        }

        var chars = Array(text)
        while chars.count > 1 {
            chars.removeLast()
            candidate = String(chars).trimmingCharacters(in: .whitespaces) + ellipsis
            measured = measure(candidate, fontSize)
            if measured.width <= availableWidth { break }
        }
        if measured.width > availableWidth {
            // Not even one character plus the ellipsis fits. The mark alone
            // still says "there is a label here" without covering geometry.
            candidate = ellipsis
            measured = measure(candidate, fontSize)
        }
        return Fit(text: candidate, fontSize: fontSize, size: measured)
    }

    /// Canvas-space size whose on-screen product is at most `screenPoints`.
    ///
    /// `screenPoints / scale * scale` can land an ulp ABOVE `screenPoints`, so
    /// the quotient is stepped down until the product actually holds. Callers
    /// (and their tests) can then assert the ceiling exactly instead of
    /// carrying a tolerance for binary rounding.
    static func canvasSize(atMost screenPoints: CGFloat, scale: CGFloat) -> CGFloat {
        var size = screenPoints / scale
        var steps = 0
        while size * scale > screenPoints, steps < ulpStepLimit {
            size = size.nextDown
            steps += 1
        }
        return size
    }

    /// Canvas-space size whose on-screen product is at least `screenPoints` —
    /// the legibility floor's mirror of `canvasSize(atMost:scale:)`.
    static func canvasSize(atLeast screenPoints: CGFloat, scale: CGFloat) -> CGFloat {
        var size = screenPoints / scale
        var steps = 0
        while size * scale < screenPoints, steps < ulpStepLimit {
            size = size.nextUp
            steps += 1
        }
        return size
    }

    /// A correctly rounded quotient is within one ulp of the exact value; a
    /// handful of steps is a generous bound that also stops the loop dead on a
    /// non-finite scale.
    private static let ulpStepLimit = 8
}
