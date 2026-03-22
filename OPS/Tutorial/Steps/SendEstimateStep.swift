import SwiftUI

/// Step 2: "Send the Estimate"
///
/// Emotional beat: DISCOVERY
/// Before: Curious. After: "This is fast."
///
/// The estimate card assembles itself — header, line items staggering in,
/// total rolling up, send button appearing. User taps to send.
/// The card dispatches to the right.
struct SendEstimateStep: View {

    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var showHeader = false
    @State private var visibleItems: Int = 0
    @State private var showDivider = false
    @State private var showTotal = false
    @State private var showButton = false
    @State private var sent = false
    @State private var exitProgress: CGFloat = 0
    @State private var buildTimer: Timer?

    var body: some View {
        ZStack {
            if !sent {
                estimateCard
                    .scaleEffect(showHeader ? 1.0 : 0.96)
                    .opacity(showHeader ? 1.0 : 0)
                    .padding(.horizontal, 24)
            } else {
                estimateCard
                    .offset(x: exitProgress * 420)
                    .opacity(1 - exitProgress)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startBuild() }
        .onDisappear { buildTimer?.invalidate() }
    }

    // MARK: - Card

    private var estimateCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("ESTIMATE")
                    .font(.status)
                    .foregroundStyle(OPSStyle.Colors.primaryAccent)
                    .tracking(1.5)

                Text(TutorialData.projectTitle.uppercased())
                    .font(.headingLarge)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .tracking(0.8)

                Text(TutorialData.clientName)
                    .font(.caption)
                    .foregroundStyle(OPSStyle.Colors.secondaryText)
            }
            .opacity(showHeader ? 1 : 0)
            .padding(.bottom, 16)

            // Line items — stagger in
            VStack(spacing: 0) {
                ForEach(Array(TutorialData.lineItems.enumerated()), id: \.element.id) { index, item in
                    if index < visibleItems {
                        lineItemRow(item)
                            .transition(.opacity.combined(with: .move(edge: .leading)))

                        if index < TutorialData.lineItems.count - 1 && index < visibleItems - 1 {
                            Rectangle()
                                .fill(OPSStyle.Colors.separator)
                                .frame(height: 0.5)
                                .padding(.leading, 15)
                        }
                    }
                }
            }

            // Divider
            if showDivider {
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorder)
                    .frame(height: 1)
                    .padding(.vertical, 12)
            }

            // Total
            if showTotal {
                HStack {
                    Text("TOTAL")
                        .font(.status)
                        .foregroundStyle(OPSStyle.Colors.secondaryText)
                        .tracking(1.5)
                    Spacer()
                    Text(TutorialData.formatCurrency(TutorialData.estimateTotal))
                        .font(.displayLarge)
                        .foregroundStyle(OPSStyle.Colors.primaryText)
                }
            }

            // Send button
            if showButton {
                Button(action: handleSend) {
                    Text("SEND ESTIMATE")
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
                .padding(.top, 16)
            }
        }
        .padding(20)
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

    // MARK: - Line Item

    private func lineItemRow(_ item: TutorialData.LineItem) -> some View {
        HStack(spacing: 10) {
            // Color stripe
            RoundedRectangle(cornerRadius: 1)
                .fill(item.type.color)
                .frame(width: 3, height: 28)

            // Type badge
            Text(item.type.rawValue)
                .font(.microLabel)
                .foregroundStyle(item.type.color)
                .tracking(0.8)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                        .fill(item.type.color.opacity(0.12))
                )

            // Name
            Text(item.name)
                .font(.body)
                .foregroundStyle(OPSStyle.Colors.primaryText)
                .lineLimit(1)

            Spacer()

            // Amount
            Text(TutorialData.formatCurrency(item.amount))
                .font(.bodyBold)
                .foregroundStyle(OPSStyle.Colors.primaryText)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Build Sequence

    private func startBuild() {
        guard !reduceMotion else {
            showHeader = true
            visibleItems = TutorialData.lineItems.count
            showDivider = true; showTotal = true; showButton = true
            return
        }

        // Card fades in with header
        withAnimation(.easeOut(duration: 0.3)) {
            showHeader = true
        }

        // Stagger line items — 120ms apart
        let itemDelay = 0.4
        for i in 0..<TutorialData.lineItems.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + itemDelay + (Double(i) * 0.12)) {
                withAnimation(.easeOut(duration: 0.2)) {
                    visibleItems = i + 1
                }
                TutorialHaptics.arrival()
            }
        }

        // Divider + Total
        let afterItems = itemDelay + (Double(TutorialData.lineItems.count) * 0.12) + 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + afterItems) {
            withAnimation(.easeOut(duration: 0.2)) {
                showDivider = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + afterItems + 0.15) {
            withAnimation(.easeOut(duration: 0.2)) {
                showTotal = true
            }
        }

        // Button
        DispatchQueue.main.asyncAfter(deadline: .now() + afterItems + 0.4) {
            withAnimation(.easeOut(duration: 0.2)) {
                showButton = true
            }
        }
    }

    // MARK: - Send

    private func handleSend() {
        TutorialHaptics.commit()
        sent = true

        withAnimation(.easeIn(duration: 0.25)) {
            exitProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onComplete()
        }
    }
}
