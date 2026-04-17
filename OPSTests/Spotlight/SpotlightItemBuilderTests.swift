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
}
