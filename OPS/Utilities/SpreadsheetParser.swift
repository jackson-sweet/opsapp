//
//  SpreadsheetParser.swift
//  OPS
//
//  Utility for parsing CSV and XLSX spreadsheet files
//

import Foundation
import CoreXLSX

// MARK: - Error Types

enum SpreadsheetError: LocalizedError {
    case invalidFile
    case emptyFile
    case parsingFailed(String)
    case unsupportedFormat
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "The file could not be opened"
        case .emptyFile:
            return "The file appears to be empty"
        case .parsingFailed(let message):
            return "Failed to parse file: \(message)"
        case .unsupportedFormat:
            return "Please use a CSV or Excel (.xlsx) file"
        case .accessDenied:
            return "Unable to access the file. Please check permissions."
        }
    }
}

// MARK: - Data Structures

struct SpreadsheetRow {
    let values: [String]

    func value(at index: Int) -> String {
        guard index >= 0 && index < values.count else { return "" }
        return values[index]
    }
}

struct SpreadsheetData {
    let headers: [String]
    let rows: [SpreadsheetRow]
    let sourceFileName: String

    var isEmpty: Bool {
        rows.isEmpty
    }

    var rowCount: Int {
        rows.count
    }

    var columnCount: Int {
        headers.count
    }
}

enum InventoryImportField: String, CaseIterable, Identifiable {
    case name = "Name"
    case quantity = "Quantity"
    case description = "Description"
    case sku = "SKU"
    case notes = "Notes"
    case unit = "Unit"
    case tags = "Tags"
    case skip = "Skip"

    var id: String { rawValue }

    var isRequired: Bool {
        self == .name
    }

    var icon: String {
        switch self {
        case .name: return "textformat"
        case .quantity: return "number"
        case .description: return "text.alignleft"
        case .sku: return "barcode"
        case .notes: return "note.text"
        case .unit: return "ruler"
        case .tags: return "tag"
        case .skip: return "forward"
        }
    }
}

struct ColumnMapping: Identifiable {
    let id = UUID()
    var columnIndex: Int
    var field: InventoryImportField
    var headerName: String
    var sampleValue: String
}

enum DuplicateType: Equatable {
    case nameMatch(existingId: String, existingName: String)
    case skuMatch(existingId: String, existingSku: String)

    var description: String {
        switch self {
        case .nameMatch(_, let name):
            return "Duplicate name: \(name)"
        case .skuMatch(_, let sku):
            return "Duplicate SKU: \(sku)"
        }
    }
}

struct ParsedInventoryItem: Identifiable {
    let id = UUID()
    var name: String  // Mutable to allow editing during preview
    var quantity: Double  // Mutable to allow editing during preview
    let description: String?
    let sku: String?
    let notes: String?
    let unitName: String?
    var tags: [String]  // Mutable to allow adding tags during preview
    let rowIndex: Int
    var validationErrors: [String]
    var duplicateType: DuplicateType?

    var hasErrors: Bool {
        !validationErrors.isEmpty
    }

    var isDuplicate: Bool {
        duplicateType != nil
    }

    var isValid: Bool {
        !hasErrors && !name.isEmpty
    }
}

struct ImportResult {
    let created: Int
    let skipped: Int
    let errors: Int
    let errorMessages: [String]

    var summary: String {
        var parts: [String] = []
        if created > 0 { parts.append("\(created) imported") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if errors > 0 { parts.append("\(errors) failed") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - SpreadsheetParser

class SpreadsheetParser {

    // MARK: - Public API

    /// Parse a spreadsheet file (CSV or XLSX)
    static func parse(url: URL) async throws -> SpreadsheetData {
        let fileExtension = url.pathExtension.lowercased()

        switch fileExtension {
        case "csv", "txt":
            return try await parseCSV(url: url)
        case "xlsx":
            return try await parseXLSX(url: url)
        default:
            throw SpreadsheetError.unsupportedFormat
        }
    }

    /// Transpose spreadsheet data (swap rows and columns)
    /// Converts column-oriented data to row-oriented:
    /// - First column values become the new headers (field names)
    /// - Each subsequent column becomes a new row (one item per column)
    ///
    /// Example input (columns are items):
    ///   headers: ["Name", "Lumber", "Drywall"]  <- first row parsed as headers
    ///   rows: [["Qty", "100", "50"], ["SKU", "A01", "A02"]]
    ///
    /// Output (rows are items):
    ///   headers: ["Name", "Qty", "SKU"]  <- first column becomes field names
    ///   rows: [["Lumber", "100", "A01"], ["Drywall", "50", "A02"]]
    static func transpose(_ data: SpreadsheetData) -> SpreadsheetData {
        // Combine headers (which was first row) with data rows
        // to get all rows for transposition
        var allRows: [[String]] = []
        allRows.append(data.headers) // First row was parsed as headers
        for row in data.rows {
            allRows.append(row.values)
        }

        guard !allRows.isEmpty, let firstRow = allRows.first, !firstRow.isEmpty else {
            return SpreadsheetData(headers: [], rows: [], sourceFileName: data.sourceFileName)
        }

        // New headers come from the first column of all rows
        var newHeaders: [String] = []
        for row in allRows {
            if !row.isEmpty {
                newHeaders.append(row[0])
            }
        }

        // Each subsequent column becomes a row (one item per column)
        let maxColumns = allRows.map { $0.count }.max() ?? 0
        var newRows: [SpreadsheetRow] = []

        for colIndex in 1..<maxColumns {
            var rowValues: [String] = []
            for row in allRows {
                if colIndex < row.count {
                    rowValues.append(row[colIndex])
                } else {
                    rowValues.append("")
                }
            }
            newRows.append(SpreadsheetRow(values: rowValues))
        }

        return SpreadsheetData(
            headers: newHeaders,
            rows: newRows,
            sourceFileName: data.sourceFileName
        )
    }

    /// Suggest column mappings based on header names
    static func suggestMappings(for data: SpreadsheetData) -> [ColumnMapping] {
        var mappings: [ColumnMapping] = []

        for (index, header) in data.headers.enumerated() {
            let normalizedHeader = header.lowercased().trimmingCharacters(in: .whitespaces)
            let field = detectField(from: normalizedHeader)
            let sampleValue = data.rows.first?.value(at: index) ?? ""

            mappings.append(ColumnMapping(
                columnIndex: index,
                field: field,
                headerName: header,
                sampleValue: sampleValue
            ))
        }

        return mappings
    }

    /// Suggest row mappings for single item mode (rows are fields, not items)
    /// Each row represents a field name and value for a single item
    static func suggestRowMappings(for data: SpreadsheetData) -> [ColumnMapping] {
        var mappings: [ColumnMapping] = []

        // Combine headers (first row) with data rows since each row is a field
        var allRows: [[String]] = []
        allRows.append(data.headers)
        for row in data.rows {
            allRows.append(row.values)
        }

        // Each row is a potential field mapping
        // First column = field name, second column = value
        for (rowIndex, row) in allRows.enumerated() {
            guard !row.isEmpty else { continue }
            let fieldName = row[0]
            let normalizedName = fieldName.lowercased().trimmingCharacters(in: .whitespaces)
            let field = detectField(from: normalizedName)
            let sampleValue = row.count > 1 ? row[1] : ""

            mappings.append(ColumnMapping(
                columnIndex: rowIndex, // Using rowIndex as identifier
                field: field,
                headerName: fieldName,
                sampleValue: sampleValue
            ))
        }

        return mappings
    }

    /// Parse rows into inventory items using column mappings
    static func parseItems(from data: SpreadsheetData, using mappings: [ColumnMapping]) -> [ParsedInventoryItem] {
        var items: [ParsedInventoryItem] = []

        // Build field index map
        var fieldIndices: [InventoryImportField: Int] = [:]
        for mapping in mappings where mapping.field != .skip {
            fieldIndices[mapping.field] = mapping.columnIndex
        }

        for (rowIndex, row) in data.rows.enumerated() {
            let name = fieldIndices[.name].map { row.value(at: $0) } ?? ""
            let quantityString = fieldIndices[.quantity].map { row.value(at: $0) } ?? "0"
            let description = fieldIndices[.description].map { row.value(at: $0) }
            let sku = fieldIndices[.sku].map { row.value(at: $0) }
            let notes = fieldIndices[.notes].map { row.value(at: $0) }
            let unitName = fieldIndices[.unit].map { row.value(at: $0) }
            let tagsString = fieldIndices[.tags].map { row.value(at: $0) } ?? ""

            // Parse quantity
            let quantity = Double(quantityString.replacingOccurrences(of: ",", with: "")) ?? 0

            // Parse tags (comma or semicolon separated)
            let tags = tagsString
                .components(separatedBy: CharacterSet(charactersIn: ",;"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Validation
            var errors: [String] = []
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append("Name is required")
            }

            let item = ParsedInventoryItem(
                name: name.trimmingCharacters(in: .whitespaces),
                quantity: quantity,
                description: description?.isEmpty == true ? nil : description,
                sku: sku?.isEmpty == true ? nil : sku,
                notes: notes?.isEmpty == true ? nil : notes,
                unitName: unitName?.isEmpty == true ? nil : unitName,
                tags: tags,
                rowIndex: rowIndex + 2, // +2 for 1-indexed and header row
                validationErrors: errors,
                duplicateType: nil
            )

            items.append(item)
        }

        return items
    }

    /// Parse a single item from row-based field mappings
    /// In this mode, each row represents a field (not an item)
    static func parseSingleItem(from data: SpreadsheetData, using mappings: [ColumnMapping]) -> [ParsedInventoryItem] {
        // Combine headers (first row) with data rows
        var allRows: [[String]] = []
        allRows.append(data.headers)
        for row in data.rows {
            allRows.append(row.values)
        }

        // Build field value map from rows
        var fieldValues: [InventoryImportField: String] = [:]

        for mapping in mappings where mapping.field != .skip {
            // mapping.columnIndex is actually the row index in single item mode
            let rowIndex = mapping.columnIndex
            if rowIndex < allRows.count {
                let row = allRows[rowIndex]
                // Value is in second column (index 1)
                let value = row.count > 1 ? row[1] : (row.count > 0 ? row[0] : "")
                fieldValues[mapping.field] = value
            }
        }

        let name = fieldValues[.name] ?? ""
        let quantityString = fieldValues[.quantity] ?? "0"
        let quantity = Double(quantityString.replacingOccurrences(of: ",", with: "")) ?? 0
        let tagsString = fieldValues[.tags] ?? ""
        let tags = tagsString
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Name is required")
        }

        let item = ParsedInventoryItem(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: quantity,
            description: fieldValues[.description]?.isEmpty == true ? nil : fieldValues[.description],
            sku: fieldValues[.sku]?.isEmpty == true ? nil : fieldValues[.sku],
            notes: fieldValues[.notes]?.isEmpty == true ? nil : fieldValues[.notes],
            unitName: fieldValues[.unit]?.isEmpty == true ? nil : fieldValues[.unit],
            tags: tags,
            rowIndex: 1,
            validationErrors: errors,
            duplicateType: nil
        )

        return [item]
    }

    /// Parse items with variations (grid format)
    /// Each row is an item type, each column (after first) is a variation
    /// Cell values are quantities
    ///
    /// Example input:
    ///   headers: ["", "White", "Black"]
    ///   rows: [["Left Post", "2", "4"], ["Right Post", "7", "4"]]
    ///
    /// Output: 4 items
    ///   - "Left Post" (White) qty 2
    ///   - "Left Post" (Black) qty 4
    ///   - "Right Post" (White) qty 7
    ///   - "Right Post" (Black) qty 4
    static func parseVariations(from data: SpreadsheetData, includeVariationInName: Bool = false) -> [ParsedInventoryItem] {
        var items: [ParsedInventoryItem] = []

        // Combine headers with rows (first row may have been parsed as headers)
        var allRows: [[String]] = []
        allRows.append(data.headers)
        for row in data.rows {
            allRows.append(row.values)
        }

        guard allRows.count >= 2 else { return items }

        // First row contains variation names (column headers)
        let variationRow = allRows[0]
        let variations = Array(variationRow.dropFirst()) // Skip first column (item names column)

        // Subsequent rows contain item data
        for rowIndex in 1..<allRows.count {
            let row = allRows[rowIndex]
            guard !row.isEmpty else { continue }

            let baseName = row[0].trimmingCharacters(in: .whitespaces)
            guard !baseName.isEmpty else { continue }

            // Create one item per variation (column)
            for (colIndex, variation) in variations.enumerated() {
                let valueIndex = colIndex + 1 // +1 because first column is item name
                let quantityString = valueIndex < row.count ? row[valueIndex] : "0"
                let quantity = Double(quantityString.replacingOccurrences(of: ",", with: "")) ?? 0

                // Skip if quantity is 0 or empty
                let trimmedQty = quantityString.trimmingCharacters(in: .whitespaces)
                if trimmedQty.isEmpty {
                    continue
                }

                let variationName = variation.trimmingCharacters(in: .whitespaces)
                let itemName = includeVariationInName && !variationName.isEmpty
                    ? "\(baseName) - \(variationName)"
                    : baseName

                var tags: [String] = []
                if !variationName.isEmpty {
                    tags.append(variationName)
                }

                var errors: [String] = []
                if baseName.isEmpty {
                    errors.append("Name is required")
                }

                let item = ParsedInventoryItem(
                    name: itemName,
                    quantity: quantity,
                    description: nil,
                    sku: nil,
                    notes: nil,
                    unitName: nil,
                    tags: tags,
                    rowIndex: rowIndex + 1, // +1 for display (1-indexed)
                    validationErrors: errors,
                    duplicateType: nil
                )

                items.append(item)
            }
        }

        return items
    }

    /// Check for duplicates against existing inventory
    static func checkDuplicates(
        _ items: [ParsedInventoryItem],
        existingItems: [InventoryItem]
    ) -> [ParsedInventoryItem] {
        let existingNames = Set(existingItems
            .filter { $0.deletedAt == nil }
            .map { $0.name.lowercased() })

        let existingSkus = Dictionary(uniqueKeysWithValues:
            existingItems
                .filter { $0.deletedAt == nil && $0.sku != nil && !$0.sku!.isEmpty }
                .map { ($0.sku!.lowercased(), $0) }
        )

        return items.map { item in
            var updatedItem = item

            // Check name duplicate
            if existingNames.contains(item.name.lowercased()) {
                if let existing = existingItems.first(where: {
                    $0.name.lowercased() == item.name.lowercased() && $0.deletedAt == nil
                }) {
                    updatedItem.duplicateType = .nameMatch(existingId: existing.id, existingName: existing.name)
                }
            }

            // Check SKU duplicate (if SKU provided and not already flagged)
            if let sku = item.sku, !sku.isEmpty, updatedItem.duplicateType == nil {
                if let existing = existingSkus[sku.lowercased()] {
                    updatedItem.duplicateType = .skuMatch(existingId: existing.id, existingSku: existing.sku ?? "")
                }
            }

            return updatedItem
        }
    }

    // MARK: - CSV Parsing

    private static func parseCSV(url: URL) async throws -> SpreadsheetData {
        // Security-scoped URL access
        guard url.startAccessingSecurityScopedResource() else {
            throw SpreadsheetError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Try other encodings
            do {
                content = try String(contentsOf: url, encoding: .isoLatin1)
            } catch {
                throw SpreadsheetError.parsingFailed("Could not read file contents")
            }
        }

        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard !lines.isEmpty else {
            throw SpreadsheetError.emptyFile
        }

        let headers = parseCSVLine(lines[0])
        let rows = lines.dropFirst().map { SpreadsheetRow(values: parseCSVLine($0)) }

        return SpreadsheetData(
            headers: headers,
            rows: rows,
            sourceFileName: url.lastPathComponent
        )
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var currentField = ""
        var inQuotes = false
        var previousChar: Character?

        for char in line {
            if char == "\"" {
                if inQuotes && previousChar == "\"" {
                    // Escaped quote
                    currentField.append(char)
                    previousChar = nil
                    continue
                }
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else {
                currentField.append(char)
            }
            previousChar = char
        }

        result.append(currentField.trimmingCharacters(in: .whitespaces))
        return result
    }

    // MARK: - XLSX Parsing

    private static func parseXLSX(url: URL) async throws -> SpreadsheetData {
        // Security-scoped URL access
        guard url.startAccessingSecurityScopedResource() else {
            throw SpreadsheetError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let file = XLSXFile(filepath: url.path) else {
            throw SpreadsheetError.invalidFile
        }

        // Get first worksheet
        let worksheetPaths: [String]
        do {
            worksheetPaths = try file.parseWorksheetPaths()
        } catch {
            throw SpreadsheetError.parsingFailed("Could not find worksheets")
        }

        guard let firstPath = worksheetPaths.first else {
            throw SpreadsheetError.emptyFile
        }

        let worksheet: Worksheet
        let sharedStrings: SharedStrings?

        do {
            worksheet = try file.parseWorksheet(at: firstPath)
            sharedStrings = try file.parseSharedStrings()
        } catch {
            throw SpreadsheetError.parsingFailed("Could not parse worksheet")
        }

        guard let data = worksheet.data, !data.rows.isEmpty else {
            throw SpreadsheetError.emptyFile
        }

        let rows = data.rows

        // Extract headers from first row
        let headerRow = rows[0]
        let headers = headerRow.cells.map { cell -> String in
            cellValue(cell, sharedStrings: sharedStrings)
        }

        // Extract data rows
        let dataRows = rows.dropFirst().map { row -> SpreadsheetRow in
            // Ensure we have values for all columns
            var values: [String] = []
            for i in 0..<headers.count {
                if let cell = row.cells.first(where: { columnIndex(from: $0.reference) == i }) {
                    values.append(cellValue(cell, sharedStrings: sharedStrings))
                } else {
                    values.append("")
                }
            }
            return SpreadsheetRow(values: values)
        }

        return SpreadsheetData(
            headers: headers,
            rows: Array(dataRows),
            sourceFileName: url.lastPathComponent
        )
    }

    private static func cellValue(_ cell: Cell, sharedStrings: SharedStrings?) -> String {
        if let sharedStrings = sharedStrings, let value = cell.stringValue(sharedStrings) {
            return value
        }
        if let value = cell.value {
            return value
        }
        return ""
    }

    private static func columnIndex(from reference: CellReference) -> Int {
        let letters = reference.column.value
        var result = 0
        for char in letters {
            result = result * 26 + Int(char.asciiValue! - Character("A").asciiValue!) + 1
        }
        return result - 1
    }

    // MARK: - Field Detection

    private static func detectField(from header: String) -> InventoryImportField {
        switch header {
        case "name", "item name", "item", "product", "product name", "material", "material name":
            return .name
        case "qty", "quantity", "count", "amount", "stock", "on hand":
            return .quantity
        case "description", "desc", "details":
            return .description
        case "sku", "part number", "part #", "part no", "item #", "item number", "item no", "code", "product code":
            return .sku
        case "notes", "note", "comments", "comment", "remarks":
            return .notes
        case "unit", "units", "uom", "unit of measure", "measure":
            return .unit
        case "tags", "tag", "category", "categories", "type", "types":
            return .tags
        default:
            return .skip
        }
    }
}
