// OPS/OPS/DeckBuilder/Views/VoiceWaveformView.swift

import SwiftUI

/// Animated audio waveform bars that pulse when listening.
struct VoiceWaveformView: View {
    var isListening: Bool

    private let barCount = 24
    @State private var animationPhase: CGFloat = 0
    @State private var timer: Timer?

    var body: some View {
        Canvas { context, size in
            let barWidth: CGFloat = 2
            let totalBarSpace = CGFloat(barCount) * barWidth
            let gap: CGFloat = barCount > 1 ? (size.width - totalBarSpace) / CGFloat(barCount - 1) : 0
            let midY = size.height / 2
            let maxAmp = size.height * 0.45

            for i in 0..<barCount {
                let x = CGFloat(i) * (barWidth + gap)
                let amplitude: CGFloat
                if isListening {
                    let phase = Double(i) * 0.4 + Double(animationPhase)
                    let wave1 = sin(phase * 3.5) * 0.6
                    let wave2 = sin(phase * 5.2 + 1.3) * 0.4
                    amplitude = maxAmp * CGFloat(abs(wave1 + wave2))
                } else {
                    amplitude = 2
                }

                let h = max(amplitude, 2)
                let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(Color.white.opacity(isListening ? 0.7 : 0.15))
                )
            }
        }
        .onChange(of: isListening) { listening in
            if listening {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        .onAppear {
            if isListening { startAnimation() }
        }
        .onDisappear { stopAnimation() }
    }

    private func startAnimation() {
        stopAnimation()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            animationPhase += 0.05
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}
