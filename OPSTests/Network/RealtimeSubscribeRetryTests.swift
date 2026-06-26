//
//  RealtimeSubscribeRetryTests.swift
//  OPSTests
//
//  Locks the capped exponential backoff used to self-heal a Realtime channel
//  join that fails while the socket is still up.
//
//  Context (reschedule-not-live investigation, 2026-06-24): a transient
//  server-side failure (a Supabase Realtime infra-migration window crashed
//  `create_subscription` tenant-wide) made `subscribeWithError()` throw
//  "Maximum retry attempts reached". The old catch block gave up forever, so
//  realtime stayed dead until the next foreground. RealtimeProcessor now
//  re-attempts with this backoff so it recovers without user intervention.
//

import XCTest
@testable import OPS

final class RealtimeSubscribeRetryTests: XCTestCase {

    func testBackoffDoublesFromFiveSeconds() {
        XCTAssertEqual(RealtimeProcessor.subscribeRetryDelay(attempt: 1), 5)
        XCTAssertEqual(RealtimeProcessor.subscribeRetryDelay(attempt: 2), 10)
        XCTAssertEqual(RealtimeProcessor.subscribeRetryDelay(attempt: 3), 20)
        XCTAssertEqual(RealtimeProcessor.subscribeRetryDelay(attempt: 4), 40)
    }

    func testBackoffClampsAtSixtySeconds() {
        XCTAssertEqual(RealtimeProcessor.subscribeRetryDelay(attempt: 5), 60)
        XCTAssertEqual(RealtimeProcessor.subscribeRetryDelay(attempt: 6), 60)
        XCTAssertEqual(RealtimeProcessor.subscribeRetryDelay(attempt: 50), 60)
    }

    func testBackoffNeverNegativeOrZeroForValidAttempts() {
        // Defensive: an unexpected non-positive attempt must not produce a
        // zero/negative sleep that would hot-loop the retry.
        XCTAssertEqual(RealtimeProcessor.subscribeRetryDelay(attempt: 0), 5)
        XCTAssertGreaterThanOrEqual(RealtimeProcessor.subscribeRetryDelay(attempt: 1), 5)
    }

    func testRealtimeTopicMatchesSupabaseCachedChannelKey() {
        XCTAssertEqual(
            RealtimeProcessor.realtimeTopic(forChannelName: "company-ddee107c"),
            "realtime:company-ddee107c"
        )
    }

    func testSupabaseRoleClaimDetectionRequiresAuthenticatedRole() throws {
        let authenticatedToken = try makeUnsignedJWT(
            claims: ["sub": "firebase-uid", "role": "authenticated"]
        )
        let missingRoleToken = try makeUnsignedJWT(
            claims: ["sub": "firebase-uid"]
        )
        let anonRoleToken = try makeUnsignedJWT(
            claims: ["sub": "firebase-uid", "role": "anon"]
        )

        XCTAssertEqual(RealtimeProcessor.jwtSupabaseRole(authenticatedToken), "authenticated")
        XCTAssertTrue(RealtimeProcessor.hasAuthenticatedSupabaseRole(authenticatedToken))
        XCTAssertNil(RealtimeProcessor.jwtSupabaseRole(missingRoleToken))
        XCTAssertFalse(RealtimeProcessor.hasAuthenticatedSupabaseRole(missingRoleToken))
        XCTAssertEqual(RealtimeProcessor.jwtSupabaseRole(anonRoleToken), "anon")
        XCTAssertFalse(RealtimeProcessor.hasAuthenticatedSupabaseRole(anonRoleToken))
    }

    private func makeUnsignedJWT(claims: [String: Any]) throws -> String {
        let header = ["alg": "none", "typ": "JWT"]
        return try [
            base64URLEncodedJSON(header),
            base64URLEncodedJSON(claims),
            "signature"
        ].joined(separator: ".")
    }

    private func base64URLEncodedJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
