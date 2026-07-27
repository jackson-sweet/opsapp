//
//  LeadsDiscardSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the Leads Discard action (2026-07-05).
//  Renders the Phase C reason chooser, the legacy first-run explainer, and the
//  LostReasonSheet (which carries the "Discard instead" escape hatch) to PNGs.
//  Uses a real UIHostingController in a UIWindow — unlike ImageRenderer this
//  resolves OPS asset-catalog colors AND lays out the sheets' ScrollView +
//  bottom-anchored footer faithfully. A rendering harness, not an assertion.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/LeadsDiscardSnapshotTests
//  Extract: xcrun xcresulttool export attachments --path <result.xcresult> ...
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class LeadsDiscardSnapshotTests: XCTestCase {

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-leads-discard-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, size: CGSize, @ViewBuilder _ content: () -> V) {
        let host = UIHostingController(rootView: content())
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))

        let renderer = UIGraphicsImageRenderer(size: size)
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

    private func sampleLead() -> Opportunity {
        Opportunity.preview(
            title: "Fence replacement — 90 lf",
            contactName: "Jordan Blake",
            stage: .quoted,
            estimatedValue: 6_800,
            daysInStage: 4
        )
    }

    /// First-run education — DISCARD vs LOST, with the rose DISCARD LEAD CTA.
    func testRenderDiscardExplainer() {
        snapshot("discard_explainer", size: CGSize(width: 393, height: 560)) {
            DiscardExplainerSheet(opportunity: sampleLead(), onConfirm: { true })
        }
    }

    /// Phase C correction surface — reasons are visible at once and every row
    /// is the submit action; no second confirmation or mandatory note.
    func testRenderPhaseCDispositionReasons() {
        snapshot("phase_c_disposition_reasons", size: CGSize(width: 393, height: 852)) {
            LeadDispositionReasonSheet(
                opportunity: sampleLead(),
                onSelect: { _, _ in true }
            )
        }
    }

    /// The mark-as-lost sheet now carries the subordinate "Not a real lead?
    /// Discard instead" escape hatch below CONFIRM LOST.
    func testRenderLostSheetWithDiscardLink() {
        snapshot("lost_sheet_discard_link", size: CGSize(width: 393, height: 760)) {
            LostReasonSheet(opportunity: sampleLead())
                .environmentObject(DataController())
        }
    }
}
#endif
