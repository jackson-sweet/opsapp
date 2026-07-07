import XCTest
@testable import OPS

final class CalendarUserEventDTOTests: XCTestCase {
    func test_createDTO_encodesReviewerFieldsForApprovedTimeOff() throws {
        let dto = CreateCalendarUserEventDTO(
            userId: "crew-1",
            companyId: "company-1",
            type: "time_off",
            title: "Training day",
            startDate: "2026-07-10T00:00:00Z",
            endDate: "2026-07-10T00:00:00Z",
            allDay: true,
            notes: "Training day",
            status: "approved",
            reviewedBy: "admin-1",
            reviewedAt: "2026-07-07T18:44:42Z"
        )

        let data = try JSONEncoder().encode(dto)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["reviewed_by"] as? String, "admin-1")
        XCTAssertEqual(object["reviewed_at"] as? String, "2026-07-07T18:44:42Z")
    }
}
