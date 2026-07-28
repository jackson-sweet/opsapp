//
//  DaySheetCardSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for DaySheetLeadCard — the day sheet's expanded
//  accordion cell. Proves the states that matter: the full lead (every block
//  present), the viewer without edit rights (photos yes, stamp no), the
//  finances-scoped operator (the quiet EST line), the sparse lead where most
//  blocks are ABSENT rather than empty, and both halves of the milestone's
//  5-second undo window — pressed with signal, and pressed dark (`QUEUED`).
//
//  Harness is DaySheetRowSnapshotTests' verbatim, including the safe-area fix
//  (a UIWindow inherits the device insets whatever its frame, which pushes the
//  card down and clips it out of the canvas). A rendering harness, not an
//  assertion.
//
//  Remote photo tiles render as their loading placeholder — the harness does
//  not wait on a network round trip. The card's geometry is what this proves.
//
//  The deck design is INJECTED (`deckSource: .injected`) rather than resolved:
//  the production path reads `@Query` + `modelContext`, both of which need a
//  ModelContainer in the environment that a bare UIWindow host does not have.
//  The seam keeps the test honest about the tile — including the sparse case,
//  where `.injected(nil)` proves the tile is genuinely absent — while leaving
//  resolution to the app.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DaySheetCardSnapshotTests
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class DaySheetCardSnapshotTests: XCTestCase {

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-day-sheet-card-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, size: CGSize, @ViewBuilder _ content: () -> V) {
        let host = UIHostingController(rootView: content().ignoresSafeArea())
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { XCTFail("render \(name)"); return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name)")
    }

    // MARK: - Fixtures

    private static let cardWidth: CGFloat = 390

    /// A lead with everything: address, both channels, an agent summary two
    /// days old, and two site photos.
    private func fullLead() -> Opportunity {
        let entered = Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date()
        let lead = Opportunity(
            id: "D1",
            companyId: "c1",
            contactName: "Marcus Webb",
            stage: .quoting,
            stageEnteredAt: entered
        )
        lead.address = "1841 Beckwith Ave, Burnaby BC"
        lead.contactPhone = "604-555-0142"
        lead.contactEmail = "marcus.webb@example.com"
        lead.estimatedValue = 14_200
        lead.images = [
            "https://example.com/site-a.jpg",
            "https://example.com/site-b.jpg"
        ]
        lead.aiSummary = "Quote sent Tuesday. Asked about triple-pane pricing; wife prefers the bronze frames. Decision expected after the 15th."
        lead.aiSummaryUpdatedAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
        return lead
    }

    /// Phone only — no address, no email, no photos, no summary, no deck.
    private func sparseLead() -> Opportunity {
        let entered = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        let lead = Opportunity(
            id: "D2",
            companyId: "c1",
            contactName: "Cedar Ridge HOA",
            stage: .negotiation,
            stageEnteredAt: entered
        )
        lead.contactPhone = "604-555-0188"
        return lead
    }

    /// A two-run deck with glass rail on composite boards — enough geometry for
    /// the tile's `W × L · MATERIAL · RAIL` line to resolve every segment.
    private func deckFixture() -> DeckDesign {
        var drawing = DeckDrawingData()
        // Vertices are NOT optional scenery: `fromJSON` prunes any edge whose
        // endpoints are missing, so an edges-only fixture round-trips to an
        // empty drawing and the tile's meta line silently loses its span and
        // its railing.
        drawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 192, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 192, y: 144))
        ]
        drawing.edges = [
            DeckEdge(
                id: "e1", startVertexId: "v1", endVertexId: "v2",
                dimension: 192,
                railingConfig: RailingConfig(railingType: .glass, maxPostSpacing: 60)
            ),
            DeckEdge(
                id: "e2", startVertexId: "v2", endVertexId: "v3",
                dimension: 144,
                railingConfig: RailingConfig(railingType: .glass, maxPostSpacing: 60)
            )
        ]
        drawing.surfaces = [
            DeckSurface(id: "s1", vertexIds: ["v1", "v2", "v3"], boardMaterial: "composite")
        ]
        return DeckDesign(
            id: "11111111-1111-1111-1111-111111111111",
            companyId: "c1",
            opportunityId: "D1",
            title: "Back deck — wraparound",
            drawingDataJSON: drawing.toJSON()
        )
    }

    /// The default LEADS preview store: pipeline manage/view + lead.create, and
    /// deliberately NO `finances.view` — so three of the four renders must show
    /// no EST line at all.
    private func standardStore() -> PermissionStore {
        PermissionStore.previewWithFullAccess()
    }

    /// Same grants plus the finances read, built inline rather than folded into
    /// the shared preview store — the EST line's gate is only worth proving if
    /// the other renders genuinely lack the grant.
    private func financesStore() -> PermissionStore {
        let store = PermissionStore.previewWithFullAccess()
        store.permissions["finances.view"] = "all"
        return store
    }

    private func row(
        _ lead: Opportunity,
        _ urgency: DaySheetViewModel.Urgency,
        _ milestone: LeadMilestone?
    ) -> DaySheetViewModel.Row {
        DaySheetViewModel.Row(lead: lead, urgency: urgency, milestone: milestone)
    }

    /// A committer parked mid-window, so the card can be rendered in the state
    /// a runner sees the instant his thumb lifts. Every seam is inert — no
    /// network — and the scheduler never fires, so the window stays open for
    /// as long as the render needs it.
    private func heldCommitter(online: Bool) -> LeadMilestoneCommitter {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LeadMilestoneCommitter(
            companyId: "c1",
            queue: MilestoneWriteQueue(directory: directory, backgroundWorkEnabled: false),
            isOnline: { online },
            moveStage: { _, _ in },
            flipLocalStage: { _, _ in },
            logActivity: { _ in "activity-1" },
            deleteActivity: { _ in },
            currentStageRaw: { _ in PipelineStage.quoting.rawValue },
            notifyLeadUpdated: { _ in },
            schedule: { _, _ in LeadMilestoneCommitter.ScheduledExpiry {} }
        )
    }

    @ViewBuilder
    private func hosted(
        _ row: DaySheetViewModel.Row,
        canEdit: Bool,
        canConvert: Bool,
        store: PermissionStore,
        deck: DeckDesign? = nil,
        committer: LeadMilestoneCommitter? = nil
    ) -> some View {
        DaySheetLeadCard(
            row: row,
            canEdit: canEdit,
            canConvert: canConvert,
            isExpanded: true,
            committer: committer,
            deckSource: .injected(deck)
        )
        .padding(OPSStyle.Layout.spacing2)
        .frame(width: Self.cardWidth)
        .background(Color.black)
        .environmentObject(store)
    }

    // MARK: - Renders

    /// Every block present — photos, deck, summary, all three contact rows,
    /// three quick actions, the accent QUOTE SENT stamp, and the footer. No EST
    /// line: this operator has no finances grant.
    func testRenderFullCard() {
        snapshot("day_sheet_card_full", size: CGSize(width: Self.cardWidth, height: 700)) {
            hosted(
                row(fullLead(), .late(days: 3), .quoteSent),
                canEdit: true,
                canConvert: true,
                store: standardStore(),
                deck: deckFixture()
            )
        }
    }

    /// Viewer scope — the same lead, no edit rights. Photos still visible (no
    /// ADD tile), quick actions still open the conversation, NO milestone.
    func testRenderViewerOnlyCard() {
        snapshot("day_sheet_card_viewer_only", size: CGSize(width: Self.cardWidth, height: 640)) {
            hosted(
                row(fullLead(), .yourMove, nil),
                canEdit: false,
                canConvert: false,
                store: standardStore(),
                deck: deckFixture()
            )
        }
    }

    /// Finances grant — the quiet `EST $14,200` line under the stamp.
    func testRenderFinancesCard() {
        snapshot("day_sheet_card_finances", size: CGSize(width: Self.cardWidth, height: 700)) {
            hosted(
                row(fullLead(), .today, .quoteSent),
                canEdit: true,
                canConvert: true,
                store: financesStore(),
                deck: deckFixture()
            )
        }
    }

    /// The five seconds after the press: the stamp button settles into an
    /// accent OUTLINE carrying the milestone's own confirmation copy, with
    /// `UNDO` on the trailing edge. The card has not moved — the sheet is
    /// frozen on its pre-press groups until the window closes.
    func testRenderPendingUndoCard() async {
        let lead = fullLead()
        let committer = heldCommitter(online: true)
        await committer.press(.quoteSent, lead: lead, userId: "u1", canEdit: true)

        snapshot("day_sheet_card_pending_undo", size: CGSize(width: Self.cardWidth, height: 700)) {
            hosted(
                row(lead, .late(days: 3), .quoteSent),
                canEdit: true,
                canConvert: true,
                store: standardStore(),
                deck: deckFixture(),
                committer: committer
            )
        }
    }

    /// The same window, pressed with no signal: identical confirmation, plus a
    /// quiet neutral `QUEUED` tag. The operator is told the truth — it counted,
    /// it just has not left the phone yet.
    func testRenderQueuedPendingCard() async {
        let lead = fullLead()
        let committer = heldCommitter(online: false)
        await committer.press(.quoteSent, lead: lead, userId: "u1", canEdit: true)

        snapshot("day_sheet_card_pending_queued", size: CGSize(width: Self.cardWidth, height: 700)) {
            hosted(
                row(lead, .late(days: 3), .quoteSent),
                canEdit: true,
                canConvert: true,
                store: standardStore(),
                deck: deckFixture(),
                committer: committer
            )
        }
    }

    /// Sparse — no photos and no add rights, no deck, no summary, no email.
    /// Strip, deck tile, summary band and the EMAIL button are ABSENT, not
    /// blank; CALL and TEXT flex to fill the row.
    func testRenderSparseCard() {
        snapshot("day_sheet_card_sparse", size: CGSize(width: Self.cardWidth, height: 340)) {
            hosted(
                row(sparseLead(), .waiting(back: "BACK FRI"), nil),
                canEdit: false,
                canConvert: false,
                store: standardStore()
            )
        }
    }
}
#endif
