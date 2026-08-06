// OPS/DeckBuilder/Models/DeckCanvasViewportLayout.swift

import CoreGraphics

/// Separates the pixels the canvas renders from the work area left visible by
/// bottom chrome. The render frame is always full bleed; camera fitting, pan
/// constraints, edge pan, and floating canvas instruments use the unobstructed
/// frame so important geometry stays above the toolbar.
struct DeckCanvasViewportLayout: Equatable {
    let renderSize: CGSize
    let bottomChromeInset: CGFloat

    init(renderSize: CGSize, bottomChromeInset: CGFloat) {
        self.renderSize = CGSize(
            width: Self.sanitizedDimension(renderSize.width),
            height: Self.sanitizedDimension(renderSize.height)
        )
        self.bottomChromeInset = min(
            Self.sanitizedDimension(bottomChromeInset),
            self.renderSize.height
        )
    }

    var renderFrame: CGRect {
        CGRect(origin: .zero, size: renderSize)
    }

    var unobstructedSize: CGSize {
        CGSize(
            width: renderSize.width,
            height: renderSize.height - bottomChromeInset
        )
    }

    var unobstructedFrame: CGRect {
        CGRect(origin: .zero, size: unobstructedSize)
    }

    /// When dynamic chrome changes height, move the camera by exactly the
    /// visible-center delta. The same world point therefore remains centered
    /// in the work area instead of jumping beneath the new toolbar.
    func offsetPreservingUnobstructedCenter(
        _ offset: CGSize,
        from previous: DeckCanvasViewportLayout
    ) -> CGSize {
        CGSize(
            width: offset.width + unobstructedFrame.midX - previous.unobstructedFrame.midX,
            height: offset.height + unobstructedFrame.midY - previous.unobstructedFrame.midY
        )
    }

    private static func sanitizedDimension(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(value, 0) : 0
    }
}
