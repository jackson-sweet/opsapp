//
//  LeadsConsoleSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the LEADS console redesign (2026-08-05). Renders the REAL
//  screens — `LeadsTabView` and the stage browser — hosted in the app's own
//  window at a fixed 390×844 dark frame (`FixedSizeSnapshot`; ImageRenderer is
//  banned here — asset colours resolve yellow and the SwiftUI lifecycle never
//  runs). A rendering harness, not an assertion suite: it writes PNGs for a
//  human to inspect and for docs/artifacts.
//
//  Six proofs, one per spec §11.7 row: working band, quiet band, search with
//  matches, NO MATCHES, NEWEST flat with assignee labels, stage browser tabs
//  (WON active).
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/LeadsConsoleSnapshotTests \
//          -resultBundlePath /private/tmp/leads-console-proofs.xcresult
//  Export: xcrun xcresulttool export attachments \
//          --path /private/tmp/leads-console-proofs.xcresult \
//          --output-path docs/artifacts/leads-console-redesign
//

#if DEBUG
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class LeadsConsoleSnapshotTests: XCTestCase {

    private let frameSize = CGSize(width: 390, height: 844)

    /// Lowercase uuids, matching Postgres — the roster folds case, and these
    /// prove it against the `User` rows below.
    private let jasonId = "11111111-1111-1111-1111-111111111111"
    private let danaId  = "22222222-2222-2222-2222-222222222222"

    private var outDir: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("leads-console-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Fixtures

    /// `Opportunity.preview` exposes neither the text fields search reads
    /// (description, address, email, phone, source) nor an exact `createdAt`,
    /// so the harness widens it locally rather than changing production
    /// preview support.
    private func lead(
        id: String,
        contact: String,
        title: String,
        stage: PipelineStage = .quoted,
        value: Double? = nil,
        daysInStage: Int = 2,
        followUpInDays: Int? = nil,
        assignedTo: String? = nil,
        source: String? = nil,
        address: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        createdDaysAgo: Int = 0,
        closedDaysAgo: Int? = nil,
        awaitingReplyDaysAgo: Int? = nil
    ) -> Opportunity {
        let opp = Opportunity.preview(
            id: id,
            title: title,
            contactName: contact,
            stage: stage,
            estimatedValue: value,
            daysInStage: daysInStage,
            nextFollowUpDaysFromNow: followUpInDays,
            assignedTo: assignedTo,
            actualCloseDaysAgo: closedDaysAgo
        )
        opp.source = source
        opp.address = address
        opp.contactEmail = email
        opp.contactPhone = phone
        opp.createdAt = Date().addingTimeInterval(-Double(createdDaysAgo) * 86_400)
        if let awaitingReplyDaysAgo {
            opp.lastMessageDirection = "in"
            opp.lastInboundAt = Calendar.current.date(
                byAdding: .day, value: -awaitingReplyDaysAgo, to: Date()
            )
        }
        return opp
    }

    /// A working pipeline: two overdue, one due today, one awaiting your reply,
    /// one fresh, one parked — spread across two operators and one unassigned
    /// lead so the assignee token has all three of its forms to show.
    private func workingPipeline() -> [Opportunity] {
        [
            lead(id: "aaaaaaa1-0000-0000-0000-000000000001",
                 contact: "Marcus Webb", title: "Roof tear-off — 28 sq",
                 stage: .quoting, value: 14_200, daysInStage: 5, followUpInDays: -3,
                 assignedTo: jasonId, source: "referral",
                 address: "1240 Maple Ave", email: "marcus@example.com",
                 phone: "(555) 123-4567", createdDaysAgo: 9),
            lead(id: "aaaaaaa2-0000-0000-0000-000000000002",
                 contact: "Cedar Ridge HOA", title: "Cedar Ridge roof replacement",
                 stage: .negotiation, value: 78_500, daysInStage: 6, followUpInDays: -5,
                 assignedTo: danaId, source: "website", createdDaysAgo: 14),
            lead(id: "aaaaaaa3-0000-0000-0000-000000000003",
                 contact: "The Hensons", title: "Window install — 8 units",
                 stage: .quoted, value: 11_800, daysInStage: 3, followUpInDays: 0,
                 assignedTo: jasonId, createdDaysAgo: 4),
            lead(id: "aaaaaaa4-0000-0000-0000-000000000004",
                 contact: "Aimee Watari", title: "Skylight quote question",
                 stage: .quoted, value: 6_400, daysInStage: 2,
                 assignedTo: nil, source: "email", createdDaysAgo: 2,
                 awaitingReplyDaysAgo: 2),
            lead(id: "aaaaaaa5-0000-0000-0000-000000000005",
                 contact: "Jamie Park", title: "Leak repair — kitchen ceiling",
                 stage: .newLead, value: 2_200, daysInStage: 0,
                 assignedTo: danaId, createdDaysAgo: 0),
            lead(id: "aaaaaaa6-0000-0000-0000-000000000006",
                 contact: "Dana Ruiz", title: "Gutter replacement — 140 lf",
                 stage: .quoted, value: 8_600, daysInStage: 4, followUpInDays: 3,
                 assignedTo: jasonId, source: "referral", createdDaysAgo: 6),
            // Closed work — invisible to the queue, browsable in the stage
            // browser, and the source of the band's WON figure.
            lead(id: "aaaaaaa7-0000-0000-0000-000000000007",
                 contact: "Tom Liu", title: "Maple Lane porch",
                 stage: .won, value: 11_200, daysInStage: 12,
                 assignedTo: jasonId, source: "referral",
                 createdDaysAgo: 30, closedDaysAgo: 3),
            lead(id: "aaaaaaa8-0000-0000-0000-000000000008",
                 contact: "Jen Foster", title: "Foster patio rebuild",
                 stage: .won, value: 9_400, daysInStage: 6,
                 assignedTo: danaId, createdDaysAgo: 21, closedDaysAgo: 1),
            lead(id: "aaaaaaa9-0000-0000-0000-000000000009",
                 contact: "Beacon Hill LLC", title: "Beacon Hill addition",
                 stage: .lost, value: 26_500, daysInStage: 20,
                 assignedTo: jasonId, createdDaysAgo: 40, closedDaysAgo: 5)
        ]
    }

    /// Nothing due, nobody waiting on the operator — open leads only.
    private func quietPipeline() -> [Opportunity] {
        [
            lead(id: "bbbbbbb1-0000-0000-0000-000000000001",
                 contact: "Mike Smith", title: "Smith deck addition",
                 stage: .newLead, value: 8_500, daysInStage: 1,
                 assignedTo: jasonId, createdDaysAgo: 1),
            lead(id: "bbbbbbb2-0000-0000-0000-000000000002",
                 contact: "Anna Patel", title: "Hilltop pool deck",
                 stage: .quoting, value: 22_400, daysInStage: 2,
                 assignedTo: danaId, source: "referral", createdDaysAgo: 3),
            lead(id: "bbbbbbb3-0000-0000-0000-000000000003",
                 contact: "Pat Donovan", title: "Donovan fence rebuild",
                 stage: .followUp, value: 6_200, daysInStage: 2, followUpInDays: 6,
                 assignedTo: jasonId, createdDaysAgo: 5)
        ]
    }

    /// Two named operators — the smallest crew that opens the assignment gate.
    /// No company id is set on the harness DataController, so the roster
    /// resolves through the lead-referenced arm; that is the same path a
    /// departed teammate's leads take in production.
    private func crewContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: User.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(User(id: jasonId, firstName: "Jason", lastName: "Wagner",
                            role: .crew, companyId: "preview-company"))
        context.insert(User(id: danaId, firstName: "Dana", lastName: "Whitfield",
                            role: .crew, companyId: "preview-company"))
        // A hand-made context does NOT autosave, and the view's `@Query` reads
        // the container's main context — without this the console renders with
        // an empty roster and the assignment gate silently closed.
        try context.save()
        return container
    }

    private func console(
        _ opportunities: [Opportunity],
        controls: LeadsListControls = LeadsListControls(),
        container: ModelContainer
    ) -> some View {
        LeadsTabView(
            viewModel: .previewLoaded(opportunities: opportunities, currentUserId: jasonId),
            initialControls: controls
        )
        .leadsPreviewEnvironment()
        .modelContainer(container)
    }

    // MARK: - Proofs (spec §11.7)

    func testRenderConsoleBandStates() throws {
        let container = try crewContainer()
        renderToPNG("console-band-working") {
            console(workingPipeline(), container: container)
        }
        renderToPNG("console-band-quiet") {
            console(quietPipeline(), container: container)
        }
    }

    func testRenderConsoleSearchStates() throws {
        let container = try crewContainer()
        renderToPNG("console-search-matches") {
            console(workingPipeline(),
                    controls: LeadsListControls(query: "roof"),
                    container: container)
        }
        renderToPNG("console-search-no-matches") {
            console(workingPipeline(),
                    controls: LeadsListControls(query: "zzz"),
                    container: container)
        }
    }

    func testRenderConsoleNewestSort() throws {
        let container = try crewContainer()
        renderToPNG("console-sort-newest") {
            console(workingPipeline(),
                    controls: LeadsListControls(sort: .newest),
                    container: container)
        }
    }

    func testRenderStageBrowserWonTab() throws {
        let container = try crewContainer()
        let leads = workingPipeline()
        let viewModel = PipelineViewModel.previewLoaded(
            opportunities: leads, currentUserId: jasonId
        )
        let roster = LeadsQueryEngine.roster(
            users: [
                User(id: jasonId, firstName: "Jason", lastName: "Wagner",
                     role: .crew, companyId: "preview-company"),
                User(id: danaId, firstName: "Dana", lastName: "Whitfield",
                     role: .crew, companyId: "preview-company")
            ],
            leads: leads,
            companyId: "preview-company"
        )
        var index: [String: String] = [:]
        for lead in leads {
            index[lead.id] = LeadsQueryEngine.assigneeLabel(for: lead.assignedTo, roster: roster)
        }
        renderToPNG("stage-browser-won") {
            NavigationStack {
                PipelineStageListView(stage: .won, viewModel: viewModel, assigneeIndex: index)
            }
            .leadsPreviewEnvironment()
            .modelContainer(container)
        }
    }

    // MARK: - Render harness (FixedSizeSnapshot — app-hosted, fixed size)

    private func renderToPNG(_ name: String, @ViewBuilder _ make: () -> some View) {
        let image: UIImage
        do {
            image = try FixedSizeSnapshot.render(make(), size: frameSize)
        } catch {
            XCTFail("Could not acquire the app host window for \(name): \(error)")
            return
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
        print("📸 SNAPSHOT \(name) -> \(outDir.appendingPathComponent("\(name).png").path)")
    }
}
#endif
