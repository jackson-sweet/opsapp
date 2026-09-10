//
//  LeadsFieldReports0908SnapshotTests.swift
//  OPSTests
//
//  Visual proof for the 2026-09-08 leads field-report cluster:
//
//    908888f6_client_row_…    — the CLIENT row the moment an assignment lands
//                               (link written, roster still in flight) beside
//                               a lead that genuinely has none. Before the fix
//                               both showed ASSIGN CLIENT.
//    18dea542_link_project_…  — LINK PROJECT rows state WHO the project is for
//                               before where it is; search can only match what
//                               the operator can see.
//    53e869f6_title_editing   — the dossier header IS the editor, at the
//                               header's own type size, with the dossier's
//                               check / cancel controls.
//    52cc8dae_banner_present  — a booked visit leads the dossier: the fact,
//                               then START · REBOOK · CANCEL.
//    52cc8dae_banner_absent   — the same head with no open booking. Nothing
//                               renders. No empty banner, no placeholder.
//    52cc8dae_banner_future   — booked for a later day: no START, because a
//                               visit you are not at cannot be started.
//    9a49bd47_client_actions  — NEW LEAD and BOOK VISIT, named and visible on
//                               the client's Leads section.
//
//  The three dossier-head shots render header + banner + hero exactly as
//  LeadDetailView composes them, because the question the banner raises is not
//  "does it look right on its own" but "how does it read against the KPI strip
//  under it".
//
//  Rendered through FixedSizeSnapshot (the app host's own window), never a
//  test-created UIWindow.
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import OPS

@MainActor
final class LeadsFieldReports0908SnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393
    /// Fixed so the tokens in every shot read the same on any run.
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func lead(title: String? = "Jaime Taylor - Lead") -> Opportunity {
        let opportunity = Opportunity(
            id: "11111111-1111-1111-1111-111111111111",
            companyId: "22222222-2222-2222-2222-222222222222",
            contactName: "Jaime Taylor",
            stage: .qualifying
        )
        opportunity.title = title
        opportunity.address = "1240 Maple Ave, Victoria BC"
        opportunity.estimatedValue = 14_200
        return opportunity
    }

    private func controller(for lead: Opportunity) -> LeadFieldEditController {
        LeadFieldEditController(opportunity: lead) { _ in lead }
    }

    private func permissions() -> PermissionStore {
        let store = PermissionStore()
        store.permissions = [
            "pipeline.view": "all",
            "pipeline.create": "all",
            "pipeline.edit": "all",
            "pipeline.convert": "all",
            "pipeline.assign": "all"
        ]
        return store
    }

    // MARK: - 53e869f6 · hold the header to edit it

    func testHeaderTitleEditingState() throws {
        let opportunity = lead()
        let fieldEdit = controller(for: opportunity)
        fieldEdit.begin(.title)

        let image = try FixedSizeSnapshot.render(
            VStack(spacing: 0) {
                LeadDetailStickyHeader(
                    opportunity: opportunity,
                    clientName: "Traditional Homes",
                    canEdit: true,
                    fieldEdit: fieldEdit
                )
                Spacer(minLength: 0)
            }
            .frame(width: deviceWidth, alignment: .top)
            .background(OPSStyle.Colors.background)
            .environmentObject(permissions())
            .environment(\.colorScheme, .dark),
            size: CGSize(width: deviceWidth, height: 260),
            minimumSettle: 0.3
        )

        XCTAssertTrue(fieldEdit.isEditing(.title))
        attach(image, named: "53e869f6_title_editing")
    }

    /// The same header at rest, so the pair reads as before / during.
    func testHeaderTitleAtRest() throws {
        let opportunity = lead()
        let fieldEdit = controller(for: opportunity)

        let image = try FixedSizeSnapshot.render(
            VStack(spacing: 0) {
                LeadDetailStickyHeader(
                    opportunity: opportunity,
                    clientName: "Traditional Homes",
                    canEdit: true,
                    fieldEdit: fieldEdit
                )
                Spacer(minLength: 0)
            }
            .frame(width: deviceWidth, alignment: .top)
            .background(OPSStyle.Colors.background)
            .environmentObject(permissions())
            .environment(\.colorScheme, .dark),
            size: CGSize(width: deviceWidth, height: 260),
            minimumSettle: 0.3
        )

        attach(image, named: "53e869f6_title_at_rest")
    }

    // MARK: - 52cc8dae · the booked visit leads the dossier

    func testVisitBannerPresent() throws {
        try snapshotDossierHead(
            scheduledAt: now.addingTimeInterval(3 * 3_600),   // later today
            name: "52cc8dae_banner_present"
        )
    }

    func testVisitBannerForALaterDayOffersNoStart() throws {
        try snapshotDossierHead(
            scheduledAt: now.addingTimeInterval(4 * 86_400),  // next week
            name: "52cc8dae_banner_future"
        )
    }

    /// Bug 2b085519 — a booking from two weeks ago that nobody closed reads
    /// as missed with its real date, and offers REBOOK / CANCEL, not START.
    func testVisitBannerForAnEarlierDayReadsMissed() throws {
        try snapshotDossierHead(
            scheduledAt: now.addingTimeInterval(-13 * 86_400),
            name: "2b085519_banner_missed"
        )
    }

    func testVisitBannerAbsentWithNoBooking() throws {
        try snapshotDossierHead(scheduledAt: nil, name: "52cc8dae_banner_absent")
    }

    /// The dossier head EXACTLY as `LeadDetailView` composes it: pinned
    /// header, then the banner, then the hero. Rendering the banner on its own
    /// would prove it looks right and hide the only question that matters —
    /// how it reads against the KPI strip immediately under it.
    private func snapshotDossierHead(scheduledAt: Date?, name: String) throws {
        let opportunity = lead(title: "Cedar deck rebuild, 320 sq ft")
        // A nudge behind the appointment — the fact the KPI strip's NEXT TOUCH
        // cell now carries alone, since the banner states the visit.
        opportunity.nextFollowUpAt = now.addingTimeInterval(9 * 86_400)
        let state = LeadSiteVisitBannerState.resolve(scheduledAt: scheduledAt, now: now)

        let image = try FixedSizeSnapshot.render(
            VStack(spacing: 0) {
                LeadDetailStickyHeader(
                    opportunity: opportunity,
                    clientName: "Traditional Homes"
                )
                LeadSiteVisitBanner(state: state, canManage: true, onDetails: {})
                    .padding(.bottom, scheduledAt == nil ? 0 : 18)
                DetailHero(
                    opportunity: opportunity,
                    clientName: "Traditional Homes",
                    assigneeName: "Jackson S"
                )
                Spacer(minLength: 0)
            }
            .frame(width: deviceWidth, alignment: .top)
            .background(OPSStyle.Colors.background)
            .environmentObject(permissions())
            .environment(\.colorScheme, .dark),
            size: CGSize(width: deviceWidth, height: 440),
            minimumSettle: 0.3
        )

        attach(image, named: name)
    }

    // MARK: - 9a49bd47 · starting work from a client

    func testClientLeadsSectionOffersBothCreateVerbs() throws {
        let container = try makeContainer()
        let client = Client(
            id: "33333333-3333-3333-3333-333333333333",
            name: "Traditional Homes",
            email: "office@traditionalhomes.example",
            phoneNumber: "250-555-0142",
            companyId: "22222222-2222-2222-2222-222222222222"
        )

        let image = try FixedSizeSnapshot.render(
            VStack(spacing: 0) {
                ClientLeadsSection(client: client, previewLeads: [])
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                Spacer(minLength: 0)
            }
            .frame(width: deviceWidth, alignment: .top)
            .padding(.top, OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.background)
            .environmentObject(DataController())
            .environmentObject(permissions())
            .modelContainer(container)
            .environment(\.colorScheme, .dark),
            size: CGSize(width: deviceWidth, height: 340),
            minimumSettle: 0.5
        )

        attach(image, named: "9a49bd47_client_actions")
    }

    // MARK: - 908888f6 · the CLIENT row states the link

    /// Three CLIENT rows, top to bottom: the instant after a picker choice
    /// lands (link written, roster still in flight — the row shows the name
    /// the operator just chose), the same lead reopened before the client's
    /// own row arrives (`LINKED CLIENT`, no chevron, because there is nothing
    /// to open yet), and a lead that genuinely has no client.
    ///
    /// Before the fix the first two rendered the third — which is what "add
    /// client does not work" looked like from the truck.
    func testClientRowAfterAnAssignmentLands() async throws {
        let justPicked = lead(title: "Cedar deck rebuild, 320 sq ft")
        let pickedController = controller(for: justPicked)
        justPicked.clientId = Self.clientId
        await pickedController.commitClient(id: Self.clientId, name: "Traditional Homes")

        let unnamed = lead(title: "Cedar deck rebuild, 320 sq ft")
        unnamed.clientId = Self.clientId

        let unassigned = lead(title: "Cedar deck rebuild, 320 sq ft")

        let image = try FixedSizeSnapshot.render(
            VStack(spacing: OPSStyle.Layout.spacing3) {
                // Clipped to the CLIENT row — the rest of the dossier document
                // is proved by its own snapshots and only crowds this one.
                clientRowStrip(
                    lead: justPicked,
                    rosterState: .notOnFile,
                    fieldEdit: pickedController
                )
                clientRowStrip(lead: unnamed, rosterState: .notOnFile)
                clientRowStrip(lead: unassigned, rosterState: .noClient)
            }
            .frame(width: deviceWidth, alignment: .top)
            .padding(.vertical, OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.background)
            .environmentObject(permissions())
            .environment(\.colorScheme, .dark),
            size: CGSize(width: deviceWidth, height: 460),
            minimumSettle: 0.3
        )

        attach(image, named: "908888f6_client_row_linked_vs_absent")
    }

    private static let clientId = "33333333-3333-3333-3333-333333333333"

    /// The dossier document, cropped to its header and CLIENT row.
    private func clientRowStrip(
        lead: Opportunity,
        rosterState: LeadContactRosterState,
        fieldEdit: LeadFieldEditController? = nil
    ) -> some View {
        LeadDetailsDocument(
            lead: lead,
            client: nil,
            rosterState: rosterState,
            canEdit: true,
            projectName: nil,
            attachments: [],
            estimates: [],
            fieldEdit: fieldEdit ?? controller(for: lead)
        )
        .frame(width: deviceWidth, height: 126, alignment: .top)
        .clipped()
    }

    // MARK: - 18dea542 · the LINK PROJECT row says who it is for

    /// Search can only match what the operator can see, so the row now leads
    /// with the client and the address follows it.
    func testLinkProjectRowsStateTheirClient() throws {
        let candidates = [
            ConvertToProjectSheet.ProjectLinkCandidate(
                id: "aaaaaaaa-1111-1111-1111-111111111111",
                title: "Rear deck rebuild",
                address: "3998 Holland Ave, Victoria BC V8X 1V4",
                status: nil,
                sameAddress: true,
                sameClient: true,
                clientName: "Traditional Homes",
                contactName: "Helen Calloway"
            ),
            ConvertToProjectSheet.ProjectLinkCandidate(
                id: "bbbbbbbb-2222-2222-2222-222222222222",
                title: "1616 Barksdale Dr",
                address: "1616 Barksdale Dr, Victoria BC",
                status: nil,
                sameAddress: false,
                sameClient: true,
                clientName: "Calloway Homes",
                contactName: nil
            ),
            // A project this phone has not cached: address only, exactly as
            // the row read before.
            ConvertToProjectSheet.ProjectLinkCandidate(
                id: "cccccccc-3333-3333-3333-333333333333",
                title: "2779 Schooner Way",
                address: "2779 Schooner Way, Pender Island BC",
                status: nil,
                sameAddress: false,
                sameClient: false,
                clientName: nil,
                contactName: nil
            )
        ]

        let image = try FixedSizeSnapshot.render(
            ProjectLinkPickerSheet(
                candidates: candidates,
                selectedProjectId: candidates[0].id,
                onSelect: { _ in }
            )
            .environmentObject(permissions()),
            size: CGSize(width: deviceWidth, height: 500),
            minimumSettle: 0.4
        )

        attach(image, named: "18dea542_link_project_rows")
    }

    // MARK: - Harness

    private func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Schema(versionedSchema: OPSSchemaCurrent.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        retainedContainers.append(container)
        return container
    }

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-field-reports-leads-0908", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func attach(_ image: UIImage, named name: String) {
        guard let data = image.pngData() else {
            XCTFail("\(name) produced no PNG data")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("SNAPSHOT \(name)")
    }
}
#endif
