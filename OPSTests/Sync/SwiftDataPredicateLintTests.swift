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


    /// Second crash class, same family, worse failure mode. Bug (2026-09-09):
    /// `$0.assigneeIds.contains(user)` in `SiteVisitCaptureViewModel.openVisits()`
    /// killed the process with SIGSEGV — `_NSCoreDataStringSearch` →
    /// `CFStringGetLength` on a null CFString — whenever the term actually
    /// evaluated. It hid for months because SQLite short-circuits `OR`:
    /// `createdBy == user` matched first for self-made visits, so the array
    /// term never ran. A visit someone else created and assigned to this
    /// operator reached it, and so did the site-visit form snapshot test on its
    /// second render.
    ///
    /// Measured, not assumed (probes on iOS 26.5): the fault is the ARRAY
    /// attribute, in every combination — empty needle over an empty or
    /// populated array, real needle over an empty array, real needle over a
    /// matching array, and the term alone with no `OR` around it. All SIGSEGV.
    /// A `contains` over a stored STRING attribute is fine and stays legal —
    /// `MainTabView`'s field-role project fetch searches
    /// `teamMemberIdsString` on every launch and is unaffected — so this guard
    /// flags array-backed properties only. Filter array membership in Swift
    /// after the fetch.
    func testNoContainsOverAnArrayBackedAttributeInAnyPredicate() throws {
        let root = try Self.appSourceRoot()
        let arrayProperties = try Self.arrayBackedModelProperties(under: root)
        XCTAssertFalse(
            arrayProperties.isEmpty,
            "Model scan found no array-backed properties — the guard would pass vacuously"
        )

        var offenders: [String] = []
        for file in try Self.swiftFiles(under: root) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for block in Self.predicateBlocks(in: text) {
                let subject = Self.predicateSubject(of: block.body)
                for receiver in Self.containsReceivers(in: block.body) {
                    guard let property = Self.attributePath(of: receiver, rootedAt: subject),
                          arrayProperties.contains(property) else { continue }
                    let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
                    offenders.append("\(relative):\(block.line) (\(receiver))")
                }
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "`contains(...)` over an array-backed @Model attribute inside a #Predicate segfaults the process at fetch time (CoreData _NSCoreDataStringSearch dereferences a null CFString — not a catchable error). Fetch on the scalar terms and filter array membership in Swift afterwards. Offenders: \(offenders.joined(separator: ", "))"
        )
    }

    /// Names of every stored property declared with an array type inside a
    /// file that defines `@Model` types — the schema plus its versioned copies.
    static func arrayBackedModelProperties(under root: URL) throws -> Set<String> {
        let declaration = try NSRegularExpression(
            pattern: #"(?m)^\s*(?:@\w+(?:\([^)]*\))?\s+)*var\s+([A-Za-z0-9_]+)\s*:\s*\["#
        )
        var names: Set<String> = []
        for file in try swiftFiles(under: root) {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains("@Model") else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in declaration.matches(in: text, range: range) {
                guard let captured = Range(match.range(at: 1), in: text) else { continue }
                names.insert(String(text[captured]))
            }
        }
        return names
    }

    /// The name the predicate's closure gives its model — `thing` in
    /// `{ thing in … }`, otherwise the implicit `$0`.
    static func predicateSubject(of body: String) -> String {
        let head = body.dropFirst().prefix(120)
        guard let inKeyword = head.range(of: " in ") ?? head.range(of: " in\n") else { return "$0" }
        let candidate = head[..<inKeyword.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = !candidate.isEmpty && candidate.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        return valid ? candidate : "$0"
    }

    /// The receiver expression in front of every `.contains(` in a predicate
    /// body — `$0.assigneeIds` in `$0.assigneeIds.contains(user)`, `ids` in
    /// `ids.contains($0.id)`.
    static func containsReceivers(in body: String) -> [String] {
        var receivers: [String] = []
        var searchRange = body.startIndex..<body.endIndex
        while let call = body.range(of: ".contains(", range: searchRange) {
            var start = call.lowerBound
            while start > body.startIndex {
                let previous = body.index(before: start)
                let character = body[previous]
                guard character.isLetter || character.isNumber
                    || character == "_" || character == "." || character == "$" else { break }
                start = previous
            }
            if start < call.lowerBound {
                receivers.append(String(body[start..<call.lowerBound]))
            }
            searchRange = call.upperBound..<body.endIndex
        }
        return receivers
    }

    /// The attribute name a receiver reads off the predicate's model, or nil
    /// when the receiver is a captured collection instead.
    static func attributePath(of receiver: String, rootedAt subject: String) -> String? {
        guard receiver.hasPrefix(subject + ".") else { return nil }
        return receiver.dropFirst(subject.count + 1).split(separator: ".").last.map(String.init)
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

    func testArrayAttributeScannerSeparatesModelArraysFromCapturedCollections() {
        let sample = """
        let a = FetchDescriptor<Visit>(predicate: #Predicate<Visit> { $0.assigneeIds.contains(user) })
        let b = FetchDescriptor<Visit>(predicate: #Predicate<Visit> { ids.contains($0.id) })
        let c = FetchDescriptor<Project>(predicate: #Predicate<Project> { p in p.teamMemberIdsString.contains(user) })
        let d = FetchDescriptor<Visit>(predicate: #Predicate<Visit> { visit in visit.assigneeIds.contains(user) })
        """
        let blocks = Self.predicateBlocks(in: sample)
        XCTAssertEqual(blocks.count, 4)

        let arrays: Set<String> = ["assigneeIds"]
        var flagged: [String] = []
        for block in blocks {
            let subject = Self.predicateSubject(of: block.body)
            for receiver in Self.containsReceivers(in: block.body) {
                if let property = Self.attributePath(of: receiver, rootedAt: subject),
                   arrays.contains(property) {
                    flagged.append(receiver)
                }
            }
        }
        // Flagged: both the implicit-$0 and the named-parameter array reads.
        // Untouched: the captured-id `IN` shape, and the String CONTAINS that
        // MainTabView relies on.
        XCTAssertEqual(flagged, ["$0.assigneeIds", "visit.assigneeIds"])
        XCTAssertEqual(Self.predicateSubject(of: blocks[2].body), "p")
        XCTAssertEqual(Self.predicateSubject(of: blocks[0].body), "$0")
        XCTAssertEqual(Self.containsReceivers(in: blocks[1].body), ["ids"])
    }
}
