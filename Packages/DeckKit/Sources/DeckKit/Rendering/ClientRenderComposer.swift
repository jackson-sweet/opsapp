import CoreGraphics
import Foundation
import OPSDesignKit
import SwiftUI
#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
private typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
private typealias PlatformColor = NSColor
private typealias PlatformFont = NSFont
#endif

public struct ClientRenderTokens: Equatable, Sendable {
    public var canvasSize: CGSize
    public var headerHeight: CGFloat
    public var contentInset: CGFloat
    public var columnGap: CGFloat
    public var hairlineWidth: CGFloat
    public var accentLineHeight: CGFloat
    public var labelFontName: String
    public var titleFontName: String
    public var valueFontName: String
    public var labelFontSize: CGFloat
    public var titleFontSize: CGFloat
    public var valueFontSize: CGFloat
    public var smallValueFontSize: CGFloat

    public init(
        canvasSize: CGSize,
        headerHeight: CGFloat,
        contentInset: CGFloat,
        columnGap: CGFloat,
        hairlineWidth: CGFloat,
        accentLineHeight: CGFloat,
        labelFontName: String,
        titleFontName: String,
        valueFontName: String,
        labelFontSize: CGFloat,
        titleFontSize: CGFloat,
        valueFontSize: CGFloat,
        smallValueFontSize: CGFloat
    ) {
        self.canvasSize = canvasSize
        self.headerHeight = headerHeight
        self.contentInset = contentInset
        self.columnGap = columnGap
        self.hairlineWidth = hairlineWidth
        self.accentLineHeight = accentLineHeight
        self.labelFontName = labelFontName
        self.titleFontName = titleFontName
        self.valueFontName = valueFontName
        self.labelFontSize = labelFontSize
        self.titleFontSize = titleFontSize
        self.valueFontSize = valueFontSize
        self.smallValueFontSize = smallValueFontSize
    }

    public static let proposalHero = ClientRenderTokens(
        canvasSize: CGSize(width: 1200, height: 900),
        headerHeight: 216,
        contentInset: OPSStyle.Layout.spacing5,
        columnGap: OPSStyle.Layout.spacing4,
        hairlineWidth: OPSStyle.Layout.Border.standard,
        accentLineHeight: OPSStyle.Layout.Border.thick,
        labelFontName: "JetBrainsMono-Regular",
        titleFontName: "CakeMono-Light",
        valueFontName: "JetBrainsMono-Medium",
        labelFontSize: 18,
        titleFontSize: 46,
        valueFontSize: 42,
        smallValueFontSize: 20
    )
}

public enum ClientRenderComposer {
    public static func composeHero(
        sceneImage: DeckKitPlatformImage,
        proposal: ClientProposal,
        branding: ProposalBranding,
        tokens: ClientRenderTokens = .proposalHero
    ) -> DeckKitPlatformImage {
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: tokens.canvasSize, format: format)
        return renderer.image { context in
            drawHero(
                in: context.cgContext,
                sceneImage: sceneImage,
                proposal: proposal,
                branding: branding,
                tokens: tokens
            )
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: tokens.canvasSize)
        image.lockFocusFlipped(true)
        if let context = NSGraphicsContext.current?.cgContext {
            drawHero(
                in: context,
                sceneImage: sceneImage,
                proposal: proposal,
                branding: branding,
                tokens: tokens
            )
        }
        image.unlockFocus()
        return image
        #endif
    }

    private static func drawHero(
        in context: CGContext,
        sceneImage: DeckKitPlatformImage,
        proposal: ClientProposal,
        branding: ProposalBranding,
        tokens: ClientRenderTokens
    ) {
        let palette = ClientRenderPalette(branding: branding)
        let canvas = CGRect(origin: .zero, size: tokens.canvasSize)

        context.setFillColor(palette.background.cgColor)
        context.fill(canvas)

        drawSceneImage(sceneImage, in: canvas, context: context)

        let header = CGRect(
            x: 0,
            y: 0,
            width: tokens.canvasSize.width,
            height: tokens.headerHeight
        )
        context.setFillColor(palette.header.cgColor)
        context.fill(header)

        context.setFillColor(palette.accent.cgColor)
        context.fill(
            CGRect(
                x: 0,
                y: 0,
                width: tokens.canvasSize.width,
                height: tokens.accentLineHeight
            )
        )

        context.setFillColor(palette.line.cgColor)
        context.fill(
            CGRect(
                x: 0,
                y: header.maxY - tokens.hairlineWidth,
                width: tokens.canvasSize.width,
                height: tokens.hairlineWidth
            )
        )

        drawHeaderText(
            proposal: proposal,
            branding: branding,
            tokens: tokens,
            palette: palette,
            header: header
        )
    }

    private static func drawHeaderText(
        proposal: ClientProposal,
        branding: ProposalBranding,
        tokens: ClientRenderTokens,
        palette: ClientRenderPalette,
        header: CGRect
    ) {
        let textX = tokens.contentInset
        let valueWidth = tokens.canvasSize.width * 0.28
        let textWidth = tokens.canvasSize.width - (tokens.contentInset * 2) - valueWidth - tokens.columnGap
        let valueX = tokens.canvasSize.width - tokens.contentInset - valueWidth

        drawText(
            branding.companyName.uppercased(),
            in: CGRect(
                x: textX,
                y: tokens.contentInset,
                width: textWidth,
                height: tokens.labelFontSize + OPSStyle.Layout.spacing2
            ),
            fontName: tokens.labelFontName,
            fontSize: tokens.labelFontSize,
            color: palette.text2,
            alignment: .left
        )

        drawText(
            proposal.title.uppercased(),
            in: CGRect(
                x: textX,
                y: tokens.contentInset + tokens.labelFontSize + OPSStyle.Layout.spacing3,
                width: textWidth,
                height: tokens.titleFontSize + OPSStyle.Layout.spacing3
            ),
            fontName: tokens.titleFontName,
            fontSize: tokens.titleFontSize,
            color: palette.text,
            alignment: .left
        )

        drawText(
            proposal.headline.uppercased(),
            in: CGRect(
                x: valueX,
                y: tokens.contentInset,
                width: valueWidth,
                height: tokens.smallValueFontSize + OPSStyle.Layout.spacing2
            ),
            fontName: tokens.labelFontName,
            fontSize: tokens.labelFontSize,
            color: palette.text2,
            alignment: .right
        )

        drawText(
            proposal.formattedTotal,
            in: CGRect(
                x: valueX,
                y: tokens.contentInset + tokens.smallValueFontSize + OPSStyle.Layout.spacing3,
                width: valueWidth,
                height: tokens.valueFontSize + OPSStyle.Layout.spacing3
            ),
            fontName: tokens.valueFontName,
            fontSize: tokens.valueFontSize,
            color: palette.text,
            alignment: .right
        )
    }

    private static func drawSceneImage(
        _ image: DeckKitPlatformImage,
        in target: CGRect,
        context: CGContext
    ) {
        let drawRect = aspectFillRect(sourceSize: image.size, target: target)
        context.saveGState()
        context.addRect(target)
        context.clip()
        #if canImport(UIKit)
        image.draw(in: drawRect)
        #elseif canImport(AppKit)
        image.draw(
            in: drawRect,
            from: CGRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        #endif
        context.restoreGState()
    }

    private static func aspectFillRect(sourceSize: CGSize, target: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return target
        }

        let scale = max(
            target.width / sourceSize.width,
            target.height / sourceSize.height
        )
        let size = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )

        return CGRect(
            x: target.midX - size.width / 2,
            y: target.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        fontName: String,
        fontSize: CGFloat,
        color: PlatformColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail

        let font = PlatformFont(name: fontName, size: fontSize) ?? fallbackFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]

        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes,
            context: nil
        )
    }

    private static func fallbackFont(size: CGFloat) -> PlatformFont {
        #if canImport(UIKit)
        return PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #elseif canImport(AppKit)
        return PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #endif
    }
}

private struct ClientRenderPalette {
    let background: PlatformColor
    let header: PlatformColor
    let line: PlatformColor
    let text: PlatformColor
    let text2: PlatformColor
    let accent: PlatformColor

    init(branding: ProposalBranding) {
        self.background = Self.platformColor(from: OPSStyle.Colors.background)
        self.header = Self.platformColor(from: OPSStyle.Colors.glassDenseApprox)
        self.line = Self.platformColor(from: OPSStyle.Colors.line)
        self.text = Self.platformColor(from: OPSStyle.Colors.text)
        self.text2 = Self.platformColor(from: OPSStyle.Colors.text2)
        self.accent = Self.color(fromHex: branding.accentHex)
            ?? Self.platformColor(from: OPSStyle.Colors.opsAccent)
    }

    private static func platformColor(from color: Color) -> PlatformColor {
        PlatformColor(color)
    }

    private static func color(fromHex rawValue: String) -> PlatformColor? {
        var hex = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }

        guard hex.count == 6,
              let value = UInt32(hex, radix: 16) else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255

        return PlatformColor(
            red: red,
            green: green,
            blue: blue,
            alpha: 1
        )
    }
}
