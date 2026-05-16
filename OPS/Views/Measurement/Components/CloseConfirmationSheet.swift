//
//  CloseConfirmationSheet.swift
//  OPS
//
//  Bottom sheet shown when the user taps × close on `DimensionedAnnotationView`
//  with unsaved measurements or calibration changes (spec §5.2 close
//  confirmation policy):
//
//      // DISCARD MEASUREMENTS?
//      [ DISCARD ]   [ KEEP EDITING ]
//
//  DISCARD is destructive (rose). KEEP EDITING is the default. Tapping
//  outside the sheet equates to KEEP EDITING.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §5.2
//

import SwiftUI
import UIKit

public struct CloseConfirmationSheet: View {

    public let measurementCount: Int
    public let includesCalibrationChange: Bool
    public var onDiscard: () -> Void
    public var onKeepEditing: () -> Void

    public init(measurementCount: Int,
                includesCalibrationChange: Bool = false,
                onDiscard: @escaping () -> Void,
                onKeepEditing: @escaping () -> Void) {
        self.measurementCount = measurementCount
        self.includesCalibrationChange = includesCalibrationChange
        self.onDiscard = onDiscard
        self.onKeepEditing = onKeepEditing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(CloseConfirmationSheetCopy.title(
                measurementCount: measurementCount,
                includesCalibrationChange: includesCalibrationChange
            ))
                .font(.custom("CakeMono-Light", size: 14))
                .tracking(1)
                .foregroundColor(OPSStyle.Colors.text)

            Text(CloseConfirmationSheetCopy.body(
                measurementCount: measurementCount,
                includesCalibrationChange: includesCalibrationChange
            ))
                .font(.custom("JetBrainsMono-Regular", size: 12))
                .foregroundColor(OPSStyle.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    onDiscard()
                } label: {
                    Text("DISCARD")
                        .font(.custom("CakeMono-Light", size: 14))
                        .tracking(1)
                        .foregroundColor(OPSStyle.Colors.rose)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(OPSStyle.Colors.rose.opacity(0.5), lineWidth: 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(OPSStyle.Colors.roseSoft)
                                )
                        )
                }
                .accessibilityIdentifier("close.discard")

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onKeepEditing()
                } label: {
                    Text("KEEP EDITING")
                        .font(.custom("CakeMono-Light", size: 14))
                        .tracking(1)
                        .foregroundColor(OPSStyle.Colors.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(OPSStyle.Colors.surfaceActive)
                        )
                }
                .accessibilityIdentifier("close.keepEditing")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }
}

enum CloseConfirmationSheetCopy {
    static func title(
        measurementCount: Int,
        includesCalibrationChange: Bool
    ) -> String {
        if measurementCount == 0 && includesCalibrationChange {
            return "// DISCARD CALIBRATION?"
        }
        if includesCalibrationChange {
            return "// DISCARD CHANGES?"
        }
        return "// DISCARD MEASUREMENTS?"
    }

    static func body(
        measurementCount: Int,
        includesCalibrationChange: Bool
    ) -> String {
        if measurementCount == 0 && includesCalibrationChange {
            return "CALIBRATION CHANGE HAS NOT BEEN SAVED. THIS CANNOT BE UNDONE."
        }
        let unit = measurementCount == 1 ? "MEASUREMENT" : "MEASUREMENTS"
        if includesCalibrationChange {
            return "\(measurementCount) \(unit) AND CALIBRATION HAVE NOT BEEN SAVED. THIS CANNOT BE UNDONE."
        }
        return "\(measurementCount) \(unit) HAVE NOT BEEN SAVED. THIS CANNOT BE UNDONE."
    }
}
