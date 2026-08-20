//
//  DeckViewportUpdateBudgetTests.swift
//  OPSTests
//
//  Main-thread budget for the read-only deck viewport.
//
//  WHY (2026-08-19): `DeckTab3DSceneView.updateUIView` answered "did the
//  drawing change?" by calling `DeckDrawingData.toJSON()` — a `ComponentEmitter`
//  pass, a full `JSONEncoder` pass, a lexical re-parse and a re-render of the
//  WHOLE drawing — on EVERY SwiftUI update. `DeckDesign` already documents the
//  same failure mode on the decode side (`DeckDrawingDataCache`): repeating that
//  work per body evaluation "can monopolize the main thread long enough for the
//  iOS watchdog to terminate the app". A device watchdog report caught exactly
//  that encode running inside `GraphHost.flushTransactions()` →
//  `_UIHostingView.layoutSubviews()`.
//
//  The cost is unbounded in the wrong variable: it scales with how often the
//  SwiftUI graph updates, not with how often the drawing changes. Measured
//  against the founder's real store (7,958-byte lead deck, 189 `DeckDesign`
//  writes over 4 s — ordinary sync traffic), the viewport performed 750 full
//  encodes and burned 2,012 ms of main-thread CPU in a 4 s window, against a
//  500 ms control with the same churn and no deck on screen.
//
//  These tests pin that work. On this fixture they measured, before the fix,
//  5 serializations to push the screen and 800 across 199 unrelated store
//  writes (2,243 ms of main-thread CPU in a 4 s window); after it, 0 and 0
//  (1,098 ms). The drawing must be serialized at most once while the screen is
//  up, no matter how many times the graph updates.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DeckViewportUpdateBudgetTests
//

#if DEBUG
import CoreGraphics
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class DeckViewportUpdateBudgetTests: XCTestCase {

    /// Serialization passes allowed while the screen is up. One tolerates an
    /// incidental encode on a sync/DTO path; the defect produced hundreds.
    private let encodeBudget = 2

    /// Main-thread CPU ceiling for the churn window. Deliberately loose: the
    /// encode budget above is the deterministic gate, and this one only has to
    /// separate "the viewport serializes per update" from "it does not" without
    /// turning into a flaky timing assertion. Measured on this fixture:
    /// 2,243 ms with the defect, 1,098 ms without it. The residue is SwiftData
    /// save + `@Query` re-fetch + body re-evaluation, which the deck does not own.
    private let churnCPUBudgetMilliseconds: Double = 1_800

    /// Store writes driven during the churn window, and the window itself.
    private let churnInterval: TimeInterval = 0.02
    private let churnDuration: TimeInterval = 4.0

    // MARK: - Fixture

    /// A three-level deck with dimensioned, labelled edges — the shape of the
    /// founder's largest real drawings (3 levels, 28 KB), so the encode this
    /// test budgets is the encode production actually pays.
    private func realisticDrawing() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.levels = [
            level(prefix: "a", name: "Level 1", originX: 0.0, sortOrder: 0, elevation: 2.5),
            level(prefix: "b", name: "Level 2", originX: 400.0, sortOrder: 1, elevation: 5.0),
            level(prefix: "c", name: "Level 3", originX: 800.0, sortOrder: 2, elevation: 7.5)
        ]
        return data
    }

    /// One closed twelve-sided level. Twelve rather than four so the encoder
    /// walks a realistic number of `DeckVertex` / `DeckEdge` values.
    private func level(
        prefix: String,
        name: String,
        originX: CGFloat,
        sortOrder: Int,
        elevation: Double
    ) -> DeckLevel {
        var level = DeckLevel(name: name, sortOrder: sortOrder)
        let steps: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 96, y: 0), CGPoint(x: 96, y: 48),
            CGPoint(x: 192, y: 48), CGPoint(x: 192, y: 144), CGPoint(x: 144, y: 144),
            CGPoint(x: 144, y: 240), CGPoint(x: 48, y: 240), CGPoint(x: 48, y: 192),
            CGPoint(x: 0, y: 192), CGPoint(x: -48, y: 144), CGPoint(x: -48, y: 48)
        ]
        level.vertices = steps.enumerated().map { index, point in
            DeckVertex(
                id: "\(prefix)v\(index)",
                position: CGPoint(x: point.x + originX, y: point.y),
                elevation: elevation
            )
        }
        level.edges = steps.indices.map { index in
            let next = (index + 1) % steps.count
            return DeckEdge(
                id: "\(prefix)e\(index)",
                startVertexId: "\(prefix)v\(index)",
                endVertexId: "\(prefix)v\(next)",
                dimension: 96.0,
                label: "Run \(index + 1)"
            )
        }
        level.elevation = elevation
        return level
    }

    private func makeContainer(drawing: DeckDrawingData, opportunityId: String) throws -> ModelContainer {
        let container = try makeEmptyContainer()
        let design = DeckDesign(
            companyId: "budget-company",
            opportunityId: opportunityId,
            title: "Budget deck"
        )
        design.drawingData = drawing
        container.mainContext.insert(design)
        try container.mainContext.save()
        return container
    }

    private func makeEmptyContainer() throws -> ModelContainer {
        try ModelContainer(
            for: DeckDesign.self, Project.self, ProjectTask.self, Product.self, CatalogItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func lead(id: String) -> Opportunity {
        Opportunity.preview(
            id: id,
            title: "Budget lead",
            contactName: "Budget",
            stage: .quoted,
            estimatedValue: 12_000,
            daysInStage: 2
        )
    }

    private func permissions() -> PermissionStore {
        let store = PermissionStore.previewWithAssignedAccess()
        store.permissions["deck_builder.view"] = "assigned"
        store.permissions["deck_builder.edit"] = "assigned"
        return store
    }

    private func threadCPUMilliseconds(since start: UInt64) -> Double {
        Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1_000_000
    }

    /// Test-host stdout is not forwarded when the runner uses simulator clones,
    /// so every measurement is also attached to the result bundle.
    private func record(_ name: String, _ measurement: String) {
        print("DECK BUDGET \(name): \(measurement)")
        let attachment = XCTAttachment(string: measurement)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Hosts the real screen in the app host's window and returns a teardown.
    /// The app host's own window — never a test-created one — because iOS 26.5
    /// renders freshly attached test windows blank once the host drops out of
    /// the foreground pipeline (see `AppHostWindow`).
    private func hostDeckScreen(
        opportunity: Opportunity,
        container: ModelContainer
    ) throws -> (window: UIWindow, restore: () -> Void) {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController

        let host = UIHostingController(
            rootView: NavigationStack { LeadDeckScreen(opportunity: opportunity) }
                .environmentObject(permissions())
                .environmentObject(DataController())
                .modelContainer(container)
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        host.safeAreaRegions = []

        window.rootViewController = host
        window.layoutIfNeeded()

        return (window, {
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        })
    }

    /// Hosts the shared deck tab directly so the tests can observe its targeted
    /// model feed without reaching through LeadDeckScreen's private state.
    private func hostDeckTab(
        opportunity: Opportunity,
        container: ModelContainer,
        onDesignChange: @escaping (DeckDesign?) -> Void
    ) throws -> (window: UIWindow, restore: () -> Void) {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController

        let host = UIHostingController(
            rootView: DeckTabView(
                owner: .lead(opportunity),
                onCreateDeckDesign: {},
                onEditDeckDesign: { _ in },
                viewMode: .constant(.threeD),
                onDesignChange: onDesignChange
            )
            .environmentObject(permissions())
            .environmentObject(DataController())
            .modelContainer(container)
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        host.safeAreaRegions = []

        window.rootViewController = host
        window.layoutIfNeeded()

        return (window, {
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        })
    }

    // MARK: - 1. The push itself

    /// Pushing the deck screen must not serialize the drawing. The host already
    /// holds the canonical `drawingDataJSON`; re-deriving it is pure main-thread
    /// waste inside the layout pass.
    func testPushDoesNotSerializeTheDrawing() throws {
        let opportunityId = UUID().uuidString.lowercased()
        let container = try makeContainer(drawing: realisticDrawing(), opportunityId: opportunityId)

        DeckDrawingData.diagnosticEncodeCount = 0
        let hosted = try hostDeckScreen(opportunity: lead(id: opportunityId), container: container)
        defer { hosted.restore() }

        // SINGLE blocking pump. A while-loop of short pumps would charge this
        // thread for its own spin and report a fabricated CPU percentage.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.0))

        let encodes = DeckDrawingData.diagnosticEncodeCount
        record("push", "toJSON calls = \(encodes) (budget \(encodeBudget))")
        XCTAssertLessThanOrEqual(
            encodes,
            encodeBudget,
            "Pushing the deck screen serialized the drawing \(encodes) times. The viewport must "
                + "compare an identity token, never re-encode the drawing, inside layoutSubviews."
        )
    }

    // MARK: - 2. Ordinary store churn while the deck is on screen

    /// The device runs a live sync engine that writes `DeckDesign` rows all day.
    /// Every write invalidates the deck tab's `@Query`, re-evaluates its body and
    /// hands the 3D canvas a fresh value. The canvas must answer "changed?" for
    /// free — the cost of showing a deck cannot scale with unrelated sync traffic.
    func testStoreChurnDoesNotSerializeTheDrawingPerUpdate() throws {
        let opportunityId = UUID().uuidString.lowercased()
        let container = try makeContainer(drawing: realisticDrawing(), opportunityId: opportunityId)
        let context = container.mainContext

        let hosted = try hostDeckScreen(opportunity: lead(id: opportunityId), container: container)
        defer { hosted.restore() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))

        // Churn from a run-loop timer so the ONLY blocking pump is the single
        // `run(until:)` below.
        var writes = 0
        let timer = Timer(timeInterval: churnInterval, repeats: true) { _ in
            let throwaway = DeckDesign(
                companyId: "budget-company",
                opportunityId: UUID().uuidString.lowercased(),
                title: "churn"
            )
            context.insert(throwaway)
            try? context.save()
            context.delete(throwaway)
            try? context.save()
            writes += 1
        }
        RunLoop.main.add(timer, forMode: .common)

        DeckDrawingData.diagnosticEncodeCount = 0
        let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: churnDuration))
        let cpuMilliseconds = threadCPUMilliseconds(since: cpuStart)
        timer.invalidate()

        let encodes = DeckDrawingData.diagnosticEncodeCount
        record("churn", "writes = \(writes), toJSON calls = \(encodes) (budget \(encodeBudget)),"
               + " mainCPU = \(String(format: "%.1f", cpuMilliseconds))ms"
               + " (budget \(String(format: "%.0f", churnCPUBudgetMilliseconds))ms)"
               + " over \(String(format: "%.1f", churnDuration))s")

        XCTAssertGreaterThan(writes, 50, "The churn driver never ran — the measurement is meaningless")
        XCTAssertLessThanOrEqual(
            encodes,
            encodeBudget,
            "\(writes) unrelated store writes caused \(encodes) full drawing serializations. "
                + "The viewport's change detection must not scale with graph updates."
        )
        XCTAssertLessThan(
            cpuMilliseconds,
            churnCPUBudgetMilliseconds,
            "The deck viewport burned \(String(format: "%.0f", cpuMilliseconds))ms of main-thread CPU "
                + "across \(writes) unrelated store writes — watchdog territory on device hardware."
        )
    }

    // MARK: - 3. Targeted feed correctness

    /// Removing the broad `@Query` must not make the empty screen stale. A new
    /// design for another lead is ignored; one for this lead appears without
    /// leaving and reopening the route.
    func testTargetedFeedIgnoresUnrelatedInsertAndShowsRelevantInsert() throws {
        let opportunityId = UUID().uuidString.lowercased()
        let container = try makeEmptyContainer()
        let context = container.mainContext
        var observedDesignIds: [String?] = []

        let hosted = try hostDeckTab(
            opportunity: lead(id: opportunityId),
            container: container,
            onDesignChange: { observedDesignIds.append($0?.id) }
        )
        defer { hosted.restore() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        let unrelated = DeckDesign(
            companyId: "budget-company",
            opportunityId: UUID().uuidString.lowercased(),
            title: "Unrelated"
        )
        context.insert(unrelated)
        try context.save()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertTrue(observedDesignIds.isEmpty, "Unrelated deck traffic changed the visible lead")

        let relevant = DeckDesign(
            companyId: "budget-company",
            opportunityId: opportunityId,
            title: "Relevant"
        )
        let relevantId = relevant.id
        context.insert(relevant)
        try context.save()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        XCTAssertEqual(observedDesignIds, [relevantId])
    }

    /// SwiftData invalidates deleted model backing storage immediately. The
    /// feed must compare persistent identity and refetch; dereferencing the
    /// deleted fault is a fatal trap rather than a catchable error.
    func testTargetedFeedSafelyClearsDeletedVisibleDesign() throws {
        let opportunityId = UUID().uuidString.lowercased()
        let container = try makeContainer(drawing: realisticDrawing(), opportunityId: opportunityId)
        let context = container.mainContext
        let design = try XCTUnwrap(context.fetch(FetchDescriptor<DeckDesign>()).first)
        let designId = design.id
        var observedDesignIds: [String?] = []

        let hosted = try hostDeckTab(
            opportunity: lead(id: opportunityId),
            container: container,
            onDesignChange: { observedDesignIds.append($0?.id) }
        )
        defer { hosted.restore() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertEqual(observedDesignIds, [designId])

        context.delete(design)
        try context.save()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        XCTAssertEqual(observedDesignIds.count, 2)
        XCTAssertNil(observedDesignIds.last!)
    }
}
#endif
