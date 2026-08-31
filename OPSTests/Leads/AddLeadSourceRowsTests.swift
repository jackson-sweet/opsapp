//
//  AddLeadSourceRowsTests.swift
//  OPSTests
//
//  Bug 55f40233 — NEW LEAD can start from the device address book
//  (IMPORT FROM CONTACTS, which FILLS the form) or from the OPS client base
//  (USE EXISTING CLIENT, which BINDS the client). Both rows vanish behind a
//  single bound chip once a client is linked.
//
//  Covered here:
//    · LeadForm.adoptClient — identity adopted, job fields preserved, source
//      flipped to repeat_client, coordinates honest.
//    · ClientPickerSheet's .leadSeed lane gates — the two lanes that create a
//      client (and therefore auto-queue its pipeline lead) must be closed, or
//      they race the lead the operator is composing into a duplicate.
//    · Rendered proof of the unbound and bound states.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/AddLeadSourceRowsTests
//  Shots land in NSTemporaryDirectory()/ops-add-lead-source-shots.
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import OPS

@MainActor
final class AddLeadSourceRowsTests: XCTestCase {

    /// A ModelContext does NOT keep its container alive — an unretained
    /// container deallocates and the next insert traps inside SwiftData.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - LeadForm.adoptClient

    /// Binding an existing client adopts their identity and flips SOURCE to
    /// repeat_client — an existing customer calling about new work is exactly
    /// that. The operator's job fields are theirs and must survive.
    func testAdoptClientBindsIdentityAndFlipsSource() {
        var form = LeadForm()
        form.title = "Cedar deck rebuild"
        form.estimatedValue = "12,500"
        form.notes = "Wants it before the long weekend"
        form.stage = .quoting
        form.priority = "high"

        let client = Client(
            id: "cl1",
            name: "Calloway Homes",
            email: "hi@calloway.com",
            phoneNumber: "5551234567",
            address: "1240 Maple Ave",
            companyId: "co-1"
        )
        client.latitude = 43.65
        client.longitude = -79.38

        form.adoptClient(client)

        // Identity adopted
        XCTAssertEqual(form.contactName, "Calloway Homes")
        XCTAssertEqual(form.email, "hi@calloway.com")
        XCTAssertEqual(form.phone, "5551234567")
        XCTAssertEqual(form.address, "1240 Maple Ave")
        XCTAssertEqual(form.latitude, 43.65)
        XCTAssertEqual(form.longitude, -79.38)
        XCTAssertEqual(form.lastResolvedAddress, "1240 Maple Ave")

        // Source flipped
        XCTAssertEqual(form.source, "repeat_client")

        // Job fields untouched — they are the operator's
        XCTAssertEqual(form.title, "Cedar deck rebuild")
        XCTAssertEqual(form.estimatedValue, "12,500")
        XCTAssertEqual(form.notes, "Wants it before the long weekend")
        XCTAssertEqual(form.stage, .quoting)
        XCTAssertEqual(form.priority, "high")
    }

    /// A client with no coordinates must NULL any coordinates already on the
    /// form rather than leave them pointing at a previous address — a stale
    /// lat/lng sends a crew to the wrong site.
    func testAdoptClientWithoutCoordsClearsStaleCoords() {
        var form = LeadForm()
        form.address = "99 Old Street, Vancouver, BC"
        form.addressResolved("99 Old Street, Vancouver, BC", latitude: 49.28, longitude: -123.12)

        form.adoptClient(Client(id: "cl2", name: "Maple Corp", address: "1240 Maple Ave"))

        XCTAssertEqual(form.address, "1240 Maple Ave")
        XCTAssertNil(form.latitude)
        XCTAssertNil(form.longitude)
        XCTAssertNil(form.lastResolvedAddress)
    }

    /// After adopting, a hand-edited address drops the client's coordinates
    /// through the form's own divergence rule — same contract as every other
    /// address edit in the app.
    func testAdoptClientThenHandEditDropsCoords() {
        var form = LeadForm()
        let client = Client(id: "cl3", name: "Calloway Homes", address: "1240 Maple Ave")
        client.latitude = 43.65
        client.longitude = -79.38

        form.adoptClient(client)
        XCTAssertNotNil(form.latitude, "precondition: adopting carried the coords")

        form.address = "77 Elsewhere Rd"
        form.addressTextChanged("77 Elsewhere Rd")

        XCTAssertNil(form.latitude)
        XCTAssertNil(form.longitude)
    }

    /// A client carrying no contact channels still binds cleanly — empty
    /// strings, not stale values from whatever was typed before.
    func testAdoptSparseClientClearsContactChannels() {
        var form = LeadForm()
        form.phone = "555-0100"
        form.email = "typed@example.com"

        form.adoptClient(Client(id: "cl4", name: "Winona Keys"))

        XCTAssertEqual(form.contactName, "Winona Keys")
        XCTAssertEqual(form.phone, "")
        XCTAssertEqual(form.email, "")
        XCTAssertEqual(form.address, "")
    }

    /// `repeat_client` must be an offerable SOURCE chip, or adopting a client
    /// would leave the chip group with nothing selected and the next tap would
    /// silently overwrite a correct value.
    func testRepeatClientIsAnOfferableSourceChip() {
        XCTAssertTrue(
            LeadFormView.sourceOptions.contains { $0.id == "repeat_client" },
            "adoptClient sets source=repeat_client — the chip must exist"
        )
    }

    // MARK: - ClientPickerSheet lane gates

    /// The lead-seed context closes both lanes that CREATE a client. Each one
    /// funnels through ClientLeadAutocreateQueue, which would mint a second
    /// lead alongside the one being composed.
    func testLeadSeedContextHidesContactAndCreateLanes() {
        XCTAssertFalse(
            ClientPickerSheet.showsPhoneContacts(
                context: .leadSeed,
                canRead: true,
                searchEmpty: false
            ),
            "the phone-contact lane creates a client and auto-queues its lead"
        )
        XCTAssertFalse(
            ClientPickerSheet.showsCreateRow(context: .leadSeed),
            "the create row funnels through ClientSheet, which queues a lead"
        )
    }

    /// Project reassignment is unchanged — both lanes stay exactly as they
    /// were, including the search-empty and permission conditions.
    func testProjectReassignContextKeepsBothLanes() {
        XCTAssertTrue(
            ClientPickerSheet.showsPhoneContacts(
                context: .projectReassign,
                canRead: true,
                searchEmpty: false
            )
        )
        XCTAssertFalse(
            ClientPickerSheet.showsPhoneContacts(
                context: .projectReassign,
                canRead: false,
                searchEmpty: false
            ),
            "no contacts access ⇒ no phone rows, unchanged"
        )
        XCTAssertFalse(
            ClientPickerSheet.showsPhoneContacts(
                context: .projectReassign,
                canRead: true,
                searchEmpty: true
            ),
            "an empty field lists existing clients, not the whole address book"
        )
        XCTAssertTrue(ClientPickerSheet.showsCreateRow(context: .projectReassign))
    }

    /// The lead-seed gate is absolute: it does not soften when contacts ARE
    /// readable and a search is in flight.
    func testLeadSeedGateIgnoresContactPermissionAndSearchState() {
        for canRead in [true, false] {
            for searchEmpty in [true, false] {
                XCTAssertFalse(
                    ClientPickerSheet.showsPhoneContacts(
                        context: .leadSeed,
                        canRead: canRead,
                        searchEmpty: searchEmpty
                    ),
                    "leadSeed never lists phone contacts (canRead=\(canRead), searchEmpty=\(searchEmpty))"
                )
            }
        }
    }

    // MARK: - Rendered proof

    /// Unbound: the two source rows sit above the form's CONTACT NAME field.
    func testRendersUnboundSourceRows() throws {
        let image = try render(seedClient: nil)
        attach(image, named: "add-lead-source-rows-unbound")
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// Bound (opened from a client's page): the chip replaces both rows — the
    /// operator's current reality, not every possible one.
    func testRendersBoundClientChip() throws {
        let client = Client(
            id: "cl-render",
            name: "Calloway Homes",
            email: "hi@calloway.com",
            phoneNumber: "5551234567",
            address: "1240 Maple Ave",
            companyId: "co-1"
        )
        let image = try render(seedClient: client)
        attach(image, named: "add-lead-source-rows-bound")
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - Harness

    private var snapshotSchema: Schema {
        // AddressAutocompleteField's known-place suggestions fetch Project,
        // Client, and SubClient; SwiftData wants the whole relationship
        // closure, not just the rows a test seeds. This is the proven set
        // DetailsTabSnapshotTests builds against.
        Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            ProjectVinylOrderMarker.self,
            DeckDesign.self
        ])
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: snapshotSchema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: snapshotSchema, configurations: [configuration])
        retainedContainers.append(container)
        return container
    }

    private func render(seedClient: Client?) throws -> UIImage {
        let container = try makeContainer()
        let size = CGSize(width: 393, height: 620)

        return try FixedSizeSnapshot.render(
            AddLeadSheet(seedClient: seedClient)
                .environmentObject(DataController())
                .modelContainer(container),
            size: size,
            minimumSettle: 0.4
        )
    }

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-add-lead-source-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func attach(_ image: UIImage, named name: String) {
        guard let data = image.pngData() else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name)")
    }
}
#endif
