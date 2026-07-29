//
//  BooksFormatTests.swift
//  OPSTests
//
//  OPS money renders in the en_US canon on every device — the same rendering
//  web ships via `Intl.NumberFormat("en-US")`. Left to the device locale,
//  Foundation renders USD as "US$14,200" on Canadian-region phones (the exact
//  users OPS serves). This suite must pass under any device region: run it
//  both plain and with `-testLanguage en -testRegion CA` — the CA run is the
//  regression this file exists for.
//

import XCTest
@testable import OPS

final class BooksFormatTests: XCTestCase {

    // MARK: - Device-region independence (the "US$" bug)

    /// Whole-dollar money is "$14,200" everywhere — never "US$14,200".
    func testCurrencyIsDeviceRegionIndependent() {
        XCTAssertEqual(BooksFormat.currency(14_200), "$14,200")
        XCTAssertFalse(BooksFormat.currency(14_200).contains("US$"))
    }

    /// The failure mode itself, pinned as proof: an UNPINNED USD style
    /// resolved under an en_CA (Canadian-region) locale renders the "US$"
    /// prefix. The shipped formatter must be immune — same plain-dollar
    /// string no matter the region. If the first assertion ever stops
    /// holding, Foundation changed underneath us and the pin's rationale
    /// needs a fresh look.
    func testEnCARegionForcesUSPrefixOnlyWithoutThePin() {
        let enCA = Locale(identifier: "en_CA")
        let unpinned = 14_200.0.formatted(
            .currency(code: "USD").precision(.fractionLength(0)).locale(enCA)
        )
        XCTAssertTrue(unpinned.hasPrefix("US$"), "expected the en_CA failure mode, got \(unpinned)")

        XCTAssertEqual(BooksFormat.currency(14_200), "$14,200")
        XCTAssertEqual(BooksFormat.exact(14_200), "$14,200.00")
        XCTAssertEqual(BooksFormat.price(14_200), "$14,200")
        XCTAssertFalse(BooksFormat.symbol(for: "USD").contains("US$"))
    }

    // MARK: - Canon strings, register by register

    func testExactCents() {
        XCTAssertEqual(BooksFormat.exact(1_223.58), "$1,223.58")
        XCTAssertEqual(BooksFormat.exact(0), "$0.00")
        XCTAssertEqual(BooksFormat.exact(250), "$250.00")
        XCTAssertEqual(BooksFormat.exact(-125.5), "-$125.50")
    }

    func testWholeDollars() {
        XCTAssertEqual(BooksFormat.currency(0), "$0")
        XCTAssertEqual(BooksFormat.currency(18_240), "$18,240")
        XCTAssertEqual(BooksFormat.currency(-500), "-$500")
    }

    /// Catalog price register: whole dollars when even, exact cents when not.
    func testPriceRegister() {
        XCTAssertEqual(BooksFormat.price(250), "$250")
        XCTAssertEqual(BooksFormat.price(250.5), "$250.50")
        XCTAssertEqual(BooksFormat.price(1_250.25), "$1,250.25")
        XCTAssertEqual(BooksFormat.price(0), "$0")
    }

    /// Per-record ISO codes render deterministically too — a CAD expense is
    /// "CA$50.00" on every device (web's canon), never bare on one region
    /// and prefixed on another.
    func testPerRecordCurrencyCodes() {
        XCTAssertEqual(BooksFormat.exact(50, code: "CAD"), "CA$50.00")
        XCTAssertEqual(BooksFormat.exact(50, code: "USD"), "$50.00")
    }

    /// The expense form's amount-field symbol follows the canon, not the
    /// device: USD is "$" (a Canadian-region NumberFormatter says "US$").
    func testSymbols() {
        XCTAssertEqual(BooksFormat.symbol(for: "USD"), "$")
        XCTAssertEqual(BooksFormat.symbol(for: "CAD"), "CA$")
        XCTAssertEqual(BooksFormat.symbol(for: "GBP"), "£")
    }

    func testCompactTiles() {
        XCTAssertEqual(BooksFormat.compact(34_800), "$34.8K")
        XCTAssertEqual(BooksFormat.compact(34_000), "$34K")
        XCTAssertEqual(BooksFormat.compact(1_240_000), "$1.2M")
        XCTAssertEqual(BooksFormat.compact(640), "$640")
        XCTAssertEqual(BooksFormat.compact(-4_500), "-$4.5K")
    }

    func testSignedPercent() {
        XCTAssertEqual(BooksFormat.signedPct(14.2), "+14%")
        XCTAssertEqual(BooksFormat.signedPct(-3), "-3%")
        XCTAssertEqual(BooksFormat.signedPct(0), "0%")
    }

    /// Document line-item meta composes through the same canon — the row
    /// math always reconciles with the server-stored line total.
    func testLineItemMetaStaysOnCanon() {
        XCTAssertEqual(
            LineItemDisplay.quantityPriceMeta(quantity: 2, unit: "each", unitPrice: 250),
            "2 each × $250.00"
        )
        XCTAssertEqual(LineItemDisplay.quantityString(2.5), "2.5")
        XCTAssertEqual(LineItemDisplay.taxRateString(8.25), "8.25")
    }
}
