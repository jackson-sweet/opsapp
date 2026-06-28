import XCTest
@testable import DeckKit

final class ClientProposalBuilderTests: XCTestCase {
    func testProposalTotalsSumLineItemsAndGroupsByCategory() {
        let items = [
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
                sortOrder: 1,
                isOptional: false
            ),
            EstimateGeneratorService.GeneratedLineItem(
                name: "Railing",
                description: "Top mount picket rail",
                type: .material,
                quantity: 40,
                unit: "linear ft",
                unitPrice: 95,
                productId: nil,
                taskTypeId: nil,
                category: "Railing",
                sortOrder: 0,
                isOptional: false
            ),
        ]

        let proposal = ClientProposalBuilder.build(
            deck: ClientProposalDeck(id: "d1", title: "Back Deck"),
            lineItems: items,
            branding: ProposalBranding(
                companyName: "Acme Decks",
                logoURL: nil,
                accentHex: "#3F5A73"
            )
        )

        XCTAssertEqual(proposal.title, "Back Deck proposal")
        XCTAssertEqual(proposal.sections.map(\.category), ["Surface", "Railing"])
        XCTAssertEqual(proposal.sections.first?.lineItems.first?.name, "Composite Decking")
        XCTAssertEqual(proposal.subtotal, 4650, accuracy: 0.001)
        XCTAssertEqual(proposal.total, 4650, accuracy: 0.001)
        XCTAssertEqual(proposal.formattedTotal, "$4,650.00")
    }

    func testProposalCarriesNoCodeOrStructuralClaim() {
        let proposal = ClientProposalBuilder.build(
            deck: ClientProposalDeck(id: "d1", title: "Back Deck"),
            lineItems: [],
            branding: ProposalBranding(
                companyName: "Acme Decks",
                logoURL: nil,
                accentHex: "#3F5A73"
            )
        )

        let text = proposal.allText.lowercased()

        for banned in [
            "code-compliant",
            "safe",
            "guaranteed",
            "will pass",
            "engineer-stamped",
            "permit-ready",
        ] {
            XCTAssertFalse(text.contains(banned), "\(banned) leaked into proposal text")
        }
    }

    func testOptionalLineItemsStayPricedButOutsideRequiredTotal() {
        let proposal = ClientProposalBuilder.build(
            deck: ClientProposalDeck(id: "d1", title: "Back Deck"),
            lineItems: [
                EstimateGeneratorService.GeneratedLineItem(
                    name: "Decking",
                    description: nil,
                    type: .material,
                    quantity: 10,
                    unit: "sq ft",
                    unitPrice: 10,
                    productId: nil,
                    taskTypeId: nil,
                    category: "Surface",
                    sortOrder: 0,
                    isOptional: false
                ),
                EstimateGeneratorService.GeneratedLineItem(
                    name: "Privacy screen",
                    description: nil,
                    type: .material,
                    quantity: 1,
                    unit: "set",
                    unitPrice: 500,
                    productId: nil,
                    taskTypeId: nil,
                    category: "Other",
                    sortOrder: 1,
                    isOptional: true
                ),
            ],
            branding: ProposalBranding(
                companyName: "Acme Decks",
                logoURL: nil,
                accentHex: "#3F5A73"
            )
        )

        XCTAssertEqual(proposal.subtotal, 100, accuracy: 0.001)
        XCTAssertEqual(proposal.optionalTotal, 500, accuracy: 0.001)
        XCTAssertEqual(proposal.total, 100, accuracy: 0.001)
        XCTAssertEqual(proposal.sections.last?.lineItems.first?.isOptional, true)
    }
}
