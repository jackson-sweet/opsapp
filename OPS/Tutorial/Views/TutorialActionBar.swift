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
                    .foregroundColor(isBackDisabled ? Color.white.opacity(0.2) : Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
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
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundColor(isContinueDisabled ? Color.white.opacity(0.25) : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isContinueDisabled ? Color.white.opacity(0.1) : Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isContinueDisabled ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
                )
            }
            .disabled(isContinueDisabled)

            // Skip button (right)
            Button(action: onSkip) {
                Text("SKIP")
                    .font(.custom("Mohave-Regular", size: 14))
                    .foregroundColor(Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .padding(.top, 12)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.95), Color.black.opacity(0.7), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea(.all, edges: .bottom)
        )
    }
}
