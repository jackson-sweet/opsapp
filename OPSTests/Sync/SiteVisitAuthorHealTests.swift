//
//  SiteVisitAuthorHealTests.swift
//  OPSTests
//
//  Author resolution for site-visit rows the V19→V20 lightweight migration left
//  holding a nil `createdBy`. Pure precedence and canonicalization only — the
//  outbound sync boundary owns persistence, the DTO layer owns UUID validation.
//

import XCTest
@testable import OPS

final class SiteVisitAuthorHealTests: XCTestCase {

    private let rowAuthor = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    private let visitAuthor = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let sessionAuthor = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

    // MARK: - Precedence

    func test_ownAuthorWinsOverParentAndSession() {
        XCTAssertEqual(
            SiteVisitAuthorHeal.resolvedAuthor(
                current: rowAuthor,
                parentVisitAuthor: visitAuthor,
                sessionUserId: sessionAuthor
            ),
            rowAuthor.lowercased()
        )
    }

    func test_blankOwnAuthorFallsThroughToParentVisitAuthor() {
        for blank in [nil, "", "   ", "\n", " \t\n "] as [String?] {
            XCTAssertEqual(
                SiteVisitAuthorHeal.resolvedAuthor(
                    current: blank,
                    parentVisitAuthor: visitAuthor,
                    sessionUserId: sessionAuthor
                ),
                visitAuthor,
                "own author \(String(describing: blank)) should not count as usable"
            )
        }
    }

    func test_blankParentAuthorFallsThroughToSessionUser() {
        for blank in [nil, "", "  ", "\n"] as [String?] {
            XCTAssertEqual(
                SiteVisitAuthorHeal.resolvedAuthor(
                    current: nil,
                    parentVisitAuthor: blank,
                    sessionUserId: sessionAuthor
                ),
                sessionAuthor,
                "parent author \(String(describing: blank)) should not count as usable"
            )
        }
    }

    func test_noUsableCandidateResolvesToNil() {
        XCTAssertNil(
            SiteVisitAuthorHeal.resolvedAuthor(
                current: nil,
                parentVisitAuthor: nil,
                sessionUserId: nil
            )
        )
        XCTAssertNil(
            SiteVisitAuthorHeal.resolvedAuthor(
                current: "  ",
                parentVisitAuthor: "",
                sessionUserId: "\n\t"
            )
        )
    }

    // MARK: - Canonicalization

    func test_resolvedAuthorIsTrimmedAndLowercased() {
        XCTAssertEqual(
            SiteVisitAuthorHeal.resolvedAuthor(
                current: "  \(rowAuthor)\n",
                parentVisitAuthor: nil,
                sessionUserId: nil
            ),
            rowAuthor.lowercased()
        )
        XCTAssertEqual(
            SiteVisitAuthorHeal.resolvedAuthor(
                current: nil,
                parentVisitAuthor: " \(visitAuthor.uppercased()) ",
                sessionUserId: nil
            ),
            visitAuthor
        )
    }

    /// UUID validation belongs to the DTO layer (`SiteVisitWire.payloadUUID`), so a
    /// malformed author still resolves here and surfaces as a payload error rather
    /// than being silently dropped into an unresolvable row.
    func test_malformedAuthorStillResolvesForTheDTOLayerToReject() {
        XCTAssertEqual(
            SiteVisitAuthorHeal.resolvedAuthor(
                current: " Not-A-UUID ",
                parentVisitAuthor: visitAuthor,
                sessionUserId: sessionAuthor
            ),
            "not-a-uuid"
        )
    }

    // MARK: - Session user

    func test_sessionUserIdReadsCanonicalizedDefaultsValue() {
        withDefaults { defaults in
            defaults.set("  \(sessionAuthor.uppercased()) ", forKey: "currentUserId")
            XCTAssertEqual(
                SiteVisitAuthorHeal.sessionUserId(defaults: defaults),
                sessionAuthor
            )
        }
    }

    func test_sessionUserIdIsNilWhenAbsentOrBlank() {
        withDefaults { defaults in
            XCTAssertNil(SiteVisitAuthorHeal.sessionUserId(defaults: defaults))
            defaults.set("   ", forKey: "currentUserId")
            XCTAssertNil(SiteVisitAuthorHeal.sessionUserId(defaults: defaults))
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "SiteVisitAuthorHealTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Could not open an isolated defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
