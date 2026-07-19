//
//  VinylBulkOrderComposerTests.swift
//  OPSTests
//
//  Locks the combined supplier message to Jackson's exact format (spec § 7):
//  per-job sections in order, blank-line separation, consumables tail with
//  singular/plural correctness and zero-line omission. Cut lines are rendered
//  through the REAL cut template machinery + feet-and-inches formatter so the
//  golden string can never drift from what the wizard sends.
//

import XCTest
@testable import OPS

final class VinylBulkOrderComposerTests: XCTestCase {

    /// Render one cut line exactly the way the wizard does: the user's cut
    /// template through the shared token machinery, lengths through
    /// `vinylFormatFeetAndInches`.
    private func cutLine(quantity: Int, lengthInches: Double) -> String {
        VinylCutListTextTemplate.replacingTokens(
            in: VinylCutListTextTemplate.defaultCutTemplate,
            replacements: [
                "quantity": "\(quantity)",
                "length": vinylFormatFeetAndInches(lengthInches)
            ]
        )
    }

    /// The exact example Jackson supplied, verbatim — two cut-list jobs plus
    /// the consumables tail. Locks `13' 6"` formatting through the real
    /// formatter.
    func testGoldenJacksonFormat() {
        let sections = [
            VinylBulkOrderSection(
                po: "6836 Mark Ln",
                color: "68mil Cobblestone",
                cutLines: [
                    cutLine(quantity: 9, lengthInches: 108),   // 9'
                    cutLine(quantity: 2, lengthInches: 156)    // 13'
                ],
                rollsLine: nil
            ),
            VinylBulkOrderSection(
                po: "303 Stevens",
                color: "68mil Hansberry",
                cutLines: [
                    cutLine(quantity: 2, lengthInches: 312),   // 26'
                    cutLine(quantity: 4, lengthInches: 162)    // 13' 6"
                ],
                rollsLine: nil
            )
        ]
        let consumables = VinylConsumablesSuggestion(
            dripTubes: 2, ninetyTubes: 1, clipTubes: 1, glueBuckets: 7,
            totalDripSticks: 44, totalNinetySticks: 12, totalClipSticks: 40,
            exactGlueBuckets: 6.2
        )

        let message = VinylBulkOrderComposer.compose(sections: sections, consumables: consumables)

        XCTAssertEqual(message, """
        PO 6836 Mark Ln
        Color: 68mil Cobblestone
        -9 @ 9'
        -2 @ 13'

        PO 303 Stevens
        Color: 68mil Hansberry
        -2 @ 26'
        -4 @ 13' 6"

        -2 tubes drip edge
        -1 tube 90 flash
        -1 tube clip
        -7 buckets glue
        """)
    }

    /// Color+PO-only job (no drawing / unconfirmed scale): section is exactly
    /// two lines, no blank-line artifact where [cuts] was.
    func testColorPOOnlySectionHasNoCutsArtifact() {
        let sections = [
            VinylBulkOrderSection(po: "88 Ridge Rd", color: "68mil Slate", cutLines: [], rollsLine: nil),
            VinylBulkOrderSection(po: "6836 Mark Ln", color: "68mil Cobblestone", cutLines: [cutLine(quantity: 1, lengthInches: 120)], rollsLine: nil)
        ]

        let message = VinylBulkOrderComposer.compose(sections: sections, consumables: nil)

        XCTAssertEqual(message, """
        PO 88 Ridge Rd
        Color: 68mil Slate

        PO 6836 Mark Ln
        Color: 68mil Cobblestone
        -1 @ 10'
        """)
    }

    /// Full-roll jobs emit the rolls line in place of cut lines.
    func testFullRollSectionUsesRollsLine() {
        let sections = [
            VinylBulkOrderSection(
                po: "45 Bayview",
                color: "68mil Sandstone",
                cutLines: [],
                rollsLine: "3 ROLLS @ 75' × 72\""
            )
        ]

        let message = VinylBulkOrderComposer.compose(sections: sections, consumables: nil)

        XCTAssertEqual(message, """
        PO 45 Bayview
        Color: 68mil Sandstone
        3 ROLLS @ 75' × 72"
        """)
    }

    /// Empty color renders the FIELD CONFIRM placeholder.
    func testEmptyColorRendersFieldConfirm() {
        let message = VinylBulkOrderComposer.compose(
            sections: [VinylBulkOrderSection(po: "12 Elm", color: "", cutLines: [], rollsLine: nil)],
            consumables: nil
        )
        XCTAssertEqual(message, "PO 12 Elm\nColor: FIELD CONFIRM")
    }

    /// All-zero consumables append no tail; nil appends no tail.
    func testAllZeroConsumablesOmitTail() {
        let zero = VinylConsumablesSuggestion(
            dripTubes: 0, ninetyTubes: 0, clipTubes: 0, glueBuckets: 0,
            totalDripSticks: 0, totalNinetySticks: 0, totalClipSticks: 0,
            exactGlueBuckets: 0
        )
        let sections = [VinylBulkOrderSection(po: "12 Elm", color: "Slate", cutLines: [], rollsLine: nil)]

        XCTAssertEqual(
            VinylBulkOrderComposer.compose(sections: sections, consumables: zero),
            "PO 12 Elm\nColor: Slate"
        )
        XCTAssertNil(VinylBulkOrderComposer.consumablesTail(zero))
        XCTAssertNil(VinylBulkOrderComposer.consumablesTail(nil))
    }

    /// Zero lines inside a non-zero tail are omitted; singular forms correct.
    func testTailSingularPluralAndZeroOmission() {
        let suggestion = VinylConsumablesSuggestion(
            dripTubes: 1, ninetyTubes: 0, clipTubes: 3, glueBuckets: 1,
            totalDripSticks: 8, totalNinetySticks: 0, totalClipSticks: 120,
            exactGlueBuckets: 0.6
        )
        XCTAssertEqual(
            VinylBulkOrderComposer.consumablesTail(suggestion),
            "-1 tube drip edge\n-3 tubes clip\n-1 bucket glue"
        )
    }

    /// A custom section template reorders/rewrites the section body.
    func testCustomSectionTemplateOverride() {
        let message = VinylBulkOrderComposer.compose(
            sections: [
                VinylBulkOrderSection(
                    po: "303 Stevens",
                    color: "Hansberry",
                    cutLines: [cutLine(quantity: 2, lengthInches: 312)],
                    rollsLine: nil
                )
            ],
            consumables: nil,
            sectionTemplate: "[color] // [project]\n[cuts]"
        )
        XCTAssertEqual(message, "Hansberry // 303 Stevens\n-2 @ 26'")
    }

    /// Comma separator joins cut lines on one line.
    func testCommaSeparatorJoinsCuts() {
        let message = VinylBulkOrderComposer.compose(
            sections: [
                VinylBulkOrderSection(
                    po: "6836 Mark Ln",
                    color: "Cobblestone",
                    cutLines: [cutLine(quantity: 9, lengthInches: 108), cutLine(quantity: 2, lengthInches: 156)],
                    rollsLine: nil
                )
            ],
            consumables: nil,
            cutSeparator: .comma
        )
        XCTAssertEqual(message, "PO 6836 Mark Ln\nColor: Cobblestone\n-9 @ 9', -2 @ 13'")
    }

    /// Blank/whitespace template falls back to the default.
    func testBlankTemplateFallsBackToDefault() {
        let message = VinylBulkOrderComposer.compose(
            sections: [VinylBulkOrderSection(po: "12 Elm", color: "Slate", cutLines: [], rollsLine: nil)],
            consumables: nil,
            sectionTemplate: "   \n  "
        )
        XCTAssertEqual(message, "PO 12 Elm\nColor: Slate")
    }
}
