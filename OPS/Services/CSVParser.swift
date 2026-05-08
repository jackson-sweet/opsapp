//
//  CSVParser.swift
//  OPS
//
//  RFC 4180 CSV parser. Pure-function: takes the raw text of a CSV
//  file, returns a header row + array of rows keyed by header.
//
//  Handles:
//    - Quoted fields (with embedded commas, embedded quotes via "")
//    - LF, CRLF, and lone CR line terminators
//    - UTF-8 BOM at the start of the file (stripped)
//    - Empty fields, fields with leading/trailing whitespace
//    - Header row required (caller-facing error when missing)
//
//  Surfaces line numbers in errors so the import preview can point at
//  the right CSV row. Line numbers are 1-based and refer to the raw
//  input — including the header row, which is line 1.
//

import Foundation

enum CSVParseError: Error, LocalizedError {
    /// File did not contain at least a header row.
    case empty
    /// A row had a different field count than the header.
    /// `lineNumber` is 1-based across the raw input.
    case rowFieldCountMismatch(lineNumber: Int, expected: Int, actual: Int)
    /// A quoted field never closed before EOF.
    case unterminatedQuote(lineNumber: Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "CSV is empty — at minimum a header row is required."
        case .rowFieldCountMismatch(let line, let expected, let actual):
            return "Line \(line): expected \(expected) fields, got \(actual)."
        case .unterminatedQuote(let line):
            return "Line \(line): quoted field never closed."
        }
    }
}

struct CSVParseResult {
    /// Trimmed header names in original order.
    let headers: [String]
    /// One dict per data row, keyed by trimmed header. Values are
    /// untrimmed (the caller decides whether to trim).
    let rows: [[String: String]]
    /// 1-based line number of each data row, parallel to `rows`. The
    /// import preview uses this so a per-row error can point the user
    /// at the actual CSV line.
    let lineNumbers: [Int]
}

enum CSVParser {

    /// Parse raw CSV text. Throws `CSVParseError` on structural
    /// failures (empty, unterminated quote, row width mismatch).
    static func parse(_ raw: String) throws -> CSVParseResult {
        // Strip UTF-8 BOM if present.
        var text = raw
        if let first = text.unicodeScalars.first, first == "\u{FEFF}" {
            text.removeFirst()
        }

        let fields = try tokenize(text)
        guard !fields.isEmpty else { throw CSVParseError.empty }

        // First row is the header.
        let headerRow = fields[0]
        let headers = headerRow.values.map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let expectedCount = headers.count

        var rows: [[String: String]] = []
        var lineNumbers: [Int] = []

        for raw in fields.dropFirst() {
            // Skip purely empty trailing lines (one empty field, blank).
            if raw.values.count == 1, raw.values[0].isEmpty { continue }

            if raw.values.count != expectedCount {
                throw CSVParseError.rowFieldCountMismatch(
                    lineNumber: raw.lineNumber,
                    expected: expectedCount,
                    actual: raw.values.count
                )
            }
            var dict: [String: String] = [:]
            for (i, header) in headers.enumerated() {
                dict[header] = raw.values[i]
            }
            rows.append(dict)
            lineNumbers.append(raw.lineNumber)
        }

        return CSVParseResult(headers: headers, rows: rows, lineNumbers: lineNumbers)
    }

    // MARK: - Tokenizer

    /// One row's worth of tokenized fields, plus the 1-based line
    /// number where the row started in the raw input.
    private struct RawRow {
        let values: [String]
        let lineNumber: Int
    }

    /// State machine that walks the input one scalar at a time.
    /// Cheaper than `String.split` because we have to honour quoted
    /// fields (where a comma or newline does NOT terminate the field).
    private static func tokenize(_ text: String) throws -> [RawRow] {
        var rows: [RawRow] = []
        var currentValues: [String] = []
        var currentField = ""
        var inQuotes = false
        var line = 1
        var rowStartLine = 1
        var i = text.startIndex

        // Track whether a row has accumulated *anything* — distinguishes
        // a real empty row at EOF from an in-progress row.
        var rowHasContent = false

        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    // Look ahead for an escaped quote ("").
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        currentField.append("\"")
                        i = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                        i = text.index(after: i)
                        continue
                    }
                } else {
                    if c == "\n" || c == "\r" {
                        // Newline inside a quoted field — keep it, bump
                        // line counter for any newline so error
                        // messages still align with the editor's view.
                        line += 1
                    }
                    currentField.append(c)
                    i = text.index(after: i)
                    continue
                }
            }

            // Outside quotes
            if c == "\"" {
                // Quote opens a quoted field. We allow this only at the
                // start of a field — but most parsers tolerate mid-field
                // quotes. Stay strict: only honour the quote-open at
                // field start; otherwise treat as a literal.
                if currentField.isEmpty {
                    inQuotes = true
                    rowHasContent = true
                    i = text.index(after: i)
                    continue
                } else {
                    currentField.append(c)
                    i = text.index(after: i)
                    continue
                }
            }

            if c == "," {
                currentValues.append(currentField)
                currentField = ""
                rowHasContent = true
                i = text.index(after: i)
                continue
            }

            if c == "\r" {
                // Could be \r\n or lone \r.
                let next = text.index(after: i)
                if next < text.endIndex, text[next] == "\n" {
                    // Skip the \n on the next iteration.
                    i = next
                }
                // Fall through: treat as row terminator.
                if rowHasContent || !currentField.isEmpty {
                    currentValues.append(currentField)
                    rows.append(RawRow(values: currentValues, lineNumber: rowStartLine))
                }
                currentValues = []
                currentField = ""
                rowHasContent = false
                line += 1
                rowStartLine = line
                i = text.index(after: i)
                continue
            }

            if c == "\n" {
                if rowHasContent || !currentField.isEmpty {
                    currentValues.append(currentField)
                    rows.append(RawRow(values: currentValues, lineNumber: rowStartLine))
                }
                currentValues = []
                currentField = ""
                rowHasContent = false
                line += 1
                rowStartLine = line
                i = text.index(after: i)
                continue
            }

            currentField.append(c)
            rowHasContent = true
            i = text.index(after: i)
        }

        if inQuotes {
            throw CSVParseError.unterminatedQuote(lineNumber: rowStartLine)
        }

        // Flush trailing row (no trailing newline).
        if rowHasContent || !currentField.isEmpty {
            currentValues.append(currentField)
            rows.append(RawRow(values: currentValues, lineNumber: rowStartLine))
        }

        return rows
    }
}
