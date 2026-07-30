//
//  LeadSiteVisitRowSnapshotTests.swift
//  OPSTests
//
//  The lead activity rail's two site-visit states, side by side:
//
//    05_timeline_visit_resolved — the visit is on this device, so the row is
//       the SITE VISIT RECORD card, sitting among the plain message rows.
//    06_timeline_visit_unresolved — the same activity with no local visit
//       (captured on a teammate's phone; site visits never sync). The row
//       stays exactly the plain row it has always been. No empty card, no
//       invented content.
//
//  Both shots render the REAL `ActivityTimeline` over a real model container,
//  so what the PNG shows is what the rail does.
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import OPS

@MainActor
final class LeadSiteVisitRowSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393
    private let visitId = "visit-1"
    private let base = Date(timeIntervalSince1970: 1_785_000_000)

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-site-visit-record-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Fixtures

    private func lead() -> Opportunity {
        let o = Opportunity(
            id: "lead-1",
            companyId: "company-1",
            contactName: "Helen Calloway",
            stage: .quoting
        )
        o.estimatedValue = 18_400
        o.address = "1100 Maple Ave, Springfield"
        return o
    }

    /// One email and one completed site visit — the rail's normal mix.
    private func activities() -> [Activity] {
        let email = Activity(
            id: "act-email",
            opportunityId: "lead-1",
            companyId: "company-1",
            type: .email,
            createdAt: base.addingTimeInterval(-3_600)
        )
        email.subject = "Re: Deck quote"
        email.direction = "inbound"
        email.fromEmail = "helen.calloway@example.com"
        email.bodyText = "Sounds good — see you Thursday."

        let visit = Activity(
            id: "act-visit",
            opportunityId: "lead-1",
            companyId: "company-1",
            type: .siteVisit,
            createdAt: base
        )
        visit.subject = "Site visit"
        visit.siteVisitId = visitId
        visit.createdBy = "user-1"
        visit.bodyText = "2 photos, 1 measurement"

        return [visit, email]
    }

    /// Seeds the device-local capture the resolved shot needs.
    private func seedLocalVisit(into context: ModelContext) {
        let visit = SiteVisit(id: visitId, opportunityId: "lead-1", companyId: "company-1")
        visit.address = "1100 Maple Ave, Springfield"
        context.insert(visit)

        context.insert(TeamMember(
            id: "user-1",
            firstName: "Dale",
            lastName: "Harmon",
            role: "Field"
        ))

        for (index, kind) in [SiteVisitCaptureArtifactKind.photo, .photo].enumerated() {
            context.insert(SiteVisitCaptureArtifact(
                siteVisitId: visitId,
                companyId: "company-1",
                kind: kind,
                source: .camera,
                capturedAt: base.addingTimeInterval(Double(index))
            ))
        }
        context.insert(SiteVisitCaptureArtifact(
            siteVisitId: visitId,
            companyId: "company-1",
            kind: .measurement,
            source: .laser,
            title: "Deck footprint",
            body: "12' x 16'",
            capturedAt: base.addingTimeInterval(3)
        ))
        context.insert(SiteVisitIdentityDraft(
            siteVisitId: visitId,
            companyId: "company-1",
            clientName: "Calloway Ltd"
        ))
    }

    // MARK: - The pair

    func testTimelineRendersTheRecordWhenTheVisitIsOnThisDevice() throws {
        try snapshotTimeline("05_timeline_visit_resolved", seedVisit: true)
    }

    func testTimelineKeepsThePlainRowWhenTheVisitIsNotOnThisDevice() throws {
        try snapshotTimeline("06_timeline_visit_unresolved", seedVisit: false)
    }

    // MARK: - Harness

    private func snapshotTimeline(_ name: String, seedVisit: Bool) throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: OPSSchemaV21.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        if seedVisit { seedLocalVisit(into: container.mainContext) }

        let permissions = PermissionStore()
        permissions.permissions = ["finances.view": "all"]

        // `.fixedSize` vertically pins the rail to its intrinsic height. A row's
        // direction rule is `maxHeight: .infinity` (it runs the row's height in
        // the real app, where a scroll view leaves no slack), so in a
        // fixed-height harness that row would otherwise swallow every spare
        // point and render as a bare stripe.
        let root = VStack(spacing: 0) {
            ActivityTimeline(
                activities: activities(),
                transitions: [],
                opportunity: lead()
            )
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .frame(width: deviceWidth, alignment: .top)
        .background(OPSStyle.Colors.background)
        .environmentObject(permissions)
        .environmentObject(DataController())
        .modelContainer(container)
        .environment(\.colorScheme, .dark)

        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .dark
        // Fixed height: the shot must include the plain email row UNDER the
        // record, because "does the record sit coherently beside the message
        // rows" is the question these PNGs exist to answer.
        let frame = CGRect(origin: .zero, size: CGSize(width: deviceWidth, height: 440))
        host.view.frame = frame
        host.view.backgroundColor = .black

        // Draw the hosted VIEW inside the app's own window — a test-created
        // window renders blank mid-suite (see AppHostWindow).
        let window = try AppHostWindow.acquire()
        let previous = window.rootViewController
        defer {
            window.rootViewController = previous
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        window.rootViewController = host
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        let renderer = UIGraphicsImageRenderer(size: frame.size)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let data = try XCTUnwrap(image.pngData(), "render \(name)")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
    }
}
#endif
