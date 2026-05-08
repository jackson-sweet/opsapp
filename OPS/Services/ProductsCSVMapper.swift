//
//  ProductsCSVMapper.swift
//  OPS
//
//  Takes the parsed CSV rows + a column-mapping config + the company's
//  existing catalog vocabulary (categories, units), and produces a
//  ProductsImportPayload ready for the validate / apply RPC.
//
//  One CSV row = one product. Unlike CatalogCSVMapper there is NO family
//  grouping — products are flat. Typed text columns for `category` and
//  `unit` are resolved to FK ids via case-insensitive name match within
//  the company; an unmatched value is a hard error (same fallback the
//  iOS QuickAddProductSheet uses when a user types a category that does
//  not exist).
//

import Foundation

// MARK: - Column mapping

/// Which CSV header maps to each logical column. Values are the CSV
/// header name (the column the user picked in the import sheet).
/// `nil` = "not mapped".
struct ProductsImportColumnMapping {
    // Required
    var name: String?
    var basePrice: String?

    // Optional
    var description: String?
    var unitCost: String?
    var category: String?           // typed text, resolved to category_id
    var unit: String?               // typed text, resolved to unit_id (display)
    var pricingUnit: String?        // free-text legacy enum
    var sku: String?
    var kind: String?               // 'service' | 'good'
    var type: String?               // LineItemType raw
    var isTaxable: String?          // any truthy/falsy text

    var isReadyToMap: Bool {
        name != nil && basePrice != nil
    }

    /// Auto-suggest a mapping based on header names. Cheap fuzzy match
    /// — case-insensitive substring or alias hit. The user can override
    /// every field in the UI before previewing.
    static func suggest(from headers: [String]) -> ProductsImportColumnMapping {
        var m = ProductsImportColumnMapping()
        let lookup = Dictionary(uniqueKeysWithValues: headers.map {
            (normalize($0), $0)
        })

        func find(_ aliases: [String]) -> String? {
            for alias in aliases {
                if let hit = lookup[normalize(alias)] { return hit }
            }
            for alias in aliases {
                let needle = normalize(alias)
                for header in headers {
                    if normalize(header).contains(needle) { return header }
                }
            }
            return nil
        }

        m.name         = find(["name", "product", "product name", "item", "title"])
        m.basePrice    = find(["base price", "price", "unit price", "list price", "rate"])
        m.description  = find(["description", "desc", "notes"])
        m.unitCost     = find(["cost", "unit cost", "wholesale", "our cost"])
        m.category     = find(["category", "cat", "group"])
        m.unit         = find(["unit", "uom", "unit of measure"])
        m.pricingUnit  = find(["pricing unit", "billing unit"])
        m.sku          = find(["sku", "part", "part number", "code", "item code"])
        m.kind         = find(["kind", "service or good", "type kind"])
        m.type         = find(["line item type", "labor or material", "labor material"])
        m.isTaxable    = find(["taxable", "is taxable", "tax"])

        return m
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

// MARK: - Local validation errors

extension ProductsImportError {
    static func mapping(rowIndex: Int, field: String, reason: String) -> ProductsImportError {
        ProductsImportError(scope: "mapping", rowIndex: rowIndex, field: field, reason: reason)
    }
}

// MARK: - Mapper output

struct ProductsCSVMapResult {
    /// Payload ready for the RPC. Only populated when `errors` is empty.
    let payload: ProductsImportPayload?
    /// Local errors discovered during mapping. Empty = good to dry-run.
    let errors: [ProductsImportError]
    /// 1-based source line numbers for every product in the payload —
    /// parallel to `payload.products`. Useful so the UI can render
    /// "Line 47: …" instead of the abstract row_index.
    let productSourceLineNumbers: [Int]
}

// MARK: - Mapper

enum ProductsCSVMapper {

    /// Map parsed CSV rows to a `ProductsImportPayload` using the given
    /// column mapping and catalog vocabulary. Per-row local validation
    /// runs here so the user gets fast feedback before any network call.
    /// Lookup arguments are arrays of `(id, name/display)` tuples — kept
    /// model-agnostic so the mapper can be unit-tested without
    /// SwiftData / SwiftUI.
    static func map(
        rows: [[String: String]],
        lineNumbers: [Int],
        mapping: ProductsImportColumnMapping,
        categories: [(id: String, name: String)],
        units: [(id: String, display: String)]
    ) -> ProductsCSVMapResult {
        guard let nameCol = mapping.name else {
            return ProductsCSVMapResult(
                payload: nil,
                errors: [.mapping(rowIndex: -1, field: "name", reason: "No CSV column mapped to Name.")],
                productSourceLineNumbers: []
            )
        }
        guard let basePriceCol = mapping.basePrice else {
            return ProductsCSVMapResult(
                payload: nil,
                errors: [.mapping(rowIndex: -1, field: "base_price", reason: "No CSV column mapped to Base Price.")],
                productSourceLineNumbers: []
            )
        }

        let categoryByName = Dictionary(
            categories.map { ($0.name.lowercased().trimmingCharacters(in: .whitespaces), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let unitByDisplay = Dictionary(
            units.map { ($0.display.lowercased().trimmingCharacters(in: .whitespaces), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        var products: [ProductsImportProduct] = []
        var productLines: [Int] = []
        var errors: [ProductsImportError] = []

        for (i, row) in rows.enumerated() {
            let line = i < lineNumbers.count ? lineNumbers[i] : (i + 2)

            let name = row[nameCol]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty {
                errors.append(.mapping(rowIndex: i, field: "name", reason: "Line \(line): name is blank."))
                continue
            }

            // base_price required
            let parsedBasePrice = parseNumber(
                raw: row[basePriceCol],
                rowIndex: i, field: "base_price",
                line: line, errors: &errors
            )
            guard let basePrice = parsedBasePrice else {
                // parseNumber already pushed an error for the bad/blank value.
                // If it returned nil because the cell was blank, ensure we
                // still surface a "required" error (parseNumber stays silent
                // on blanks).
                if (row[basePriceCol]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty {
                    errors.append(.mapping(
                        rowIndex: i, field: "base_price",
                        reason: "Line \(line): base_price is required."
                    ))
                }
                continue
            }

            let unitCost = parseNumber(
                raw: mapping.unitCost.flatMap { row[$0] },
                rowIndex: i, field: "unit_cost",
                line: line, errors: &errors
            )

            let description: String? = mapping.description.flatMap { col in
                row[col]?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.flatMap { $0.isEmpty ? nil : $0 }

            // Category resolution — typed text → FK id. Unmatched is hard error.
            var categoryId: String? = nil
            var categoryText: String? = nil
            if let col = mapping.category, let raw = row[col]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                categoryText = raw
                if let id = categoryByName[raw.lowercased()] {
                    categoryId = id
                } else {
                    errors.append(.mapping(
                        rowIndex: i, field: "category",
                        reason: "Line \(line): category '\(raw)' not found in your catalog. Create it first or remove the value."
                    ))
                }
            }

            // Unit resolution — typed text → FK id. Unmatched is hard error.
            var unitId: String? = nil
            var unitText: String? = nil
            if let col = mapping.unit, let raw = row[col]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                unitText = raw
                if let id = unitByDisplay[raw.lowercased()] {
                    unitId = id
                } else {
                    errors.append(.mapping(
                        rowIndex: i, field: "unit",
                        reason: "Line \(line): unit '\(raw)' not found in your catalog. Create it first or remove the value."
                    ))
                }
            }

            let pricingUnit: String? = mapping.pricingUnit.flatMap { col in
                row[col]?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.flatMap { $0.isEmpty ? nil : $0 }

            let sku: String? = mapping.sku.flatMap { col in
                row[col]?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.flatMap { $0.isEmpty ? nil : $0 }

            // kind enum
            var kind: String? = nil
            if let col = mapping.kind, let raw = row[col]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                let lower = raw.lowercased()
                if lower == "service" || lower == "good" {
                    kind = lower
                } else {
                    errors.append(.mapping(
                        rowIndex: i, field: "kind",
                        reason: "Line \(line): kind '\(raw)' must be 'service' or 'good'."
                    ))
                }
            }

            // type enum (LineItemType — uppercase)
            var type: String? = nil
            if let col = mapping.type, let raw = row[col]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                let upper = raw.uppercased()
                if upper == "LABOR" || upper == "MATERIAL" || upper == "OTHER" {
                    type = upper
                } else {
                    errors.append(.mapping(
                        rowIndex: i, field: "type",
                        reason: "Line \(line): type '\(raw)' must be 'LABOR', 'MATERIAL', or 'OTHER'."
                    ))
                }
            }

            // is_taxable — accept truthy/falsy text. Default nil = use server default.
            var isTaxable: Bool? = nil
            if let col = mapping.isTaxable, let raw = row[col]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                let lower = raw.lowercased()
                switch lower {
                case "true", "yes", "y", "1", "t":
                    isTaxable = true
                case "false", "no", "n", "0", "f":
                    isTaxable = false
                default:
                    errors.append(.mapping(
                        rowIndex: i, field: "is_taxable",
                        reason: "Line \(line): is_taxable '\(raw)' must be true/false (or yes/no)."
                    ))
                }
            }

            products.append(ProductsImportProduct(
                rowIndex: products.count,
                name: name,
                description: description,
                basePrice: basePrice,
                unitCost: unitCost,
                categoryId: categoryId,
                unitId: unitId,
                category: categoryText,
                unit: unitText,
                pricingUnit: pricingUnit,
                sku: sku,
                kind: kind,
                type: type,
                isTaxable: isTaxable
            ))
            productLines.append(line)
        }

        if rows.isEmpty {
            errors.append(.mapping(rowIndex: -1, field: "rows", reason: "CSV has no data rows."))
        }

        let payload: ProductsImportPayload? = errors.isEmpty
            ? ProductsImportPayload(products: products)
            : nil

        return ProductsCSVMapResult(
            payload: payload,
            errors: errors,
            productSourceLineNumbers: productLines
        )
    }

    // MARK: - Number parsing

    /// Permissive numeric parse — tolerates `$`, `,`, leading/trailing
    /// whitespace. Returns nil for blank input. Appends an error if the
    /// input is non-blank and unparseable.
    private static func parseNumber(
        raw: String?,
        rowIndex: Int,
        field: String,
        line: Int,
        errors: inout [ProductsImportError]
    ) -> Double? {
        guard let raw = raw else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        if cleaned.isEmpty { return nil }
        if let n = Double(cleaned) {
            if n < 0 {
                errors.append(.mapping(
                    rowIndex: rowIndex, field: field,
                    reason: "Line \(line): \(field) cannot be negative."
                ))
                return nil
            }
            return n
        }
        errors.append(.mapping(
            rowIndex: rowIndex, field: field,
            reason: "Line \(line): \(field) is not a valid number ('\(raw)')."
        ))
        return nil
    }
}
