//
//  TutorialActionBar.swift
//  OPS
//
//  Bottom action bar for the tutorial.
//  Always shows: Back (left) | Continue (center) | Skip (right)
//  Continue is disabled during action phases, enabled during continue phases.
//

import SwiftUI

struct TutorialActionBar: View {
    let isActionPhase: Bool
    let continueLabel: String
    let phaseIndex: Int
    let onBack: () -> Void
    let onContinue: () -> Void
    let onSkip: () -> Void

    private var isBackDisabled: Bool {
        phaseIndex <= 0
    }

    private var isContinueDisabled: Bool {
        isActionPhase
    }

    var body: some View {
        HStack(spacing: 10) {
            // Back button (left)
            Button(action: onBack) {
                Text("BACK")
                    .font(.custom("Mohave-Regular", size: 14))
                    .foregroundColor(isBackDisabled ? OPSStyle.Colors.inputFieldBorder : OPSStyle.Colors.primaryText.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(OPSStyle.Colors.cardBorder)
                    .cornerRadius(OPSStyle.Layout.largeCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .disabled(isBackDisabled)

            // Continue button (center)
            Button(action: {
                TutorialHaptics.lightTap()
                onContinue()
            }) {
                HStack(spacing: 6) {
                    Text(continueLabel)
                        .font(.custom("Mohave-Medium", size: 14))
                    if !isContinueDisabled {
                        Image(systemName: "arrow.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                    }
                }
                .foregroundColor(isContinueDisabled ? OPSStyle.Colors.primaryText.opacity(0.25) : OPSStyle.Colors.invertedText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isContinueDisabled ? OPSStyle.Colors.cardBorder : Color.white)
                .cornerRadius(OPSStyle.Layout.largeCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                        .stroke(isContinueDisabled ? OPSStyle.Colors.inputFieldBorder : Color.clear, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
            .disabled(isContinueDisabled)

            // Skip button (right)
            Button(action: onSkip) {
                Text("SKIP")
                    .font(.custom("Mohave-Regular", size: 14))
                    .foregroundColor(OPSStyle.Colors.primaryText.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(OPSStyle.Colors.cardBorder)
                    .cornerRadius(OPSStyle.Layout.largeCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .padding(.top, 12)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.95), OPSStyle.Colors.overlayStrong, Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea(.all, edges: .bottom)
        )
    }
}
