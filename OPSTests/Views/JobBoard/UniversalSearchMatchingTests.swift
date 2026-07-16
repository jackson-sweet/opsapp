//
//  UniversalSearchMatchingTests.swift
//  OPSTests
//
//  Proves universal search now indexes leads, invoices, and estimates by the
//  things a user actually types — a customer name, a job name, a contact —
//  not just the invoice / estimate number. Bug ac2ace7a: leads were absent
//  entirely, and money records only matched their own number/title.
//

import XCTest
@testable import OPS

@MainActor
final class UniversalSearchMatchingTests: XCTestCase {

    // A user has one client "Mitchell Residence" and one project "Cedar Deck
    // Rebuild"; money records / leads link to them by id, and search resolves
    // those ids back to names the way the sheet's lookup maps do.
    private let clientNameById = ["cli-1": "Mitchell Residence", "cli-2": "Harbor Cafe"]
    private let projectTitleById = ["prj-1": "Cedar Deck Rebuild"]

    // MARK: - Leads (were not indexed at all before this fix)

    func testLeadMatchesByContactName() {
        let lead = Opportunity(companyId: "co", contactName: "Dana Mitchell")
        XCTAssertTrue(UniversalSearchMatching.matches(opportunity: lead, query: "mitch", clientNameById: [:]))
    }

    func testLeadMatchesByTitle() {
        let lead = Opportunity(companyId: "co", contactName: "Dana")
        lead.title = "Backyard deck + rail"
        XCTAssertTrue(UniversalSearchMatching.matches(opportunity: lead, query: "rail", clientNameById: [:]))
    }

    func testLeadMatchesByEmailPhoneAddress() {
        let lead = Opportunity(companyId: "co", contactName: "Dana")
        lead.contactEmail = "dana@example.com"
        lead.contactPhone = "555-0142"
        lead.address = "18 Cedar Lane"
        XCTAssertTrue(UniversalSearchMatching.matches(opportunity: lead, query: "example.com", clientNameById: [:]))
        XCTAssertTrue(UniversalSearchMatching.matches(opportunity: lead, query: "0142", clientNameById: [:]))
        XCTAssertTrue(UniversalSearchMatching.matches(opportunity: lead, query: "cedar", clientNameById: [:]))
    }

    func testLeadMatchesByLinkedClientName() {
        let lead = Opportunity(companyId: "co", contactName: "Site contact")
        lead.clientId = "cli-1"
        XCTAssertTrue(UniversalSearchMatching.matches(opportunity: lead, query: "mitchell", clientNameById: clientNameById))
    }

    func testLeadNoMatchReturnsFalse() {
        let lead = Opportunity(companyId: "co", contactName: "Dana Mitchell")
        lead.title = "Deck"
        XCTAssertFalse(UniversalSearchMatching.matches(opportunity: lead, query: "plumbing", clientNameById: clientNameById))
    }

    // MARK: - Invoices (only matched number/title before; now client + project)

    func testInvoiceMatchesByNumber() {
        let inv = Invoice(companyId: "co", invoiceNumber: "INV-1007")
        XCTAssertTrue(UniversalSearchMatching.matches(invoice: inv, query: "1007", clientNameById: [:], projectTitleById: [:]))
    }

    func testInvoiceMatchesByTitle() {
        let inv = Invoice(companyId: "co", invoiceNumber: "INV-1007")
        inv.title = "Deposit — phase 1"
        XCTAssertTrue(UniversalSearchMatching.matches(invoice: inv, query: "deposit", clientNameById: [:], projectTitleById: [:]))
    }

    func testInvoiceMatchesByClientName() {
        let inv = Invoice(companyId: "co", invoiceNumber: "INV-1007")
        inv.clientId = "cli-1"
        XCTAssertTrue(UniversalSearchMatching.matches(invoice: inv, query: "mitchell", clientNameById: clientNameById, projectTitleById: [:]))
    }

    func testInvoiceMatchesByProjectTitle() {
        let inv = Invoice(companyId: "co", invoiceNumber: "INV-1007")
        inv.projectId = "prj-1"
        XCTAssertTrue(UniversalSearchMatching.matches(invoice: inv, query: "cedar deck", clientNameById: [:], projectTitleById: projectTitleById))
    }

    func testInvoiceNoMatchReturnsFalse() {
        let inv = Invoice(companyId: "co", invoiceNumber: "INV-1007")
        inv.clientId = "cli-2"  // Harbor Cafe — should not match a Mitchell search
        XCTAssertFalse(UniversalSearchMatching.matches(invoice: inv, query: "mitchell", clientNameById: clientNameById, projectTitleById: projectTitleById))
    }

    // MARK: - Estimates (same widening as invoices)

    func testEstimateMatchesByNumber() {
        let est = Estimate(companyId: "co", estimateNumber: "EST-204")
        XCTAssertTrue(UniversalSearchMatching.matches(estimate: est, query: "204", clientNameById: [:], projectTitleById: [:]))
    }

    func testEstimateMatchesByClientName() {
        let est = Estimate(companyId: "co", estimateNumber: "EST-204")
        est.clientId = "cli-1"
        XCTAssertTrue(UniversalSearchMatching.matches(estimate: est, query: "mitchell", clientNameById: clientNameById, projectTitleById: [:]))
    }

    func testEstimateMatchesByProjectTitle() {
        let est = Estimate(companyId: "co", estimateNumber: "EST-204")
        est.projectId = "prj-1"
        XCTAssertTrue(UniversalSearchMatching.matches(estimate: est, query: "rebuild", clientNameById: [:], projectTitleById: projectTitleById))
    }

    func testEstimateNoMatchReturnsFalse() {
        let est = Estimate(companyId: "co", estimateNumber: "EST-204")
        XCTAssertFalse(UniversalSearchMatching.matches(estimate: est, query: "invoice", clientNameById: clientNameById, projectTitleById: projectTitleById))
    }
}
