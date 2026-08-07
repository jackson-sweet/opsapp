//
//  SiteVisitRecordLocalCaptureTests.swift
//  OPSTests
//
//  A lead's timeline cannot read a visit's synced packet — the packet is only
//  written when the visit is handed off to a job, and most visits happen before
//  the lead is a job at all. So the lead-side record assembles from the local
//  capture instead, through the SAME payload + packet builders the handoff
//  uses, so one visit reads identically before and after conversion.
//
//  Two properties matter most and are pinned here:
//
//   - the money still comes from the local opportunity behind `finances.view`,
//     exactly as on the project surface; and
//   - a visit that captured nothing returns NO record, so the caller keeps its
//     plain activity row instead of rendering an empty card.
//

import XCTest
@testable import OPS

final class SiteVisitRecordLocalCaptureTests: XCTestCase {

    private let visitId = "visit-1"

    private func visit(address: String? = "1100 Maple Ave") -> SiteVisit {
        let v = SiteVisit(id: visitId, opportunityId: "lead-1", companyId: "company-1")
        v.address = address
        return v
    }

    private func opportunity(estimatedValue: Double? = nil) -> Opportunity {
        let o = Opportunity(
            id: "lead-1",
            companyId: "company-1",
            contactName: "Helen Calloway",
            stage: .quoting
        )
        o.estimatedValue = estimatedValue
        return o
    }

    private func artifact(
        kind: SiteVisitCaptureArtifactKind,
        title: String? = nil,
        body: String? = nil,
        localAssetURL: String? = nil,
        capturedAt: TimeInterval = 1_000
    ) -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            siteVisitId: visitId,
            companyId: "company-1",
            kind: kind,
            source: .camera,
            title: title,
            body: body,
            localAssetURL: localAssetURL,
            capturedAt: Date(timeIntervalSince1970: capturedAt)
        )
    }

    private func record(
        artifacts: [SiteVisitCaptureArtifact],
        checklistAnswers: [SiteVisitChecklistAnswer] = [],
        identity: SiteVisitIdentityDraft? = nil,
        opportunity: Opportunity? = nil,
        canViewFinancials: Bool = true
    ) -> SiteVisitRecord? {
        SiteVisitRecord.assembleFromLocalCapture(
            visit: visit(),
            artifacts: artifacts,
            checklistAnswers: checklistAnswers,
            identity: identity,
            opportunity: opportunity,
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000),
            operatorName: "Dale Harmon",
            canViewFinancials: canViewFinancials
        )
    }

    // MARK: - Nothing captured means no record

    func test_noRecord_whenTheVisitCapturedNothing() {
        XCTAssertNil(
            record(artifacts: []),
            "An empty visit must produce no record, so the timeline keeps its plain row instead of showing an empty card."
        )
    }

    func test_noRecord_whenEveryArtifactWasExcludedFromReview() {
        let excluded = artifact(kind: .photo)
        excluded.includedInProjectReview = false
        let deleted = artifact(kind: .note, body: "deleted")
        deleted.deletedAt = Date(timeIntervalSince1970: 2_000)

        XCTAssertNil(record(artifacts: [excluded, deleted]))
    }

    // MARK: - What the visit brought back

    func test_assemblesCapturedEvidenceFromTheLocalArtifacts() throws {
        let subject = try XCTUnwrap(record(artifacts: [
            artifact(kind: .photo, localAssetURL: "local://photo-1"),
            artifact(kind: .photo, localAssetURL: "local://photo-2", capturedAt: 1_100),
            artifact(kind: .measurement, title: "Deck footprint", body: "12' x 16'", capturedAt: 1_200),
            artifact(kind: .note, body: "Gate code 4417", capturedAt: 1_300)
        ]))

        XCTAssertEqual(subject.photoCount, 2)
        XCTAssertEqual(subject.measurements.map(\.label), ["Deck footprint"])
        XCTAssertEqual(subject.measurements.map(\.value), ["12' x 16'"])
        XCTAssertEqual(subject.notes, ["Gate code 4417"])
        XCTAssertEqual(subject.summaryLine, "2 PHOTOS · 1 MEASUREMENT · 1 NOTE")
    }

    /// The photos are ON this device — the strip must show them, not report
    /// them as undownloaded the way a teammate's phone has to.
    func test_photoStripUsesTheLocalArtifactAssets() throws {
        let subject = try XCTUnwrap(record(artifacts: [
            artifact(kind: .photo, localAssetURL: "local://photo-1"),
            artifact(kind: .photo, localAssetURL: "local://photo-2", capturedAt: 1_100)
        ]))

        XCTAssertEqual(subject.photoURLs, ["local://photo-1", "local://photo-2"])
    }

    func test_identityPrefersTheLeadThenTheDraftsBusiness() throws {
        let draft = SiteVisitIdentityDraft(
            siteVisitId: visitId,
            companyId: "company-1",
            clientName: "Calloway Ltd"
        )
        let subject = try XCTUnwrap(record(
            artifacts: [artifact(kind: .photo)],
            identity: draft,
            opportunity: opportunity()
        ))

        XCTAssertEqual(subject.identityLine, "HELEN CALLOWAY · CALLOWAY LTD")
    }

    func test_addressFallsBackToTheVisitWhenTheDraftHasNone() throws {
        let subject = try XCTUnwrap(record(artifacts: [artifact(kind: .photo)]))
        XCTAssertEqual(subject.address, "1100 Maple Ave")
    }

    func test_checklistAnswersTravelIntoTheRecord() throws {
        let answer = SiteVisitChecklistAnswer(
            siteVisitId: visitId,
            companyId: "company-1",
            opportunityId: "lead-1",
            siteVisitTypeId: "type-1",
            fieldId: "client-goals",
            label: "What the client wants",
            kind: .longText,
            required: false,
            sortOrder: 10,
            answerValue: .text("Composite, not cedar")
        )
        let subject = try XCTUnwrap(record(
            artifacts: [artifact(kind: .photo)],
            checklistAnswers: [answer]
        ))

        XCTAssertTrue(subject.sections.contains(.checklist))
        XCTAssertEqual(subject.checklist.count, 1)
    }

    // MARK: - Money, same gate as everywhere else

    func test_value_comesFromTheLocalOpportunity() throws {
        let subject = try XCTUnwrap(record(
            artifacts: [artifact(kind: .photo)],
            opportunity: opportunity(estimatedValue: 18_400),
            canViewFinancials: true
        ))
        XCTAssertEqual(subject.value, "$18,400")
        XCTAssertTrue(subject.sections.contains(.value))
    }

    func test_value_isOmittedEntirely_forAViewerWithoutFinancialVisibility() throws {
        let subject = try XCTUnwrap(record(
            artifacts: [artifact(kind: .photo)],
            opportunity: opportunity(estimatedValue: 18_400),
            canViewFinancials: false
        ))
        XCTAssertNil(subject.value)
        XCTAssertFalse(
            subject.sections.contains(.value),
            "The lead rail must gate money exactly as the project feed does."
        )
    }

    func test_value_isAbsent_whenTheLeadIsNotOnThisDevice() throws {
        let subject = try XCTUnwrap(record(
            artifacts: [artifact(kind: .photo)],
            opportunity: nil,
            canViewFinancials: true
        ))
        XCTAssertNil(subject.value)
    }
}
