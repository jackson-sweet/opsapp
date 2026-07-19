//
//  LeadDetailDataTests.swift
//  OPSTests
//
//  ON FILE roster-state logic for the lead detail's CLIENT row (Leads
//  redesign spec §5.9) — mirrors the web DealContactRow normalization rules:
//  the lead's person mirrors the client (name OR email OR phone), matches a
//  sub_clients row (email first, then name), or is not on file yet.
//

import XCTest
@testable import OPS

@MainActor
final class LeadDetailDataTests: XCTestCase {

    private func client(name: String = "Calloway Homes",
                        email: String? = nil,
                        phone: String? = nil) -> Client {
        Client(id: "c1", name: name, email: email, phoneNumber: phone)
    }

    private func sub(name: String, email: String? = nil, deleted: Bool = false) -> SubClient {
        let s = SubClient(id: UUID().uuidString, name: name, email: email)
        if deleted { s.deletedAt = Date() }
        return s
    }

    func testMirrorsClientByName() {
        XCTAssertEqual(
            LeadDetailViewModel.rosterState(
                contactName: "  Calloway Homes ", contactEmail: nil, contactPhone: nil,
                client: client(), subClients: []),
            .mirrorsClient)
    }

    func testMirrorsClientByPhone() {
        XCTAssertEqual(
            LeadDetailViewModel.rosterState(
                contactName: "Helen", contactEmail: nil, contactPhone: "(555) 123-4567",
                client: client(phone: "555-123-4567"), subClients: []),
            .mirrorsClient)
    }

    func testOnFileByEmail() {
        XCTAssertEqual(
            LeadDetailViewModel.rosterState(
                contactName: "Someone Else", contactEmail: "HELEN@x.com", contactPhone: nil,
                client: client(), subClients: [sub(name: "Helen C", email: "helen@x.com")]),
            .onFile)
    }

    func testOnFileByName() {
        XCTAssertEqual(
            LeadDetailViewModel.rosterState(
                contactName: "Helen Calloway", contactEmail: nil, contactPhone: nil,
                client: client(), subClients: [sub(name: "helen calloway")]),
            .onFile)
    }

    func testDeletedSubClientDoesNotCount() {
        XCTAssertEqual(
            LeadDetailViewModel.rosterState(
                contactName: "Helen Calloway", contactEmail: nil, contactPhone: nil,
                client: client(), subClients: [sub(name: "Helen Calloway", deleted: true)]),
            .notOnFile)
    }

    func testNotOnFile() {
        XCTAssertEqual(
            LeadDetailViewModel.rosterState(
                contactName: "Helen Calloway", contactEmail: "h@x.com", contactPhone: nil,
                client: client(), subClients: [sub(name: "Marcus Webb", email: "m@x.com")]),
            .notOnFile)
    }

    func testNoClient() {
        XCTAssertEqual(
            LeadDetailViewModel.rosterState(
                contactName: "Helen Calloway", contactEmail: nil, contactPhone: nil,
                client: nil, subClients: []),
            .noClient)
    }
}
