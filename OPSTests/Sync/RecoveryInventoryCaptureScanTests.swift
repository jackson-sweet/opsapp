//
//  RecoveryInventoryCaptureScanTests.swift
//  OPSTests
//
//  Locks the capture-scan short-circuit in `RecoveryInventory.captureSnapshots`.
//  The artifact and checklist-answer fetches are whole-live-table scans (their
//  predicate is only `deletedAt == nil`; the visit match is an in-memory
//  lowercased `contains`) over tables that grow without bound as server rows
//  merge in. `RecoveryInventory.load` runs on the main context every time the
//  sync pill or the PENDING WORK screen refreshes, so when no draft and no
//  site-visit operation names a visit, neither table may be touched at all —
//  an empty result is not enough, the fetch itself must not happen.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class RecoveryInventoryCaptureScanTests: XCTestCase {

    private let companyId = "company-1"
    private let visitId = "visit-1"

    /// Containers are retained for the life of a test so their in-memory stores
    /// outlive the contexts under test.
    private var liveContainers: [ModelContainer] = []

    override func tearDown() {
        liveContainers.removeAll()
        super.tearDown()
    }

    // MARK: - The skip

    func test_captureFetchesNeverRunWhenNoDraftOrOperationNamesAVisit() throws {
        let context = try makeContext()
        context.insert(makeArtifact())
        context.insert(makeAnswer())
        try context.save()

        var artifactFetches = 0
        var answerFetches = 0

        let captures = RecoveryInventory.captureSnapshots(
            visitIds: [],
            activeCompanyId: companyId,
            fetchArtifacts: {
                artifactFetches += 1
                return Self.artifacts(in: context)
            },
            fetchAnswers: {
                answerFetches += 1
                return Self.answers(in: context)
            }
        )

        XCTAssertEqual(artifactFetches, 0, "An empty visit-id set must not scan the artifact table")
        XCTAssertEqual(answerFetches, 0, "An empty visit-id set must not scan the checklist-answer table")
        XCTAssertTrue(captures.artifacts.isEmpty)
        XCTAssertTrue(captures.answers.isEmpty)

        // The rows are there — the empty result above is a skipped scan, not an
        // empty store.
        XCTAssertEqual(Self.artifacts(in: context).count, 1)
        XCTAssertEqual(Self.answers(in: context).count, 1)
    }

    // MARK: - The scan, when it is earned

    func test_captureFetchesRunOnceAndScopeToCompanyAndVisit() throws {
        let context = try makeContext()
        context.insert(makeArtifact(id: "artifact-mine"))
        context.insert(makeAnswer(id: "answer-mine"))
        context.insert(makeArtifact(id: "artifact-other-visit", siteVisitId: "visit-2"))
        context.insert(makeAnswer(id: "answer-other-visit", siteVisitId: "visit-2"))
        context.insert(makeArtifact(id: "artifact-other-company", companyId: "company-2"))
        context.insert(makeAnswer(id: "answer-other-company", companyId: "company-2"))
        try context.save()

        var artifactFetches = 0
        var answerFetches = 0

        let captures = RecoveryInventory.captureSnapshots(
            visitIds: [visitId],
            activeCompanyId: companyId,
            fetchArtifacts: {
                artifactFetches += 1
                return Self.artifacts(in: context)
            },
            fetchAnswers: {
                answerFetches += 1
                return Self.answers(in: context)
            }
        )

        XCTAssertEqual(artifactFetches, 1)
        XCTAssertEqual(answerFetches, 1)
        XCTAssertEqual(captures.artifacts.map(\.id), ["artifact-mine"])
        XCTAssertEqual(captures.answers.map(\.id), ["answer-mine"])
    }

    // MARK: - Casing

    /// `UUID().uuidString` is uppercase; Postgres `uuid` columns are lowercase.
    /// `load` happens to lowercase before calling in, but the match must not
    /// depend on every future call site remembering to — the failure mode is
    /// silent (zero captured items on a row that has them), which is exactly how
    /// this class of bug has escaped here before.
    func test_captureFetchesMatchWhateverCaseTheCallerPassesIn() throws {
        let context = try makeContext()
        context.insert(makeArtifact(id: "artifact-mine"))
        context.insert(makeAnswer(id: "answer-mine"))
        try context.save()

        let captures = RecoveryInventory.captureSnapshots(
            visitIds: [visitId.uppercased()],
            activeCompanyId: companyId.uppercased(),
            fetchArtifacts: { Self.artifacts(in: context) },
            fetchAnswers: { Self.answers(in: context) }
        )

        XCTAssertEqual(captures.artifacts.map(\.id), ["artifact-mine"])
        XCTAssertEqual(captures.answers.map(\.id), ["answer-mine"])
    }

    // MARK: - Fixtures

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        liveContainers.append(container)
        return container.mainContext
    }

    private func makeArtifact(
        id: String = "artifact-1",
        siteVisitId: String? = nil,
        companyId: String? = nil
    ) -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            id: id,
            siteVisitId: siteVisitId ?? visitId,
            companyId: companyId ?? self.companyId,
            kind: .note,
            source: .keyboard,
            body: "Captured on site"
        )
    }

    private func makeAnswer(
        id: String = "answer-1",
        siteVisitId: String? = nil,
        companyId: String? = nil
    ) -> SiteVisitChecklistAnswer {
        SiteVisitChecklistAnswer(
            id: id,
            siteVisitId: siteVisitId ?? visitId,
            companyId: companyId ?? self.companyId,
            opportunityId: nil,
            siteVisitTypeId: nil,
            fieldId: "field-1",
            label: "Access",
            kind: .shortText,
            required: false,
            sortOrder: 0,
            answerValue: .text("Side gate")
        )
    }

    private static func artifacts(in context: ModelContext) -> [SiteVisitCaptureArtifact] {
        let descriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate<SiteVisitCaptureArtifact> { $0.deletedAt == nil }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func answers(in context: ModelContext) -> [SiteVisitChecklistAnswer] {
        let descriptor = FetchDescriptor<SiteVisitChecklistAnswer>(
            predicate: #Predicate<SiteVisitChecklistAnswer> { $0.deletedAt == nil }
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
