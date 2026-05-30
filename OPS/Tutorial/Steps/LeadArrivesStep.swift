import SwiftUI
import UIKit

/// Step 1: "The Lead Arrives"
///
/// Emotional beat: ENTRY/ARRIVAL
/// Before: Skeptical, blank. After: "This is precise."
///
/// Sequence:
/// 1. Dark canvas. 0.6s of stillness.
/// 2. Card drops in from top — sharp ease-out, lands with purpose.
/// 3. "NEW LEAD" badge visible on arrival.
/// 4. Client name types in character by character.
/// 5. Project title types in.
/// 6. Source badge fades in. Border glow develops.
/// 7. User taps → card exits right → advance.
///
/// Framework: SwiftUI Tier 1 (state-driven + typewriter timer)
/// Haptic: arrival() on card landing, commit() on tap
struct LeadArrivesStep: View {

    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Animation State

    /// Controls the card entry and glow sequence
    @State private var phase: StepPhase = .waiting

    /// Typewriter character counts
    @State private var clientChars: Int = 0
    @State private var projectChars: Int = 0
    @State private var showSource = false

    /// Card can be tapped after typewriter finishes
    @State private var interactive = false

    /// Exit animation
    @State private var exitProgress: CGFloat = 0

    // MARK: - Constants

    private let clientText: String = TutorialData.clientName.uppercased()
    private let projectText: String = TutorialData.projectTitle
    /// 35ms per character — fast enough to feel mechanical, slow enough to read
    private let charInterval: TimeInterval = 0.035
    /// Typewriter timer
    @State private var typewriterTimer: Timer?

    private enum StepPhase {
        case waiting     // Dark canvas
        case entering    // Card dropping in
        case settled     // Card landed, typewriter running
        case glowing     // Border glow active, interactive
        case exiting     // User tapped, card leaving
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if phase != .exiting {
                cardView
                    .offset(y: phase == .waiting ? -280 : 0)
                    .opacity(phase == .waiting ? 0 : 1)
                    .padding(.horizontal, 24)
            } else {
                cardView
                    .offset(x: exitProgress * 420)
                    .opacity(1 - exitProgress)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if interactive { handleTap() } }
        .onAppear { startSequence() }
        .onDisappear { typewriterTimer?.invalidate() }
    }

    // MARK: - Card

    private var cardView: some View {
        let glowAmount = (phase == .glowing || phase == .exiting) ? 1.0 : 0.0

        return VStack(alignment: .leading, spacing: 0) {
            // Reserve full height with invisible layout
            ZStack(alignment: .topLeading) {
                // Invisible spacer — full card content at final size
                VStack(alignment: .leading, spacing: 12) {
                    badgeRow
                    Text(clientText).font(.headingLarge).tracking(0.8)
                    Text(projectText).font(.body)
                    sourceRow.padding(.top, 4)
                }
                .opacity(0)

                // Visible content — types in over the reserved space
                VStack(alignment: .leading, spacing: 12) {
                    // Badge — always visible once card enters
                    badgeRow
                        .opacity(phase != .waiting ? 1 : 0)

                    // Client name — typewriter
                    Text(clientChars > 0 ? String(clientText.prefix(clientChars)) : " ")
                        .font(.headingLarge)
                        .foregroundStyle(OPSStyle.Colors.primaryText)
                        .tracking(0.8)
                        .opacity(clientChars > 0 ? 1 : 0)

                    // Project title — typewriter
                    Text(projectChars > 0 ? String(projectText.prefix(projectChars)) : " ")
                        .font(.body)
                        .foregroundStyle(OPSStyle.Colors.secondaryText)
                        .opacity(projectChars > 0 ? 1 : 0)

                    // Source badge — fades in after typewriter
                    sourceRow
                        .padding(.top, 4)
                        .opacity(showSource ? 1 : 0)
                }
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
                .stroke(
                    OPSStyle.Colors.primaryAccent.opacity(glowAmount * 0.3),
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New lead: \(TutorialData.clientName), \(TutorialData.projectTitle). Tap to accept.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Subviews

    private var badgeRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(OPSStyle.Colors.warningStatus)
                .frame(width: 6, height: 6)
            Text("NEW LEAD")
                .font(.status)
                .foregroundStyle(OPSStyle.Colors.warningStatus)
                .tracking(1.5)
        }
    }

    private var sourceRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 11))
            Text("GMAIL")
                .font(.microLabel)
                .tracking(1.2)
        }
        .foregroundStyle(OPSStyle.Colors.primaryAccent)
    }

    // MARK: - Sequence

    private func startSequence() {
        TutorialHaptics.prepare()

        guard !reduceMotion else {
            // Reduced motion: show everything immediately, fade in
            phase = .glowing
            clientChars = clientText.count
            projectChars = projectText.count
            showSource = true
            interactive = true
            return
        }

        // 0.0s — Dark. Waiting.

        // 0.6s — Card drops in. Sharp ease-out. Lands and stops.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(OPSStyle.Animation.fast) {
                // dampingFraction not needed — ease-out lands without bounce
                phase = .entering
            }

            // Haptic at landing (0.35s after animation start)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                TutorialHaptics.arrival()
                phase = .settled
                startTypewriter()
            }
        }
    }

    private func startTypewriter() {
        var totalChars = 0
        let allChars = clientText.count + projectText.count

        typewriterTimer = Timer.scheduledTimer(withTimeInterval: charInterval, repeats: true) { timer in
            totalChars += 1

            if totalChars <= clientText.count {
                clientChars = totalChars
            } else {
                let projectIndex = totalChars - clientText.count
                if projectIndex <= projectText.count {
                    // Small gap between client and project
                    if projectIndex == 1 {
                        // Brief pause between the two lines
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            projectChars = 1
                        }
                        return
                    }
                    projectChars = projectIndex
                }
            }

            if totalChars >= allChars {
                timer.invalidate()
                finishTypewriter()
            }
        }
    }

    private func finishTypewriter() {
        // Source badge fades in
        withAnimation(OPSStyle.Animation.fast) {
            showSource = true
        }

        // Border glow develops — slow, atmospheric
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(OPSStyle.Animation.smooth) {
                phase = .glowing
            }
            interactive = true
        }
    }

    // MARK: - Tap

    private func handleTap() {
        guard interactive, phase == .glowing else { return }
        interactive = false
        TutorialHaptics.commit()

        phase = .exiting

        // Card exits right — decisive, 250ms
        withAnimation(OPSStyle.Animation.smooth) {
            exitProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onComplete()
        }
    }
}
