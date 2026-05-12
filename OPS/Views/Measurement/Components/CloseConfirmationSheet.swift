//
//  CloseConfirmationSheet.swift
//  OPS
//
//  Bottom sheet shown when the user taps × close on `DimensionedAnnotationView`
//  with unsaved measurements (spec §5.2 close confirmation policy):
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
    public var onDiscard: () -> Void
    public var onKeepEditing: () -> Void

    public init(measurementCount: Int,
                onDiscard: @escaping () -> Void,
                onKeepEditing: @escaping () -> Void) {
        self.measurementCount = measurementCount
        self.onDiscard = onDiscard
        self.onKeepEditing = onKeepEditing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("// DISCARD MEASUREMENTS?")
                .font(.custom("CakeMono-Light", size: 14))
                .tracking(1)
                .foregroundColor(OPSStyle.Colors.text)

            Text(bodyCopy)
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

    private var bodyCopy: String {
        let unit = measurementCount == 1 ? "MEASUREMENT" : "MEASUREMENTS"
        return "\(measurementCount) \(unit) HAVE NOT BEEN SAVED. THIS CANNOT BE UNDONE."
    }
}
