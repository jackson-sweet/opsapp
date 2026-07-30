//
//  ActivitySiteVisitLinkTests.swift
//  OPSTests
//
//  `activities.site_visit_id` is written by this app and was then thrown away
//  on the way back in — the same failure the per-message email identity had
//  (bug 183f7ec9). A completed site visit therefore arrived on the lead's
//  timeline as an unremarkable row with no route back to what the visit
//  captured, even though the link had been sitting in the payload all along.
//
//  The WRITE half is already pinned by
//  `ActivityRepositoryTests.test_passThroughFields_preserved`. These pin the
//  read back — the half that was missing.
//

import XCTest
@testable import OPS

final class ActivitySiteVisitLinkTests: XCTestCase {

    func test_decodesTheSiteVisitLinkOntoTheModel() throws {
        let activity = try model(from: """
        {
          "id": "act-1",
          "opportunity_id": "lead-1",
          "company_id": "company-1",
          "type": "site_visit",
          "subject": "Site visit",
          "body_text": "2 photos, 1 measurement",
          "site_visit_id": "visit-77",
          "created_at": "2026-05-28T20:26:00+00:00"
        }
        """)
        XCTAssertEqual(activity.siteVisitId, "visit-77")
        XCTAssertEqual(activity.type, .siteVisit)
    }

    /// Every note, call, and email — plus every row written before the column
    /// existed — carries no link, and must decode to nil rather than failing.
    func test_aRowWithoutTheLinkDecodesToNil() throws {
        let activity = try model(from: """
        {
          "id": "act-2",
          "opportunity_id": "lead-1",
          "company_id": "company-1",
          "type": "note",
          "body_text": "Left a voicemail",
          "created_at": "2026-05-28T20:26:00+00:00"
        }
        """)
        XCTAssertNil(activity.siteVisitId)
    }

    func test_anExplicitNullLinkDecodesToNil() throws {
        let activity = try model(from: """
        {
          "id": "act-3",
          "opportunity_id": "lead-1",
          "company_id": "company-1",
          "type": "note",
          "site_visit_id": null,
          "created_at": "2026-05-28T20:26:00+00:00"
        }
        """)
        XCTAssertNil(activity.siteVisitId)
    }

    // MARK: - Harness

    private func model(from json: String) throws -> Activity {
        let dto = try JSONDecoder().decode(ActivityDTO.self, from: Data(json.utf8))
        return dto.toModel()
    }
}
