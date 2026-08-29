//
//  LeadDeckSectionFeedTests.swift
//  OPSTests
//
//  The dossier DECK row's targeted store feed (bug 2fa645a8).
//
//  `LeadDeckSection` held the last broad `@Query private var allDesigns:
//  [DeckDesign]` on the lead dossier — the exact screen the crash report names.
//  SwiftData invalidates such a query for EVERY save of the entity type, so a
//  company's ordinary realtime deck traffic re-fetched the whole table and
//  re-evaluated this row on the main thread while the operator stood on the
//  dossier. `DeckViewportUpdateBudgetTests` measured that same family on
//  `DeckTabView` (≈2,000 ms of main-thread CPU over a 4 s churn window) and
//  proved the owner-scoped did-save feed that replaced it. This file pins the
//  same feed on the section.
//
//  The risk this change introduces is staleness, not churn — a feed that stops
//  listening shows a deck that is no longer there, or misses one that just
//  arrived. Both tests attack exactly that:
//
//    1. fifty unrelated deck saves must not disturb the row, and the store must
//       still resolve the SAME design;
//    2. a design saved onto this lead must appear without leaving and
//       reopening the dossier.
//
//  The row is observed through hosted geometry rather than a production seam:
//  the design row is a `touchTargetMin`-floored line and both empty states are
//  short chips, so the section's ideal height says which state is on screen
//  without `LeadDeckSection` growing a test-only callback.
//

#if DEBUG
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class LeadDeckSectionFeedTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    /// Unrelated deck traffic elsewhere in the company must leave this lead's
    /// row exactly where it was — both on screen and in the store's own
    /// resolution of the display candidate.
    func testUnrelatedDeckSavesDoNotChangeTheResolvedCandidate() throws {
        let opportunityId = UUID().uuidString.lowercased()
        let container = try makeContainer()
        let context = container.mainContext

        let mine = DeckDesign(
            companyId: "preview-company",
            opportunityId: opportunityId,
            title: "Calloway Deck",
            drawingDataJSON: square().toJSON()
        )
        mine.updatedAt = Date().addingTimeInterval(-3_600)
        context.insert(mine)
        try context.save()
        let mineIdentifier = mine.persistentModelID

        let hosted = try hostSection(opportunity: lead(id: opportunityId), container: container)
        defer { hosted.restore() }

        XCTAssertTrue(
            showsDesignRow(hosted),
            "the seeded deck must resolve into the DECK row before the churn means anything"
        )

        for index in 0..<50 {
            let unrelated = DeckDesign(
                companyId: "preview-company",
                opportunityId: UUID().uuidString.lowercased(),
                title: "Churn \(index)",
                drawingDataJSON: square().toJSON()
            )
            context.insert(unrelated)
            try context.save()
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        XCTAssertTrue(
            showsDesignRow(hosted),
            "fifty unrelated deck saves emptied this lead's DECK row — the targeted feed is not owner-scoped"
        )
        XCTAssertEqual(
            try resolvedCandidate(forOpportunityId: opportunityId, in: context)?.persistentModelID,
            mineIdentifier,
            "the lead's display candidate changed under unrelated deck traffic"
        )
    }

    /// A deck can arrive for this lead while the dossier is already open — the
    /// builder saving, a realtime row landing, or the self-repair fetch filling
    /// a cold store. Without the `@Query`, the did-save feed is the only thing
    /// that makes it appear.
    func testDesignReassignedToThisLeadAppears() throws {
        let opportunityId = UUID().uuidString.lowercased()
        let container = try makeContainer()
        let context = container.mainContext

        let hosted = try hostSection(opportunity: lead(id: opportunityId), container: container)
        defer { hosted.restore() }

        XCTAssertFalse(
            showsDesignRow(hosted),
            "the lead has no deck — the section must be showing its empty state"
        )

        let arriving = DeckDesign(
            companyId: "preview-company",
            opportunityId: opportunityId,
            title: "Arrived Deck",
            drawingDataJSON: square().toJSON()
        )
        arriving.updatedAt = Date()
        context.insert(arriving)
        try context.save()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        XCTAssertTrue(
            showsDesignRow(hosted),
            "a deck saved onto this lead did not appear — the DECK row is stale without its broad @Query"
        )
        XCTAssertEqual(
            try resolvedCandidate(forOpportunityId: opportunityId, in: context)?.persistentModelID,
            arriving.persistentModelID
        )
    }

    // MARK: - Harness

    private struct Harness {
        let host: UIHostingController<AnyView>
        let window: UIWindow
        let restore: () -> Void
    }

    /// Hosts the section in the app host's own window — never a test-created
    /// one, which iOS 26.5 drops out of the render pipeline mid-suite (see
    /// `AppHostWindow`). A window host is also what makes `.onAppear` and
    /// `.task` run at all, and those are what seed the feed.
    private func hostSection(
        opportunity: Opportunity,
        container: ModelContainer
    ) throws -> Harness {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController

        let host = UIHostingController(
            rootView: AnyView(
                LeadDeckSection(opportunity: opportunity, canManage: true)
                    .environmentObject(PermissionStore.previewWithFullAccess())
                    .modelContainer(container)
                    .frame(width: deviceWidth)
                    .environment(\.sizeCategory, .large)
                    .environment(\.colorScheme, .dark)
            )
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        host.safeAreaRegions = []

        window.rootViewController = host
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        return Harness(
            host: host,
            window: window,
            restore: {
                window.rootViewController = originalRoot
                window.layoutIfNeeded()
            }
        )
    }

    /// Which state the section is in, read from its ideal height.
    ///
    /// `designRow` floors at `OPSStyle.Layout.touchTargetMin`; the START chip
    /// (9pt mono in 5pt vertical padding) and the `—` placeholder are both
    /// roughly half that, so the threshold has a wide margin and needs no
    /// pixel sampling.
    private func showsDesignRow(_ harness: Harness) -> Bool {
        harness.window.layoutIfNeeded()
        let ideal = harness.host.sizeThatFits(
            in: CGSize(width: deviceWidth, height: .greatestFiniteMagnitude)
        )
        return ideal.height >= OPSStyle.Layout.touchTargetMin
    }

    /// The store's own answer, independent of the view — the value the feed is
    /// supposed to be tracking.
    private func resolvedCandidate(
        forOpportunityId opportunityId: String,
        in context: ModelContext
    ) throws -> DeckDesign? {
        DeckDesign.displayCandidate(
            in: try context.fetch(FetchDescriptor<DeckDesign>()),
            forOpportunityId: opportunityId
        )
    }

    // MARK: - Fixtures

    /// No `SyncOperation` is seeded: after the shared merge became
    /// predicate-free nothing on this path fetches one, and an empty operation
    /// table is the store shape that used to trap.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: DeckDesign.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func lead(id: String) -> Opportunity {
        Opportunity.preview(
            id: id,
            title: "Deck feed lead",
            contactName: "Helen Calloway",
            stage: .quoted,
            estimatedValue: 14_200,
            daysInStage: 2
        )
    }

    /// Closed square (4 verts + 4 edges) so the geometry survives the JSON
    /// round-trip — orphan (edgeless) vertices are pruned on decode.
    private func square() -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120))
        ]
        drawing.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        ]
        drawing.scaleFactor = 1
        return drawing
    }
}
#endif
