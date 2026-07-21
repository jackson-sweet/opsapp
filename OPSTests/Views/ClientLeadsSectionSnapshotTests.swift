//
//  ClientLeadsSectionSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the assembled ClientLeadsSection on the
//  client profile: the open-leads list with the collapsed won/lost history
//  peek, and the create-enabled empty state. Renders via a real
//  UIHostingController in a UIWindow (ImageRenderer mis-resolves OPS asset
//  colors). Leads are injected through the section's preview seem — no network.
//  A rendering harness, not an assertion.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/ClientLeadsSectionSnapshotTests
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class ClientLeadsSectionSnapshotTests: XCTestCase {

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-client-leads-section-shots", isDirectory: true)
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
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.9))

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

    private func sampleClient() -> Client {
        Client(id: "CL1", name: "Calloway Homes", companyId: "c1")
    }

    private func granted() -> PermissionStore {
        let p = PermissionStore()
        p.permissions = ["pipeline.view": "all", "pipeline.create": "all"]
        return p
    }

    private func lead(_ id: String, _ title: String, _ stage: PipelineStage,
                      est: Double? = nil, actual: Double? = nil, activity: Double = 1_000) -> Opportunity {
        let o = Opportunity(id: id, companyId: "c1", contactName: "—", stage: stage)
        o.clientId = "CL1"
        o.title = title
        o.assignedTo = "u1"
        o.estimatedValue = est
        o.actualValue = actual
        o.lastActivityAt = Date(timeIntervalSince1970: activity)
        return o
    }

    private func populatedLeads() -> [Opportunity] {
        [
            lead("O1", "Roof tear-off — 28 sq", .quoting, est: 18_500, activity: 3_000),
            lead("O2", "Gutter run — 140 lf", .followUp, est: 4_200, activity: 2_000),
            lead("W1", "Deck rebuild — 320 sf", .won, est: 21_000, actual: 21_500, activity: 500),
            lead("L1", "Siding quote", .lost, est: 9_000, activity: 400),
        ]
    }

    @ViewBuilder private func host(_ leads: [Opportunity]) -> some View {
        NavigationStack {
            ScrollView {
                ClientLeadsSection(client: sampleClient(), previewLeads: leads)
                    .padding(.horizontal)
                    .padding(.top, 12)
            }
        }
        .environmentObject(DataController())
        .environmentObject(granted())
        .background(Color.black)
    }

    /// Open leads (job-first) + the collapsed "// 1 WON · 1 LOST" history peek.
    func testRenderPopulated() {
        snapshot("client_leads_section_populated", size: CGSize(width: 393, height: 560)) {
            host(populatedLeads())
        }
    }

    /// No leads yet, create-enabled → the "No leads yet / Create one?" empty state.
    func testRenderEmptyCreate() {
        snapshot("client_leads_section_empty_create", size: CGSize(width: 393, height: 360)) {
            host([])
        }
    }
}
#endif
