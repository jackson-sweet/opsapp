// OPS/OPSTests/DeckBuilder/DeckMeasurementPickerTests.swift

import Speech
import XCTest
@testable import OPS

final class DeckMeasurementPickerTests: XCTestCase {

    // MARK: - Dictation tap action (bug 722b1606)

    /// THE regression: a user who granted speech access in any earlier
    /// session must get listening on the FIRST tap — the old inline logic
    /// read a stale `.notDetermined` and silently re-requested authorization,
    /// eating the first mic tap on every speed-draw edge.
    func testDictationTapListensOnFirstTapWhenAlreadyAuthorized() {
        XCTAssertEqual(
            DictationTapAction.resolve(isListening: false, authorizationStatus: .authorized),
            .startListening
        )
    }

    func testDictationTapChainsAuthorizationIntoListeningWhenUndetermined() {
        XCTAssertEqual(
            DictationTapAction.resolve(isListening: false, authorizationStatus: .notDetermined),
            .requestAuthorizationThenStart
        )
    }

    func testDictationTapShowsGuidanceWhenAccessBlocked() {
        XCTAssertEqual(
            DictationTapAction.resolve(isListening: false, authorizationStatus: .denied),
            .showDeniedGuidance
        )
        XCTAssertEqual(
            DictationTapAction.resolve(isListening: false, authorizationStatus: .restricted),
            .showDeniedGuidance
        )
    }

    func testDictationTapStopsWhileListeningRegardlessOfStatus() {
        for status: SFSpeechRecognizerAuthorizationStatus in [.authorized, .notDetermined, .denied, .restricted] {
            XCTAssertEqual(
                DictationTapAction.resolve(isListening: true, authorizationStatus: status),
                .stopListening
            )
        }
    }

    /// The published status must be seeded from the system at init — the
    /// object is recreated per speed-draw edge, so a `.notDetermined`
    /// default made every recreated picker forget the user's grant.
    @MainActor
    func testVoiceInputSeedsAuthorizationStatusFromSystemAtInit() {
        let input = VoiceDimensionInput(
            expectedDimensionCount: 1,
            authorizationStatusProvider: { .authorized }
        )
        XCTAssertTrue(input.isAuthorized)

        let blocked = VoiceDimensionInput(
            expectedDimensionCount: 1,
            authorizationStatusProvider: { .denied }
        )
        XCTAssertFalse(blocked.isAuthorized)
        XCTAssertEqual(blocked.authorizationStatus, .denied)
    }

    // MARK: - Touch targets (bug 722b1606)

    /// Mic + continue are the per-edge workhorses — they get the standard
    /// 56pt field target, not the 44pt floor.
    func testDictationAndCommitUseStandardTouchTarget() {
        XCTAssertEqual(DeckMeasurementPickerTokens.standardTouch, 56)
        XCTAssertGreaterThanOrEqual(
            DeckMeasurementPickerTokens.standardTouch,
            DeckMeasurementPickerTokens.minTouch
        )
    }

    /// The action row at 56pt targets must still fit the narrowest supported
    /// phone (375pt): two 44pt escape hatches + 88pt unit toggle + mic and
    /// continue at 56pt + four gaps + the overlay's horizontal padding.
    func testActionRowWithStandardTargetsFitsNarrowestPhone() {
        let rowWidth = 2 * DeckMeasurementPickerTokens.minTouch
            + 2 * DeckMeasurementPickerTokens.minTouch
            + 2 * DeckMeasurementPickerTokens.standardTouch
            + 4 * DeckMeasurementPickerTokens.standardGap
            + 2 * OPSStyle.Layout.spacing3
        XCTAssertLessThanOrEqual(rowWidth, 375)
    }

    func testImperialOverflowNormalizesThroughStandardValue() {
        let value = DeckMeasurementValue.imperial(feet: 2, inches: 48, sixteenths: 0)
        let components = value.imperialComponents

        XCTAssertEqual(value.totalInches, 72, accuracy: 0.0001)
        XCTAssertEqual(components.feet, 6)
        XCTAssertEqual(components.inches, 0)
        XCTAssertEqual(components.sixteenths, 0)
    }

    func testMetricComponentsRoundTripThroughStandardValue() {
        let value = DeckMeasurementValue.metric(meters: 2, centimeters: 40, millimeters: 5)
        let components = value.metricComponents

        XCTAssertEqual(value.totalInches, 2405.0 / 25.4, accuracy: 0.0001)
        XCTAssertEqual(components.meters, 2)
        XCTAssertEqual(components.centimeters, 40)
        XCTAssertEqual(components.millimeters, 5)
    }

    func testLegacyPerimeterDraftAliasesStandardValue() {
        let value: PerimeterLengthDraft = .imperial(feet: 6, inches: 0, sixteenths: 0)

        XCTAssertEqual(value.totalInches, DeckMeasurementValue.imperial(feet: 6, inches: 0, sixteenths: 0).totalInches)
    }

    func testMeasurementWheelDataClampsSelectionIntoConfiguredRange() {
        XCTAssertEqual(DeckMeasurementWheelData.clampedValue(-4, in: 0...10), 0)
        XCTAssertEqual(DeckMeasurementWheelData.clampedValue(7, in: 0...10), 7)
        XCTAssertEqual(DeckMeasurementWheelData.clampedValue(22, in: 0...10), 10)
    }

    func testMeasurementWheelDataMapsRowsToRangeValues() {
        XCTAssertEqual(DeckMeasurementWheelData.row(for: 12, in: 10...15), 2)
        XCTAssertEqual(DeckMeasurementWheelData.row(for: 99, in: 10...15), 5)
        XCTAssertEqual(DeckMeasurementWheelData.value(forRow: 0, in: 10...15), 10)
        XCTAssertEqual(DeckMeasurementWheelData.value(forRow: 4, in: 10...15), 14)
        XCTAssertEqual(DeckMeasurementWheelData.value(forRow: 100, in: 10...15), 15)
    }

    func testDeckBuilderPickerTokensFitBottomTouchZone() {
        XCTAssertGreaterThanOrEqual(DeckMeasurementPickerTokens.wheelWidth, 72)
        XCTAssertGreaterThanOrEqual(DeckMeasurementPickerTokens.wheelHeight, 108)
        XCTAssertGreaterThanOrEqual(DeckMeasurementPickerTokens.systemToggleWidth, 150)
        XCTAssertLessThanOrEqual(DeckMeasurementPickerTokens.panelMaxWidth, 390)
        XCTAssertEqual(PerimeterSpeedDrawOverlayLayout.touchZoneHeightFraction, 0.4, accuracy: 0.0001)
    }
}
