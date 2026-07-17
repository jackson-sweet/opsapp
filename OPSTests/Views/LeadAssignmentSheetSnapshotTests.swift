//
//  LeadAssignmentSheetSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the lead assignment sheet — the three
//  states an operator can land in: the guarded candidate list (with the
//  Unassign row and CURRENT marker), the no-eligible-team-members empty
//  state, and the load-failure state with its RETRY escape hatch. Renders
//  PNGs from a stubbed repository so no network or Supabase is touched —
//  a rendering harness on the LeadDetailAdditionsSnapshotTests pattern
//  (UIHostingController + UIWindow + drawHierarchy), not an assertion test.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/LeadAssignmentSheetSnapshotTests
//  Shots land in NSTemporaryDirectory()/ops-lead-assignment-shots.
//

#if DEBUG
import XCTest
import SwiftUI
import Supabase
@testable import OPS

@MainActor
final class LeadAssignmentSheetSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-lead-assignment-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// UIHostingController + UIWindow + drawHierarchy — the Books-harness
    /// pattern shared with LeadDetailAdditionsSnapshotTests. ImageRenderer
    /// leaves ScrollView content blank and skips onAppear; rendering the live
    /// window layer captures the sheet exactly as the app draws it.
    private func snapshot<V: View>(
        _ name: String,
        height: CGFloat = 852,
        settle: TimeInterval = 0.4,
        @ViewBuilder _ content: () -> V
    ) {
        let size = CGSize(width: deviceWidth, height: height)
        let host = UIHostingController(
            rootView: content()
                .frame(width: deviceWidth)
                .background(OPSStyle.Colors.background)
                .environment(\.colorScheme, .dark)
        )
        host.view.backgroundColor = .black

        // The window MUST adopt the app host's scene — an unsceened window is
        // never picked up by the render server, so drawHierarchy silently
        // produces a blank white image.
        let window: UIWindow
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        // Let layout passes and the sheet's .task-driven load settle.
        RunLoop.main.run(until: Date().addingTimeInterval(settle))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        window.isHidden = true
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    // MARK: - Fixtures

    private func leadFixture() -> Opportunity {
        Opportunity.preview(
            id: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            title: "Roof tear-off, 28 sq",
            contactName: "Helen Calloway",
            stage: .quoted,
            estimatedValue: 14_200,
            daysInStage: 9,
            assignedTo: "user-jason"
        )
    }

    private func candidateEnvelope() -> OpportunityAssignmentCandidates {
        OpportunityAssignmentCandidates(
            canUnassign: true,
            candidates: [
                OpportunityAssignmentCandidate(
                    id: "user-jason",
                    firstName: "Jason",
                    lastName: "Zavarella",
                    profileImageURL: nil,
                    userColor: "#6F94B0"
                ),
                OpportunityAssignmentCandidate(
                    id: "user-amy",
                    firstName: "Amy",
                    lastName: "Chen",
                    profileImageURL: nil,
                    userColor: nil
                ),
                OpportunityAssignmentCandidate(
                    id: "user-chris",
                    firstName: "Chris",
                    lastName: "Ng",
                    profileImageURL: nil,
                    userColor: nil
                )
            ]
        )
    }

    /// Drives the view model to a deterministic state before rendering. The
    /// stub returns the same result on every call, so the sheet's own
    /// `.task`-driven reload lands in the identical state — render timing
    /// cannot change what the PNG shows.
    private func makeViewModel(
        result: Result<OpportunityAssignmentCandidates, Error>
    ) async -> LeadAssignmentViewModel {
        let viewModel = LeadAssignmentViewModel(
            opportunity: leadFixture(),
            repository: SheetSnapshotRepositoryStub(candidatesResult: result)
        )
        await viewModel.loadCandidates(isOnline: true)
        return viewModel
    }

    // MARK: - States

    /// Candidate list: Unassign row on top, three named candidates, the
    /// current assignee marked CURRENT with a trailing check.
    func testRenderCandidatesWithUnassign() async {
        let viewModel = await makeViewModel(result: .success(candidateEnvelope()))

        snapshot("lead_assignment_sheet_candidates", height: 560) {
            LeadAssignmentSheet(viewModel: viewModel, isOnline: true)
        }
    }

    /// Guarded envelope came back empty and forbids unassign — the sheet
    /// states NO ELIGIBLE TEAM MEMBERS and offers nothing else.
    func testRenderEmptyState() async {
        let viewModel = await makeViewModel(
            result: .success(
                OpportunityAssignmentCandidates(canUnassign: false, candidates: [])
            )
        )

        snapshot("lead_assignment_sheet_empty", height: 320) {
            LeadAssignmentSheet(viewModel: viewModel, isOnline: true)
        }
    }

    /// Candidate load failed — rose error line plus the RETRY action.
    func testRenderErrorState() async {
        let viewModel = await makeViewModel(
            result: .failure(URLError(.notConnectedToInternet))
        )

        snapshot("lead_assignment_sheet_error", height: 360) {
            LeadAssignmentSheet(viewModel: viewModel, isOnline: true)
        }
    }
}

// MARK: - Repository stub

/// Idempotent stand-in for the guarded assignment repository: every
/// `listAssignmentCandidates` call returns the same configured result, so
/// pre-driving the view model and the sheet's own `.task` reload are
/// guaranteed to agree. Mutation paths are unreachable in a render harness
/// and fail loudly if ever hit.
@MainActor
private final class SheetSnapshotRepositoryStub: LeadAssignmentRepositoryProtocol {
    private let candidatesResult: Result<OpportunityAssignmentCandidates, Error>

    init(candidatesResult: Result<OpportunityAssignmentCandidates, Error>) {
        self.candidatesResult = candidatesResult
    }

    func listAssignmentCandidates(
        opportunityId: String
    ) async throws -> OpportunityAssignmentCandidates {
        try candidatesResult.get()
    }

    func changeAssignment(
        opportunityId: String,
        expectedAssignmentVersion: Int64,
        expectedAssignedTo: String?,
        newAssignedTo: String?,
        source: OpportunityAssignmentSource,
        suggestionId: String?,
        metadata: [String: AnyJSON]
    ) async throws -> OpportunityAssignmentChangeResult {
        XCTFail("Snapshot harness must never mutate assignment")
        throw URLError(.unsupportedURL)
    }

    func fetchAssignmentSnapshot(
        opportunityId: String
    ) async throws -> OpportunityAssignmentSnapshot {
        XCTFail("Snapshot harness must never fetch the assignment snapshot")
        throw URLError(.unsupportedURL)
    }
}
#endif
