//
//  DeckDictationSnapshotTests.swift
//  OPSTests
//
//  Visual proof for bug 722b1606 — the speed-draw dictate button fix.
//  Renders the length-entry strip (mic + continue now on the 56pt standard
//  touch target) and the deck settings sheet's new DICTATION toggle to PNGs.
//  NOT pass/fail — writes images for inspection.
//
//  Rendered via UIHostingController + UIWindow + drawHierarchy so
//  asset-catalog colors resolve and onAppear runs (ImageRenderer does
//  neither). Dictation auto-start cannot go hot here: the test runner has no
//  speech grant, so the isAuthorized guard keeps the mic cold — which is
//  exactly the shipping behavior for an unauthorized user.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DeckDictationSnapshotTests
//

#if DEBUG
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class DeckDictationSnapshotTests: XCTestCase {

    private let frameSize = CGSize(width: 393, height: 852) // iPhone 17

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-deck-dictation-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, view: V, size: CGSize? = nil) {
        let renderSize = size ?? frameSize
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: renderSize)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: renderSize))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Let onAppear + the panel transition settle before capture.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))

        let renderer = UIGraphicsImageRenderer(size: renderSize)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name)")
    }

    /// Build a view model already sitting in `.enteringLength` — the state the
    /// dictate button lives in. Drawing data is assigned post-init so the
    /// anchor vertex survives (the JSON round-trip prunes edgeless vertices).
    private func lengthEntryViewModel(draft: PerimeterLengthDraft) -> DeckBuilderViewModel {
        var data = DeckDrawingData()
        data.vertices = [DeckVertex(id: "v1", position: CGPoint(x: 200, y: 300))]

        let design = DeckDesign(
            companyId: "company-1",
            title: "Dictation proof deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        let viewModel = DeckBuilderViewModel(deckDesign: design)
        viewModel.drawingData = data
        viewModel.beginPerimeterEntry(fromVertexId: "v1")
        viewModel.selectPerimeterDirection(.right)
        if draft.totalInches > 0 {
            viewModel.updatePerimeterLength(draft)
        }
        return viewModel
    }

    /// The strip mounted the way DeckBuilderView mounts it — bottom-anchored
    /// over the canvas backdrop.
    private func stripHarness(viewModel: DeckBuilderViewModel) -> some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            PerimeterSpeedDrawOverlayView(viewModel: viewModel)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    func testRenderLengthEntryStrip() {
        // 1. Fresh length entry — mic idle on the 56pt standard target,
        //    continue disabled (no length yet).
        snapshot(
            "01-length-entry-empty",
            view: stripHarness(viewModel: lengthEntryViewModel(draft: .zero(system: .imperial)))
        )

        // 2. Length dialed in — continue lights up (44pt accent circle inside
        //    its 56pt hit zone; visuals unchanged from the shipped design).
        snapshot(
            "02-length-entry-filled",
            view: stripHarness(viewModel: lengthEntryViewModel(
                draft: .imperial(feet: 12, inches: 6, sixteenths: 0)
            ))
        )
    }

    func testRenderSettingsDictationToggle() throws {
        let container = try ModelContainer(
            for: CatalogItem.self, CatalogVariant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let design = DeckDesign(
            companyId: "company-1",
            title: "Dictation proof deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        let viewModel = DeckBuilderViewModel(deckDesign: design)

        // 3. Settings sheet — DICTATION section with the default-on toggle.
        //    Tall viewport so the whole list (dictation sits after vinyl)
        //    lands in one frame without scripted scrolling.
        snapshot(
            "03-settings-dictation-toggle",
            view: DeckSettingsSheet(viewModel: viewModel)
                .modelContainer(container),
            size: CGSize(width: 393, height: 1500)
        )
    }
}
#endif
