// OPS/OPS/DeckBuilder/Models/DeckStairRiseEntry.swift

import Foundation

/// A stair's vertical drop, held in both vocabularies at once.
///
/// The sheet lets the drop be entered as a measured height OR as a tread
/// count, because those are the two ways a deck builder actually knows the
/// number. They are not two settings — they are two readings of ONE
/// dimension, so entering either has to move the other. Keeping them as
/// independent pieces of view state is what let the dial go stale: enter
/// 4'0" under Height, switch to Treads, and the dial still showed whatever
/// it held before (bug 46c2d6eb, A1).
///
/// Deriving happens on ENTRY, never on mode switch. That matters: 4'0" needs
/// 7 steps, and 7 steps spans 4'4½" — re-deriving in both directions on every
/// switch would walk the number away from what the operator typed. Here the
/// entered side stays exactly as entered and the other side follows, so
/// flipping back and forth is lossless.
struct DeckStairRiseEntry: Equatable {

    /// Which vocabulary the operator is currently typing in — the one a
    /// change to the code's rise-per-step must leave alone.
    enum Authority {
        case height
        case treads
    }

    /// Matches the tread dial's bounds. A stair has at least one step; 30 is
    /// well past any residential run.
    static let treadRange = 1...30

    private(set) var feet: Int
    private(set) var inches: Int
    private(set) var treadCount: Int
    private(set) var risePerStep: Double

    init(totalRiseInches: Double, risePerStep: Double) {
        self.risePerStep = risePerStep
        let clamped = max(0, totalRiseInches)
        let components = DeckFeetInchesWheels.components(fromFeet: clamped / 12.0)
        self.feet = components.feet
        self.inches = components.inches
        self.treadCount = Self.treads(forRiseInches: clamped, risePerStep: risePerStep)
    }

    /// The drop as entered on the dials.
    var heightRiseInches: Double { Double(feet * 12 + inches) }

    /// The drop the current tread count spans — what Treads mode commits,
    /// and what Height mode shows as the consequence of its own entry.
    var treadRiseInches: Double { Double(treadCount) * risePerStep }

    // MARK: - Entry points

    /// Height dials moved. Inches beyond a foot roll up rather than being
    /// rejected, so a voice/AR value like 2'18" lands as 3'6".
    mutating func setHeight(feet: Int, inches: Int) {
        setTotalRiseInches(Double(max(0, feet) * 12 + max(0, inches)))
    }

    /// Tread dial moved.
    mutating func setTreadCount(_ count: Int) {
        treadCount = count.clamped(to: Self.treadRange)
        let components = DeckFeetInchesWheels.components(fromFeet: treadRiseInches / 12.0)
        feet = components.feet
        inches = components.inches
    }

    /// A measured or prefilled drop — AR, or a level's resolved height.
    /// Both vocabularies follow it.
    mutating func setTotalRiseInches(_ value: Double) {
        let clamped = max(0, value)
        let components = DeckFeetInchesWheels.components(fromFeet: clamped / 12.0)
        feet = components.feet
        inches = components.inches
        treadCount = Self.treads(forRiseInches: clamped, risePerStep: risePerStep)
    }

    /// The code envelope's rise-per-step changed. Whichever vocabulary the
    /// operator is typing in stays put; the other re-derives from it.
    mutating func setRisePerStep(_ value: Double, authority: Authority) {
        risePerStep = value
        switch authority {
        case .height:
            treadCount = Self.treads(forRiseInches: heightRiseInches, risePerStep: value)
        case .treads:
            let components = DeckFeetInchesWheels.components(fromFeet: treadRiseInches / 12.0)
            feet = components.feet
            inches = components.inches
        }
    }

    // MARK: - Helpers

    private static func treads(forRiseInches rise: Double, risePerStep: Double) -> Int {
        StairConfig.calculateTreadCount(totalRise: rise, risePerStep: risePerStep)
            .clamped(to: treadRange)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
