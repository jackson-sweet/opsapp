//
//  CatalogCSVMapper.swift
//  OPS
//
//  Takes the parsed CSV rows + a column-mapping config + the company's
//  existing catalog vocabulary (categories, units), and produces a
//  CatalogImportPayload ready for the validate / apply RPC.
//
//  One CSV row = one variant. The mapper groups variants into families
//  by the `family_name` column (case-insensitive trimmed). The first
//  occurrence of a family_name carries the family-level fields
//  (description, category, etc.); later rows with the same family_name
//  contribute additional variants under it.
//

import Foundation

// MARK: - Column mapping

/// Which CSV header maps to each logical column. Values are the CSV
/// header name (the column the user picked in the import sheet).
/// `nil` = "not mapped".
struct CatalogImportColumnMapping {
    // Required
    var familyName: String?
    var quantity: String?

    // Optional family-level
    var familyDescription: String?
    var category: String?
    var defaultUnit: String?
    var defaultPrice: String?
    var defaultUnitCost: String?

    // Optional variant-level
    var sku: String?
    var variantUnit: String?
    var priceOverride: String?
    var unitCostOverride: String?
    var warningThreshold: String?
    var criticalThreshold: String?

    var isReadyToMap: Bool {
        familyName != nil && quantity != nil
    }

    /// Auto-suggest a mapping based on header names. Cheap fuzzy match
    /// — case-insensitive substring or alias hit. The user can override
    /// every field in the UI before previewing.
    static func suggest(from headers: [String]) -> CatalogImportColumnMapping {
        var m = CatalogImportColumnMapping()
        let lookup = Dictionary(uniqueKeysWithValues: headers.map {
            (normalize($0), $0)
        })

        func find(_ aliases: [String]) -> String? {
            for alias in aliases {
                if let hit = lookup[normalize(alias)] { return hit }
            }
            // Fall back to substring match.
            for alias in aliases {
                let needle = normalize(alias)
                for header in headers {
                    if normalize(header).contains(needle) { return header }
                }
            }
            return nil
        }

        m.familyName         = find(["family", "family_name", "product family", "name", "item"])
        m.quantity           = find(["quantity", "qty", "stock", "on hand", "count"])
        m.familyDescription  = find(["description", "desc", "notes"])
        m.category           = find(["category", "cat", "type"])
        m.defaultUnit        = find(["unit", "uom", "unit of measure"])
        m.defaultPrice       = find(["price", "default price", "unit price", "list price"])
        m.defaultUnitCost    = find(["cost", "unit cost", "default cost", "wholesale"])
        m.sku                = find(["sku", "part", "part number", "code", "item code"])
        m.variantUnit        = find(["variant unit", "v unit"])
        m.priceOverride      = find(["price override", "variant price"])
        m.unitCostOverride   = find(["cost override", "variant cost"])
        m.warningThreshold   = find(["warning threshold", "warning", "low warn"])
        m.criticalThreshold  = find(["critical threshold", "critical", "low critical", "min"])

        return m
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

// MARK: - Local validation errors

/// Errors raised during the client-side mapping step (before the
/// payload reaches the server). Same shape as the server-side
/// CatalogImportError so the preview screen can render them uniformly.
extension CatalogImportError {
    static func mapping(rowIndex: Int, field: String, reason: String) -> CatalogImportError {
        CatalogImportError(scope: "mapping", rowIndex: rowIndex, field: field, reason: reason)
    }
}

// MARK: - Mapper output

struct CatalogCSVMapResult {
    /// Payload ready for the RPC. Only populated when `errors` is empty.
    let payload: CatalogImportPayload?
    /// Local errors discovered during mapping. Empty = good to dry-run.
    let errors: [CatalogImportError]
    /// 1-based source line numbers for every variant in the payload —
    /// parallel to `payload.variants`. Useful so the UI can render
    /// "Line 47: …" instead of the abstract row_index.
    let variantSourceLineNumbers: [Int]
}

// MARK: - Mapper

enum CatalogCSVMapper {

    /// Map parsed CSV rows to a `CatalogImportPayload` using the given
    /// column mapping and catalog vocabulary. Per-row local validation
    /// runs here so the user gets fast feedback before any network call.
    /// Lookup arguments are arrays of `(id, name/display)` tuples — kept
    /// model-agnostic so the mapper can be unit-tested without
    /// SwiftData / SwiftUI.
    static func map(
        rows: [[String: String]],
        lineNumbers: [Int],
        mapping: CatalogImportColumnMapping,
        categories: [(id: String, name: String)],
        units: [(id: String, display: String)]
    ) -> CatalogCSVMapResult {
        guard let familyNameCol = mapping.familyName else {
            return CatalogCSVMapResult(
                payload: nil,
                errors: [.mapping(rowIndex: -1, field: "family_name", reason: "No CSV column mapped to Family Name.")],
                variantSourceLineNumbers: []
            )
        }
        guard let quantityCol = mapping.quantity else {
            return CatalogCSVMapResult(
                payload: nil,
                errors: [.mapping(rowIndex: -1, field: "quantity", reason: "No CSV column mapped to Quantity.")],
                variantSourceLineNumbers: []
            )
        }

        // Case-insensitive lookup for category + unit name → id.
        let categoryByName = Dictionary(
            categories.map { ($0.name.lowercased().trimmingCharacters(in: .whitespaces), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let unitByDisplay = Dictionary(
            units.map { ($0.display.lowercased().trimmingCharacters(in: .whitespaces), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        var families: [CatalogImportFamily] = []
        var variants: [CatalogImportVariant] = []
        var variantLines: [Int] = []
        var familyIndexByKey: [String: Int] = [:]
        var errors: [CatalogImportError] = []

        for (i, row) in rows.enumerated() {
            let line = i < lineNumbers.count ? lineNumbers[i] : (i + 2)

            let familyName = row[familyNameCol]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if familyName.isEmpty {
                errors.append(.mapping(rowIndex: i, field: "family_name", reason: "Line \(line): family name is blank."))
                continue
            }

            let key = familyName.lowercased()
            let familyIndex: Int
            if let existing = familyIndexByKey[key] {
                familyIndex = existing
            } else {
                familyIndex = families.count
                familyIndexByKey[key] = familyIndex

                // Family-level fields — pulled from the FIRST row carrying
                // this family_name. Later rows are assumed to share these
                // values; if they differ we ignore the differences (the
                // first wins). This is documented behaviour in the
                // import sheet.
                var categoryId: String? = nil
                if let col = mapping.category, let rawCat = row[col]?.trimmingCharacters(in: .whitespacesAndNewlines), !rawCat.isEmpty {
                    if let id = categoryByName[rawCat.lowercased()] {
                        categoryId = id
                    } else {
                        errors.append(.mapping(
                            rowIndex: familyIndex,
                            field: "category",
                            reason: "Line \(line): category '\(rawCat)' not found in your catalog. Create it first or remove the value."
                        ))
                    }
                }

                var defaultUnitId: String? = nil
                if let col = mapping.defaultUnit, let rawUnit = row[col]?.trimmingCharacters(in: .whitespacesAndNewlines), !rawUnit.isEmpty {
                    if let id = unitByDisplay[rawUnit.lowercased()] {
                        defaultUnitId = id
                    } else {
                        errors.append(.mapping(
                            rowIndex: familyIndex,
                            field: "default_unit",
                            reason: "Line \(line): unit '\(rawUnit)' not found in your catalog. Create it first or remove the value."
                        ))
                    }
                }

                let description: String? = mapping.familyDescription.flatMap { col in
                    row[col]?.trimmingCharacters(in: .whitespacesAndNewlines)
                }.flatMap { $0.isEmpty ? nil : $0 }

                let defaultPrice = parseNumber(
                    raw: mapping.defaultPrice.flatMap { row[$0] },
                    rowIndex: familyIndex, field: "default_price",
                    line: line, errors: &errors
                )
                let defaultUnitCost = parseNumber(
                    raw: mapping.defaultUnitCost.flatMap { row[$0] },
                    rowIndex: familyIndex, field: "default_unit_cost",
                    line: line, errors: &errors
                )

                families.append(CatalogImportFamily(
                    rowIndex: familyIndex,
                    name: familyName,
                    description: description,
                    categoryId: categoryId,
                    defaultUnitId: defaultUnitId,
                    defaultPrice: defaultPrice,
                    defaultUnitCost: defaultUnitCost,
                    defaultWarningThreshold: nil,
                    defaultCriticalThreshold: nil
                ))
            }

            // Variant fields — every CSV row contributes one.
            let quantity: Double = parseNumber(
                raw: row[quantityCol],
                rowIndex: i, field: "quantity",
                line: line, errors: &errors
            ) ?? 0

            let sku: String? = mapping.sku.flatMap { col in
                row[col]?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.flatMap { $0.isEmpty ? nil : $0 }

            let priceOverride = parseNumber(
                raw: mapping.priceOverride.flatMap { row[$0] },
                rowIndex: i, field: "price_override",
                line: line, errors: &errors
            )
            let unitCostOverride = parseNumber(
                raw: mapping.unitCostOverride.flatMap { row[$0] },
                rowIndex: i, field: "unit_cost_override",
                line: line, errors: &errors
            )
            let warning = parseNumber(
                raw: mapping.warningThreshold.flatMap { row[$0] },
                rowIndex: i, field: "warning_threshold",
                line: line, errors: &errors
            )
            let critical = parseNumber(
                raw: mapping.criticalThreshold.flatMap { row[$0] },
                rowIndex: i, field: "critical_threshold",
                line: line, errors: &errors
            )

            var variantUnitId: String? = nil
            if let col = mapping.variantUnit, let rawUnit = row[col]?.trimmingCharacters(in: .whitespacesAndNewlines), !rawUnit.isEmpty {
                if let id = unitByDisplay[rawUnit.lowercased()] {
                    variantUnitId = id
                } else {
                    errors.append(.mapping(
                        rowIndex: i,
                        field: "variant_unit",
                        reason: "Line \(line): unit '\(rawUnit)' not found in your catalog."
                    ))
                }
            }

            variants.append(CatalogImportVariant(
                rowIndex: variants.count,
                familyRowIndex: familyIndex,
                sku: sku,
                quantity: quantity,
                priceOverride: priceOverride,
                unitCostOverride: unitCostOverride,
                warningThreshold: warning,
                criticalThreshold: critical,
                unitId: variantUnitId
            ))
            variantLines.append(line)
        }

        if rows.isEmpty {
            errors.append(.mapping(rowIndex: -1, field: "rows", reason: "CSV has no data rows."))
        }

        let payload: CatalogImportPayload? = errors.isEmpty
            ? CatalogImportPayload(families: families, variants: variants)
            : nil

        return CatalogCSVMapResult(
            payload: payload,
            errors: errors,
            variantSourceLineNumbers: variantLines
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
        errors: inout [CatalogImportError]
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
