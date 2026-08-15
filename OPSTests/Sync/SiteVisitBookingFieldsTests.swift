import SwiftData
import XCTest
@testable import OPS

/// Booking discriminator fields (`booked_at`, `reminder_lead_minutes`) are
/// server-owned: only the booking RPCs write them, the device merely converges.
/// These tests pin the additive wire contract and the merge semantics.
@MainActor
final class SiteVisitBookingFieldsTests: XCTestCase {
    private let visitId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let companyId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let opportunityId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    private let userId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"

    // MARK: - Wire decode

    func testVisitDTODecodesBookingFields() throws {
        let dto = try decodeVisit(extraFields: """
            ,"booked_at":"2026-08-11T17:00:00Z"
            ,"reminder_lead_minutes":45
            """)

        XCTAssertEqual(dto.bookedAt, isoDate("2026-08-11T17:00:00Z"))
        XCTAssertEqual(dto.reminderLeadMinutes, 45)
    }

    func testVisitDTODecodesLegacyRowsWithoutBookingFieldsAsNil() throws {
        let dto = try decodeVisit(extraFields: "")

        XCTAssertNil(dto.bookedAt)
        XCTAssertNil(dto.reminderLeadMinutes)
    }

    func testVisitDTODecodesExplicitNullBookingFieldsAsNil() throws {
        let dto = try decodeVisit(extraFields: """
            ,"booked_at":null
            ,"reminder_lead_minutes":null
            """)

        XCTAssertNil(dto.bookedAt)
        XCTAssertNil(dto.reminderLeadMinutes)
    }

    // MARK: - Model discriminator

    func testIsBookedAppointmentTracksBookedAtOnly() {
        let visit = SiteVisit(
            companyId: companyId,
            status: .scheduled,
            scheduledAt: Date(timeIntervalSince1970: 100),
            createdBy: userId
        )
        XCTAssertFalse(visit.isBookedAppointment)

        visit.bookedAt = Date(timeIntervalSince1970: 50)
        XCTAssertTrue(visit.isBookedAppointment)
    }

    // MARK: - Inbound merge

    func testMergeInsertsBookedVisitWithBookingFields() throws {
        let context = try makeContext()
        let dto = try decodeVisit(extraFields: """
            ,"booked_at":"2026-08-11T17:00:00Z"
            ,"reminder_lead_minutes":15
            """)

        let report = try SiteVisitServerMerge.merge(
            visit: dto,
            companyId: companyId,
            into: context
        )

        XCTAssertEqual(report.inserted, 1)
        let local = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisit>()).first)
        XCTAssertEqual(local.bookedAt, isoDate("2026-08-11T17:00:00Z"))
        XCTAssertEqual(local.reminderLeadMinutes, 15)
        XCTAssertTrue(local.isBookedAppointment)
    }

    func testMergeAppliesBookingFieldsEvenWhileLocalWorkIsPending() throws {
        let context = try makeContext()
        let local = SiteVisit(
            id: visitId,
            opportunityId: opportunityId,
            companyId: companyId,
            status: .scheduled,
            scheduledAt: Date(timeIntervalSince1970: 1),
            createdBy: userId
        )
        local.notes = "Local unsent note"
        local.needsSync = true
        context.insert(local)
        context.insert(
            SyncOperation(
                entityType: "siteVisit",
                entityId: visitId,
                operationType: "update",
                payload: Data(),
                changedFields: ["notes"]
            )
        )
        try context.save()

        let dto = try decodeVisit(extraFields: """
            ,"booked_at":"2026-08-11T17:00:00Z"
            ,"reminder_lead_minutes":60
            ,"notes":"Stale server note"
            """)
        let report = try SiteVisitServerMerge.merge(
            visit: dto,
            companyId: companyId,
            into: context
        )

        XCTAssertEqual(report.updated, 1)
        // Local field protection still holds for locally-authored fields...
        XCTAssertEqual(local.notes, "Local unsent note")
        // ...while server-owned booking state converges regardless.
        XCTAssertEqual(local.bookedAt, isoDate("2026-08-11T17:00:00Z"))
        XCTAssertEqual(local.reminderLeadMinutes, 60)
    }

    func testStaleEchoCannotRevertBookingFields() throws {
        let context = try makeContext()
        let booked = try decodeVisit(extraFields: """
            ,"booked_at":"2026-08-11T17:00:00Z"
            ,"reminder_lead_minutes":30
            ,"updated_at":"2026-08-11T17:05:00Z"
            """)
        _ = try SiteVisitServerMerge.merge(visit: booked, companyId: companyId, into: context)

        // Pre-booking echo: no booking fields, older updated_at.
        let stale = try decodeVisit(extraFields: """
            ,"updated_at":"2026-08-11T16:00:00Z"
            """)
        _ = try SiteVisitServerMerge.merge(visit: stale, companyId: companyId, into: context)

        let local = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisit>()).first)
        XCTAssertEqual(local.bookedAt, isoDate("2026-08-11T17:00:00Z"))
        XCTAssertEqual(local.reminderLeadMinutes, 30)
    }

    func testRedundantBookedEchoResolvesUnchanged() throws {
        let context = try makeContext()
        let dto = try decodeVisit(extraFields: """
            ,"booked_at":"2026-08-11T17:00:00Z"
            ,"reminder_lead_minutes":30
            """)
        _ = try SiteVisitServerMerge.merge(visit: dto, companyId: companyId, into: context)

        let report = try SiteVisitServerMerge.merge(
            visit: dto,
            companyId: companyId,
            into: context
        )

        XCTAssertEqual(report.unchanged, 1)
        XCTAssertEqual(report.updated, 0)
    }

    func testReminderOverrideClearedByServerLandsLocally() throws {
        let context = try makeContext()
        let withOverride = try decodeVisit(extraFields: """
            ,"booked_at":"2026-08-11T17:00:00Z"
            ,"reminder_lead_minutes":30
            ,"updated_at":"2026-08-11T17:05:00Z"
            """)
        _ = try SiteVisitServerMerge.merge(visit: withOverride, companyId: companyId, into: context)

        // Reschedule cleared the override (p_reminder_lead_minutes = -1 server-side).
        let cleared = try decodeVisit(extraFields: """
            ,"booked_at":"2026-08-11T17:00:00Z"
            ,"updated_at":"2026-08-11T17:10:00Z"
            """)
        _ = try SiteVisitServerMerge.merge(visit: cleared, companyId: companyId, into: context)

        let local = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisit>()).first)
        XCTAssertEqual(local.bookedAt, isoDate("2026-08-11T17:00:00Z"))
        XCTAssertNil(local.reminderLeadMinutes)
    }

    // MARK: - Outbound contract: the device never writes booking state

    func testCreatePayloadOmitsBookingColumns() throws {
        let model = SiteVisit(
            id: visitId,
            opportunityId: opportunityId,
            companyId: companyId,
            status: .scheduled,
            scheduledAt: Date(timeIntervalSince1970: 100),
            createdBy: userId
        )
        model.bookedAt = Date(timeIntervalSince1970: 50)
        model.reminderLeadMinutes = 30

        let payload = try CreateSiteVisitDTO(model: model)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(payload)
            ) as? [String: Any]
        )

        XCTAssertNil(json["booked_at"], "walk-up create must never carry booking state")
        XCTAssertNil(json["reminder_lead_minutes"], "walk-up create must never carry booking state")
    }

    func testUpdatePayloadRejectsBookingColumns() {
        XCTAssertThrowsError(
            try SiteVisitUpdateDTO(values: ["booked_at": .string("2026-08-11T17:00:00Z")])
        ) { error in
            XCTAssertEqual(
                error as? SiteVisitPayloadError,
                .unsupportedUpdateField("booked_at")
            )
        }
        XCTAssertThrowsError(
            try SiteVisitUpdateDTO(values: ["reminder_lead_minutes": .integer(30)])
        ) { error in
            XCTAssertEqual(
                error as? SiteVisitPayloadError,
                .unsupportedUpdateField("reminder_lead_minutes")
            )
        }
    }

    // MARK: - Helpers

    private func decodeVisit(extraFields: String) throws -> SiteVisitDTO {
        let data = Data("""
        {
          "id":"\(visitId)",
          "company_id":"\(companyId)",
          "opportunity_id":"\(opportunityId)",
          "scheduled_at":"2026-08-11T17:00:00Z",
          "status":"scheduled",
          "created_by":"\(userId)"
          \(extraFields)
        }
        """.utf8)
        return try JSONDecoder().decode(SiteVisitDTO.self, from: data)
    }

    private func isoDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            SyncOperation.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContext(ModelContainer(for: schema, configurations: [configuration]))
    }
}
