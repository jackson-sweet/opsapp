//
//  PendingWorkSnapshotTests.swift
//  OPSTests
//
//  SYNC RECOVERY · T6 — visual proof for the PENDING WORK recovery screen. Uses
//  the same UIHostingController + UIWindow + drawHierarchy harness as
//  SyncStatusPanelSnapshotTests (ImageRenderer can't resolve asset colours), and
//  drives the PURE `PendingWorkView` from hand-built `RecoveryInventory` fixtures
//  assembled by the pure builder — no SwiftData container needed. Each of the five
//  states renders to a PNG attachment.
//
//  Existence proof: render success (non-nil, correct size, non-blank pixels) plus
//  content-richness differentiation — a populated inventory draws materially more
//  than the zero-state, proving the fixture actually flowed into the rendered
//  layout. (The rows/bundle/draft/orphan/actions/empty state DO carry real
//  `.accessibilityLabel`s for VoiceOver — §15 — but SwiftUI does not realise its
//  accessibility tree inside a headless XCTest host with no active a11y client,
//  so a rendered-tree label harvest is not a reliable signal here; the pixel-level
//  differentiation is.)
//
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult --output-path <dir>
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class PendingWorkSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 390
    private let deviceHeight: CGFloat = 844

    // Fixed clock so relative times / backoff render byte-stably.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-pending-work-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Fixtures

    /// A parked site-visit bundle (Charles) + a loose failed op → NEEDS ATTENTION.
    private func attentionInventory() -> RecoveryInventory {
        let clientOp = SyncOpSnapshot(
            id: UUID(), entityType: "client", entityId: "c1", operationType: "create",
            status: "parked", retryCount: 20,
            lastAttemptedAt: ago(7200), lastError: "22023 unsupported_opportunity_field", createdAt: ago(7200)
        )
        let deckOp = SyncOpSnapshot(
            id: UUID(), entityType: "deckDesign", entityId: "deck1", operationType: "linkOpportunity",
            status: "parked", retryCount: 20,
            lastAttemptedAt: ago(7000), lastError: "23514 different opportunity", createdAt: ago(7000)
        )
        let looseOp = SyncOpSnapshot(
            id: UUID(), entityType: "project", entityId: "p1", operationType: "update",
            status: "failed", retryCount: 20,
            lastAttemptedAt: ago(3600), lastError: "foreign key constraint", createdAt: ago(3600)
        )
        let autocreate = AutocreateSnapshot(
            clientId: "c1", name: "Charles", createdAt: ago(7200),
            attempts: 3, lastAttemptAt: ago(600), lastError: "400 source_thread_key", isParked: true
        )
        let draft = DraftSnapshot(
            id: "d1", siteVisitId: "v1", clientId: "c1", opportunityId: nil,
            displayName: "Charles", createdAt: ago(7200), lastCommittedAt: nil
        )
        let artifact = ArtifactSnapshot(id: "a1", siteVisitId: "v1", deckDesignId: "deck1", kind: "deck")

        return RecoveryInventory.build(
            ops: [clientOp, deckOp, looseOp], autocreates: [autocreate], photos: [],
            drafts: [draft], artifacts: [artifact], orphans: [], now: now
        )
    }

    /// In-flight work — a saving op, a backing-off create, a draining autocreate.
    private func sendingInventory() -> RecoveryInventory {
        let inProgress = SyncOpSnapshot(
            id: UUID(), entityType: "project", entityId: "p2", operationType: "update",
            status: "inProgress", retryCount: 0, lastAttemptedAt: ago(3), lastError: nil, createdAt: ago(300)
        )
        let backingOff = SyncOpSnapshot(
            id: UUID(), entityType: "projectTask", entityId: "t1", operationType: "create",
            status: "pending", retryCount: 3, lastAttemptedAt: ago(2), lastError: nil, createdAt: ago(280)
        )
        let autocreate = AutocreateSnapshot(
            clientId: "c2", name: "Lyall", createdAt: ago(200),
            attempts: 0, lastAttemptAt: nil, lastError: nil, isParked: false
        )
        return RecoveryInventory.build(
            ops: [inProgress, backingOff], autocreates: [autocreate], photos: [],
            drafts: [], artifacts: [], orphans: [], now: now
        )
    }

    /// An abandoned, never-committed capture → DRAFTS.
    private func draftsInventory() -> RecoveryInventory {
        let draft = DraftSnapshot(
            id: "d2", siteVisitId: "v2", clientId: nil, opportunityId: nil,
            displayName: "Site visit — Elm St", createdAt: ago(3600), lastCommittedAt: nil
        )
        return RecoveryInventory.build(
            ops: [], autocreates: [], photos: [], drafts: [draft], artifacts: [], orphans: [], now: now
        )
    }

    /// Chronic server-orphaned deck designs → NOT LINKED.
    private func unlinkedInventory() -> RecoveryInventory {
        let a = OrphanDesignSnapshot(id: "o1", title: "Site visit deck", createdAt: ago(1800), hasThumbnail: true)
        let b = OrphanDesignSnapshot(id: "o2", title: "Back deck", createdAt: ago(90000), hasThumbnail: false)
        return RecoveryInventory.build(
            ops: [], autocreates: [], photos: [], drafts: [], artifacts: [], orphans: [a, b], now: now
        )
    }

    private func emptyInventory() -> RecoveryInventory {
        RecoveryInventory.build(ops: [], autocreates: [], photos: [], drafts: [], artifacts: [], orphans: [], now: now)
    }

    // MARK: - Tests

    func testAttentionWithBundle() {
        let inventory = attentionInventory()
        XCTAssertFalse(inventory.attention.isEmpty, "Fixture should populate the attention section")
        let image = renderAndAttach("pending-work-attention", inventory: inventory)
        assertContentRendered(image, context: "attention")
    }

    func testSending() {
        let inventory = sendingInventory()
        XCTAssertFalse(inventory.sending.isEmpty, "Fixture should populate the sending section")
        let image = renderAndAttach("pending-work-sending", inventory: inventory)
        assertContentRendered(image, context: "sending")
    }

    func testDrafts() {
        let inventory = draftsInventory()
        XCTAssertFalse(inventory.drafts.isEmpty, "Fixture should populate the drafts section")
        let image = renderAndAttach("pending-work-drafts", inventory: inventory)
        assertContentRendered(image, context: "drafts")
    }

    func testUnlinked() {
        let inventory = unlinkedInventory()
        XCTAssertFalse(inventory.unlinked.isEmpty, "Fixture should populate the unlinked section")
        let image = renderAndAttach("pending-work-unlinked", inventory: inventory)
        assertContentRendered(image, context: "unlinked")
    }

    func testEmpty() {
        let inventory = emptyInventory()
        XCTAssertTrue(inventory.isEmpty, "Fixture should be the zero-state")
        let image = renderAndAttach("pending-work-empty", inventory: inventory)
        // The zero-state still draws its hero glyph + label (non-blank)…
        XCTAssertGreaterThan(nonBlackPixelCount(image), 0, "empty: zero-state hero + label should draw")
        // …but is materially sparser than a populated screen.
        let populated = render(attentionInventory())
        XCTAssertLessThan(
            nonBlackPixelCount(image), nonBlackPixelCount(populated),
            "empty state should render sparser than a populated screen"
        )
    }

    // MARK: - Render harness (drawHierarchy, not ImageRenderer — asset colours)

    /// Renders the pure view full-screen and returns the image (no attachment).
    private func render(_ inventory: RecoveryInventory) -> UIImage {
        let root = PendingWorkView(inventory: inventory, actions: .noop, now: now)
            .frame(width: deviceWidth, height: deviceHeight)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)

        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .dark
        let size = CGSize(width: deviceWidth, height: deviceHeight)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = UIColor.black

        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
    }

    /// Renders, attaches the PNG, and asserts a real (correctly-sized, non-blank)
    /// frame was produced. Returns the image for further per-state assertions.
    @discardableResult
    private func renderAndAttach(_ name: String, inventory: RecoveryInventory) -> UIImage {
        let image = render(inventory)

        if let data = image.pngData() {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "\(name).png"
            attachment.lifetime = .keepAlways
            add(attachment)
            try? data.write(to: outDir.appendingPathComponent("\(name).png"))
            print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
        } else {
            XCTFail("Failed to render \(name)")
        }

        XCTAssertEqual(Int(image.size.width), Int(deviceWidth), "\(name): unexpected width")
        XCTAssertEqual(Int(image.size.height), Int(deviceHeight), "\(name): unexpected height")
        XCTAssertGreaterThan(nonBlackPixelCount(image), 0, "\(name): render produced a blank frame")
        return image
    }

    // MARK: - Content assertions

    /// A populated inventory draws sections / rows / text / glyphs (and, for
    /// attention, the accent CTA) the zero-state never does, so its rendered
    /// bitmap MUST differ from the empty render. A byte-level inequality is a
    /// deterministic proof the fixture flowed into the layout — no brittle pixel
    /// threshold, no dependence on the (headless-unrealised) accessibility tree.
    private func assertContentRendered(_ image: UIImage, context: String) {
        XCTAssertNotEqual(
            rgbaBytes(image), rgbaBytes(render(emptyInventory())),
            "\(context): populated screen must render differently from the empty state"
        )
    }

    /// The drawn bitmap as raw RGBA bytes — the basis for both the non-blank
    /// check and the content-differentiation comparison.
    private func rgbaBytes(_ image: UIImage) -> [UInt8] {
        guard let cg = image.cgImage else { return [] }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return [] }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// Count of meaningfully non-black pixels — a stable content-presence signal
    /// (render success + empty-vs-populated sparsity) from the drawn bitmap.
    private func nonBlackPixelCount(_ image: UIImage) -> Int {
        let pixels = rgbaBytes(image)
        var count = 0
        var index = 0
        let limit = pixels.count - 3
        while index <= limit {
            if pixels[index] > 24 || pixels[index + 1] > 24 || pixels[index + 2] > 24 {
                count += 1
            }
            index += 4
        }
        return count
    }
}
#endif
