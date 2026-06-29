import XCTest
@testable import DeckKit

final class CodeProfileResolverTests: XCTestCase {
    func testManualResolverReturnsProfileForMatchingJurisdiction() throws {
        let profile = profile(jurisdictionId: "jurisdiction-north-ops", maxJoistSpanInches: 119)
        let resolver = DeckManualCodeProfileResolver(profiles: [profile])
        let request = DeckCodeProfileRequest(
            siteAddress: address(),
            jurisdictionId: "jurisdiction-north-ops"
        )

        let resolution = resolver.resolve(request)

        XCTAssertEqual(resolution.status, .available)
        XCTAssertEqual(resolution.request, request)
        XCTAssertEqual(resolution.profile, profile)
        XCTAssertNil(resolution.reasonToken)
    }

    func testManualResolverReturnsNotConfiguredWhenJurisdictionIsMissing() {
        let resolver = DeckManualCodeProfileResolver(
            profiles: [profile(jurisdictionId: "jurisdiction-north-ops", maxJoistSpanInches: 119)]
        )
        let request = DeckCodeProfileRequest(siteAddress: address(), jurisdictionId: nil)

        let resolution = resolver.resolve(request)

        XCTAssertEqual(resolution.status, .notConfigured)
        XCTAssertEqual(resolution.request, request)
        XCTAssertNil(resolution.profile)
        XCTAssertEqual(resolution.reasonToken, .notConfigured)
    }

    func testManualResolverReturnsUnavailableWithoutFabricatingFallbackRules() {
        let resolver = DeckManualCodeProfileResolver(
            profiles: [profile(jurisdictionId: "jurisdiction-north-ops", maxJoistSpanInches: 119)]
        )
        let request = DeckCodeProfileRequest(
            siteAddress: address(),
            jurisdictionId: "jurisdiction-south-ops"
        )

        let resolution = resolver.resolve(request)

        XCTAssertEqual(resolution.status, .unavailable)
        XCTAssertNil(resolution.profile)
        XCTAssertEqual(resolution.reasonToken, .unavailable)
    }

    func testManualResolverWithEmptyCatalogDoesNotCreateSyntheticCodeProfile() {
        let resolver = DeckManualCodeProfileResolver(profiles: [])
        let request = DeckCodeProfileRequest(
            siteAddress: address(),
            jurisdictionId: "jurisdiction-north-ops"
        )

        let resolution = resolver.resolve(request)

        XCTAssertEqual(resolution.status, .unavailable)
        XCTAssertNil(resolution.profile)
        XCTAssertEqual(resolution.reasonToken, .unavailable)
    }

    func testProfileRequestAndResolutionRoundTripCodable() throws {
        let profile = profile(jurisdictionId: "jurisdiction-north-ops", maxJoistSpanInches: 119)
        let request = DeckCodeProfileRequest(
            siteAddress: address(),
            jurisdictionId: "jurisdiction-north-ops"
        )
        let resolution = DeckManualCodeProfileResolver(profiles: [profile]).resolve(request)

        XCTAssertEqual(try roundTrip(request), request)
        XCTAssertEqual(try roundTrip(resolution), resolution)
    }

    private func address() -> DeckSiteAddress {
        DeckSiteAddress(
            addressLine1: "100 Example Ave",
            addressLine2: "Unit 4",
            locality: "North Ops",
            administrativeArea: "WA",
            postalCode: "98052",
            countryCode: "US"
        )
    }

    private func profile(jurisdictionId: String, maxJoistSpanInches: Double) -> DeckCodeProfile {
        DeckCodeProfile(
            id: "profile-\(jurisdictionId)",
            jurisdiction: DeckJurisdiction(id: jurisdictionId),
            source: DeckCodeProfileSource(profileSourceToken: "deck.code.source.testProfile"),
            rules: [
                DeckCodeRule(
                    id: "rule-joist-span",
                    token: "deck.code.rule.joistSpan.max",
                    scope: DeckCodeRuleScope(memberRole: .joist),
                    metric: .memberSpan,
                    limit: .maximumInches(maxJoistSpanInches),
                    severity: .violation,
                    citation: DeckCodeCitation(
                        authorityToken: "deck.code.authority.test",
                        sectionToken: "deck.code.section.joistSpan.test"
                    ),
                    annotationToken: DeckCodeAnnotationToken("deck.code.annotation.violation.memberInline"),
                    messageToken: DeckCodeMessageToken("deck.code.message.memberSpanExceeded")
                ),
            ]
        )
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
