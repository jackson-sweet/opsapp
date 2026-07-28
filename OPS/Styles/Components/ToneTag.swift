//
//  ToneTag.swift
//  OPS
//
//  The earth-tone micro tag — `StageTag` without the stage. Same metrics, same
//  mobile-lift (`-M`) token family, so a tone chip and a stage chip sitting in
//  the same row read as ONE component with two jobs: the stage chip says where
//  the lead is, the tone chip says how urgent it is.
//
//  Tones map to the semantic earth palette, never to accent — accent is
//  reserved for the single primary action on a screen:
//
//    .rose     overdue / missed         (XD LATE)
//    .tan      due now / attention      (TODAY)
//    .neutral  informational            (YOUR MOVE)
//
//  Contrast follows MOBILE.md §1 (outdoor glare): the `-M` variants only.
//

import SwiftUI

struct ToneTag: View {

    enum Tone {
        case rose
        case tan
        case neutral
    }

    let text: String
    var tone: Tone = .neutral

    init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            // Numbers inside a tag are still numbers — tabular, never jittering
            // between "3D LATE" and "11D LATE" as the sheet refreshes.
            .monospacedDigit()
            .font(OPSStyle.Typography.nanoLabel)
            .fontWeight(.semibold)
            .kerning(1.4)
            .foregroundColor(textColor)
            .textCase(.uppercase)
            // StageTag's established chip metrics — copied verbatim so the two
            // chips share a baseline and a cap height in the same row.
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private var fillColor: Color {
        switch tone {
        case .rose:    return OPSStyle.Colors.roseFillM
        case .tan:     return OPSStyle.Colors.tanFillM
        case .neutral: return OPSStyle.Colors.surfaceHover
        }
    }

    private var borderColor: Color {
        switch tone {
        case .rose:    return OPSStyle.Colors.roseLineM
        case .tan:     return OPSStyle.Colors.tanLineM
        case .neutral: return OPSStyle.Colors.line
        }
    }

    private var textColor: Color {
        switch tone {
        case .rose:    return OPSStyle.Colors.roseTextM
        case .tan:     return OPSStyle.Colors.tanTextM
        case .neutral: return OPSStyle.Colors.text2
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ToneTag / tones") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ToneTag("3D LATE", tone: .rose)
            ToneTag("TODAY", tone: .tan)
            ToneTag("YOUR MOVE", tone: .neutral)
        }
    }
    .preferredColorScheme(.dark)
}
#endif
