import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class HousePhase5IntegrationTests: XCTestCase {
    func test_fullHouseDesignRoundTripsProjectsRendersAndSchedulesOpenings() throws {
        let data = resolvedTwoStoryFreestandingDesign()

        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(data.toJSON()))
        XCTAssertEqual(decoded.house, data.house)
        XCTAssertEqual(decoded.framing, data.framing)
        XCTAssertEqual(decoded.footings, data.footings)

        let schedule = HouseOpeningSchedule.rows(for: decoded)
        XCTAssertEqual(schedule.map(\.calloutTag), ["D1", "W1", "W2"])
        XCTAssertEqual(schedule.map(\.edgeId), [
            Self.upperHouseEdgeId,
            Self.upperHouseEdgeId,
            Self.upperHouseEdgeId,
        ])

        let elevations = HouseElevationProjector.projectAllFaces(decoded)
        XCTAssertEqual(elevations.map(\.edgeId), [Self.upperHouseEdgeId])
        let elevation = try XCTUnwrap(elevations.first)
        XCTAssertEqual(elevation.wallLengthInches, 240, accuracy: 0.001)
        XCTAssertEqual(elevation.deckSurfaceYInches, 108, accuracy: 0.001)
        XCTAssertEqual(elevation.wallTopYInches, 216, accuracy: 0.001)
        XCTAssertEqual(elevation.openings.map(\.calloutTag), ["D1", "W1", "W2"])

        let image = HouseElevationRenderer.render(elevation, size: Self.snapshotSize)
        XCTAssertEqual(image.size.width, Self.snapshotSize.width)
        XCTAssertEqual(image.size.height, Self.snapshotSize.height)
        let imageData = try Self.imageData(from: image)
        XCTAssertGreaterThan(imageData.count, 1_000)
        XCTAssertGreaterThan(try Self.distinctSampledColorCount(in: image), 1)

        let attachment = Self.attachment(from: imageData)
        attachment.name = "phase-5-two-story-house-elevation"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Phase 5 Two-story House Elevation") { activity in
            activity.add(attachment)
        }
    }

    func test_brickLedgerResolutionPersistsFreestandingBeamLineAndFootings() throws {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: Self.twoStoryHouseDesign(),
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        let strategy = model.resolveLedger(
            forEdge: Self.upperHouseEdgeId,
            houseSideBeamSpanInches: 240
        )

        guard case let .freestanding(detail, fallback)? = strategy else {
            XCTFail("Expected brick cladding to resolve as freestanding.")
            return
        }

        XCTAssertEqual(detail, LedgerDetail(cladding: .brick, attachmentAllowed: false))
        XCTAssertEqual(model.drawingData.house?.ledger, detail)

        let memberSet = try XCTUnwrap(
            model.drawingData.framing?.members.first { $0.levelId == Self.upperLevelId }
        )
        let beam = try XCTUnwrap(
            memberSet.members.first { $0.id == "ledger-fallback-beam-\(Self.upperHouseEdgeId)" }
        )
        XCTAssertEqual(beam.role, .beam)
        XCTAssertEqual(beam.start, CGPoint(x: 40, y: 20))
        XCTAssertEqual(beam.end, CGPoint(x: 280, y: 20))
        XCTAssertNil(beam.nominalSize)
        XCTAssertNil(beam.sizing)
        XCTAssertEqual(beam, fallback.beamMembers.single)

        let footings = try XCTUnwrap(model.drawingData.footings?.footings)
        XCTAssertEqual(footings.map(\.id), fallback.footingAnchors.map(\.id))
        XCTAssertTrue(footings.allSatisfy { $0.sizing == nil })
        XCTAssertEqual(persisted.last?.framing, model.drawingData.framing)
        XCTAssertEqual(persisted.last?.footings, model.drawingData.footings)
    }

    func test_lightOpensFullTwoStoryDesignWithoutHouseFramingOrFootingLoss() throws {
        let full = resolvedTwoStoryFreestandingDesign()
        var persisted: [DeckDrawingData] = []
        let lightModel = DeckDrawingEditorModel(
            drawingData: full,
            capabilities: .light,
            onPersist: { persisted.append($0) }
        )

        XCTAssertNil(
            lightModel.resolveLedger(
                forEdge: Self.upperHouseEdgeId,
                houseSideBeamSpanInches: 240
            )
        )

        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(lightModel.drawingData.toJSON()))
        XCTAssertEqual(decoded.house, full.house)
        XCTAssertEqual(decoded.framing?.members, full.framing?.members)
        XCTAssertEqual(decoded.framing?.generatedAtSchemaVersion, DeckSchemaMigration.houseSchemaVersion)
        XCTAssertEqual(decoded.footings, full.footings)
        XCTAssertTrue(persisted.isEmpty)
    }

    func test_stairsToGradePresentForUpperStoryFloorLine() {
        let result = StairsToGradeEngine.stairsToGrade(
            levelId: Self.upperLevelId,
            widthInches: 48,
            data: Self.twoStoryHouseDesign()
        )

        XCTAssertEqual(result.totalRiseInches, 108, accuracy: 0.001)
        XCTAssertFalse(result.flights.isEmpty)
        XCTAssertEqual(result.landingCount, 0)
        XCTAssertFalse(result.landingInserted)
    }

    private static let lowerLevelId = "lower-level"
    private static let upperLevelId = "upper-level"
    private static let upperHouseEdgeId = "upper-house-edge"
    private static let snapshotSize = CGSize(width: 800, height: 600)

    private func resolvedTwoStoryFreestandingDesign() -> DeckDrawingData {
        let model = DeckDrawingEditorModel(
            drawingData: Self.twoStoryHouseDesign(),
            capabilities: .full
        )

        guard case .freestanding? = model.resolveLedger(
            forEdge: Self.upperHouseEdgeId,
            houseSideBeamSpanInches: 240
        ) else {
            XCTFail("Expected brick cladding to resolve as freestanding.")
            return model.drawingData
        }

        return model.drawingData
    }

    private static func twoStoryHouseDesign() -> DeckDrawingData {
        var lower = DeckLevel(id: lowerLevelId, name: "Lower deck", displayColor: .green, sortOrder: 0)
        lower.elevation = 0
        lower.vertices = [
            DeckVertex(id: "lower-v1", position: CGPoint(x: 80, y: 220)),
            DeckVertex(id: "lower-v2", position: CGPoint(x: 260, y: 220)),
            DeckVertex(id: "lower-v3", position: CGPoint(x: 260, y: 340)),
            DeckVertex(id: "lower-v4", position: CGPoint(x: 80, y: 340)),
        ]
        lower.edges = [
            DeckEdge(id: "lower-back", startVertexId: "lower-v1", endVertexId: "lower-v2"),
            DeckEdge(id: "lower-side", startVertexId: "lower-v2", endVertexId: "lower-v3"),
            DeckEdge(id: "lower-front", startVertexId: "lower-v3", endVertexId: "lower-v4"),
            DeckEdge(id: "lower-return", startVertexId: "lower-v4", endVertexId: "lower-v1"),
        ]

        var upper = DeckLevel(id: upperLevelId, name: "Upper deck", displayColor: .blue, sortOrder: 1)
        upper.elevation = 9
        upper.vertices = [
            DeckVertex(id: "upper-v1", position: CGPoint(x: 40, y: 20)),
            DeckVertex(id: "upper-v2", position: CGPoint(x: 280, y: 20)),
            DeckVertex(id: "upper-v3", position: CGPoint(x: 280, y: 164)),
            DeckVertex(id: "upper-v4", position: CGPoint(x: 40, y: 164)),
        ]
        upper.edges = [
            DeckEdge(
                id: upperHouseEdgeId,
                startVertexId: "upper-v1",
                endVertexId: "upper-v2",
                edgeType: .houseEdge,
                dimension: 240,
                label: "Kitchen wall",
                houseEdgeMaterial: .brick
            ),
            DeckEdge(id: "upper-side", startVertexId: "upper-v2", endVertexId: "upper-v3"),
            DeckEdge(id: "upper-front", startVertexId: "upper-v3", endVertexId: "upper-v4"),
            DeckEdge(id: "upper-return", startVertexId: "upper-v4", endVertexId: "upper-v1"),
        ]

        var data = DeckDrawingData()
        data.schemaVersion = 5
        data.scaleFactor = 1
        data.levels = [lower, upper]
        data.levelConnections = [
            LevelConnection(
                id: "upper-to-grade",
                upperLevelId: upperLevelId,
                lowerLevelId: lowerLevelId,
                upperEdgeId: "upper-front",
                lowerEdgeId: "lower-back",
                stairConfig: StairConfig(width: 48, totalRiseInches: 108)
            ),
        ]
        data.house = HouseModel(
            floorLineFeet: 9,
            storyHeights: [9, 8],
            openings: [
                WallOpening(
                    id: "patio-door",
                    edgeId: upperHouseEdgeId,
                    kind: .patioDoor,
                    widthInches: 72,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 24
                ),
                WallOpening(
                    id: "kitchen-window",
                    edgeId: upperHouseEdgeId,
                    kind: .window,
                    widthInches: 42,
                    heightInches: 48,
                    sillHeightInches: 36,
                    offsetAlongEdgeInches: 132
                ),
                WallOpening(
                    id: "living-window",
                    edgeId: upperHouseEdgeId,
                    kind: .window,
                    widthInches: 36,
                    heightInches: 36,
                    sillHeightInches: 42,
                    offsetAlongEdgeInches: 184
                ),
            ]
        )
        return data
    }

    private static func imageData(from image: DeckKitPlatformImage) throws -> Data {
        #if canImport(UIKit)
        return try XCTUnwrap(image.pngData())
        #elseif canImport(AppKit)
        return try XCTUnwrap(image.tiffRepresentation)
        #endif
    }

    private static func attachment(from data: Data) -> XCTAttachment {
        #if canImport(UIKit)
        return XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        #elseif canImport(AppKit)
        return XCTAttachment(data: data, uniformTypeIdentifier: "public.tiff")
        #endif
    }

    private static func cgImage(from image: DeckKitPlatformImage) throws -> CGImage {
        #if canImport(UIKit)
        return try XCTUnwrap(image.cgImage)
        #elseif canImport(AppKit)
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return try XCTUnwrap(
            image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        )
        #endif
    }

    private static func distinctSampledColorCount(
        in image: DeckKitPlatformImage
    ) throws -> Int {
        let cgImage = try cgImage(from: image)
        let sampleWidth = 80
        let sampleHeight = 60
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](
            repeating: 0,
            count: sampleWidth * sampleHeight * bytesPerPixel
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )

        context.interpolationQuality = .none
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
        )

        var colors = Set<UInt32>()
        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            guard pixels[offset + 3] > 0 else { continue }
            let red = UInt32(pixels[offset])
            let green = UInt32(pixels[offset + 1])
            let blue = UInt32(pixels[offset + 2])
            let alpha = UInt32(pixels[offset + 3])
            colors.insert(red << 24 | green << 16 | blue << 8 | alpha)
        }
        return colors.count
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}
