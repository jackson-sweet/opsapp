//
//  ProjectCompletionMoment.swift
//  OPS
//
//  The completion moment for COMPLETE PROJECT — a single radial draw-on ring
//  that sweeps outward once from the action-bar button and resolves into the
//  status stamping to COMPLETED. Completing a project is the app's biggest
//  achievement beat; before this it was silent.
//
//  Brand contract (.claude/animation-studio.local.md § celebration):
//  a draw-on sequence is explicitly sanctioned for "status transitions on
//  long-tracked deals". Confetti, particles, bounce, colour flashes and sound
//  are forbidden. A stamp, not a parade — the state change IS the celebration,
//  and the ring's only job is to carry the eye to it.
//
//  Motion contract:
//  • One easing curve — `OPSStyle.Animation.curve(_:)` = cubic-bezier(0.22, 1, 0.36, 1).
//    No spring, no bounce.
//  • Primary gesture 250–350ms; the whole sequence including the status settle
//    stays under ~600ms so it is over before the operator looks away.
//  • Reduce Motion → opacity-only at 150ms per step, and the completed state is
//    still reached. Equivalence, not removal.
//

import SwiftUI

// MARK: - Timeline

/// Pure, testable description of the completion moment. Holds no view state
/// and starts nothing — `ProjectActionBar` reads a timeline and drives its own
/// `@State` from it, so there is no fire-and-forget animation anywhere.
enum ProjectCompletionMoment {

    // MARK: Geometry (design-system tokens only)

    /// Final ring diameter — the action-bar touch target plus one spacing step.
    /// The ring therefore encircles the button and still clears the action
    /// bar's 10pt vertical padding, so the enclosing horizontal `ScrollView`
    /// never clips it.
    static let ringDiameter: CGFloat = OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing2

    /// Ring stroke weight — the standard heavy hairline.
    static let ringLineWidth: CGFloat = OPSStyle.Layout.Border.thick

    /// Scale the ring starts at. 0.45 × 64pt ≈ 29pt — the footprint of the
    /// button's own glyph — so the ring reads as originating at the checkmark
    /// the finger just hit and sweeping outward past it. It ends at 1.0 with
    /// no overshoot: the OPS curve lands, it does not settle.
    static let ringStartScale: CGFloat = 0.45

    /// The ring's scale for a given draw progress. Scale and trim are both
    /// derived from one value so the sweep reads as a single motion rather
    /// than two animations that happen to agree.
    static func ringScale(at progress: Double) -> CGFloat {
        ringStartScale + (1 - ringStartScale) * CGFloat(progress.clampedToUnitInterval)
    }

    /// The stamped status colour — `Color("StatusCompleted")` via the shared
    /// status accessor. Never a literal.
    static var completedColor: Color { OPSStyle.Colors.statusColor(for: .completed) }

    /// The label the button stamps to. Sourced from the status vocabulary
    /// itself, so the button literally becomes the project's status rather
    /// than inventing a second word for the same state.
    static var stampedLabel: String { Status.completed.displayName }

    /// The glyph the button stamps to — THE icon for Complete.
    static var stampedIcon: String { OPSStyle.Icons.complete }

    // MARK: Timing

    /// One step of the sequence.
    struct Step: Equatable {
        let delay: Double
        let duration: Double

        var end: Double { delay + duration }
    }

    /// The full choreography for one playback.
    struct Timeline: Equatable {
        /// True when the ring sweeps (trim + scale). False under Reduce
        /// Motion, where the ring is seeded at its final geometry and only
        /// its opacity ever moves.
        let sweeps: Bool

        /// Ring reveal — the outward draw-on when `sweeps`, an opacity
        /// fade-in otherwise.
        let ringReveal: Step

        /// The status stamping to COMPLETED on the button itself.
        let stamp: Step

        /// The ring retiring once it has handed the eye to the stamp.
        let ringFade: Step

        /// Wall-clock length of the visible motion.
        var motionDuration: Double {
            max(ringReveal.end, max(stamp.end, ringFade.end))
        }

        /// How long project mode is held open after the moment starts. The
        /// stamped state must be legible for a beat before the action bar
        /// leaves, otherwise the celebration is cut off by the teardown.
        var exitDwell: Double { motionDuration + ProjectCompletionMoment.settleBeat }
    }

    /// Dwell after the motion resolves, before project mode exits — one panel
    /// beat, long enough to read COMPLETED and no longer.
    static let settleBeat: Double = OPSStyle.Animation.durationPanel

    /// Reduce-motion step length — the design system's mandated fallback.
    static let reducedStepDuration: Double = OPSStyle.Animation.durationReducedFallback

    /// The choreography for the current accessibility setting. Every duration
    /// is a design-system token; nothing here is a bespoke number.
    ///
    /// Full motion (500ms total):
    ///   0ms   ring begins drawing outward from the glyph      (durationFlip)
    ///   200ms status begins stamping — starts while the ring  (durationPanel)
    ///         is still drawing, so the ring hands the eye to
    ///         the state change rather than ending beside it
    ///   350ms ring closes, begins retiring
    ///   450ms stamp settled                                   (durationPage)
    ///   500ms ring gone                                       (durationHover)
    ///
    /// Reduce Motion (300ms total): no geometry moves at all — the ring is
    /// seeded closed at final size, fades in over 150ms while the button
    /// cross-fades to COMPLETED, then fades out over 150ms.
    static func timeline(reduceMotion: Bool) -> Timeline {
        guard !reduceMotion else {
            return Timeline(
                sweeps: false,
                ringReveal: Step(delay: 0, duration: reducedStepDuration),
                // No delay — under Reduce Motion the state change leads
                // rather than being escorted in by a sweep that isn't there.
                stamp: Step(delay: 0, duration: reducedStepDuration),
                ringFade: Step(delay: reducedStepDuration, duration: reducedStepDuration)
            )
        }

        // 350ms — the token the brand config already assigns to "a moment that
        // matters", and the top of the 250–350ms primary-gesture window.
        let sweep = OPSStyle.Animation.durationFlip

        return Timeline(
            sweeps: true,
            ringReveal: Step(delay: 0, duration: sweep),
            // Overlaps the ring's tail on purpose.
            stamp: Step(
                delay: OPSStyle.Animation.durationPanel,
                duration: OPSStyle.Animation.durationPage
            ),
            ringFade: Step(delay: sweep, duration: OPSStyle.Animation.durationHover)
        )
    }

    /// The one OPS curve at a step's duration, delayed to its slot. Routing
    /// every step through the design-system token keeps the curve — and its
    /// built-in reduce-motion fallback — in exactly one place.
    static func animation(for step: Step) -> Animation {
        OPSStyle.Animation.curve(step.duration).delay(step.delay)
    }
}

private extension Double {
    var clampedToUnitInterval: Double { Swift.min(1, Swift.max(0, self)) }
}

// MARK: - Ring

/// The draw-on ring. Pure decoration in the strict sense — it renders, it never
/// participates in layout or hit testing, and it carries no state of its own.
struct ProjectCompletionRing: View {
    /// 0 → 1. Drives trim and scale together.
    let progress: Double
    let opacity: Double

    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                ProjectCompletionMoment.completedColor,
                style: StrokeStyle(
                    lineWidth: ProjectCompletionMoment.ringLineWidth,
                    lineCap: .butt
                )
            )
            // Draw from 12 o'clock, clockwise — a seal being inscribed.
            .rotationEffect(.degrees(-90))
            .frame(
                width: ProjectCompletionMoment.ringDiameter,
                height: ProjectCompletionMoment.ringDiameter
            )
            // Transform only — never a frame/layout animation.
            .scaleEffect(ProjectCompletionMoment.ringScale(at: progress))
            .opacity(opacity)
            // Must never steal a tap from the action bar underneath it.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
