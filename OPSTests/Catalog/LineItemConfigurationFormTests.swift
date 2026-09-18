//
//  LineItemConfigurationFormTests.swift
//  OPSTests
//
//  The line item editor's option rules. A count option (end posts, corners) is
//  the job's geometry: the editor never fills one — not from the catalogue's
//  default_value, not with a fallback 0 — and a required option left blank
//  stops the save. An entered 0 is a real count and is kept. Mirrors the web
//  editor's resolver (ops-web `resolveProductConfiguration`, 2026-09-17), which
//  acceptance relies on: the server refuses a blank count, but cannot tell an
//  injected 0 from a real one.
//

import XCTest
@testable import OPS

final class LineItemConfigurationFormTests: XCTestCase {

    private typealias Form = LineItemConfigurationForm

    // MARK: - Canpro "Picket Rail — Level" fixture

    /// Two selects, one boolean and five counts. The counts carry the catalogue
    /// defaults production held before 2026-09-17 (1, 1, 0, 0, 0), so every test
    /// below proves a count default is never used, whatever the data says.
    private func canproOptions() -> [ProductOption] {
        [
            ProductOption(id: "o_color", productId: "p_rail", name: "Color",
                          kind: .select, affectsRecipe: true, defaultValue: "Black", sortOrder: 0),
            ProductOption(id: "o_mount", productId: "p_rail", name: "Mount Type",
                          kind: .select, affectsRecipe: true, defaultValue: "Side mount", sortOrder: 1),
            ProductOption(id: "o_left", productId: "p_rail", name: "Left ends",
                          kind: .integer, affectsRecipe: true, defaultValue: "1", sortOrder: 2),
            ProductOption(id: "o_right", productId: "p_rail", name: "Right ends",
                          kind: .integer, affectsRecipe: true, defaultValue: "1", sortOrder: 3),
            ProductOption(id: "o_corners", productId: "p_rail", name: "Corners",
                          kind: .integer, affectsRecipe: true, defaultValue: "0", sortOrder: 4),
            ProductOption(id: "o_45", productId: "p_rail", name: "45° corners",
                          kind: .integer, affectsRecipe: true, defaultValue: "0", sortOrder: 5),
            ProductOption(id: "o_wall", productId: "p_rail", name: "Wall returns",
                          kind: .integer, affectsRecipe: true, defaultValue: "0", sortOrder: 6),
            ProductOption(id: "o_lights", productId: "p_rail", name: "Post lights",
                          kind: .boolean, affectsPrice: true, required: false, defaultValue: "true", sortOrder: 7),
        ]
    }

    private func canproValues() -> [ProductOptionValue] {
        [
            ProductOptionValue(id: "v_black", optionId: "o_color", value: "Black", sortOrder: 0),
            ProductOptionValue(id: "v_white", optionId: "o_color", value: "White", sortOrder: 1),
            ProductOptionValue(id: "v_top", optionId: "o_mount", value: "Top mount", sortOrder: 0),
            ProductOptionValue(id: "v_side", optionId: "o_mount", value: "Side mount", sortOrder: 1),
        ]
    }

    private let countIds = ["o_left", "o_right", "o_corners", "o_45", "o_wall"]

    // MARK: - Seeding a new line

    func test_seeded_fillsSelectAndBooleanDefaults() {
        let seeded = Form.seeded([:], options: canproOptions(), optionValues: canproValues())

        XCTAssertEqual(seeded["o_color"], .selectId("v_black"))
        XCTAssertEqual(seeded["o_mount"], .selectId("v_side"))
        XCTAssertEqual(seeded["o_lights"], .boolean(true))
    }

    func test_seeded_selectWithoutAMatchingDefault_takesTheFirstValue_asToday() {
        var options = canproOptions()
        options[0] = ProductOption(id: "o_color", productId: "p_rail", name: "Color",
                                   kind: .select, defaultValue: "Bronze", sortOrder: 0)

        let seeded = Form.seeded([:], options: options, optionValues: canproValues())

        XCTAssertEqual(seeded["o_color"], .selectId("v_black"))
    }

    func test_seeded_neverFillsACount_evenWhenTheCatalogueCarriesADefault() {
        let seeded = Form.seeded([:], options: canproOptions(), optionValues: canproValues())

        for id in countIds {
            XCTAssertNil(seeded[id], "\(id) must stay blank, not take its default or 0")
        }
    }

    func test_seeded_neverFillsACount_whateverTheDefaultText() {
        for defaultValue in ["1", "0", " 2 ", "-1", "abc", "1.5", "", nil] as [String?] {
            let count = ProductOption(id: "o_left", productId: "p_rail", name: "Left ends",
                                      kind: .integer, defaultValue: defaultValue, sortOrder: 0)

            let seeded = Form.seeded([:], options: [count], optionValues: [])

            XCTAssertNil(seeded["o_left"], "default \(String(describing: defaultValue)) must not fill the count")
        }
    }

    func test_seeded_keepsEveryValueAlreadyOnTheLine_includingAnEnteredZero() {
        let existing: [String: Form.OptionValue] = [
            "o_color": .selectId("v_white"),
            "o_left": .integer(2),
            "o_corners": .integer(0),
            "o_lights": .boolean(false),
        ]

        let seeded = Form.seeded(existing, options: canproOptions(), optionValues: canproValues())

        XCTAssertEqual(seeded["o_color"], .selectId("v_white"))
        XCTAssertEqual(seeded["o_left"], .integer(2))
        XCTAssertEqual(seeded["o_corners"], .integer(0))
        XCTAssertEqual(seeded["o_lights"], .boolean(false))
        XCTAssertNil(seeded["o_right"])
    }

    // MARK: - Hydrating an existing line for edit

    func test_hydrated_existingLineKeepsItsCounts_andShowsAMissingCountBlank() {
        let snapshot = #"{"o_color":"v_white","o_left":3,"o_right":0,"o_corners":1}"#

        let hydrated = Form.hydrated(snapshotJSON: snapshot, options: canproOptions(), optionValues: canproValues())

        XCTAssertEqual(hydrated["o_color"], .selectId("v_white"))
        XCTAssertEqual(hydrated["o_left"], .integer(3))
        XCTAssertEqual(hydrated["o_right"], .integer(0), "a stored 0 is a count")
        XCTAssertEqual(hydrated["o_corners"], .integer(1))
        XCTAssertNil(hydrated["o_45"], "a count the line never carried stays blank")
        XCTAssertNil(hydrated["o_wall"])
        // A select the stored line never carried takes its default, as a new line does.
        XCTAssertEqual(hydrated["o_mount"], .selectId("v_side"))
    }

    func test_hydrated_readsALegacyStringCount_asACount() {
        let snapshot = #"{"o_left":"2","o_right":" 4 "}"#

        let hydrated = Form.hydrated(snapshotJSON: snapshot, options: canproOptions(), optionValues: canproValues())

        XCTAssertEqual(hydrated["o_left"], .integer(2))
        XCTAssertEqual(hydrated["o_right"], .integer(4))
    }

    func test_hydrated_treatsAnUnreadableCount_asBlank_neverAsZero() {
        let snapshot = #"{"o_left":"two","o_right":true,"o_corners":2.5}"#

        let hydrated = Form.hydrated(snapshotJSON: snapshot, options: canproOptions(), optionValues: canproValues())

        XCTAssertNil(hydrated["o_left"])
        XCTAssertNil(hydrated["o_right"])
        XCTAssertNil(hydrated["o_corners"])
    }

    func test_hydrated_withNoSnapshot_matchesANewLine() {
        let hydrated = Form.hydrated(snapshotJSON: nil, options: canproOptions(), optionValues: canproValues())

        XCTAssertEqual(hydrated, Form.seeded([:], options: canproOptions(), optionValues: canproValues()))
    }

    // MARK: - Required options

    func test_missingRequiredOptions_namesEveryBlankCount_inDisplayOrder() {
        let seeded = Form.seeded([:], options: canproOptions(), optionValues: canproValues())

        let missing = Form.missingRequiredOptions(options: canproOptions(), optionValues: canproValues(), configured: seeded)

        XCTAssertEqual(missing.map(\.id), countIds)
    }

    func test_missingRequiredOptions_isEmpty_onceEveryCountIsEntered_zeroIncluded() {
        var configured = Form.seeded([:], options: canproOptions(), optionValues: canproValues())
        configured["o_left"] = .integer(1)
        configured["o_right"] = .integer(1)
        configured["o_corners"] = .integer(0)
        configured["o_45"] = .integer(0)
        configured["o_wall"] = .integer(0)

        let missing = Form.missingRequiredOptions(options: canproOptions(), optionValues: canproValues(), configured: configured)

        XCTAssertEqual(missing, [])
    }

    func test_missingRequiredOptions_ignoresAnOptionalBlankOption() {
        let optionalCount = ProductOption(id: "o_extra", productId: "p_rail", name: "Extra posts",
                                          kind: .integer, required: false, defaultValue: "1", sortOrder: 0)

        let missing = Form.missingRequiredOptions(options: [optionalCount], optionValues: [], configured: [:])

        XCTAssertEqual(missing, [])
    }

    func test_missingRequiredOptions_countsAValueOfTheWrongKind_asMissing() {
        let configured: [String: Form.OptionValue] = [
            "o_color": .integer(1),
            "o_left": .selectId("v_black"),
        ]
        let options = canproOptions().filter { ["o_color", "o_left"].contains($0.id) }

        let missing = Form.missingRequiredOptions(options: options, optionValues: canproValues(), configured: configured)

        XCTAssertEqual(missing.map(\.id), ["o_color", "o_left"])
    }

    func test_missingRequiredOptions_countsASelectPointingAtNoValue_asMissing() {
        let options = canproOptions().filter { $0.id == "o_color" }

        let missing = Form.missingRequiredOptions(
            options: options,
            optionValues: canproValues(),
            configured: ["o_color": .selectId("v_gone")]
        )

        XCTAssertEqual(missing.map(\.id), ["o_color"])
    }

    // MARK: - Save gate

    func test_saveGate_blocksABlankRequiredCount_andNamesIt() {
        var configured = Form.seeded([:], options: canproOptions(), optionValues: canproValues())
        configured["o_left"] = .integer(1)
        configured["o_right"] = .integer(1)
        configured["o_45"] = .integer(0)

        let gate = Form.saveGate(options: canproOptions(), optionValues: canproValues(), configured: configured)

        XCTAssertEqual(gate, .blocked(missingOptionIds: ["o_corners", "o_wall"]))
        XCTAssertEqual(Form.blockedMessage(for: Form.missingRequiredOptions(
            options: canproOptions(), optionValues: canproValues(), configured: configured
        )), "Corners, Wall returns. Required to save.")
    }

    func test_saveGate_letsTheLineSave_whenEveryCountIsEntered_zeroIncluded() {
        var configured = Form.seeded([:], options: canproOptions(), optionValues: canproValues())
        for id in countIds { configured[id] = .integer(0) }

        let gate = Form.saveGate(options: canproOptions(), optionValues: canproValues(), configured: configured)

        XCTAssertEqual(gate, .ready)
    }

    func test_saveGate_isReady_forAProductWithNoOptions() {
        XCTAssertEqual(Form.saveGate(options: [], optionValues: [], configured: [:]), .ready)
    }

    func test_blockedMessage_namesASingleOption() {
        let corners = canproOptions().first { $0.id == "o_corners" }!

        XCTAssertEqual(Form.blockedMessage(for: [corners]), "Corners. Required to save.")
        XCTAssertEqual(Form.blockedTitle, "// NOT ENTERED")
    }

    // MARK: - Count control

    func test_countStepping_fromBlank_minusEntersZero_plusEntersOne() {
        XCTAssertEqual(Form.decremented(nil), 0, "entering 0 from blank is one tap")
        XCTAssertEqual(Form.incremented(nil), 1)
        XCTAssertTrue(Form.canDecrement(nil))
        XCTAssertTrue(Form.canIncrement(nil))
    }

    func test_countStepping_neverGoesBelowZeroOrAboveTheCeiling() {
        XCTAssertEqual(Form.decremented(3), 2)
        XCTAssertEqual(Form.decremented(0), 0)
        XCTAssertFalse(Form.canDecrement(0), "a dead minus at 0 tells the operator it is the floor")
        XCTAssertEqual(Form.incremented(2), 3)
        XCTAssertEqual(Form.incremented(999), 999)
        XCTAssertFalse(Form.canIncrement(999))
    }

    func test_count_readsOnlyAnIntegerValue() {
        let configured: [String: Form.OptionValue] = [
            "o_left": .integer(0),
            "o_right": .selectId("3"),
        ]

        XCTAssertEqual(Form.count(in: configured, optionId: "o_left"), 0)
        XCTAssertNil(Form.count(in: configured, optionId: "o_right"))
        XCTAssertNil(Form.count(in: configured, optionId: "o_corners"))
    }

    // MARK: - Saved snapshot (the wire the server guard reads)

    func test_snapshotJSON_omitsABlankCount_andKeepsAnEnteredZeroAsANumber() throws {
        let configured: [String: Form.OptionValue] = [
            "o_color": .selectId("v_black"),
            "o_left": .integer(0),
            "o_lights": .boolean(false),
        ]

        let json = try XCTUnwrap(Form.snapshotJSON(configured))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), ["o_color", "o_left", "o_lights"])
        XCTAssertEqual(object["o_color"] as? String, "v_black")
        let zero = try XCTUnwrap(object["o_left"] as? NSNumber)
        XCTAssertNotEqual(CFGetTypeID(zero as CFTypeRef), CFBooleanGetTypeID(), "0 must not become false")
        XCTAssertEqual(zero.intValue, 0)
        XCTAssertNil(object["o_right"])
    }

    func test_snapshotJSON_isNil_forNoOptions() {
        XCTAssertNil(Form.snapshotJSON([:]))
    }

    /// The edit path sends the snapshot through `UpdateLineItemDTO`. A count of 0
    /// or 1 must reach PostgREST as a JSON number, never as a boolean.
    func test_updateDTO_carriesTheSnapshot_withCountsAsNumbers() throws {
        let configured: [String: Form.OptionValue] = [
            "o_left": .integer(0),
            "o_right": .integer(1),
            "o_color": .selectId("v_black"),
        ]
        let dto = UpdateLineItemDTO(
            description: "Picket Rail — Level",
            quantity: 20,
            unitPrice: 70,
            isOptional: false,
            configuredOptions: Form.snapshotJSON(configured).map { RawJSONColumn(rawJSONString: $0) },
            resolvedUnitPrice: 70,
            resolvedOptionsLabel: "Black · 1 right ends"
        )

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as? [String: Any]
        )
        let options = try XCTUnwrap(body["configured_options"] as? [String: Any])
        for (key, expected) in [("o_left", 0), ("o_right", 1)] {
            let number = try XCTUnwrap(options[key] as? NSNumber, "\(key) missing")
            XCTAssertNotEqual(CFGetTypeID(number as CFTypeRef), CFBooleanGetTypeID(), "\(key) became a boolean")
            XCTAssertEqual(number.intValue, expected)
        }
        XCTAssertEqual(options["o_color"] as? String, "v_black")
        XCTAssertEqual(body["resolved_unit_price"] as? Double, 70)
        XCTAssertEqual(body["resolved_options_label"] as? String, "Black · 1 right ends")
    }
}
