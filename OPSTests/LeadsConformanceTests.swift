import XCTest
@testable import OPS

/// Regression tests for the LEADS pre-merge review (2026-05-31).
///
/// These lock the two data-model defects that shipped silently:
///   * C-3 / C-4 — the lead form offered `priority`/`source` chip ids (and
///     defaults) that are NOT members of the Postgres CHECK constraints, so
///     every create/edit with the defaults 400'd. These tests fail if a chip id
///     or default ever drifts off the constraint set again.
///   * C-5 — `PipelineStage` had no `discarded` case, so server `discarded`
///     opportunities were coerced to `.newLead` and surfaced as fresh leads.
///
/// The allowed sets below are transcribed from the live constraints
/// (`opportunities_priority_check`, `opportunities_source_check`,
/// `opportunities_stage_check`) verified against the database on 2026-05-31. If
/// the DB constraint changes, update these sets in lockstep.
final class LeadsConformanceTests: XCTestCase {

    /// opportunities_priority_check
    private let allowedPriorities: Set<String> = ["low", "medium", "high"]

    /// opportunities_source_check
    private let allowedSources: Set<String> = [
        "referral", "website", "email", "phone", "walk_in",
        "social_media", "repeat_client", "voice_log", "other"
    ]

    /// opportunities_stage_check
    private let allowedStages: Set<String> = [
        "new_lead", "qualifying", "quoting", "quoted", "follow_up",
        "negotiation", "won", "lost", "discarded"
    ]

    // MARK: - C-3 / C-4 — form values must satisfy the DB CHECK constraints

    func testPriorityChipIdsAreValidConstraintMembers() {
        let ids = Set(LeadFormView.priorityOptions.map(\.id))
        XCTAssertTrue(
            ids.isSubset(of: allowedPriorities),
            "PRIORITY chip ids \(ids) must be a subset of opportunities_priority_check \(allowedPriorities)"
        )
    }

    func testSourceChipIdsAreValidConstraintMembers() {
        let ids = Set(LeadFormView.sourceOptions.map(\.id))
        XCTAssertTrue(
            ids.isSubset(of: allowedSources),
            "SOURCE chip ids \(ids) must be a subset of opportunities_source_check \(allowedSources)"
        )
    }

    func testStageChipIdsAreValidConstraintMembers() {
        let ids = Set(LeadFormView.stageOptions.map(\.id))
        XCTAssertTrue(
            ids.isSubset(of: allowedStages),
            "STAGE chip ids \(ids) must be a subset of opportunities_stage_check \(allowedStages)"
        )
    }

    /// The new-lead form defaults are the common path — they MUST be valid, or
    /// the default Add-Lead save fails outright (the exact C-3/C-4 regression).
    func testLeadFormDefaultsAreValidConstraintMembers() {
        let form = LeadForm()
        XCTAssertTrue(allowedPriorities.contains(form.priority),
                      "Default priority '\(form.priority)' must satisfy opportunities_priority_check")
        XCTAssertTrue(allowedSources.contains(form.source),
                      "Default source '\(form.source)' must satisfy opportunities_source_check")
        XCTAssertTrue(allowedStages.contains(form.stage.rawValue),
                      "Default stage '\(form.stage.rawValue)' must satisfy opportunities_stage_check")
    }

    // MARK: - C-5 — discarded stage is modeled and terminal (never coerced)

    func testDiscardedStageRoundTrips() {
        XCTAssertEqual(PipelineStage(rawValue: "discarded"), .discarded,
                       "A 'discarded' opportunity must map to .discarded, not be coerced to .newLead")
    }

    func testDiscardedStageIsTerminal() {
        XCTAssertTrue(PipelineStage.discarded.isTerminal,
                      ".discarded must be terminal so it is excluded from the triage queue + open counts")
        XCTAssertNil(PipelineStage.discarded.next,
                     ".discarded must have no next stage (it is terminal)")
    }

    /// Every PipelineStage rawValue must be a valid DB stage, so a model value
    /// can never be rejected by opportunities_stage_check on write-back.
    func testAllPipelineStagesAreValidConstraintMembers() {
        for stage in PipelineStage.allCases {
            XCTAssertTrue(allowedStages.contains(stage.rawValue),
                          "PipelineStage.\(stage) rawValue '\(stage.rawValue)' is not in opportunities_stage_check")
        }
    }
}
