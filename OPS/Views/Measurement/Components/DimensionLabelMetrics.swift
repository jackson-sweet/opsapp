//
//  DimensionLabelMetrics.swift
//  OPS
//
//  Shared live-chip measurement for LiDAR dimension labels. The SwiftUI
//  annotation view and its placement tests use this instead of fixed chip
//  dimensions so Dynamic Type has real layout space before rendering.
//

import SwiftUI
import UIKit

public struct DimensionLabelLayout: Equatable {
    public let chipSize: CGSize
    public let hintSize: CGSize
    public let boundsSize: CGSize

    public init(chipSize: CGSize, hintSize: CGSize, boundsSize: CGSize) {
        self.chipSize = chipSize
        self.hintSize = hintSize
        self.boundsSize = boundsSize
    }
}

public struct DimensionLabelMetrics: Equatable {
    public static let canvasEdgeMargin: CGFloat = 8
    public static let chipLineSpacing: CGFloat = 1
    public static let inlineHintCenterYOffset: CGFloat = 12

    public let dynamicTypeSize: DynamicTypeSize

    public init(dynamicTypeSize: DynamicTypeSize) {
        self.dynamicTypeSize = dynamicTypeSize
    }

    public var primaryFontSize: CGFloat { scaled(14) }
    public var secondaryFontSize: CGFloat { scaled(10) }
    public var hintFontSize: CGFloat { scaled(10) }
    public var chipHorizontalPadding: CGFloat { scaled(8) }
    public var chipVerticalPadding: CGFloat { scaled(4) }
    public var hintHorizontalPadding: CGFloat { scaled(6) }
    public var hintVerticalPadding: CGFloat { scaled(2) }

    public static func maximumLabelWidth(in canvasSize: CGSize) -> CGFloat {
        max(1, canvasSize.width - canvasEdgeMargin * 2)
    }

    public func layout(
        primaryText: String,
        secondaryText: String,
        inlineHint: String?,
        maximumWidth: CGFloat? = nil
    ) -> DimensionLabelLayout {
        let chip = chipSize(
            primaryText: primaryText,
            secondaryText: secondaryText,
            maximumWidth: maximumWidth
        )
        let hint = hintSize(
            inlineHint: inlineHint,
            maximumWidth: maximumWidth
        )
        let bounds = boundsSize(chipSize: chip, hintSize: hint)
        return DimensionLabelLayout(chipSize: chip, hintSize: hint, boundsSize: bounds)
    }

    public func chipSize(
        primaryText: String,
        secondaryText: String,
        maximumWidth: CGFloat? = nil
    ) -> CGSize {
        let primaryFont = monospacedFont(size: primaryFontSize)
        let secondaryFont = monospacedFont(size: secondaryFontSize)
        let hasSecondary = !secondaryText.isEmpty && secondaryText != primaryText
        let primaryWidth = measuredWidth(primaryText, font: primaryFont)
        let secondaryWidth = hasSecondary ? measuredWidth(secondaryText, font: secondaryFont) : 0
        let rawContentWidth = max(primaryWidth, secondaryWidth)
        let maxContentWidth = maximumWidth.map {
            max(1, $0 - chipHorizontalPadding * 2)
        } ?? .greatestFiniteMagnitude
        let contentWidth = min(rawContentWidth, maxContentWidth)

        let primaryHeight = ceil(primaryFont.lineHeight)
        let secondaryHeight = hasSecondary ? ceil(secondaryFont.lineHeight) : 0
        let spacing = hasSecondary ? Self.chipLineSpacing : 0
        let contentHeight = primaryHeight + spacing + secondaryHeight

        return CGSize(
            width: ceil(contentWidth + chipHorizontalPadding * 2),
            height: ceil(contentHeight + chipVerticalPadding * 2)
        )
    }

    public func hintSize(
        inlineHint: String?,
        maximumWidth: CGFloat? = nil
    ) -> CGSize {
        guard let inlineHint,
              !inlineHint.isEmpty else {
            return .zero
        }

        let font = monospacedFont(size: hintFontSize)
        let rawContentWidth = measuredWidth(inlineHint, font: font)
        let maxContentWidth = maximumWidth.map {
            max(1, $0 - hintHorizontalPadding * 2)
        } ?? .greatestFiniteMagnitude
        let contentWidth = min(rawContentWidth, maxContentWidth)

        return CGSize(
            width: ceil(contentWidth + hintHorizontalPadding * 2),
            height: ceil(font.lineHeight + hintVerticalPadding * 2)
        )
    }

    public func boundsRect(
        forChipRect chipRect: CGRect,
        inlineHint: String?,
        maximumWidth: CGFloat? = nil
    ) -> CGRect {
        let hint = hintSize(inlineHint: inlineHint, maximumWidth: maximumWidth)
        guard hint != .zero else { return chipRect }

        let hintRect = CGRect(
            x: chipRect.midX - hint.width / 2,
            y: chipRect.maxY + Self.inlineHintCenterYOffset - hint.height / 2,
            width: hint.width,
            height: hint.height
        )
        return chipRect.union(hintRect)
    }

    public func clampedChipRect(
        _ chipRect: CGRect,
        inlineHint: String?,
        canvasSize: CGSize,
        maximumWidth: CGFloat? = nil
    ) -> CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return chipRect
        }

        let usableFrame = CGRect(origin: .zero, size: canvasSize).insetBy(
            dx: min(Self.canvasEdgeMargin, canvasSize.width / 2),
            dy: min(Self.canvasEdgeMargin, canvasSize.height / 2)
        )
        guard usableFrame.width > 0, usableFrame.height > 0 else {
            return chipRect
        }

        let bounds = boundsRect(
            forChipRect: chipRect,
            inlineHint: inlineHint,
            maximumWidth: maximumWidth
        )
        let dx = offset(for: bounds.minX, max: bounds.maxX, length: bounds.width,
                        insideMin: usableFrame.minX, insideMax: usableFrame.maxX)
        let dy = offset(for: bounds.minY, max: bounds.maxY, length: bounds.height,
                        insideMin: usableFrame.minY, insideMax: usableFrame.maxY)

        return chipRect.offsetBy(dx: dx, dy: dy)
    }

    private func boundsSize(chipSize: CGSize, hintSize: CGSize) -> CGSize {
        guard hintSize != .zero else { return chipSize }
        let boundsHeight = chipSize.height + Self.inlineHintCenterYOffset + hintSize.height / 2
        return CGSize(
            width: max(chipSize.width, hintSize.width),
            height: ceil(boundsHeight)
        )
    }

    private func offset(
        for min: CGFloat,
        max: CGFloat,
        length: CGFloat,
        insideMin: CGFloat,
        insideMax: CGFloat
    ) -> CGFloat {
        let insideLength = insideMax - insideMin
        if length > insideLength {
            return (insideMin + insideLength / 2) - (min + length / 2)
        }
        if min < insideMin { return insideMin - min }
        if max > insideMax { return insideMax - max }
        return 0
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        base * scaleFactor
    }

    private var scaleFactor: CGFloat {
        switch dynamicTypeSize {
        case .xSmall: return 0.82
        case .small: return 0.88
        case .medium: return 0.94
        case .large: return 1
        case .xLarge: return 1.12
        case .xxLarge: return 1.23
        case .xxxLarge: return 1.35
        case .accessibility1: return 1.64
        case .accessibility2: return 1.95
        case .accessibility3: return 2.35
        case .accessibility4: return 2.76
        case .accessibility5: return 3.12
        @unknown default: return 1
        }
    }

    private func measuredWidth(_ text: String, font: UIFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.width)
    }

    private func monospacedFont(size: CGFloat) -> UIFont {
        UIFont(name: "JetBrainsMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
