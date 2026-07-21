//
//  ClientLeadRowSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for ClientLeadRow — the client-profile lead row
//  (job-first, same grammar as the ContactDetailView project rows). Renders an
//  open row and a dimmed won-history row via a real UIHostingController in a
//  UIWindow (ImageRenderer mis-resolves OPS asset colors). A rendering harness,
//  not an assertion.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/ClientLeadRowSnapshotTests
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class ClientLeadRowSnapshotTests: XCTestCase {

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-client-lead-row-shots", isDirectory: true)
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

    private func openLead() -> Opportunity {
        let o = Opportunity(id: "L1", companyId: "c1", contactName: "Jordan Blake", stage: .quoting)
        o.title = "Fence replacement — 90 lf"
        o.estimatedValue = 6_800
        return o
    }

    private func wonLead() -> Opportunity {
        let o = Opportunity(id: "L2", companyId: "c1", contactName: "Maple Corp", stage: .won)
        o.title = "Deck rebuild — 320 sf"
        o.actualValue = 21_500
        return o
    }

    func testRenderOpenRow() {
        snapshot("client_lead_row_open", size: CGSize(width: 360, height: 64)) {
            ClientLeadRow(lead: openLead())
                .frame(width: 360)
                .background(Color.black)
        }
    }

    func testRenderHistoryWonRow() {
        snapshot("client_lead_row_history_won", size: CGSize(width: 360, height: 64)) {
            ClientLeadRow(lead: wonLead(), isHistory: true)
                .frame(width: 360)
                .background(Color.black)
        }
    }
}
#endif
