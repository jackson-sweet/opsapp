//
//  BooksFormat.swift
//  OPS
//
//  The one money formatter. Every dollar figure the app renders — hero
//  numbers, ledger rows, document line items, expense amounts, lead values —
//  formats through here so money reads identically on every device.
//
//  Rendering is locked to the en_US canon, the same rendering web ships via
//  `formatCurrency` (`Intl.NumberFormat("en-US")`). Left to the device
//  locale, Foundation renders USD as "US$14,200" on Canadian-region phones —
//  wrong-looking money for the exact users OPS serves. One rendering, every
//  device, both platforms.
//
//  Two display registers, deliberately distinct:
//    • `currency` — whole dollars ("$18,240") for scan surfaces: heroes,
//      tiles, cards, list rows.
//    • `exact`    — exact cents ("$1,223.58") for document surfaces:
//      estimates, invoices, payments, expense amounts. Line totals are a
//      server-generated column, so rounding cents away is what made rows
//      read as broken (bug a8e156a2).
//
//  (Born in BooksCommandKit for the Money & Leads command grids; promoted to
//  Utilities when it absorbed LineItemDisplay.money and became app-wide.)
//

import Foundation

enum BooksFormat {

    /// The locale every money string renders under — en_US, the
    /// cross-platform canon shared with web. Number formatting that composes
    /// money strings elsewhere (LineItemDisplay quantities, the lead hero's
    /// compact values) pins to this same constant: one locale, one rendering.
    static let locale = Locale(identifier: "en_US")

    /// Full currency, no cents — `$18,240`. Hero numbers and lead values.
    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)).locale(locale))
    }

    /// Exact-cents currency — `$1,223.58`; `CA$50.00` when a record carries
    /// its own ISO code (expense rows, company-currency balances).
    static func exact(_ value: Double, code: String = "USD") -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(2)).locale(locale))
    }

    /// Catalog price register — whole dollars when the value is even
    /// (`$250`), exact cents when it isn't (`$250.50`). Product base prices,
    /// bundle line math, option deltas.
    static func price(_ value: Double) -> String {
        value.rounded() == value ? currency(value) : exact(value)
    }

    /// The symbol an amount will render with under the canon — "$" for USD,
    /// "CA$" for CAD. (A device-locale NumberFormatter turns USD's symbol
    /// into "US$" on Canadian-region phones.) Falls back to the ISO code
    /// itself if Foundation can't produce a symbol.
    static func symbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    /// Compact currency for dense tiles — `$34.8K`, `$1.2M`, `$640`. Drops a
    /// trailing `.0` so round thousands read `$34K` not `$34.0K`.
    static func compact(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return "\(sign)$\(trim(magnitude / 1_000_000))M"
        }
        if magnitude >= 1_000 {
            return "\(sign)$\(trim(magnitude / 1_000))K"
        }
        return "\(sign)$\(Int(magnitude.rounded()))"
    }

    /// Signed percent — `+14%`, `-3%`, `0%`. Caller colors it olive/rose.
    static func signedPct(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded > 0 { return "+\(rounded)%" }
        return "\(rounded)%"
    }

    /// One-decimal with a stripped trailing `.0` (`34.8`, `12`, `1.2`).
    /// `String(format:)` is locale-blind by design — always a `.` separator.
    private static func trim(_ value: Double) -> String {
        let s = String(format: "%.1f", value)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}
