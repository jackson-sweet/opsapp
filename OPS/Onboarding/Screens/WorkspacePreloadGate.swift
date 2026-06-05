//
//  WorkspacePreloadGate.swift
//  OPS
//
//  Full-screen preload gate shown to RETURNING-login users while their
//  initial data load/sync completes. Without it, a returning user is dropped
//  straight into the app while projects, photos, and comments stream in behind
//  spinners — a slow, clunky first impression (bug 95bf7c82).
//
//  This gate mirrors the onboarding-only AppSetupScreen visual pattern (OPS
//  logo + thin sweeping accent bar + tactical status copy) so the two entry
//  paths feel like one product. Unlike AppSetupScreen, this view performs NO
//  sync of its own — it is purely presentational. The parent (ContentView)
//  drives dismissal off the existing DataController / AppState sync-state
//  signals and reveals MainTabView once the load is done.
//
//  Escape hatch: after a fixed wait the gate surfaces an "ENTER ANYWAY"
//  affordance so a slow sync can never trap the user behind the gate.
//

import SwiftUI

struct WorkspacePreloadGate: View {
    /// Honor Reduce Motion — swap the ambient sweep + staged fades for a flat,
    /// instant presentation. The emotional beat (calm, confident "we've got
    /// this") is preserved; only the motion is removed.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fired when the user taps the escape-hatch button. The parent dismisses
    /// the gate and reveals the app immediately.
    var onEnterAnyway: () -> Void

    /// Seconds the user waits before the escape hatch appears. The gate now
    /// arms at the START of the initial sync (covering its full duration), so a
    /// healthy ~15s sync reveals the app on its own well before this fires —
    /// keeping the hatch out of the normal path. It only surfaces for a genuinely
    /// stalled sync, and stays comfortably under the 30s ContentView watchdog.
    private static let escapeHatchDelay: TimeInterval = 20.0

    /// Fixed footprint reserved for the escape hatch (button height + gap +
    /// caption) so the content above doesn't shift when the button appears.
    private var escapeHatchReservedHeight: CGFloat {
        CGFloat(OPSStyle.Layout.touchTargetStandard) + 28
    }

    // Staged fade-in state (mirrors AppSetupScreen's entrance choreography).
    @State private var logoOpacity: Double = 0
    @State private var loadingOpacity: Double = 0
    @State private var messageOpacity: Double = 0

    // Escape-hatch reveal.
    @State private var showEnterAnyway = false
    @State private var escapeHatchTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // OPS mark — same asset and sizing as AppSetupScreen.
                Image("LogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .opacity(logoOpacity)

                Spacer()
                    .frame(height: 48)

                // Ambient in-progress indicator — a thin accent segment that
                // sweeps the track. Reduce Motion gets a static hairline instead.
                WorkspaceSweepBar(reduceMotion: reduceMotion)
                    .opacity(loadingOpacity)

                Spacer()
                    .frame(height: 24)

                // Status copy — UPPERCASE authority headline matches the
                // onboarding gate verbatim so both login paths read identically.
                VStack(spacing: 10) {
                    Text("SETTING UP YOUR WORKSPACE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .tracking(2)
                        .multilineTextAlignment(.center)

                    Text("Loading your jobs, photos, and crew")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .multilineTextAlignment(.center)
                }
                .opacity(messageOpacity)

                Spacer()

                // Escape hatch — only after the delay, only if still gated.
                VStack(spacing: 8) {
                    if showEnterAnyway {
                        Button(action: handleEnterAnyway) {
                            Text("ENTER ANYWAY")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .tracking(2)
                                .frame(maxWidth: .infinity)
                                .frame(height: OPSStyle.Layout.touchTargetStandard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.cardBorderSubtle, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                        }
                        .padding(.horizontal, 48)

                        Text("The rest will finish in the background")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                // Reserve the escape-hatch footprint so the layout above doesn't
                // jump when the button appears. Height ≈ button + gap + caption.
                .frame(height: escapeHatchReservedHeight)
                .padding(.bottom, 24)
            }
        }
        .onAppear(perform: startSequence)
        .onDisappear {
            escapeHatchTask?.cancel()
            escapeHatchTask = nil
        }
    }

    // MARK: - Entrance + Escape-Hatch Timing

    private func startSequence() {
        if reduceMotion {
            // Instant, no staged fades — present everything at once.
            logoOpacity = 1
            loadingOpacity = 1
            messageOpacity = 1
        } else {
            // Staged fade-in on the single OPS curve. Mirrors AppSetupScreen so
            // the returning-login arrival feels identical to the onboarding one.
            withAnimation(OPSStyle.Animation.standard) {
                logoOpacity = 1
            }
            withAnimation(OPSStyle.Animation.standard.delay(0.4)) {
                loadingOpacity = 1
            }
            withAnimation(OPSStyle.Animation.standard.delay(0.6)) {
                messageOpacity = 1
            }
        }

        // Arm the escape hatch. Structured Task (not a timer) so it cancels
        // cleanly when the gate is dismissed mid-wait.
        escapeHatchTask?.cancel()
        escapeHatchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.escapeHatchDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if reduceMotion {
                showEnterAnyway = true
            } else {
                withAnimation(OPSStyle.Animation.standard) {
                    showEnterAnyway = true
                }
            }
        }
    }

    private func handleEnterAnyway() {
        escapeHatchTask?.cancel()
        escapeHatchTask = nil
        onEnterAnyway()
    }
}

// MARK: - Sweep Bar

/// A thin horizontal bar with a glowing accent segment that sweeps
/// left-to-right. Matches AppSetupScreen.SyncSweepBar (monochrome track, accent
/// segment, ultra-thin line, single OPS easing). Under Reduce Motion the sweep
/// is replaced by a static centered accent segment — no looping animation.
private struct WorkspaceSweepBar: View {
    let reduceMotion: Bool

    @State private var sweepPhase: CGFloat = 0

    private let trackWidth: CGFloat = 120
    private let trackHeight: CGFloat = 2

    var body: some View {
        ZStack(alignment: .leading) {
            // Base track — barely-there hairline.
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.08))
                .frame(width: trackWidth, height: trackHeight)

            // Accent segment.
            RoundedRectangle(cornerRadius: 1)
                .fill(OPSStyle.Colors.primaryAccent)
                .frame(width: trackWidth * 0.3, height: trackHeight)
                .offset(x: reduceMotion
                        ? trackWidth * 0.35           // static, centered
                        : sweepPhase * trackWidth * 0.7)
        }
        .frame(width: trackWidth, height: trackHeight)
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .onAppear {
            guard !reduceMotion else { return }
            // Continuous ambient sweep on the OPS curve. Autoreverses so the
            // segment glides back without a hard jump.
            withAnimation(
                .timingCurve(0.22, 1, 0.36, 1, duration: 1.4)
                .repeatForever(autoreverses: true)
            ) {
                sweepPhase = 1.0
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WorkspacePreloadGate(onEnterAnyway: {})
        .preferredColorScheme(.dark)
}
