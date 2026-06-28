import CoreGraphics
import XCTest
@testable import DeckKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class ClientRenderComposerTests: XCTestCase {
    func testComposeHeroProducesExpectedSizeAndAttachment() throws {
        let scene = Self.makeSceneImage(size: CGSize(width: 640, height: 420))
        let proposal = Self.stubProposal()

        let image = ClientRenderComposer.composeHero(
            sceneImage: scene,
            proposal: proposal,
            branding: proposal.branding
        )

        XCTAssertEqual(image.size.width, 1200)
        XCTAssertEqual(image.size.height, 900)

        let data = try Self.imageData(from: image)
        XCTAssertGreaterThan(data.count, 1_000)

        let attachment = Self.attachment(from: data)
        attachment.name = "client-proposal-hero"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Client Proposal Hero") { activity in
            activity.add(attachment)
        }
    }

    func testComposeHeroUsesProposalTextAndTokenizedCanvas() {
        let scene = Self.makeSceneImage(size: CGSize(width: 320, height: 180))
        let proposal = Self.stubProposal()

        let image = ClientRenderComposer.composeHero(
            sceneImage: scene,
            proposal: proposal,
            branding: proposal.branding,
            tokens: .proposalHero
        )

        XCTAssertEqual(image.size, ClientRenderTokens.proposalHero.canvasSize)
        XCTAssertTrue(proposal.allText.contains("Back Deck proposal"))
        XCTAssertEqual(proposal.formattedTotal, "$850.00")
    }

    private static func stubProposal() -> ClientProposal {
        ClientProposalBuilder.build(
            deck: ClientProposalDeck(id: "d1", title: "Back Deck"),
            lineItems: [
                EstimateGeneratorService.GeneratedLineItem(
                    name: "Composite Decking",
                    description: nil,
                    type: .material,
                    quantity: 100,
                    unit: "sq ft",
                    unitPrice: 8.5,
                    productId: nil,
                    taskTypeId: nil,
                    category: "Surface",
                    sortOrder: 0,
                    isOptional: false
                ),
            ],
            branding: ProposalBranding(
                companyName: "Acme Decks",
                logoURL: nil,
                accentHex: "#3F5A73"
            )
        )
    }

    private static func makeSceneImage(size: CGSize) -> DeckKitPlatformImage {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.lightGray.setFill()
            context.fill(CGRect(x: 64, y: 96, width: 420, height: 180))
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        NSColor.darkGray.setFill()
        CGRect(origin: .zero, size: size).fill()
        NSColor.lightGray.setFill()
        CGRect(x: 64, y: 96, width: 180, height: 72).fill()
        image.unlockFocus()
        return image
        #endif
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
}
