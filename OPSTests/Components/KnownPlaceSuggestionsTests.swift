//
//  KnownPlaceSuggestionsTests.swift
//  OPSTests
//
//  Bug 29b75dce — the matcher behind known-place address suggestions. Pure
//  input/output over a snapshot of local rows, so it is pinned directly rather
//  than through a field: what the snapshot includes, how a shared address
//  collapses, and the three match tiers an operator expects.
//

import XCTest
import SwiftData
import CoreLocation
@testable import OPS

@MainActor
final class KnownPlaceSuggestionsTests: XCTestCase {

    // MARK: - Snapshot

    func testCandidatesSkipEmptyAddresses() throws {
        let context = try makeContext()

        let addressed = Project(id: "project-1", title: "Cedar deck", status: .accepted)
        addressed.address = "1486 Finlayson Pl, Victoria"
        context.insert(addressed)

        let blankProject = Project(id: "project-2", title: "No address yet", status: .rfq)
        blankProject.address = "   "
        context.insert(blankProject)

        let nilProject = Project(id: "project-3", title: "Never entered", status: .rfq)
        context.insert(nilProject)

        let blankClient = Client(id: "client-1", name: "Northline Builders", address: "")
        context.insert(blankClient)
        try context.save()

        let candidates = KnownPlaceSuggestions.candidates(in: context)

        XCTAssertEqual(candidates.map(\.id), ["project-project-1"])
    }

    /// A client and one of their jobs sharing an address is the common case,
    /// not the exception. One row, and it is the job — the job's title says
    /// more about the address than the client's name does.
    func testDedupePrefersJob() throws {
        let context = try makeContext()

        let project = Project(id: "project-1", title: "Cedar deck", status: .accepted)
        project.address = "1486 Finlayson Pl, Victoria"
        context.insert(project)

        let client = Client(
            id: "client-1",
            name: "Northline Builders",
            address: "1486 FINLAYSON PL,  Victoria"
        )
        context.insert(client)
        try context.save()

        let candidates = KnownPlaceSuggestions.candidates(in: context)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.kind, .job)
        XCTAssertEqual(candidates.first?.context, "Cedar deck")
    }

    /// A trashed job's address is a tombstone, not a suggestion.
    func testCandidatesSkipTrashedRows() throws {
        let context = try makeContext()

        let live = Project(id: "project-live", title: "Cedar deck", status: .accepted)
        live.address = "1486 Finlayson Pl, Victoria"
        context.insert(live)

        let trashed = Project(id: "project-trashed", title: "Cancelled job", status: .rfq)
        trashed.address = "22 Wharf St, Victoria"
        trashed.deletedAt = Date()
        context.insert(trashed)

        let trashedClient = Client(id: "client-trashed", name: "Old Co", address: "9 Store St")
        trashedClient.deletedAt = Date()
        context.insert(trashedClient)
        try context.save()

        XCTAssertEqual(KnownPlaceSuggestions.candidates(in: context).map(\.id), ["project-project-live"])
    }

    /// The client's stored coordinate rides along, so selecting an
    /// OPS-canonical address needs no MapKit geocode round trip.
    func testClientCandidateCarriesItsStoredCoordinate() throws {
        let context = try makeContext()

        let client = Client(id: "client-1", name: "Northline Builders", address: "9 Store St, Victoria")
        client.latitude = 48.4284
        client.longitude = -123.3656
        context.insert(client)
        try context.save()

        let coordinate = KnownPlaceSuggestions.candidates(in: context).first?.coordinate

        XCTAssertEqual(coordinate?.latitude ?? 0, 48.4284, accuracy: 0.0001)
        XCTAssertEqual(coordinate?.longitude ?? 0, -123.3656, accuracy: 0.0001)
    }

    // MARK: - Matching

    func testMatchByAddressPrefix() {
        let matches = KnownPlaceSuggestions.match("1486", in: sampleCandidates())

        XCTAssertEqual(matches.first?.address, "1486 Finlayson Pl, Victoria")
    }

    /// Typing who it is for, rather than where it is — the Calendar behaviour.
    func testMatchByContextName() {
        let matches = KnownPlaceSuggestions.match("phoebe", in: sampleCandidates())

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.context, "Phoebe J. Southwood")
        XCTAssertEqual(matches.first?.kind, .client)
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(KnownPlaceSuggestions.match("", in: sampleCandidates()).isEmpty)
        XCTAssertTrue(KnownPlaceSuggestions.match("   ", in: sampleCandidates()).isEmpty)
    }

    func testLimitCaps() {
        let candidates = (1...4).map { index in
            KnownPlace(
                id: "place-\(index)",
                kind: .job,
                address: "22 Wharf St Unit \(index)",
                context: "Job \(index)",
                latitude: nil,
                longitude: nil
            )
        }

        XCTAssertEqual(KnownPlaceSuggestions.match("22 wharf", in: candidates).count, 3)
    }

    func testNormalizeFoldsCaseDiacriticsPunctuation() {
        XCTAssertEqual(
            KnownPlaceSuggestions.normalize("Ch\u{00E2}teaux-Blvd,  SUITE 4"),
            "chateaux blvd suite 4"
        )
    }

    // MARK: - Fixtures

    private func sampleCandidates() -> [KnownPlace] {
        [
            KnownPlace(
                id: "project-1", kind: .job,
                address: "1486 Finlayson Pl, Victoria", context: "Cedar deck",
                latitude: nil, longitude: nil
            ),
            KnownPlace(
                id: "client-1", kind: .client,
                address: "22 Wharf St, Victoria", context: "Phoebe J. Southwood",
                latitude: nil, longitude: nil
            )
        ]
    }

    /// Containers outlive the contexts they vend, for the whole test case. A
    /// `ModelContext` does not keep its container alive, and inserting into a
    /// context whose container has been released traps inside SwiftData
    /// (uncatchable EXC_BREAKPOINT) — the test dies before its first assertion.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try makeContainer()
        retainedContainers.append(container)
        return ModelContext(container)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: OPSSchemaV25.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
