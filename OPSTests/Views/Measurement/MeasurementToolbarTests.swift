//
//  MeasurementToolbarTests.swift
//  OPSTests
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §5.2
//

import XCTest
import SwiftUI
@testable import OPS

final class MeasurementToolbarTests: XCTestCase {

    private func makeToolbar(config: MeasurementToolbarConfig,
                             activeTool: MeasurementTool = .measure) -> MeasurementToolbar {
        return MeasurementToolbar(
            activeTool: .constant(activeTool),
            config: config,
            onSelect: { _ in },
            onUndo: {},
            onRedo: {}
        )
    }

    func test_visibleTools_lidarWithOpeningNoMeasurements_hidesIncompleteAndUnavailableTools() {
        let bar = makeToolbar(config: .init(hasAuto: true, hasCalibrate: true,
                                            canExport: false, canUndo: false, canRedo: false))
        let visible = bar.visibleTools()
        XCTAssertEqual(visible, [.measure, .auto, .calibrate])
        XCTAssertFalse(visible.contains(.mark),
                       "MARK must stay hidden until PencilKit output is persisted/exported by this feature.")
        XCTAssertFalse(visible.contains(.note),
                       "NOTE must stay hidden until it has an implemented action.")
        XCTAssertFalse(visible.contains(.export),
                       "EXPORT must stay hidden until measurements exist.")
    }

    func test_visibleTools_noOpeningDetected_hidesAuto() {
        let bar = makeToolbar(config: .init(hasAuto: false, hasCalibrate: true,
                                            canExport: false, canUndo: false, canRedo: false))
        let visible = bar.visibleTools()
        XCTAssertFalse(visible.contains(.auto),
                       "AUTO must be HIDDEN (not greyed) when no opening detected, per §5.2")
        XCTAssertEqual(visible, [.measure, .calibrate])
    }

    func test_visibleTools_noDepthCapability_hidesCalibrate() {
        let bar = makeToolbar(config: .init(hasAuto: false, hasCalibrate: false,
                                            canExport: false, canUndo: false, canRedo: false))
        let visible = bar.visibleTools()
        XCTAssertFalse(visible.contains(.calibrate),
                       "CALIBRATE must be HIDDEN on noDepth capability per §3.8")
        XCTAssertFalse(visible.contains(.auto))
        XCTAssertEqual(visible, [.measure])
    }

    func test_export_hiddenWhenNoMeasurements() {
        let bar = makeToolbar(config: .init(hasAuto: false, hasCalibrate: true,
                                            canExport: false, canUndo: false, canRedo: false))
        XCTAssertFalse(bar.visibleTools().contains(.export))
        XCTAssertTrue(bar.isDisabled(.export),
                      "EXPORT remains disabled defensively if invoked while hidden.")
    }

    func test_export_visibleAndEnabledWhenMeasurementsExist() {
        let bar = makeToolbar(config: .init(hasAuto: false, hasCalibrate: true,
                                            canExport: true, canUndo: false, canRedo: false))
        XCTAssertEqual(bar.visibleTools(), [.measure, .calibrate, .export])
        XCTAssertFalse(bar.isDisabled(.export))
    }

    func test_markAndNote_visibilityRequiresExplicitConfig() {
        let bar = makeToolbar(config: .init(hasAuto: true, hasCalibrate: true,
                                            canExport: true, canUndo: false, canRedo: false,
                                            showsMark: true, showsNote: true))
        XCTAssertEqual(bar.visibleTools(), [.measure, .auto, .calibrate, .mark, .note, .export])
    }

    func test_availableTools_neverDisabled() {
        let bar = makeToolbar(config: .init(hasAuto: false, hasCalibrate: false,
                                            canExport: false, canUndo: false, canRedo: false))
        XCTAssertFalse(bar.isDisabled(.measure))
        XCTAssertFalse(bar.isDisabled(.auto))
        XCTAssertFalse(bar.isDisabled(.calibrate))
    }

    func test_toolSymbols_matchSpec() {
        XCTAssertEqual(MeasurementTool.measure.sfSymbol,   "ruler")
        XCTAssertEqual(MeasurementTool.auto.sfSymbol,      "viewfinder.rectangular")
        XCTAssertEqual(MeasurementTool.calibrate.sfSymbol, "creditcard")
        XCTAssertEqual(MeasurementTool.mark.sfSymbol,      "pencil.tip")
        XCTAssertEqual(MeasurementTool.note.sfSymbol,      "text.bubble")
        XCTAssertEqual(MeasurementTool.export.sfSymbol,    "square.and.arrow.up")
    }

    func test_toolLabels_uppercase() {
        for tool in MeasurementTool.allCases {
            XCTAssertEqual(tool.label, tool.label.uppercased(),
                           "Tool labels must be UPPERCASE per OPS voice")
        }
    }
}
