//
//  CompanyCreationLoadingView.swift
//  OPS
//
//  Tactical loading screen shown during company creation
//  Displays staged messages while API operations complete
//

import SwiftUI

struct CompanyCreationLoadingView: View {
    @Binding var isVisible: Bool
    @Binding var isApiComplete: Bool
    var onComplete: () -> Void

    @State private var currentPhase: LoadingPhase = .updatingCompany
    @State private var textOpacity: Double = 0
    @State private var containerOpacity: Double = 0
    @State private var isExiting: Bool = false
    @State private var minimumTimeElapsed: Bool = false
    @State private var hasReachedAssigningCode: Bool = false

    enum LoadingPhase {
        case updatingCompany
        case assigningCode
        case complete

        var message: String {
            switch self {
            case .updatingCompany:
                return "UPDATING COMPANY DATA"
            case .assigningCode:
                return "ASSIGNING CODE"
            case .complete:
                return ""
            }
        }
    }

    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Tactical loading animation
                TacticalLoadingBarAnimated(
                    barCount: 12,
                    barWidth: 3,
                    barHeight: 16,
                    spacing: 6,
                    emptyColor: OPSStyle.Colors.inputFieldBorder,
                    fillColor: OPSStyle.Colors.primaryAccent
                )

                // Status message
                Text(currentPhase.message)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(2)
                    .opacity(textOpacity)

                Spacer()
            }
        }
        .opacity(containerOpacity)
        .onAppear {
            startLoadingSequence()
        }
        .onChange(of: isApiComplete) { _, complete in
            if complete {
                checkIfReadyToComplete()
            }
        }
    }

    private func startLoadingSequence() {
        // Fade in container
        withAnimation(.easeIn(duration: 0.3)) {
            containerOpacity = 1.0
        }

        // Fade in first message
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.4)) {
                textOpacity = 1.0
            }
        }

        // After 2 seconds, transition to "assigning code"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            transitionToNextPhase()
        }

        // Minimum display time is 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            minimumTimeElapsed = true
            checkIfReadyToComplete()
        }
    }

    private func transitionToNextPhase() {
        // Fade out current text
        withAnimation(.easeOut(duration: 0.3)) {
            textOpacity = 0
        }

        // Change phase and fade in new text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            currentPhase = .assigningCode
            hasReachedAssigningCode = true

            withAnimation(.easeIn(duration: 0.4)) {
                textOpacity = 1.0
            }
        }
    }

    private func checkIfReadyToComplete() {
        // Only complete when BOTH minimum time has elapsed AND API is complete
        // AND we've shown "assigning code" for at least a moment
        guard minimumTimeElapsed && isApiComplete && hasReachedAssigningCode && !isExiting else {
            return
        }

        completeLoading()
    }

    private func completeLoading() {
        guard !isExiting else { return }
        isExiting = true

        // Navigate to next step FIRST (while overlay still visible)
        onComplete()

        // Then fade out the overlay to reveal the new screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.3)) {
                textOpacity = 0
                containerOpacity = 0
            }

            // Hide overlay after fade completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isVisible = false
            }
        }
    }
}

#Preview {
    CompanyCreationLoadingView(
        isVisible: .constant(true),
        isApiComplete: .constant(false),
        onComplete: {}
    )
}
