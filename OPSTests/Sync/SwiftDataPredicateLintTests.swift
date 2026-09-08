import Foundation
import XCTest

/// Source-level guard for a crash class no runtime test covers generally: a
/// `#Predicate` that SwiftData cannot lower to SQL does not throw a Swift
/// error — Core Data raises an Objective-C exception inside `performAndWait`,
/// which Swift cannot catch, and the process aborts. On a background context
/// the app simply vanishes.
///
/// Bug 7a726160 (2026-09-08): `deckIds.contains($0.deckDesignId ?? "")` in the
/// compact recovery reader killed the app seconds after every home-swipe. The
/// store's own verdict, captured by `RecoveryAttentionSummaryTests`:
///
///     unimplemented SQL generation for predicate :
///     (TERNARY(deckDesignId != nil, deckDesignId, "") IN {"DECK-1", "deck-1"})
///     (bad LHS) (NSInvalidArgumentException)
///
/// The shape that fails is precise: SwiftData lowers `??` to a TERNARY, and
/// Core Data cannot use a TERNARY as the operand of `IN` (`contains`). The same
/// TERNARY compiles inside an ordered comparison — `DataActor+CalendarGrid`'s
/// `(task.startDate ?? floor) >= start` predicates run on every device today —
/// so this guard flags exactly the `contains` operand, app-wide, and nothing
/// else. Coalesce in Swift after the fetch; never inside a `contains`.
final class SwiftDataPredicateLintTests: XCTestCase {

    func testNoNilCoalescingInsideAContainsOperandOfAnyPredicate() throws {
        let root = try Self.appSourceRoot()
        var offenders: [String] = []
        for file in try Self.swiftFiles(under: root) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for block in Self.predicateBlocks(in: text)
            where Self.containsArguments(in: block.body).contains(where: { $0.contains("??") }) {
                let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
                offenders.append("\(relative):\(block.line)")
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "`??` inside a #Predicate `contains(...)` operand aborts the process at fetch time (Core Data: unimplemented SQL generation, bad LHS — an uncatchable Objective-C exception). Test the optional against nil in the predicate and coalesce in Swift afterwards. Offenders: \(offenders.joined(separator: ", "))"
        )
    }

    // MARK: - Scanner

    struct PredicateBlock {
        let line: Int
        let body: String
    }

    /// Every `#Predicate … { … }` closure in `text`. The macro must be followed
    /// directly by its closure — an optional generic clause, whitespace, then
    /// `{` — so a `#Predicate` mentioned in prose never adopts the next brace
    /// it happens to precede. Line comments are skipped for the same reason.
    /// Braces inside string literals are not special-cased: predicate bodies
    /// cannot interpolate, and a stray brace could only widen a block, never
    /// hide one.
    static func predicateBlocks(in text: String) -> [PredicateBlock] {
        var blocks: [PredicateBlock] = []
        var searchRange = text.startIndex..<text.endIndex
        while let macro = text.range(of: "#Predicate", range: searchRange) {
            searchRange = macro.upperBound..<text.endIndex

            let lineStart = text[..<macro.lowerBound].lastIndex(of: "\n")
                .map { text.index(after: $0) } ?? text.startIndex
            if text[lineStart..<macro.lowerBound].contains("//") { continue }

            var cursor = macro.upperBound
            if cursor < text.endIndex, text[cursor] == "<" {
                guard let genericClose = text[cursor...].firstIndex(of: ">") else { continue }
                cursor = text.index(after: genericClose)
            }
            while cursor < text.endIndex, text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
            guard cursor < text.endIndex, text[cursor] == "{" else { continue }

            let open = cursor
            var depth = 0
            var scan = open
            var close: String.Index?
            while scan < text.endIndex {
                let character = text[scan]
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 { close = scan; break }
                }
                scan = text.index(after: scan)
            }
            guard let end = close else { break }

            let line = text[..<macro.lowerBound].reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
            blocks.append(PredicateBlock(line: line, body: String(text[open...end])))
            searchRange = text.index(after: end)..<text.endIndex
        }
        return blocks
    }

    /// The argument text of every `.contains(` call in a predicate body,
    /// paren-balanced so nested calls stay inside their operand.
    static func containsArguments(in body: String) -> [String] {
        var arguments: [String] = []
        var searchRange = body.startIndex..<body.endIndex
        while let call = body.range(of: ".contains(", range: searchRange) {
            var depth = 1
            var cursor = call.upperBound
            var close: String.Index?
            while cursor < body.endIndex {
                let character = body[cursor]
                if character == "(" { depth += 1 }
                if character == ")" {
                    depth -= 1
                    if depth == 0 { close = cursor; break }
                }
                cursor = body.index(after: cursor)
            }
            guard let end = close else { break }
            arguments.append(String(body[call.upperBound..<end]))
            searchRange = body.index(after: end)..<body.endIndex
        }
        return arguments
    }

    static func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    /// `ops-ios/OPS` — the app target's sources, resolved from this file's
    /// compile-time path so the scan follows the checkout it was built from.
    static func appSourceRoot(from file: StaticString = #filePath) throws -> URL {
        var url = URL(fileURLWithPath: "\(file)")
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("OPS.xcodeproj")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url.appendingPathComponent("OPS")
            }
        }
        throw XCTSkip("OPS.xcodeproj not found above \(file); source scan needs the checkout on disk")
    }

    // MARK: - Scanner self-checks

    func testScannerFindsClosuresSkipsProseAndTargetsOnlyContainsOperands() {
        let sample = """
        let outside = value ?? ""
        // A #Predicate mentioned in prose must not adopt this brace { ids.contains($0.id ?? "") }
        let a = FetchDescriptor<Thing>(predicate: #Predicate { $0.status == "x" && ($0.due ?? floor) >= start })
        let b = FetchDescriptor<Thing>(predicate: #Predicate<Thing> {
            ids.contains($0.id ?? "") && { $0.count > 1 }()
        })
        let c = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { ids.contains(keys.contains($0.id) ? $0.id : ($0.alt ?? "")) })
        """
        let blocks = Self.predicateBlocks(in: sample)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.map(\.line), [3, 4, 7])

        // Tolerated: `??` inside an ordered comparison (the calendar-grid shape).
        XCTAssertTrue(blocks[0].body.contains("??"))
        XCTAssertFalse(Self.containsArguments(in: blocks[0].body).contains { $0.contains("??") })

        // Flagged: `??` as the operand of `contains`, including through nesting.
        XCTAssertEqual(Self.containsArguments(in: blocks[1].body), ["$0.id ?? \"\""])
        XCTAssertTrue(blocks[1].body.hasSuffix("}"))
        XCTAssertTrue(Self.containsArguments(in: blocks[2].body).contains { $0.contains("??") })
    }
}
