//
//  ProjectActionBarLayout.swift
//  OPS
//
//  Pure layout planner for the Home ProjectActionBar.
//

import CoreGraphics
import Foundation

struct ProjectActionBarLayout: Equatable {
    enum Arrangement: Equatable {
        case singleRow
        case grid(columns: Int)
    }

    static let outerHorizontalPadding: CGFloat = 16
    static let containerHorizontalPadding: CGFloat = 4
    static let dividerWidth: CGFloat = 1
    static let horizontalDividerHeight: CGFloat = 1
    static let rowSpacing: CGFloat = 0
    static let minimumButtonWidth: CGFloat = 44
    static let preferredButtonWidth: CGFloat = 60

    private static let labelTracking: CGFloat = 0.8
    private static let labelGlyphWidth: CGFloat = 7.2
    private static let labelHorizontalBreathingRoom: CGFloat = 6
    private static let labelScaleFloor: CGFloat = 0.85
    private static let maxGridColumns = 3

    let arrangement: Arrangement
    let rowCounts: [Int]
    let minimumButtonWidth: CGFloat
    let labelsFit: Bool

    static func plan(
        availableWidth: CGFloat,
        labels: [String]
    ) -> ProjectActionBarLayout {
        guard !labels.isEmpty else {
            return ProjectActionBarLayout(
                arrangement: .singleRow,
                rowCounts: [],
                minimumButtonWidth: 0,
                labelsFit: true
            )
        }

        let buttonCount = labels.count
        let singleRowWidth = buttonWidth(availableWidth: availableWidth, columns: buttonCount)
        if singleRowWidth >= preferredButtonWidth && labelsFit(labels, in: singleRowWidth) {
            return ProjectActionBarLayout(
                arrangement: .singleRow,
                rowCounts: [buttonCount],
                minimumButtonWidth: singleRowWidth,
                labelsFit: true
            )
        }

        let maxColumns = min(maxGridColumns, buttonCount)
        for columns in stride(from: maxColumns, through: 1, by: -1) {
            let width = buttonWidth(availableWidth: availableWidth, columns: columns)
            if width >= preferredButtonWidth && labelsFit(labels, in: width) {
                return gridPlan(
                    availableWidth: availableWidth,
                    count: buttonCount,
                    columns: columns,
                    labels: labels
                )
            }
        }

        for columns in stride(from: maxColumns, through: 1, by: -1) {
            let width = buttonWidth(availableWidth: availableWidth, columns: columns)
            if width >= minimumButtonWidth && labelsFit(labels, in: width) {
                return gridPlan(
                    availableWidth: availableWidth,
                    count: buttonCount,
                    columns: columns,
                    labels: labels
                )
            }
        }

        let fallbackColumns = max(
            1,
            min(maxColumns, columnsFittingMinimumButtonWidth(availableWidth: availableWidth, maxColumns: maxColumns))
        )

        return gridPlan(
            availableWidth: availableWidth,
            count: buttonCount,
            columns: fallbackColumns,
            labels: labels
        )
    }

    static func rowCounts(count: Int, columns: Int) -> [Int] {
        guard count > 0 else { return [] }
        var remaining = count
        var rows: [Int] = []

        while remaining > 0 {
            let rowCount = min(columns, remaining)
            rows.append(rowCount)
            remaining -= rowCount
        }

        return rows
    }

    private static func gridPlan(
        availableWidth: CGFloat,
        count: Int,
        columns: Int,
        labels: [String]
    ) -> ProjectActionBarLayout {
        let rows = rowCounts(count: count, columns: columns)
        let narrowestWidth = rows
            .map { buttonWidth(availableWidth: availableWidth, columns: $0) }
            .min() ?? 0

        return ProjectActionBarLayout(
            arrangement: .grid(columns: columns),
            rowCounts: rows,
            minimumButtonWidth: narrowestWidth,
            labelsFit: labelsFit(labels, in: narrowestWidth)
        )
    }

    private static func columnsFittingMinimumButtonWidth(
        availableWidth: CGFloat,
        maxColumns: Int
    ) -> Int {
        for columns in stride(from: maxColumns, through: 1, by: -1) {
            if buttonWidth(availableWidth: availableWidth, columns: columns) >= minimumButtonWidth {
                return columns
            }
        }

        return 1
    }

    private static func buttonWidth(availableWidth: CGFloat, columns: Int) -> CGFloat {
        guard columns > 0 else { return 0 }

        let contentWidth = max(
            0,
            availableWidth
                - (outerHorizontalPadding * 2)
                - (containerHorizontalPadding * 2)
        )
        let dividerWidth = CGFloat(max(0, columns - 1)) * Self.dividerWidth

        return max(0, (contentWidth - dividerWidth) / CGFloat(columns))
    }

    private static func labelsFit(_ labels: [String], in width: CGFloat) -> Bool {
        labels.allSatisfy { requiredLabelWidth($0) <= width }
    }

    private static func requiredLabelWidth(_ label: String) -> CGFloat {
        let characterCount = label.uppercased().count
        guard characterCount > 0 else { return 0 }

        let glyphs = CGFloat(characterCount) * labelGlyphWidth
        let tracking = CGFloat(max(0, characterCount - 1)) * labelTracking

        return (glyphs + tracking + labelHorizontalBreathingRoom) * labelScaleFloor
    }
}
