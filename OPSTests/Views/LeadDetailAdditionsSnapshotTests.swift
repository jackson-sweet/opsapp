//
//  LeadDetailAdditionsSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the 2026-07-14 Leads additions: photos
//  section (strip + queued tiles + empty CTA), deck design section (card +
//  start row), the name-first edit-sheet header with the shared L-id, and
//  the address-autocomplete lead form. Renders PNGs via ImageRenderer using
//  the DEBUG preview seeders — a rendering harness, not an assertion test.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/LeadDetailAdditionsSnapshotTests
//  Shots land in NSTemporaryDirectory()/ops-lead-additions-shots.
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
@testable import OPS

@MainActor
final class LeadDetailAdditionsSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-lead-additions-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// UIHostingController + UIWindow + drawHierarchy — the Books-harness
    /// pattern. ImageRenderer leaves ScrollView content blank and skips
    /// onAppear; rendering the live window layer captures scrollers, AsyncImage
    /// placeholders, and locally-loaded images exactly as the app draws them.
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
        // produces a blank white image (first-run failure of this harness).
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

        // Let layout passes, image decodes, and onAppear-driven state settle.
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

    override func tearDown() {
        LeadImageService.shared._setQueueForSnapshots([])
        super.tearDown()
    }

    // MARK: - Fixtures

    private func leadFixture() -> Opportunity {
        let opp = Opportunity.preview(
            id: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            title: "Roof tear-off, 28 sq",
            contactName: "Helen Calloway",
            stage: .quoted,
            estimatedValue: 14_200,
            daysInStage: 9
        )
        opp.contactPhone = "(555) 123-4567"
        opp.contactEmail = "helen@example.com"
        opp.address = "1240 Maple Ave, Victoria"
        opp.source = "referral"
        return opp
    }

    /// Flat-color JPEG saved through ImageFileManager under a local:// id so
    /// the queued tile resolves exactly like a real offline capture.
    private func seedQueuedPhotos(for opportunityId: String, colors: [UIColor]) -> [PendingLeadImageUpload] {
        var uploads: [PendingLeadImageUpload] = []
        for (index, color) in colors.enumerated() {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 320))
            let image = renderer.image { ctx in
                color.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
            }
            guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
            // Must live under local://project_images/ — the only local://
            // namespace ImageFileManager.getFileURL resolves.
            let localID = "local://project_images/lead_snapshot_\(opportunityId)_\(index).jpg"
            guard ImageFileManager.shared.saveImage(data: data, localID: localID) else { continue }
            uploads.append(PendingLeadImageUpload(
                localURL: localID,
                opportunityId: opportunityId,
                companyId: "preview-company",
                timestamp: Date().addingTimeInterval(Double(-index))
            ))
        }
        return uploads
    }

    private func squareDrawing() -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.vertices = [
            DeckVertex(id: "a", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "b", position: CGPoint(x: 160, y: 0)),
            DeckVertex(id: "c", position: CGPoint(x: 160, y: 120)),
            DeckVertex(id: "d", position: CGPoint(x: 0, y: 120))
        ]
        drawing.edges = [
            DeckEdge(id: "ab", startVertexId: "a", endVertexId: "b"),
            DeckEdge(id: "bc", startVertexId: "b", endVertexId: "c"),
            DeckEdge(id: "cd", startVertexId: "c", endVertexId: "d"),
            DeckEdge(id: "da", startVertexId: "d", endVertexId: "a")
        ]
        drawing.scaleFactor = 1
        return drawing
    }

    // MARK: - Photos section

    func testRenderPhotosEmptyManage() {
        LeadImageService.shared._setQueueForSnapshots([])
        snapshot("lead_photos_empty_manage", height: 220) {
            VStack(spacing: 0) {
                LeadPhotosSection(opportunity: leadFixture(), canManage: true)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                Spacer(minLength: 0)
            }
        }
    }

    func testRenderPhotosStripWithQueuedTiles() {
        let lead = leadFixture()
        let uploads = seedQueuedPhotos(
            for: lead.id,
            colors: [.systemGray2, .systemGray4, .systemGray5]
        )
        XCTAssertEqual(uploads.count, 3, "queued fixtures must all save")
        LeadImageService.shared._setQueueForSnapshots(uploads)

        snapshot("lead_photos_strip_queued", height: 260) {
            VStack(spacing: 0) {
                LeadPhotosSection(opportunity: lead, canManage: true)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Deck section

    func testRenderDeckStartRow() throws {
        let container = try ModelContainer(
            for: DeckDesign.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        snapshot("lead_deck_start_row", height: 240) {
            VStack(spacing: 0) {
                LeadDeckSection(opportunity: leadFixture(), canManage: true)
                    .environmentObject(PermissionStore.previewWithFullAccess())
                    .modelContainer(container)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                Spacer(minLength: 0)
            }
        }
    }

    func testRenderDeckCard() throws {
        let container = try ModelContainer(
            for: DeckDesign.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let lead = leadFixture()
        let design = DeckDesign(
            companyId: "preview-company",
            opportunityId: lead.id,
            title: "Calloway Deck",
            drawingDataJSON: squareDrawing().toJSON()
        )
        design.updatedAt = Date().addingTimeInterval(-3_600)
        container.mainContext.insert(design)
        try container.mainContext.save()

        snapshot("lead_deck_card", height: 440) {
            VStack(spacing: 0) {
                LeadDeckSection(opportunity: lead, canManage: true)
                    .environmentObject(PermissionStore.previewWithFullAccess())
                    .modelContainer(container)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Edit sheet (name-first header) + lead form (autocomplete field)

    func testRenderEditLeadSheet() {
        snapshot("edit_lead_sheet") {
            EditLeadSheet(opportunity: leadFixture())
                .leadsPreviewEnvironment()
        }
    }

    /// Direct render of the shared form so the SITE ADDRESS autocomplete
    /// field's chrome parity (48pt row, token borders, location affordance)
    /// is visible outside the sheet scroller.
    private struct LeadFormHarness: View {
        @State private var form = LeadForm()
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LeadFormView(form: $form)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing2)
            }
        }
    }

    func testRenderLeadForm() {
        snapshot("lead_form_address") {
            LeadFormHarness()
        }
    }

    // MARK: - Full detail composition (sections placement + share affordance)

    func testRenderLeadDetail() throws {
        let container = try ModelContainer(
            for: DeckDesign.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let lead = leadFixture()
        LeadImageService.shared._setQueueForSnapshots(
            seedQueuedPhotos(for: lead.id, colors: [.systemGray3, .systemGray5])
        )

        snapshot("lead_detail_full", height: 1_600) {
            LeadDetailView(opportunity: lead)
                .modelContainer(container)
                .leadsPreviewEnvironment()
        }
    }
}
#endif
