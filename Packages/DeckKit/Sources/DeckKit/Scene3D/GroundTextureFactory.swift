import CoreGraphics
import SceneKit
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias OPSGroundColor = UIColor
private typealias OPSGroundScalar = Float
#elseif canImport(AppKit)
import AppKit
private typealias OPSGroundColor = NSColor
private typealias OPSGroundScalar = CGFloat
#endif

public enum GroundTextureFactory {
    private enum RenderingToken {
        static let texturePixelSize = 256
        static let materialRoughness: CGFloat = 0.92
    }

    public static func material(for cover: GroundCover, spanMeters: Float) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = materialName(for: cover)
        material.lightingModel = .physicallyBased
        material.diffuse.contents = diffuseContents(for: cover)
        material.roughness.contents = RenderingToken.materialRoughness
        material.metalness.contents = 0
        material.isDoubleSided = true

        if usesTexture(cover) {
            let repeats = textureRepeats(for: cover, spanMeters: spanMeters)
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.minificationFilter = .linear
            material.diffuse.magnificationFilter = .linear
            material.diffuse.mipFilter = .linear
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(
                OPSGroundScalar(repeats),
                OPSGroundScalar(repeats),
                1
            )
        }

        return material
    }

    public static func dominantCover(in terrain: TerrainModel?) -> GroundCover {
        guard let terrain else { return .grass }
        return terrain.groundCover
            .max { PolygonMath.area(vertices: $0.polygon) < PolygonMath.area(vertices: $1.polygon) }?
            .cover ?? .grass
    }

    private static func materialName(for cover: GroundCover) -> String {
        "ground.\(cover.rawValue).\(usesTexture(cover) ? "texture" : "flat")"
    }

    private static func usesTexture(_ cover: GroundCover) -> Bool {
        switch cover {
        case .grass, .gravel, .rock, .pavers:
            return true
        case .dirt, .concrete:
            return false
        }
    }

    private static func diffuseContents(for cover: GroundCover) -> Any {
        switch cover {
        case .grass:
            return makeTexture(for: .grass) ?? sceneColor(OPSStyle.Colors.olive)
        case .gravel:
            return makeTexture(for: .gravel) ?? sceneColor(OPSStyle.Colors.text3)
        case .rock:
            return makeTexture(for: .rock) ?? sceneColor(OPSStyle.Colors.textMute)
        case .pavers:
            return makeTexture(for: .pavers) ?? sceneColor(OPSStyle.Colors.tan)
        case .dirt:
            return sceneColor(OPSStyle.Colors.tan)
        case .concrete:
            return sceneColor(OPSStyle.Colors.text3)
        }
    }

    private static func textureRepeats(for cover: GroundCover, spanMeters: Float) -> Float {
        let tileMeters: Float
        switch cover {
        case .grass:
            tileMeters = 2.0
        case .gravel:
            tileMeters = 1.2
        case .rock:
            tileMeters = 1.8
        case .pavers:
            tileMeters = 1.6
        case .dirt, .concrete:
            tileMeters = 3.0
        }
        return max(1, spanMeters / tileMeters)
    }

    private static func makeTexture(for cover: GroundCover) -> CGImage? {
        let size = RenderingToken.texturePixelSize
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        switch cover {
        case .grass:
            drawGrass(in: context, size: size)
        case .gravel:
            drawGravel(in: context, size: size)
        case .rock:
            drawRock(in: context, size: size)
        case .pavers:
            drawPavers(in: context, size: size)
        case .dirt, .concrete:
            break
        }

        return context.makeImage()
    }

    private static func drawGrass(in context: CGContext, size: Int) {
        fill(context, size: size, color: OPSStyle.Colors.olive)
        context.setLineWidth(2)
        context.setStrokeColor(cgColor(OPSStyle.Colors.oliveLine))
        for index in stride(from: 0, to: size, by: 12) {
            context.move(to: CGPoint(x: index, y: 0))
            context.addLine(to: CGPoint(x: index + 18, y: size))
        }
        context.strokePath()

        context.setLineWidth(1)
        context.setStrokeColor(cgColor(OPSStyle.Colors.textMute))
        for index in stride(from: 6, to: size, by: 18) {
            context.move(to: CGPoint(x: 0, y: index))
            context.addLine(to: CGPoint(x: size, y: index + 10))
        }
        context.strokePath()
    }

    private static func drawGravel(in context: CGContext, size: Int) {
        fill(context, size: size, color: OPSStyle.Colors.text3)
        for index in 0..<96 {
            let x = deterministicCoordinate(index: index, multiplier: 37, modulus: size)
            let y = deterministicCoordinate(index: index, multiplier: 61, modulus: size)
            let diameter = CGFloat(3 + (index % 7))
            let color = index.isMultiple(of: 3) ? OPSStyle.Colors.text2 : OPSStyle.Colors.textMute
            context.setFillColor(cgColor(color))
            context.fillEllipse(in: CGRect(x: CGFloat(x), y: CGFloat(y), width: diameter, height: diameter))
        }
    }

    private static func drawRock(in context: CGContext, size: Int) {
        fill(context, size: size, color: OPSStyle.Colors.textMute)
        for index in 0..<28 {
            let x = CGFloat(deterministicCoordinate(index: index, multiplier: 41, modulus: size))
            let y = CGFloat(deterministicCoordinate(index: index, multiplier: 73, modulus: size))
            let width = CGFloat(18 + (index % 5) * 6)
            let height = CGFloat(12 + (index % 4) * 5)
            context.setFillColor(cgColor(index.isMultiple(of: 2) ? OPSStyle.Colors.text2 : OPSStyle.Colors.text3))
            context.beginPath()
            context.move(to: CGPoint(x: x, y: y + height * 0.35))
            context.addLine(to: CGPoint(x: x + width * 0.35, y: y))
            context.addLine(to: CGPoint(x: x + width, y: y + height * 0.25))
            context.addLine(to: CGPoint(x: x + width * 0.82, y: y + height))
            context.addLine(to: CGPoint(x: x + width * 0.18, y: y + height * 0.86))
            context.closePath()
            context.fillPath()
        }
    }

    private static func drawPavers(in context: CGContext, size: Int) {
        fill(context, size: size, color: OPSStyle.Colors.tan)
        context.setLineWidth(3)
        context.setStrokeColor(cgColor(OPSStyle.Colors.textMute))
        let module = size / 4
        for y in stride(from: 0, through: size, by: module) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: size, y: y))
        }
        for row in 0..<4 {
            let offset = row.isMultiple(of: 2) ? 0 : module / 2
            for x in stride(from: -offset, through: size, by: module) {
                context.move(to: CGPoint(x: x, y: row * module))
                context.addLine(to: CGPoint(x: x, y: (row + 1) * module))
            }
        }
        context.strokePath()
    }

    private static func fill(_ context: CGContext, size: Int, color: Color) {
        context.setFillColor(cgColor(color))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }

    private static func deterministicCoordinate(index: Int, multiplier: Int, modulus: Int) -> Int {
        (index * multiplier + multiplier / 2) % modulus
    }

    private static func sceneColor(_ color: Color) -> OPSGroundColor {
        OPSGroundColor(color)
    }

    private static func cgColor(_ color: Color) -> CGColor {
        let sceneColor = OPSGroundColor(color)
        #if canImport(AppKit)
        return sceneColor.usingColorSpace(.deviceRGB)?.cgColor ?? sceneColor.cgColor
        #else
        return sceneColor.cgColor
        #endif
    }
}
