import XCTest
import Supabase
@testable import OPS

/// The booking service is the app's ONLY write path for appointments — thin
/// wrappers over the three server RPCs. These tests pin the wire contract
/// (function names, param spelling, nil-omission semantics, the -1 clear
/// sentinel) and the user-presentable error mapping.
final class SiteVisitBookingServiceTests: XCTestCase {
    private let opportunityId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    private let visitId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let assigneeA = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    private let assigneeB = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"

    // MARK: - book_site_visit

    func testBookSendsFullParamsAndReturnsVisitId() async throws {
        let transport = RecordingBookingTransport()
        transport.response = Data("\"\(visitId.uppercased())\"".utf8)
        let service = SiteVisitBookingService(transport: transport)
        let when = Date(timeIntervalSince1970: 1_790_000_000)

        let id = try await service.book(
            opportunityId: opportunityId.uppercased(),
            scheduledAt: when,
            durationMinutes: 90,
            assigneeIds: [assigneeA.uppercased(), assigneeB],
            reminderLeadMinutes: 45
        )

        XCTAssertEqual(id, visitId)
        XCTAssertEqual(transport.requests.count, 1)
        guard case let .book(params) = transport.requests[0] else {
            return XCTFail("Expected a book request, got \(transport.requests[0])")
        }
        XCTAssertEqual(params.p_opportunity_id, opportunityId)
        XCTAssertEqual(params.p_scheduled_at, SupabaseDate.format(when))
        XCTAssertEqual(params.p_duration_minutes, 90)
        XCTAssertEqual(params.p_assignee_ids, [assigneeA, assigneeB])
        XCTAssertEqual(params.p_reminder_lead_minutes, 45)
    }

    func testBookOmitsDefaultedParamsFromWirePayload() async throws {
        let transport = RecordingBookingTransport()
        transport.response = Data("\"\(visitId)\"".utf8)
        let service = SiteVisitBookingService(transport: transport)

        _ = try await service.book(
            opportunityId: opportunityId,
            scheduledAt: Date(timeIntervalSince1970: 1_790_000_000)
        )

        guard case let .book(params) = transport.requests[0] else {
            return XCTFail("Expected a book request")
        }
        XCTAssertEqual(params.p_duration_minutes, 60)
        XCTAssertNil(params.p_assignee_ids)
        XCTAssertNil(params.p_reminder_lead_minutes)
        // Absent — not null — so the server defaults apply (assignees = booker).
        let json = try encodedKeys(of: params)
        XCTAssertFalse(json.contains("p_assignee_ids"))
        XCTAssertFalse(json.contains("p_reminder_lead_minutes"))
    }

    // MARK: - reschedule_site_visit

    func testRescheduleKeepsUnchangedFieldsByOmission() async throws {
        let transport = RecordingBookingTransport()
        transport.response = Data("\"\(visitId)\"".utf8)
        let service = SiteVisitBookingService(transport: transport)
        let newTime = Date(timeIntervalSince1970: 1_790_100_000)

        _ = try await service.reschedule(
            siteVisitId: visitId.uppercased(),
            scheduledAt: newTime
        )

        guard case let .reschedule(params) = transport.requests[0] else {
            return XCTFail("Expected a reschedule request")
        }
        XCTAssertEqual(params.p_site_visit_id, visitId)
        XCTAssertEqual(params.p_scheduled_at, SupabaseDate.format(newTime))
        let keys = try encodedKeys(of: params)
        XCTAssertFalse(keys.contains("p_duration_minutes"), "NULL keeps the current value server-side")
        XCTAssertFalse(keys.contains("p_assignee_ids"))
        XCTAssertFalse(keys.contains("p_reminder_lead_minutes"))
    }

    func testRescheduleClearSendsMinusOneSentinel() async throws {
        let transport = RecordingBookingTransport()
        transport.response = Data("\"\(visitId)\"".utf8)
        let service = SiteVisitBookingService(transport: transport)

        _ = try await service.reschedule(
            siteVisitId: visitId,
            reminderOverride: .clear
        )

        guard case let .reschedule(params) = transport.requests[0] else {
            return XCTFail("Expected a reschedule request")
        }
        XCTAssertEqual(params.p_reminder_lead_minutes, -1)
    }

    func testRescheduleSetSendsOverrideValue() async throws {
        let transport = RecordingBookingTransport()
        transport.response = Data("\"\(visitId)\"".utf8)
        let service = SiteVisitBookingService(transport: transport)

        _ = try await service.reschedule(
            siteVisitId: visitId,
            durationMinutes: 120,
            assigneeIds: [assigneeA],
            reminderOverride: .set(15)
        )

        guard case let .reschedule(params) = transport.requests[0] else {
            return XCTFail("Expected a reschedule request")
        }
        XCTAssertEqual(params.p_duration_minutes, 120)
        XCTAssertEqual(params.p_assignee_ids, [assigneeA])
        XCTAssertEqual(params.p_reminder_lead_minutes, 15)
    }

    // MARK: - cancel_site_visit_booking

    func testCancelSendsVisitIdAndReturnsIt() async throws {
        let transport = RecordingBookingTransport()
        transport.response = Data("\"\(visitId)\"".utf8)
        let service = SiteVisitBookingService(transport: transport)

        let id = try await service.cancel(siteVisitId: visitId.uppercased())

        XCTAssertEqual(id, visitId)
        guard case let .cancel(params) = transport.requests[0] else {
            return XCTFail("Expected a cancel request")
        }
        XCTAssertEqual(params.p_site_visit_id, visitId)
    }

    // MARK: - RPC names (the live transport dials by these)

    func testRequestFunctionNamesMatchServerRPCs() {
        XCTAssertEqual(
            SiteVisitBookingRequest.book(
                BookSiteVisitRPCParams(
                    p_opportunity_id: opportunityId,
                    p_scheduled_at: "2026-08-11T17:00:00Z",
                    p_duration_minutes: 60,
                    p_assignee_ids: nil,
                    p_reminder_lead_minutes: nil
                )
            ).functionName,
            "book_site_visit"
        )
        XCTAssertEqual(
            SiteVisitBookingRequest.reschedule(
                RescheduleSiteVisitRPCParams(
                    p_site_visit_id: visitId,
                    p_scheduled_at: nil,
                    p_duration_minutes: nil,
                    p_assignee_ids: nil,
                    p_reminder_lead_minutes: nil
                )
            ).functionName,
            "reschedule_site_visit"
        )
        XCTAssertEqual(
            SiteVisitBookingRequest.cancel(
                CancelSiteVisitBookingRPCParams(p_site_visit_id: visitId)
            ).functionName,
            "cancel_site_visit_booking"
        )
    }

    // MARK: - Error mapping

    func testMapsServerErrorCodesToPresentableCases() async {
        await assertBookFails(
            throwing: PostgrestError(code: "42501", message: "permission denied"),
            expecting: .permissionDenied
        )
        await assertBookFails(
            throwing: PostgrestError(code: "55000", message: "site_visit_already_booked"),
            expecting: .bookingConflict
        )
        await assertBookFails(
            throwing: PostgrestError(code: "22023", message: "duration out of bounds"),
            expecting: .validation(detail: "duration out of bounds")
        )
        await assertBookFails(
            throwing: PostgrestError(code: "P0002", message: "opportunity not found"),
            expecting: .notFound
        )
    }

    func testMapsConnectivityFailuresToOffline() async {
        await assertBookFails(
            throwing: URLError(.notConnectedToInternet),
            expecting: .offline
        )
        await assertBookFails(
            throwing: URLError(.networkConnectionLost),
            expecting: .offline
        )
        await assertBookFails(
            throwing: URLError(.timedOut),
            expecting: .offline
        )
    }

    func testMapsUnknownFailuresToServerCase() async {
        struct Mystery: Error {}
        let transport = RecordingBookingTransport()
        transport.error = Mystery()
        let service = SiteVisitBookingService(transport: transport)
        do {
            _ = try await service.cancel(siteVisitId: visitId)
            XCTFail("Expected a thrown error")
        } catch let error as SiteVisitBookingError {
            guard case .server = error else {
                return XCTFail("Expected .server, got \(error)")
            }
        } catch {
            XCTFail("Expected SiteVisitBookingError, got \(error)")
        }
    }

    func testMalformedResponseMapsToServerCase() async {
        let transport = RecordingBookingTransport()
        transport.response = Data("not-json".utf8)
        let service = SiteVisitBookingService(transport: transport)
        do {
            _ = try await service.book(
                opportunityId: opportunityId,
                scheduledAt: Date(timeIntervalSince1970: 1_790_000_000)
            )
            XCTFail("Expected a thrown error")
        } catch let error as SiteVisitBookingError {
            guard case .server = error else {
                return XCTFail("Expected .server, got \(error)")
            }
        } catch {
            XCTFail("Expected SiteVisitBookingError, got \(error)")
        }
    }

    // MARK: - Presentable copy (locked)

    func testErrorCopyStaysTerseAndActionable() {
        XCTAssertEqual(
            SiteVisitBookingError.offline.errorDescription,
            "No connection. Try again when you have signal."
        )
        XCTAssertEqual(
            SiteVisitBookingError.permissionDenied.errorDescription,
            "You don't have permission to manage site visits."
        )
        XCTAssertEqual(
            SiteVisitBookingError.bookingConflict.errorDescription,
            "This lead already has a visit booked."
        )
        XCTAssertEqual(
            SiteVisitBookingError.validation(detail: "x").errorDescription,
            "That didn't go through. Check the time and try again."
        )
        XCTAssertEqual(
            SiteVisitBookingError.notFound.errorDescription,
            "Visit not found. It may have been cancelled on another device."
        )
        XCTAssertEqual(
            SiteVisitBookingError.server(detail: "x").errorDescription,
            "Server error. Try again."
        )
    }

    // MARK: - Helpers

    private func assertBookFails(
        throwing underlying: Error,
        expecting expected: SiteVisitBookingError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let transport = RecordingBookingTransport()
        transport.error = underlying
        let service = SiteVisitBookingService(transport: transport)
        do {
            _ = try await service.book(
                opportunityId: opportunityId,
                scheduledAt: Date(timeIntervalSince1970: 1_790_000_000)
            )
            XCTFail("Expected a thrown error", file: file, line: line)
        } catch let error as SiteVisitBookingError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected SiteVisitBookingError, got \(error)", file: file, line: line)
        }
    }

    private func encodedKeys<T: Encodable>(of params: T) throws -> Set<String> {
        let data = try JSONEncoder().encode(params)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }
}

// MARK: - Recording transport

private final class RecordingBookingTransport: SiteVisitBookingTransport {
    var requests: [SiteVisitBookingRequest] = []
    var response = Data()
    var error: Error?

    func send(_ request: SiteVisitBookingRequest) async throws -> Data {
        requests.append(request)
        if let error { throw error }
        return response
    }
}
