//
//  VinylOrderSettingsControlsTests.swift
//  OPSTests
//
//  The order settings live in one place now: the single-project sheet and the
//  full-screen workspace render the same `VinylOrderSettingsControls`, so the
//  two can no longer drift. Every control routes through one edit type, which
//  is what these tests exercise — the binding write and the single re-plan
//  callback are the same code path for both callers.
//

import XCTest
@testable import OPS

final class VinylOrderSettingsControlsTests: XCTestCase {

    // MARK: - One callback per real change

    func testAnEditThatChangesNothingIsRefused() {
        let settings = VinylOrderSettings.default

        XCTAssertNil(
            VinylOrderSettingsControls.resolve(.direction(settings.direction), for: settings),
            "re-tapping the selected RUN segment must not re-plan"
        )
        XCTAssertNil(
            VinylOrderSettingsControls.resolve(.pattern(settings.patternMode), for: settings)
        )
        XCTAssertNil(
            VinylOrderSettingsControls.resolve(.rollWidth(settings.rollWidthInches), for: settings)
        )
    }

    func testEachEditMutatesExactlyItsOwnField() {
        let settings = VinylOrderSettings.default

        let turned = try! XCTUnwrap(
            VinylOrderSettingsControls.resolve(.direction(.widthwise), for: settings)
        )
        XCTAssertEqual(turned.direction, .widthwise)
        XCTAssertEqual(turned.rollWidthInches, settings.rollWidthInches)
        XCTAssertEqual(turned.seamOverlapInches, settings.seamOverlapInches)
        XCTAssertEqual(turned.edgeWrapInches, settings.edgeWrapInches)
        XCTAssertEqual(turned.patternMode, settings.patternMode)

        let wrapped = try! XCTUnwrap(
            VinylOrderSettingsControls.resolve(.edgeWrap(9), for: settings)
        )
        XCTAssertEqual(wrapped.edgeWrapInches, 9)
        XCTAssertEqual(wrapped.direction, settings.direction)
    }

    // MARK: - Behaviour carried over from the sheet

    /// A linear pattern cannot change direction mid-deck, so picking LINEAR
    /// releases the lock the same way the sheet always has.
    func testChoosingLinearClearsDirectionalChanges() {
        var settings = VinylOrderSettings.default
        settings.allowsDirectionalChanges = true

        let linear = try! XCTUnwrap(
            VinylOrderSettingsControls.resolve(.pattern(.linear), for: settings)
        )

        XCTAssertEqual(linear.patternMode, .linear)
        XCTAssertFalse(linear.allowsDirectionalChanges)
    }

    func testLockRunInvertsAllowsDirectionalChanges() {
        var settings = VinylOrderSettings.default
        settings.allowsDirectionalChanges = true

        let locked = try! XCTUnwrap(
            VinylOrderSettingsControls.resolve(.lockRun(true), for: settings)
        )
        XCTAssertFalse(locked.allowsDirectionalChanges)

        let released = try! XCTUnwrap(
            VinylOrderSettingsControls.resolve(.lockRun(false), for: locked)
        )
        XCTAssertTrue(released.allowsDirectionalChanges)
    }

    // MARK: - Bounds

    func testStepperBoundsMatchTheOnesTheSheetAndTheWizardHaveAlwaysUsed() {
        XCTAssertEqual(VinylOrderSettingsControls.rollWidthRange, 24...144)
        XCTAssertEqual(VinylOrderSettingsControls.rollWidthStep, 6)
        XCTAssertEqual(VinylOrderSettingsControls.seamRange, 0...12)
        XCTAssertEqual(VinylOrderSettingsControls.seamStep, 0.25)
        XCTAssertEqual(VinylOrderSettingsControls.wrapRange, 0...18)
        XCTAssertEqual(VinylOrderSettingsControls.wrapStep, 0.5)
    }

    func testSteppingClampsToTheBoundsRatherThanRunningPastThem() {
        XCTAssertEqual(
            VinylOrderSettingsControls.stepped(
                144,
                by: VinylOrderSettingsControls.rollWidthStep,
                in: VinylOrderSettingsControls.rollWidthRange
            ),
            144
        )
        XCTAssertEqual(
            VinylOrderSettingsControls.stepped(
                0,
                by: -VinylOrderSettingsControls.wrapStep,
                in: VinylOrderSettingsControls.wrapRange
            ),
            0
        )
        XCTAssertEqual(
            VinylOrderSettingsControls.stepped(
                1.5,
                by: VinylOrderSettingsControls.seamStep,
                in: VinylOrderSettingsControls.seamRange
            ),
            1.75
        )
    }

    // MARK: - Values read as formatted mono, never raw floats

    func testStepperValuesRenderThroughTheSharedInchFormatter() {
        XCTAssertEqual(vinylFormatInches(72), "72\"")
        XCTAssertEqual(vinylFormatInches(1.5), "1.5\"")
        XCTAssertEqual(vinylFormatInches(0), "0\"")
    }
}
