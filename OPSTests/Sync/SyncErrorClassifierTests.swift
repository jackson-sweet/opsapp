//
//  SyncErrorClassifierTests.swift
//  OPSTests
//
//  Table-driven coverage for SyncErrorClassifier.disposition(for:) — every row of
//  the SYNC RECOVERY spec §3 disposition table, built from REAL supabase-swift
//  error values (PostgrestError / HTTPError), Foundation URLErrors, our own
//  SyncError wrappers, and wrapped-unknown NSErrors that only surface a message.
//

import XCTest
import Supabase
@testable import OPS

final class SyncErrorClassifierTests: XCTestCase {

    // MARK: - Helpers

    private func postgrest(code: String?, message: String = "boom") -> PostgrestError {
        PostgrestError(detail: nil, hint: nil, code: code, message: message)
    }

    private func http(_ statusCode: Int) -> HTTPError {
        let response = HTTPURLResponse(
            url: URL(string: "https://ijeekuhbatykdomumfjx.supabase.co/rest/v1/opportunities")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return HTTPError(data: Data("{}".utf8), response: response)
    }

    /// A wrapped error that only exposes its detail through `localizedDescription`
    /// (the way re-thrown Postgres errors often reach the catch site).
    private func wrapped(_ description: String) -> NSError {
        NSError(domain: "OPS.Test", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }

    // MARK: - URLError

    func testURLErrorNetworkCodesAreTransient() {
        let transientCodes: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .timedOut,
            .cannotConnectToHost, .dataNotAllowed
        ]
        for code in transientCodes {
            XCTAssertEqual(
                SyncErrorClassifier.disposition(for: URLError(code)),
                .transient,
                "URLError \(code) should be transient"
            )
        }
    }

    func testURLErrorUserAuthenticationRequiredIsAuth() {
        XCTAssertEqual(
            SyncErrorClassifier.disposition(for: URLError(.userAuthenticationRequired)),
            .auth
        )
    }

    func testURLErrorUnknownCodeDefaultsTransient() {
        // Anything network-layer we don't explicitly name is retry-safe.
        for code in [URLError.Code.badServerResponse, .badURL, .cannotParseResponse] {
            XCTAssertEqual(
                SyncErrorClassifier.disposition(for: URLError(code)),
                .transient,
                "URLError \(code) should default transient"
            )
        }
    }

    // MARK: - PostgrestError — transient SQLSTATEs (the outage class)

    func testPostgrestTransientSQLStates() {
        for code in ["40001", "40P01", "55P03", "57014"] {
            XCTAssertEqual(
                SyncErrorClassifier.disposition(for: postgrest(code: code)),
                .transient,
                "SQLSTATE \(code) should be transient"
            )
        }
    }

    // MARK: - PostgrestError — permanent SQLSTATE classes

    func testPostgrestPermanentSQLClasses() {
        let permanentCodes = [
            "22023", "22P02", "22001", "22003", // 22 data_exception
            "23505", "23503", "23514", "23502", // 23 integrity_constraint_violation
            "42501", "42703", "42P01",          // 42 access/syntax (incl. RLS 42501)
            "P0001", "P0002"                    // deliberate SECURITY DEFINER raises
        ]
        for code in permanentCodes {
            XCTAssertEqual(
                SyncErrorClassifier.disposition(for: postgrest(code: code)),
                .permanent,
                "SQLSTATE \(code) should be permanent"
            )
        }
    }

    /// The RC1 outage error (`unsupported_opportunity_field`, errcode 22023) — the
    /// exact rejection that spun 400s forever. Must park, not retry.
    func testPostgrestRC1UnsupportedFieldIsPermanent() {
        let error = postgrest(code: "22023", message: "unsupported_opportunity_field: source_thread_key")
        XCTAssertEqual(SyncErrorClassifier.disposition(for: error), .permanent)
    }

    // MARK: - PostgrestError — auth (PGRST3xx)

    func testPostgrestJWTCodesAreAuth() {
        for code in ["PGRST301", "PGRST302", "PGRST303"] {
            XCTAssertEqual(
                SyncErrorClassifier.disposition(for: postgrest(code: code)),
                .auth,
                "PostgREST \(code) should be auth"
            )
        }
    }

    // MARK: - PostgrestError — unknown code falls through to message / transient

    func testPostgrestUnknownCodeDefaultsTransient() {
        // PGRST1xx (API request) / PGRST2xx (schema cache) aren't in a bucket and
        // the message carries no signal → transient (never park on a guess).
        for code in ["PGRST116", "PGRST204"] {
            XCTAssertEqual(
                SyncErrorClassifier.disposition(for: postgrest(code: code, message: "no rows")),
                .transient,
                "PostgREST \(code) with neutral message should be transient"
            )
        }
    }

    func testPostgrestNilAndEmptyCodeUseMessageHeuristics() {
        XCTAssertEqual(
            SyncErrorClassifier.disposition(for: postgrest(code: nil, message: "JWT expired")),
            .auth
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(for: postgrest(code: "", message: "could not serialize access due to concurrent update")),
            .transient
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(for: postgrest(code: nil, message: "something totally novel")),
            .transient
        )
    }

    /// Guard against the "401" substring inside "40001" misrouting a serialization
    /// failure to auth. The typed path must win and return transient.
    func testTransientCodeNotMisreadAsAuth() {
        XCTAssertEqual(SyncErrorClassifier.disposition(for: postgrest(code: "40001")), .transient)
        // And the pure string layer agrees.
        XCTAssertEqual(SyncErrorClassifier.stringDisposition(for: "40001"), .transient)
    }

    // MARK: - HTTPError status

    func testHTTPTransientStatuses() {
        for status in [500, 502, 503, 504, 429, 408] {
            XCTAssertEqual(
                SyncErrorClassifier.disposition(for: http(status)),
                .transient,
                "HTTP \(status) should be transient"
            )
        }
    }

    func testHTTPAuthStatus() {
        XCTAssertEqual(SyncErrorClassifier.disposition(for: http(401)), .auth)
    }

    func testHTTPPermanentStatuses() {
        for status in [400, 403, 404, 409, 422] {
            XCTAssertEqual(
                SyncErrorClassifier.disposition(for: http(status)),
                .permanent,
                "HTTP \(status) should be permanent"
            )
        }
    }

    // MARK: - SyncError wrappers

    func testSyncErrorAuthCases() {
        for error: SyncError in [.authExpired, .unauthorized, .missingUserId, .missingCompanyId] {
            XCTAssertEqual(SyncErrorClassifier.disposition(for: error), .auth)
        }
    }

    func testSyncErrorServerErrorMapsByStatus() {
        XCTAssertEqual(SyncErrorClassifier.disposition(for: SyncError.serverError(statusCode: 503, message: "x")), .transient)
        XCTAssertEqual(SyncErrorClassifier.disposition(for: SyncError.serverError(statusCode: 400, message: "x")), .permanent)
        XCTAssertEqual(SyncErrorClassifier.disposition(for: SyncError.serverError(statusCode: 401, message: "x")), .auth)
    }

    func testSyncErrorTransientAndEncodingCases() {
        XCTAssertEqual(SyncErrorClassifier.disposition(for: SyncError.networkUnavailable), .transient)
        XCTAssertEqual(SyncErrorClassifier.disposition(for: SyncError.timeout), .transient)
        // Deterministic client-side failure → permanent.
        XCTAssertEqual(SyncErrorClassifier.disposition(for: SyncError.encodingFailed(detail: "bad")), .permanent)
    }

    func testSyncErrorApiErrorRecursesIntoUnderlying() {
        // .apiError / .unknown unwrap to the real transport error.
        XCTAssertEqual(
            SyncErrorClassifier.disposition(for: SyncError.apiError(postgrest(code: "23505"))),
            .permanent
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(for: SyncError.unknown(underlying: URLError(.timedOut))),
            .transient
        )
    }

    // MARK: - Wrapped unknown (localizedDescription only)

    func testWrappedStringAuthSignals() {
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("JWT expired")), .auth)
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("PostgREST error PGRST301")), .auth)
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("HTTP 401 Unauthorized")), .auth)
    }

    func testWrappedStringTransientSignals() {
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("ERROR: could not serialize access due to concurrent update")), .transient)
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("deadlock detected")), .transient)
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("SQLSTATE 40001")), .transient)
    }

    func testWrappedStringPermanentSignals() {
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("insert or update on table violates foreign key constraint")), .permanent)
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("new row violates check constraint \"chk\"")), .permanent)
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("null value violates not-null constraint")), .permanent)
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("duplicate key value violates unique constraint \"clients_email_key\"")), .permanent)
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("invalid input syntax for type uuid")), .permanent)
    }

    func testWrappedUnknownDefaultsTransient() {
        // No signal anywhere → transient. Never park on a guess.
        XCTAssertEqual(SyncErrorClassifier.disposition(for: wrapped("mysterious backend hiccup")), .transient)
        XCTAssertNil(SyncErrorClassifier.stringDisposition(for: "mysterious backend hiccup"))
    }
}
