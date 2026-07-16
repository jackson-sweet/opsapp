//
//  SpotlightItemBuilderTests.swift
//  OPSTests
//

import XCTest
import CoreSpotlight
@testable import OPS

final class SpotlightItemBuilderTests: XCTestCase {

    func test_itemId_roundtrip() {
        let itemId = SpotlightItemId.make(domain: SpotlightDomain.estimate, id: "est-42")
        guard let decoded = SpotlightItemId.decode(itemId) else {
            XCTFail("decode failed")
            return
        }
        XCTAssertEqual(decoded.domain, SpotlightDomain.estimate)
        XCTAssertEqual(decoded.id, "est-42")
    }

    func test_itemId_decode_rejects_malformed() {
        XCTAssertNil(SpotlightItemId.decode("no-colon-here"))
    }

    func test_itemId_decode_handles_colons_in_id() {
        // Supabase IDs are UUIDs but if one ever contained a colon, only the first is the separator.
        let itemId = "co.opsapp.spotlight.project:abc:def"
        guard let decoded = SpotlightItemId.decode(itemId) else {
            XCTFail("decode failed")
            return
        }
        XCTAssertEqual(decoded.domain, "co.opsapp.spotlight.project")
        XCTAssertEqual(decoded.id, "abc:def")
    }

    func test_invoice_item_includes_amount_and_client_name() {
        let invoice = Invoice(
            id: "inv1",
            companyId: "co-1",
            invoiceNumber: "INV-001"
        )
        invoice.total = 1234.56
        invoice.title = "Kitchen reno"

        let item = SpotlightItemBuilder.buildInvoice(invoice, clientName: "Acme Corp")
        XCTAssertEqual(item.attributeSet.title, "INV-001")
        XCTAssertEqual(item.domainIdentifier, SpotlightDomain.invoice)
        XCTAssertEqual(item.uniqueIdentifier, "co.opsapp.spotlight.invoice:inv1")
        XCTAssertTrue(item.attributeSet.contentDescription?.contains("Kitchen reno") ?? false)
        XCTAssertTrue(item.attributeSet.contentDescription?.contains("Acme Corp") ?? false)
        XCTAssertTrue(item.attributeSet.contentDescription?.contains("1234.56") ?? false)
    }

    func test_estimate_item_falls_back_to_default_title_when_empty() {
        let estimate = Estimate(id: "est1", companyId: "co-1")
        // estimateNumber defaults to empty string
        estimate.total = 0

        let item = SpotlightItemBuilder.buildEstimate(estimate, clientName: nil)
        XCTAssertEqual(item.attributeSet.title, "Estimate")
        XCTAssertEqual(item.domainIdentifier, SpotlightDomain.estimate)
    }

    // MARK: - Lead (Opportunity)

    func test_lead_item_uses_contact_name_as_title_with_stage_address_metadata() {
        let opp = Opportunity(id: "opp1", companyId: "co-1", contactName: "Jane Smith", stage: .quoting)
        opp.address = "123 Main St, Halifax, NS B3H 2Y9"
        opp.contactPhone = "902-555-0100"
        opp.contactEmail = "jane@example.com"

        let item = SpotlightItemBuilder.buildLead(opp)
        XCTAssertEqual(item.attributeSet.title, "Jane Smith")
        XCTAssertEqual(item.domainIdentifier, SpotlightDomain.lead)
        XCTAssertEqual(item.uniqueIdentifier, "co.opsapp.spotlight.lead:opp1")
        // Stage + street both scan-visible in the result subtitle.
        XCTAssertTrue(item.attributeSet.contentDescription?.contains("QUOTING") ?? false)
        XCTAssertTrue(item.attributeSet.contentDescription?.contains("123 Main St") ?? false)
        // Phone + email are native searchable Spotlight attributes.
        XCTAssertEqual(item.attributeSet.phoneNumbers, ["902-555-0100"])
        XCTAssertEqual(item.attributeSet.emailAddresses, ["jane@example.com"])
    }

    func test_lead_item_falls_back_to_subject_when_contact_name_empty() {
        // Email-sourced leads can land with a blank contact_name but a subject line.
        let opp = Opportunity(id: "opp2", companyId: "co-1", contactName: "", stage: .newLead)
        opp.title = "Roof repair inquiry"

        let item = SpotlightItemBuilder.buildLead(opp)
        XCTAssertEqual(item.attributeSet.title, "Roof repair inquiry")
    }

    func test_lead_item_falls_back_to_placeholder_when_name_and_subject_empty() {
        let opp = Opportunity(id: "opp3", companyId: "co-1", contactName: "", stage: .newLead)

        let item = SpotlightItemBuilder.buildLead(opp)
        XCTAssertEqual(item.attributeSet.title, "Unnamed lead")
    }

    func test_lead_item_keywords_include_contact_name_and_stage() {
        let opp = Opportunity(id: "opp4", companyId: "co-1", contactName: "Bob Vance", stage: .followUp)

        let item = SpotlightItemBuilder.buildLead(opp)
        let keywords = item.attributeSet.keywords ?? []
        XCTAssertTrue(keywords.contains("Bob Vance"))
        XCTAssertTrue(keywords.contains("FOLLOW-UP"))
    }

    // MARK: - Indexable-lead filter (non-deleted, non-archived)

    func test_indexable_leads_excludes_archived_and_deleted() {
        let active = Opportunity(id: "a", companyId: "co-1", contactName: "Active")
        let archived = Opportunity(id: "b", companyId: "co-1", contactName: "Archived")
        archived.archivedAt = Date()
        let deleted = Opportunity(id: "c", companyId: "co-1", contactName: "Deleted")
        deleted.deletedAt = Date()

        let ids = Set(SpotlightIndexManager.indexableLeads([active, archived, deleted]).map { $0.id })
        XCTAssertEqual(ids, ["a"])
    }
}
