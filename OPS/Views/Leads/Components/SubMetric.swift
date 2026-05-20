//
//  SubMetric.swift
//  OPS
//
//  Sub-metric cell used inside the LEADS hero widget. Renders as three columns
//  on a hairline meta-row beneath the forecast hero number:
//
//      LABEL              ← JetBrains Mono 9pt, 0.14em, semantic tone color
//      VALUE              ← Mohave Light 22pt, tabular-lining (always neutral)
//      HINT               ← JetBrains Mono 8.5pt, 0.10em, text-mute
//
//  Per ops-design-system "D · HERO + SUB" pattern. The semantic tone tints the
//  LABEL only — never the value — per OPS rule "color is meaning, never
//  decoration." The number stays neutral so the operator reads the count
//  without color bias.
//

import SwiftUI

struct SubMetric: View {
    let label: String
    let value: String
    var hint: String? = nil
    var tone: Tone = .neutral

    enum Tone {
        case neutral, rose, tan, olive, steel

        var labelColor: Color {
            switch self {
            case .neutral: return OPSStyle.Colors.text3
            case .rose:    return OPSStyle.Colors.roseTextM
            case .tan:     return OPSStyle.Colors.tanTextM
            case .olive:   return OPSStyle.Colors.oliveTextM
            case .steel:   return OPSStyle.Colors.opsAccent
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.custom("JetBrainsMono-Regular", size: 9))
                .fontWeight(.semibold)
                .kerning(1.4)
                .foregroundColor(tone.labelColor)
                .textCase(.uppercase)

            Text(value)
                .font(.custom("Mohave-Light", size: 22))
                .foregroundColor(OPSStyle.Colors.text)
                .monospacedDigit()

            if let hint {
                Text(hint)
                    .font(.custom("JetBrainsMono-Regular", size: 8.5))
                    .fontWeight(.medium)
                    .kerning(1.0)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .textCase(.uppercase)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("SubMetric / 3-up hero row") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack(spacing: 24) {
            // The canonical three-up arrangement
            HStack(spacing: 14) {
                SubMetric(label: "OVERDUE",   value: "04", hint: "NEEDS NOW",   tone: .rose)
                SubMetric(label: "DUE TODAY", value: "03", hint: "FOLLOW UP",   tone: .tan)
                SubMetric(label: "OPEN",      value: "17", hint: "03 WAITING",  tone: .neutral)
            }

            Rectangle().fill(OPSStyle.Colors.line).frame(height: 1)

            // All tone variants, single column
            VStack(spacing: 16) {
                SubMetric(label: "ROSE",    value: "04", hint: "ROSE TONE",   tone: .rose)
                SubMetric(label: "TAN",     value: "03", hint: "TAN TONE",    tone: .tan)
                SubMetric(label: "OLIVE",   value: "12", hint: "OLIVE TONE",  tone: .olive)
                SubMetric(label: "STEEL",   value: "07", hint: "STEEL TONE",  tone: .steel)
                SubMetric(label: "NEUTRAL", value: "00", hint: "NEUTRAL",     tone: .neutral)
                SubMetric(label: "NO HINT", value: "—")
            }
        }
        .padding(20)
    }
    .preferredColorScheme(.dark)
}
#endif
