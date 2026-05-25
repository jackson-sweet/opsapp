//
//  Atmosphere.swift
//  OPS
//
//  Single soft radial-gradient glow per screen — the only "lit from above"
//  atmospheric cue on the pure-black canvas. Per ops-design-system
//  mobile/MOBILE.md § 3 (L0 — Canvas):
//
//      "Optional: one subtle radial glow per screen for atmosphere.
//       Positioned in top-right or bottom-left corner.
//       Maximum ONE glow. Never two of the same hue."
//
//  Position is fixed at 88% / 4% from top-left (top-right corner). Tone
//  picks the hue; opacity is conservative (6–8%) so it reads as light, not
//  decoration.
//

import SwiftUI

struct Atmosphere: View {
    let tone: Tone

    enum Tone {
        case steel, olive, tan, rose

        var color: Color {
            switch self {
            case .steel: return OPSStyle.Colors.opsAccent
            case .olive: return OPSStyle.Colors.olive
            case .tan:   return OPSStyle.Colors.tan
            case .rose:  return OPSStyle.Colors.rose
            }
        }

        /// Slightly stronger for steel since it's the most-used neutral signal.
        var opacity: Double {
            self == .steel ? 0.08 : 0.06
        }
    }

    var body: some View {
        GeometryReader { geo in
            RadialGradient(
                colors: [
                    tone.color.opacity(tone.opacity),
                    tone.color.opacity(0)
                ],
                center: UnitPoint(x: 0.88, y: 0.04),
                startRadius: 0,
                endRadius: max(geo.size.width, geo.size.height) * 0.6
            )
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

#if DEBUG
#Preview("Atmosphere / four tones") {
    TabView {
        ZStack { OPSStyle.Colors.background.ignoresSafeArea(); Atmosphere(tone: .steel)
            VStack { Spacer(); Text("STEEL").foregroundColor(.white); Spacer() } }
            .tabItem { Text("STEEL") }
        ZStack { OPSStyle.Colors.background.ignoresSafeArea(); Atmosphere(tone: .olive)
            VStack { Spacer(); Text("OLIVE").foregroundColor(.white); Spacer() } }
            .tabItem { Text("OLIVE") }
        ZStack { OPSStyle.Colors.background.ignoresSafeArea(); Atmosphere(tone: .tan)
            VStack { Spacer(); Text("TAN").foregroundColor(.white); Spacer() } }
            .tabItem { Text("TAN") }
        ZStack { OPSStyle.Colors.background.ignoresSafeArea(); Atmosphere(tone: .rose)
            VStack { Spacer(); Text("ROSE").foregroundColor(.white); Spacer() } }
            .tabItem { Text("ROSE") }
    }
    .preferredColorScheme(.dark)
}
#endif
