import SwiftUI

/// Step 6: "Invoice & Get Paid"
///
/// Emotional beat: ACHIEVEMENT → COMMITMENT
/// Before: Satisfied. After: "I need this."
///
/// Project card transforms into invoice. User taps to send.
/// Payment arrives. "PAID" stamp. Final text sequence. CTA.
struct InvoiceAndPayStep: View {

    let onGetStarted: () -> Void
    let onSkip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: StepPhase = .projectCard
    @State private var showItems = false
    @State private var showSendButton = false
    @State private var showPaid = false
    @State private var visibleWords: Int = 0
    @State private var showCTA = false

    private enum StepPhase {
        case projectCard
        case invoice
        case sent
        case paid
        case finalScreen
    }

    private let closingWords = ["LEAD.", "ESTIMATE.", "PROJECT.", "INVOICE.", "REVENUE.", "NO PAPERWORK."]

    var body: some View {
        ZStack {
            switch phase {
            case .projectCard:
                projectCardView
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .transition(.opacity)

            case .invoice, .sent:
                invoiceView
                    .padding(.horizontal, OPSStyle.Layout.spacing4)

            case .paid:
                ZStack {
                    invoiceView
                        .padding(.horizontal, OPSStyle.Layout.spacing4)

                    // PAID stamp
                    Text("PAID")
                        .font(.displayLarge)
                        .foregroundStyle(OPSStyle.Colors.successStatus)
                        .tracking(4)
                        .rotationEffect(.degrees(-12))
                        .opacity(showPaid ? 0.85 : 0)
                        .scaleEffect(showPaid ? 1.0 : 0.8)
                }

            case .finalScreen:
                finalScreenView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startSequence() }
    }

    // MARK: - Project Card

    private var projectCardView: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("COMPLETE")
                .font(.status)
                .foregroundStyle(OPSStyle.Colors.successStatus)
                .tracking(1.5)

            Text(TutorialData.projectTitle.uppercased())
                .font(.headingLarge)
                .foregroundStyle(OPSStyle.Colors.primaryText)
                .tracking(0.8)

            Text(TutorialData.clientName)
                .font(.caption)
                .foregroundStyle(OPSStyle.Colors.secondaryText)
        }
        .padding(OPSStyle.Layout.spacing3_5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.successStatus.opacity(0.25), lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Invoice Card

    private var invoiceView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INVOICE")
                        .font(.status)
                        .foregroundStyle(OPSStyle.Colors.primaryAccent)
                        .tracking(1.5)
                    Text(TutorialData.projectTitle.uppercased())
                        .font(.heading)
                        .foregroundStyle(OPSStyle.Colors.primaryText)
                        .tracking(0.5)
                }
                Spacer()
                Text(TutorialData.invoiceNumber)
                    .font(.smallCaption)
                    .foregroundStyle(OPSStyle.Colors.tertiaryText)
            }
            .padding(.bottom, OPSStyle.Layout.spacing2_5)

            // Line items
            if showItems {
                VStack(spacing: 0) {
                    ForEach(TutorialData.lineItems) { item in
                        HStack {
                            Text(item.name)
                                .font(.body)
                                .foregroundStyle(OPSStyle.Colors.primaryText)
                            Spacer()
                            Text(TutorialData.formatCurrency(item.amount))
                                .font(.bodyBold)
                                .foregroundStyle(OPSStyle.Colors.primaryText)
                        }
                        .padding(.vertical, 6)
                    }

                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: 1)
                        .padding(.vertical, OPSStyle.Layout.spacing2)

                    HStack {
                        Text("TOTAL")
                            .font(.status)
                            .foregroundStyle(OPSStyle.Colors.secondaryText)
                            .tracking(1.5)
                        Spacer()
                        Text(TutorialData.formatCurrency(TutorialData.estimateTotal))
                            .font(.headingLarge)
                            .foregroundStyle(OPSStyle.Colors.primaryText)
                    }
                }
            }

            // Send button
            if showSendButton && phase == .invoice {
                Button(action: handleSend) {
                    Text("SEND INVOICE")
                        .font(.button)
                        .tracking(1)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .fill(OPSStyle.Colors.primaryAccent)
                        )
                }
                .padding(.top, OPSStyle.Layout.spacing3)
            }
        }
        .padding(OPSStyle.Layout.spacing3_5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Final Screen

    private var finalScreenView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                ForEach(Array(closingWords.prefix(visibleWords).enumerated()), id: \.offset) { index, word in
                    let isRevenue = word == "REVENUE."
                    let isNoPaperwork = word == "NO PAPERWORK."

                    Text(word)
                        .font(isRevenue ? .headingLarge : .heading)
                        .foregroundStyle(
                            isNoPaperwork ? OPSStyle.Colors.primaryAccent :
                            isRevenue ? OPSStyle.Colors.primaryText :
                            OPSStyle.Colors.secondaryText
                        )
                        .tracking(isNoPaperwork ? 3 : 2)
                }
            }

            Spacer()

            // CTA
            if showCTA {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    Button(action: onGetStarted) {
                        Text("GET STARTED")
                            .font(.button)
                            .tracking(1)
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .fill(OPSStyle.Colors.primaryAccent)
                            )
                    }

                    Button(action: onSkip) {
                        Text("SKIP")
                            .font(.caption)
                            .foregroundStyle(OPSStyle.Colors.tertiaryText)
                            .tracking(1)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing4)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Sequences

    private func startSequence() {
        guard !reduceMotion else {
            phase = .finalScreen
            visibleWords = closingWords.count
            showCTA = true
            return
        }

        // 1.0s — Transform to invoice
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                phase = .invoice
            }
        }

        // 1.4s — Show line items
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.25)) {
                showItems = true
            }
        }

        // 1.8s — Show send button
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.2)) {
                showSendButton = true
            }
        }
    }

    private func handleSend() {
        TutorialHaptics.commit()

        withAnimation(.easeOut(duration: 0.2)) {
            phase = .sent
            showSendButton = false
        }

        // 0.8s — Payment arrives, PAID stamp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.2)) {
                phase = .paid
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.25)) {
                    showPaid = true
                }
                TutorialHaptics.milestone()
            }
        }

        // 2.2s — Transition to final screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                phase = .finalScreen
            }
            startClosingSequence()
        }
    }

    private func startClosingSequence() {
        // Stagger words — 0.45s apart
        for i in 0..<closingWords.count {
            let isLast = i == closingWords.count - 1
            let delay = Double(i) * 0.45 + (isLast ? 0.3 : 0) // Extra beat before "NO PAPERWORK."

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.2)) {
                    visibleWords = i + 1
                }
                TutorialHaptics.arrival()
            }
        }

        // CTA
        let ctaDelay = Double(closingWords.count) * 0.45 + 0.6
        DispatchQueue.main.asyncAfter(deadline: .now() + ctaDelay) {
            withAnimation(.easeOut(duration: 0.3)) {
                showCTA = true
            }
        }
    }
}
