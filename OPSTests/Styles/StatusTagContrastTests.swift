//
//  StatusTagContrastTests.swift
//  OPSTests
//
//  The mobile status-tag tokens, measured rather than asserted by eye.
//
//  MOBILE.md §1 fixes the status-tag fill at 0.32 alpha and the border at 0.88
//  — "a non-negotiable mobile delta", because the operator reads these in a
//  truck with sun on the screen. Raising the fill lifts the ground under the
//  label, so the fill and the label ink are one decision, not two: the tokens
//  drifted apart once (0.20 / 0.55, with inks that were never a real ×1.25
//  lift) and nothing caught it, because nothing here was measured.
//
//  This file is that measurement. It fails if a token is edited to a value
//  that puts field-readable text under the bar, and it fails if `*FillM` /
//  `*LineM` stop deriving from `StatusTagM` — the drift that let one set of
//  numbers claim to implement a spec the other set actually held.
//
//  Bars (ops-ios/CLAUDE.md § Field-First Implementation, WCAG 1.4.11):
//    • label on its own fill — 7:1. Tag text is 9.5pt `nanoLabel`: small text.
//    • outline on the canvas — 3:1. A border is a non-text UI component.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/StatusTagContrastTests
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class StatusTagContrastTests: XCTestCase {

    // MARK: - Bars

    /// Small text in daylight. `ops-ios/CLAUDE.md` § Field-First Implementation.
    private let textBar: Double = 7.0
    /// Non-text UI component (the tag outline) — WCAG 2.2 SC 1.4.11.
    private let nonTextBar: Double = 3.0

    /// The canvas every tag composites over. Pure black, per DESIGN.md.
    private let canvas = RGB(r: 0, g: 0, b: 0)

    // MARK: - The three tones under test

    private struct ToneCase {
        let name: String
        let base: Color
        let fill: Color
        let line: Color
        let ink: Color
        /// Minimum per-channel lift the ink must clear versus its base tone.
        /// §1 says "~25% brighter"; rose needs slightly more to hold 7:1 (see
        /// `testRoseInkIsLiftedFurtherThanTheOthersOnPurpose`).
        let minimumLift: Double
    }

    private var tones: [ToneCase] {
        [
            ToneCase(name: "olive",
                     base: OPSStyle.Colors.olive,
                     fill: OPSStyle.Colors.oliveFillM,
                     line: OPSStyle.Colors.oliveLineM,
                     ink:  OPSStyle.Colors.oliveTextM,
                     minimumLift: 0.25),
            ToneCase(name: "tan",
                     base: OPSStyle.Colors.tan,
                     fill: OPSStyle.Colors.tanFillM,
                     line: OPSStyle.Colors.tanLineM,
                     ink:  OPSStyle.Colors.tanTextM,
                     minimumLift: 0.25),
            ToneCase(name: "rose",
                     base: OPSStyle.Colors.rose,
                     fill: OPSStyle.Colors.roseFillM,
                     line: OPSStyle.Colors.roseLineM,
                     ink:  OPSStyle.Colors.roseTextM,
                     minimumLift: 0.25),
        ]
    }

    // MARK: - Spec conformance

    func testStatusTagAlphasMatchMobileSpec() {
        XCTAssertEqual(OPSStyle.Colors.StatusTagM.fill, 0.32, accuracy: 0.0001,
                       "MOBILE.md §1 fixes the mobile status-tag fill at 0.32 alpha.")
        XCTAssertEqual(OPSStyle.Colors.StatusTagM.border, 0.88, accuracy: 0.0001,
                       "MOBILE.md §1 fixes the mobile status-tag border at 0.88 alpha.")
    }

    /// The regression that started this file: `*FillM` / `*LineM` sat at
    /// 0.20 / 0.55 while a comment above them cited §1, and a second set of
    /// scalars elsewhere held the real numbers. One source of truth or the
    /// two drift again.
    func testFillAndLineDeriveFromTheStatusTagScalars() {
        for tone in tones {
            XCTAssertEqual(alpha(of: tone.fill), OPSStyle.Colors.StatusTagM.fill, accuracy: 0.005,
                           "\(tone.name)FillM must derive from StatusTagM.fill, not carry its own alpha.")
            XCTAssertEqual(alpha(of: tone.line), OPSStyle.Colors.StatusTagM.border, accuracy: 0.005,
                           "\(tone.name)LineM must derive from StatusTagM.border, not carry its own alpha.")
        }
    }

    /// The fill and line must tint the tone they are named for — a derived
    /// alpha is worthless if it is applied to the wrong hue.
    func testFillAndLineCarryTheirOwnTone() {
        for tone in tones {
            let base = rgb(of: tone.base)
            for (label, token) in [("FillM", tone.fill), ("LineM", tone.line)] {
                let opaque = rgb(of: token)
                XCTAssertEqual(opaque.r, base.r, accuracy: 0.01, "\(tone.name)\(label) hue drifted (red).")
                XCTAssertEqual(opaque.g, base.g, accuracy: 0.01, "\(tone.name)\(label) hue drifted (green).")
                XCTAssertEqual(opaque.b, base.b, accuracy: 0.01, "\(tone.name)\(label) hue drifted (blue).")
            }
        }
    }

    // MARK: - The contrast the field actually needs

    /// The bar that constrains the change. Raising the fill to 0.32 lifts the
    /// ground under the label; the old inks would land at 6.67 / 6.48 / 5.69:1
    /// here — all three under 7:1 — which is why the inks moved with the fill.
    func testLabelClearsSevenToOneOnItsOwnFill() {
        for tone in tones {
            let ground = composite(tone.fill, over: canvas)
            let measured = contrast(rgb(of: tone.ink), ground)
            XCTAssertGreaterThanOrEqual(
                measured, textBar,
                """
                \(tone.name) label is \(ratio(measured)) on its own fill — under the \
                7:1 field bar for 9.5pt text. Fill and ink move together: if the fill \
                rises, the ink has to rise with it.
                """
            )
        }
    }

    /// The reason for the change. At the old 0.55 border the outlines measured
    /// 3.30 / 3.24 / 2.55:1 — rose failed even the non-text floor.
    func testOutlineClearsTheNonTextBarOnTheCanvas() {
        for tone in tones {
            let measured = contrast(composite(tone.line, over: canvas), canvas)
            XCTAssertGreaterThanOrEqual(
                measured, nonTextBar,
                "\(tone.name) outline is \(ratio(measured)) on the canvas — under the 3:1 non-text bar."
            )
        }
    }

    /// §1's "shifted ~25% brighter", read literally and per channel — the
    /// reading the previous inks did not satisfy (tan was +9% / +12% / +25%,
    /// which is a blue-only lift wearing a ~25% label).
    func testInksAreALiteralPerChannelLift() {
        for tone in tones {
            let base = rgb(of: tone.base)
            let ink = rgb(of: tone.ink)
            for (channel, pair) in [("red", (base.r, ink.r)), ("green", (base.g, ink.g)), ("blue", (base.b, ink.b))] {
                // A channel already at the ceiling cannot lift further; that is
                // clamping, not drift, and only the unclamped channels bind.
                guard pair.0 * (1 + tone.minimumLift) <= 1.0 else { continue }
                let lift = pair.1 / pair.0 - 1
                XCTAssertGreaterThanOrEqual(
                    lift, tone.minimumLift - 0.005,
                    """
                    \(tone.name)TextM \(channel) is only \(percent(lift)) brighter than the base \
                    tone — §1 asks for ~25% on every channel, not on one.
                    """
                )
            }
        }
    }

    /// Rose is the exception, and it is deliberate. It is the darkest tone —
    /// #B58289 is 6.52:1 on black at full strength — so a ×1.25 lift leaves
    /// its label at 6.48:1, under the bar. ×1.30 is the smallest lift that
    /// clears 7:1. This test pins the reason so the outlier is not "tidied"
    /// back to ×1.25 by someone making the three tones look uniform.
    func testRoseInkIsLiftedFurtherThanTheOthersOnPurpose() {
        let rose = rgb(of: OPSStyle.Colors.rose)
        let ground = composite(OPSStyle.Colors.roseFillM, over: canvas)

        let atQuarterLift = RGB(r: min(1, rose.r * 1.25), g: min(1, rose.g * 1.25), b: min(1, rose.b * 1.25))
        XCTAssertLessThan(
            contrast(atQuarterLift, ground), textBar,
            "If rose now clears 7:1 at a ×1.25 lift, the ×1.30 exception is obsolete — collapse it."
        )
        XCTAssertGreaterThanOrEqual(
            contrast(rgb(of: OPSStyle.Colors.roseTextM), ground), textBar,
            "roseTextM must clear 7:1 on the 0.32 rose fill — that is the whole reason it is ×1.30."
        )
    }

    /// Rose's outline cannot reach the text bar at ANY alpha — a property of
    /// the tone itself, not of the alphas. Recorded so a future reader does not
    /// spend an afternoon trying to tune 0.88 upward to fix it: the fix, if it
    /// is ever wanted, is a lighter rose in the palette.
    func testRoseOutlineCannotReachTheTextBarAtAnyAlpha() {
        let ceiling = contrast(rgb(of: OPSStyle.Colors.rose), canvas)
        XCTAssertLessThan(
            ceiling, textBar,
            "Rose now clears 7:1 on black at full strength — the palette changed; revisit the rose outline note."
        )
    }

    // MARK: - Ledger

    /// Not an assertion — the measured table, printed so a run of this file is
    /// its own evidence rather than a green tick with nothing behind it.
    func testPrintContrastLedger() {
        func column(_ text: String, _ width: Int) -> String {
            text.count >= width ? text : text.padding(toLength: width, withPad: " ", startingAt: 0)
        }

        print("\n// STATUS TAG CONTRAST — measured, composited over #000000")
        print("  " + column("tone", 8) + column("label on fill", 20) + "outline on canvas")
        for tone in tones {
            let label = contrast(rgb(of: tone.ink), composite(tone.fill, over: canvas))
            let outline = contrast(composite(tone.line, over: canvas), canvas)
            print("  " + column(tone.name, 8)
                  + column("\(ratio(label)) \(label >= textBar ? "OK" : "UNDER")", 20)
                  + "\(ratio(outline)) \(outline >= nonTextBar ? "OK" : "UNDER")")
        }
        print("  bars: label 7:1 (field rule, 9.5pt) / outline 3:1 (WCAG 1.4.11)\n")
    }

    // MARK: - Colour plumbing

    private struct RGB {
        let r: Double
        let g: Double
        let b: Double
    }

    /// Resolves a SwiftUI `Color` in the dark trait the app always runs in.
    /// `UIColor` resolves asset-catalog colours correctly — it is `ImageRenderer`
    /// that cannot, which is why nothing here goes through it.
    private func resolved(_ color: Color) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    }

    private func rgb(of color: Color) -> RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGB(r: Double(r), g: Double(g), b: Double(b))
    }

    private func alpha(of color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return Double(a)
    }

    /// Source-over composite of a translucent token onto an opaque ground —
    /// what the screen actually shows, and therefore what must be measured.
    private func composite(_ color: Color, over ground: RGB) -> RGB {
        let top = rgb(of: color)
        let a = alpha(of: color)
        return RGB(r: top.r * a + ground.r * (1 - a),
                   g: top.g * a + ground.g * (1 - a),
                   b: top.b * a + ground.b * (1 - a))
    }

    /// WCAG 2.x relative luminance.
    private func luminance(_ c: RGB) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    private func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func ratio(_ value: Double) -> String { String(format: "%.2f:1", value) }
    private func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
}
#endif
