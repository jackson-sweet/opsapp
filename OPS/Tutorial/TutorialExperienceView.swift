import SwiftUI

/// Root view for the OPS "Lead to Revenue" tutorial.
struct TutorialExperienceView: View {

    let onComplete: () -> Void

    @StateObject private var state = TutorialStateManager()
    @State private var stepOpacity: Double = 1.0
    @State private var showContextLabel = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            // Current step
            currentStepView
                .opacity(stepOpacity)

            // Context label overlay — bottom area
            VStack {
                Spacer()
                if showContextLabel, let text = contextLabelText {
                    Text(text)
                        .font(.microLabel)
                        .foregroundStyle(OPSStyle.Colors.tertiaryText)
                        .tracking(1.5)
                        .transition(.opacity)
                        .padding(.bottom, 90)
                }
            }

            // Chrome: progress + skip
            VStack {
                chrome
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear { state.start() }
        .onChange(of: state.isActive) { _, active in
            if !active { onComplete() }
        }
        .onChange(of: state.currentPhase) { _, _ in
            // Show context label after a short delay on each step
            showContextLabel = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(OPSStyle.Animation.standard) {
                    showContextLabel = true
                }
            }
        }
    }

    // MARK: - Context Labels

    private var contextLabelText: String? {
        switch state.currentPhase {
        case .leadArrives:     return "TAP TO ACCEPT LEAD"
        case .crewExecutes:    return "YOUR CREW UPDATES STATUS IN REAL TIME"
        default:               return nil
        }
    }

    // MARK: - Chrome

    private var chrome: some View {
        HStack {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(0..<TutorialPhase.totalSteps, id: \.self) { i in
                    Circle()
                        .fill(dotColor(for: i))
                        .frame(width: 6, height: 6)
                }
            }
            .animation(OPSStyle.Animation.fast, value: state.currentPhase)

            Spacer()

            if state.currentPhase != .invoiceAndPay {
                Button {
                    state.skip()
                } label: {
                    Text("SKIP")
                        .font(.caption)
                        .tracking(1)
                        .foregroundStyle(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    private func dotColor(for index: Int) -> Color {
        let current = state.currentPhase.rawValue
        if index == current {
            return OPSStyle.Colors.text
        } else if index < current {
            return Color.white.opacity(0.4)
        } else {
            return Color.white.opacity(0.12)
        }
    }

    // MARK: - Step Router

    @ViewBuilder
    private var currentStepView: some View {
        switch state.currentPhase {
        case .leadArrives:
            LeadArrivesStep(onComplete: advance)

        case .sendEstimate:
            SendEstimateStep(onComplete: advance)

        case .estimateApproved:
            EstimateApprovedStep(onComplete: advance)

        case .crewExecutes:
            CrewExecutesStep(onComplete: advance)

        case .weeklyReview:
            WeeklyReviewStep(
                onComplete: advance,
                onSwipe: { index, dir in state.recordSwipe(cardIndex: index, direction: dir) }
            )

        case .invoiceAndPay:
            InvoiceAndPayStep(
                onGetStarted: {
                    state.ctaTapped(action: "getStarted")
                    onComplete()
                },
                onSkip: {
                    state.ctaTapped(action: "skip")
                    onComplete()
                }
            )
        }
    }

    // MARK: - Transition

    private func advance() {
        showContextLabel = false

        withAnimation(OPSStyle.Animation.hover) {
            stepOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            state.advancePhase()
            withAnimation(OPSStyle.Animation.panel) {
                stepOpacity = 1.0
            }
        }
    }
}
