//
//  LineItemDisplay.swift
//  OPS
//
//  Shared formatting for financial-document line items (estimates, invoices).
//  One source of truth for the per-row "qty unit × price" math meta, quantity
//  precision, and tax-rate labels — so the estimate detail, invoice detail,
//  and estimate form all present the same document the same way (and match
//  the web's canonical rendering: name / qty unit × unit price / line total).
//
//  Money on document surfaces always shows exact cents. Line totals are a
//  server-generated column (`round(qty × price × (1 − discount), 2)`), so the
//  meta this file produces always reconciles with the stored total — rounding
//  to whole dollars is what made rows read as "not displaying properly"
//  (bug a8e156a2: a 2 × $250 row rendered with no math at all).
//

import Foundation

enum LineItemDisplay {

    /// Money and numbers on financial documents are locked to en_US — the
    /// same canon as web's `formatCurrency` (`Intl.NumberFormat("en-US")`).
    /// Left to the device locale, `.currency(code: "USD")` renders "US$500.00"
    /// on Canadian-region phones — a wrong-looking document for the exact
    /// users OPS serves. One document, one rendering, on every device.
    private static let documentLocale = Locale(identifier: "en_US")

    /// Exact money for document surfaces: always "$1,223.58" — two decimals,
    /// plain dollar sign, device region irrelevant.
    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(documentLocale))
    }

    /// Quantities trimmed of trailing zeros, up to 3 decimal places —
    /// `line_items.quantity` is numeric with 3-decimal scale.
    /// 2 → "2", 2.5 → "2.5", 2.25 → "2.25", 0.125 → "0.125".
    static func quantityString(_ quantity: Double) -> String {
        quantity.formatted(.number.precision(.fractionLength(0...3)).locale(documentLocale))
    }

    /// Tax rates trimmed of trailing zeros — `estimates.tax_rate` is numeric
    /// with 4-decimal scale, so fractional rates (7.5, 8.25) are live data.
    /// 13.0000 → "13", 7.5 → "7.5", 8.25 → "8.25".
    static func taxRateString(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...4)).grouping(.never).locale(documentLocale))
    }

    /// The per-row math meta: "2 each × $250.00" (or "2 × $250.00" with no
    /// unit). Configured products display their resolved snapshot price —
    /// that is the price the line total was computed from.
    static func quantityPriceMeta(
        quantity: Double,
        unit: String?,
        unitPrice: Double,
        resolvedUnitPrice: Double? = nil
    ) -> String {
        let price = money(resolvedUnitPrice ?? unitPrice)
        let qty = quantityString(quantity)
        if let unit, !unit.isEmpty {
            return "\(qty) \(unit) × \(price)"
        }
        return "\(qty) × \(price)"
    }

    /// Document-level discount derived from the stored totals
    /// (`subtotal + tax − total`). Estimates and invoices persist discounts
    /// in columns the iOS models don't all carry, but the arithmetic gap is
    /// authoritative regardless of discount type — when it's positive the
    /// totals card must show the DISCOUNT row or subtotal + tax ≠ total
    /// on screen. Returns nil when there is no discount to show.
    static func discountAmount(subtotal: Double, taxAmount: Double, total: Double) -> Double? {
        let gap = subtotal + taxAmount - total
        return gap > 0.005 ? gap : nil
    }
}
