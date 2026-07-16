//
//  SiteVisitFormSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the site-visit form overhaul (site-visit report):
//  the numbered, sequential layout (1 · LEAD → 2 · CHECKLIST → 3 · NOTES)
//  and the per-field REQUIRED → DONE markers. Renders the real
//  SiteVisitCaptureView against an in-memory OPSSchemaV15 container with a
//  bound name-only lead, so the name group reads DONE while the contact and
//  address groups still read REQUIRED — both states in one shot.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/SiteVisitFormSnapshotTests
//  Shots land in NSTemporaryDirectory()/ops-site-visit-form-shots.
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitFormSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-site-visit-form-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: OPSSchemaV15.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testLeadFormNumberedStepsAndRequiredMarkers() throws {
        let container = try inMemoryContainer()
        // A bound lead with only a name — name/company group satisfies (DONE),
        // contact + address groups stay outstanding (REQUIRED).
        let lead = Opportunity(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            contactName: "Dale Harmon",
            stage: .newLead
        )

        let view = SiteVisitCaptureView(opportunity: lead, onCreateProject: { _ in })
            .environmentObject(DataController())
            .modelContainer(container)

        snapshot("01_lead_form_required_markers", height: 900, settle: 3.0) { view }
    }

    private func snapshot<V: View>(
        _ name: String,
        height: CGFloat,
        settle: TimeInterval,
        @ViewBuilder _ content: () -> V
    ) {
        let size = CGSize(width: deviceWidth, height: height)
        let host = UIHostingController(
            rootView: content()
                .frame(width: deviceWidth, height: height)
                .environment(\.colorScheme, .dark)
        )
        host.view.backgroundColor = .black

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

        // The view builds its view-model in an async .task and shows a spinner
        // until it's ready — give it room to load and lay out.
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

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
        print("📸 SNAPSHOT \(name)")
    }
}
#endif
