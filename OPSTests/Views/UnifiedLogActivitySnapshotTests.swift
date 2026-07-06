//
//  UnifiedLogActivitySnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the redesigned unified activity capture
//  sheet (WEB/IOS activity unification, 2026-07). Renders the sheet to PNGs
//  via SwiftUI's `ImageRenderer`. A rendering harness, not an assertion test —
//  it writes images for a human/agent to inspect (design taste checkpoint).
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/UnifiedLogActivitySnapshotTests \
//          -clonedSourcePackagesDirPath .spm-local -derivedDataPath .build-unified
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult ...
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class UnifiedLogActivitySnapshotTests: XCTestCase {

    // drawHierarchy (real UIKit render) — unlike ImageRenderer, this lays out
    // ScrollView content, so the whole sheet renders, not just the pinned chrome.
    private func snapshot<V: View>(_ name: String, size: CGSize, @ViewBuilder _ content: () -> V) {
        let root = content()
            .frame(width: size.width, height: size.height)
            .background(OPSStyle.Colors.background)
            .preferredColorScheme(.dark)

        let host = UIHostingController(rootView: root)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .black
        host.overrideUserInterfaceStyle = .dark

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Let SwiftUI complete its layout pass before capturing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let uiRenderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = uiRenderer.image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        let outDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-unified-activity-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt) → \(outDir.path)")
    }

    /// CALL, locked lead, all conditional zones (direction + duration + outcome
    /// + follow-up) visible together.
    func testRenderUnifiedSheetCall() {
        let lead = Opportunity(companyId: "preview", contactName: "Helen Calloway", stage: .qualifying)
        let vm = UnifiedLogActivityViewModel(entry: .leadDetail(lead))
        vm.selectedType = .call
        vm.direction = "inbound"
        vm.outcome = "booked_visit"
        vm.durationMinutes = 12
        vm.notesText = "Wants a quote for the deck rebuild. Sending photos tonight."
        vm.suggestedFollowUp = (title: "Send deck rebuild quote",
                                dueAt: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date())
        snapshot("unified_activity_call", size: CGSize(width: 393, height: 1120)) {
            UnifiedLogActivitySheet(viewModel: vm)
                .environmentObject(DataController())
        }
    }

    /// NOTE type, locked lead — confirms direction/duration hide, no follow-up
    /// cue, and the note-only capture reads clean.
    func testRenderUnifiedSheetNote() {
        let lead = Opportunity(companyId: "preview", contactName: "Marcus Webb", stage: .quoting)
        let vm = UnifiedLogActivityViewModel(entry: .leadDetail(lead))
        vm.selectedType = .note
        vm.notesText = "Dropped off the signed contract. Crew starts Monday."
        snapshot("unified_activity_note", size: CGSize(width: 393, height: 780)) {
            UnifiedLogActivitySheet(viewModel: vm)
                .environmentObject(DataController())
        }
    }
}
#endif
