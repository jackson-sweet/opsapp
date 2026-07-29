//
//  LeadTriageCardHeaderLayoutTests.swift
//  OPSTests
//
//  Regression coverage for bug b4eee308-83c7-434c-9f55-d83c897dd720:
//  the stage badge must be the card's top-left scan anchor, not buried in
//  the lower metadata row.
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class LeadTriageCardHeaderLayoutTests: XCTestCase {

    private let cardWidth: CGFloat = 393

    func test_statusBadgeOccupiesTopLeftHeaderWithoutLowerDuplicate() throws {
        let lead = Opportunity.preview(
            title: "Roof tear-off — 28 sq",
            contactName: "Marcus Webb",
            stage: .quoted,
            estimatedValue: 14_200,
            daysInStage: 9
        )
        let viewModel = PipelineViewModel.previewLoaded(opportunities: [lead])

        let image = try render(
            LeadTriageCard(
                lead: lead,
                viewModel: viewModel,
                bucket: .fresh
            )
            .frame(width: cardWidth)
            .background(OPSStyle.Colors.background)
            .overlay(alignment: .topLeading) {
                // Bitmap row order varies by renderer. This test-only marker
                // identifies the visual top without assuming an orientation.
                Color(red: 0, green: 1, blue: 0)
                    .frame(width: 2, height: 2)
                    .accessibilityHidden(true)
            }
            .leadsPreviewEnvironment()
        )

        let bounds = try XCTUnwrap(tanStatusBounds(in: image))
        XCTAssertLessThan(
            bounds.minX,
            60,
            "The stage badge must begin in the card's top-left zone."
        )
        XCTAssertLessThan(
            bounds.minY,
            75,
            "The stage badge must occupy the first card row."
        )
        XCTAssertLessThan(
            bounds.maxY,
            80,
            "Stage-colored pixels below the header indicate a duplicate lower badge."
        )
    }

    private func render<V: View>(_ view: V) throws -> UIImage {
        // A UIWindow inherits the device safe-area insets whatever its frame —
        // ignoring safe area keeps the card at its natural origin instead of
        // displaced ~46pt down and bottom-clipped out of the fitted canvas
        // (same correction as DaySheetRowSnapshotTests). The render host below
        // ignores safe area too; sizing must agree with it or `fitted` measures
        // a different box than the one that gets drawn.
        let sizingHost = UIHostingController(rootView: view.ignoresSafeArea())
        let fitted = sizingHost.sizeThatFits(
            in: CGSize(width: cardWidth, height: .greatestFiniteMagnitude)
        )
        let size = CGSize(width: cardWidth, height: max(fitted.height, 10))

        // Draw inside the app host's own window, never a test-created one:
        // mid-suite, window-level drawHierarchy of a freshly attached window
        // goes blank suite-wide ("[Snapshotting] … requires it to be in a
        // foreground scene") and this is the one test that pixel-asserts the
        // result. Hosting via rootViewController swap keeps the live display
        // pipeline; the pattern matches settledLaneState in
        // TabBarSnapshotTests. See AppHostWindow.
        let window = try AppHostWindow.acquire()
        let original = window.rootViewController
        defer {
            window.rootViewController = original
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }

        // Pin the card into an exact card-sized box at the window's top-left
        // (safe areas ignored), replicating the old card-sized window's
        // geometry so the pixel assertions keep their coordinate meaning.
        let host = UIHostingController(rootView: AnyView(
            ZStack(alignment: .topLeading) {
                Color.black
                view.frame(width: size.width, height: size.height, alignment: .topLeading)
            }
            .ignoresSafeArea()
        ))
        window.rootViewController = host
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let full = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let card = full.cgImage?.cropping(to: CGRect(origin: .zero, size: size)) else {
            throw PixelScanError.missingCGImage
        }
        return UIImage(cgImage: card)
    }

    private func tanStatusBounds(in image: UIImage) throws -> CGRect? {
        guard let cgImage = image.cgImage else {
            throw PixelScanError.missingCGImage
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            throw PixelScanError.contextCreationFailed
        }
        context.setBlendMode(.copy)
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        var markerY: Int?
        var tanPoints: [(x: Int, y: Int)] = []

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * bytesPerRow) + (x * 4)
                let red = Int(pixels[index])
                let green = Int(pixels[index + 1])
                let blue = Int(pixels[index + 2])

                if green > 180, red < 80, blue < 80 {
                    markerY = y
                }

                if red > 80,
                   green > 65,
                   blue < 170,
                   red >= green + 5,
                   green >= blue + 12,
                   red >= blue + 25 {
                    tanPoints.append((x, y))
                }
            }
        }

        guard let markerY else {
            throw PixelScanError.calibrationMarkerMissing
        }
        guard !tanPoints.isEmpty else { return nil }

        let rowsAreTopDown = markerY < height / 2
        let visualPoints = tanPoints.map { point in
            (
                x: point.x,
                y: rowsAreTopDown ? point.y : (height - 1 - point.y)
            )
        }
        let minX = visualPoints.map(\.x).min()!
        let maxX = visualPoints.map(\.x).max()!
        let minY = visualPoints.map(\.y).min()!
        let maxY = visualPoints.map(\.y).max()!

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    private enum PixelScanError: Error {
        case missingCGImage
        case contextCreationFailed
        case calibrationMarkerMissing
    }
}
#endif
