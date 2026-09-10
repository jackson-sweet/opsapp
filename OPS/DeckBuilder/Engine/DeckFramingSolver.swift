import Foundation

/// Chooses the framing layout with the fewest posts that every published limit
/// in `DeckSpanTables` allows.
///
/// Pure value-in, value-out: no geometry, no SceneKit, no persistence. The
/// planner turns the result into members; this type only decides how many beam
/// lines there are, how far inboard they sit, and how far apart the posts go.
///
/// The objective is post count, because posts and footings are the expensive,
/// labour-heavy items. Maximising the cantilever and the post spacing are not
/// separate goals — they are the levers that reduce post count. For a
/// ledger-attached deck, pushing the beam as far from the house as the joist
/// table allows and then cantilevering as far past it as the table allows is
/// also what maximises the ledger's share of the load.
enum DeckFramingSolver {

    // MARK: - Inputs

    struct Input: Equatable {
        /// Depth of the surface measured away from the reference edge, in inches.
        /// For a ledger-attached surface this is the ledger-to-outer-edge distance.
        let depthInches: Double
        /// Length of a beam line across the surface, in inches.
        let beamLengthInches: Double
        /// True when one boundary of the surface is a house edge carrying a ledger.
        let isLedgerAttached: Bool
        /// Table 3b note 2: guards force joists and rim boards to 2x8 or larger.
        let guardRequired: Bool

        init(
            depthInches: Double,
            beamLengthInches: Double,
            isLedgerAttached: Bool,
            guardRequired: Bool = true
        ) {
            self.depthInches = depthInches
            self.beamLengthInches = beamLengthInches
            self.isLedgerAttached = isLedgerAttached
            self.guardRequired = guardRequired
        }
    }

    // MARK: - Outputs

    /// One beam line in the solved layout.
    struct BeamLine: Equatable {
        /// Distance from the reference edge, in inches. For a ledger-attached
        /// surface, measured from the ledger; otherwise from the near outer edge.
        let offsetInches: Double
        /// The published selection, or nil where the tables give none. A nil
        /// selection always drives `FramingSolution.isPrescriptive` to false.
        let selection: DeckSpanTables.BeamSelection?
        /// Posts under this beam line: `ceil(length / spacing) + 1`, so a post
        /// sits at each end of the beam and at every interval between.
        let postCount: Int
    }

    struct FramingSolution: Equatable {
        let joistSize: LumberSize
        let joistSpacingInchesOC: Double
        /// Joists overhang the outermost beam by this much — the full Table 3b
        /// allowance for the chosen joist size, unless the deck is too shallow
        /// to fit it.
        let cantileverInches: Double
        /// Clear joist span between two supports, in inches.
        let joistClearSpanInches: Double
        let postSpacingFeet: Double
        let postSize: LumberSize
        let beamLines: [BeamLine]
        /// False when any part of the layout falls outside the published tables.
        /// Drives the extra line of the in-product disclosure.
        let isPrescriptive: Bool
        /// Plain-language reasons the layout is not prescriptive. Empty when it is.
        let advisories: [String]
        /// Every table this solution rests on.
        let citations: [String]

        var postCount: Int { beamLines.reduce(0) { $0 + $1.postCount } }
        var beamCount: Int { beamLines.count }
    }

    // MARK: - Enumeration order

    /// Largest first, so the biggest cantilever is reachable. Ties are broken
    /// toward the smallest joist that still wins, so the answer stays stable.
    static let joistSizeSearchOrder: [LumberSize] = [.twoByTwelve, .twoByTen, .twoByEight, .twoBySix]

    /// Widest legal spacing first. 24 in is the BCBC 9.23.1.1 ceiling and is the
    /// fewest joists for the same picture. The published 8 in column is
    /// deliberately excluded: nobody frames a deck at 8 in o.c., and it exists in
    /// the table to serve the narrow-joist rows the guard rule already excludes.
    static let joistSpacingSearchOrder: [Double] = [24, 16, 12]

    /// Widest first. These are the only columns the beam tables publish.
    static let postSpacingSearchOrderFeet: [Double] = [8, 6, 4]

    /// Joist runs to try before giving up on a prescriptive answer. One run — a
    /// single beam attached, two beams free-standing — covers effectively every
    /// real deck. A second run is the non-prescriptive fallback.
    static let maximumJoistRunCount = 8

    // MARK: - Guards that are geometry, not published limits

    /// A cantilever is never allowed to exceed the back-span it hangs off.
    ///
    /// This is a geometry guard, **not** a published limit — CWC gives no such
    /// rule. It only ever shortens the cantilever below the table allowance
    /// (moving the beam outward), so it can never permit something the tables
    /// do not. It exists so a very shallow deck cannot place its beam on top of
    /// the ledger.
    static let cantileverMayNotExceedBackSpan = true

    private static let epsilon = 0.000_001

    // MARK: - Solve

    /// The layout with the fewest posts that satisfies every published limit,
    /// or nil when the surface has no usable depth or length.
    ///
    /// Deterministic: the search is an exhaustive enumeration in a fixed order
    /// with a total ordering on the result, so the same input always yields the
    /// same solution.
    static func solve(_ input: Input) -> FramingSolution? {
        guard input.depthInches > epsilon, input.beamLengthInches > epsilon else { return nil }

        for joistRunCount in 1...maximumJoistRunCount {
            let candidates = self.candidates(for: input, joistRunCount: joistRunCount)
            if let best = candidates.min(by: isBetter) { return best }
        }

        // Every published combination is exhausted. Rather than draw nothing,
        // fall back to the deepest joist at the tightest spacing and say plainly
        // that the layout is outside the tables.
        return fallbackSolution(for: input)
    }

    // MARK: - Candidate generation

    private static func candidates(
        for input: Input,
        joistRunCount: Int
    ) -> [FramingSolution] {
        // A "joist run" is one clear span between two supports. Ledger-attached,
        // n runs means n beams. Free-standing, n runs means n + 1 beams.
        var results: [FramingSolution] = []

        for joistSize in joistSizeSearchOrder {
            if input.guardRequired, isSmaller(joistSize, than: DeckSpanTables.minimumSizeWhereGuardRequired) {
                continue
            }
            guard let tableCantilever = DeckSpanTables.maxCantileverInches(nominalSize: joistSize) else { continue }

            for spacing in joistSpacingSearchOrder {
                guard spacing <= DeckSpanTables.maximumJoistSpacingInchesOC + epsilon,
                      let joistRow = DeckSpanTables.joistRow(nominalSize: joistSize, spacingInchesOC: spacing)
                else { continue }

                guard let layout = layout(
                    for: input,
                    joistRunCount: joistRunCount,
                    tableCantileverInches: tableCantilever
                ), layout.clearSpanInches <= joistRow.maxSpanInches + epsilon else { continue }

                for postSpacingFeet in postSpacingSearchOrderFeet {
                    guard let solution = resolveBeams(
                        input: input,
                        layout: layout,
                        joistRow: joistRow,
                        postSpacingFeet: postSpacingFeet
                    ) else { continue }
                    results.append(solution)
                }
            }
        }

        return results
    }

    /// Where the beam lines sit and how long each joist run is, before any beam
    /// is selected. Returns nil when the geometry cannot accommodate this many
    /// beam lines.
    private struct Layout {
        let cantileverInches: Double
        let clearSpanInches: Double
        /// Offsets from the reference edge, ordered outward.
        let beamOffsetsInches: [Double]
    }

    private static func layout(
        for input: Input,
        joistRunCount: Int,
        tableCantileverInches: Double
    ) -> Layout? {
        let depth = input.depthInches

        if input.isLedgerAttached {
            // Supports are the ledger plus `joistRunCount` beams. The outermost
            // beam sits one full cantilever inboard of the outer edge; the rest
            // divide the remaining depth evenly.
            let spanCount = Double(joistRunCount)
            let maximumByGeometry = cantileverMayNotExceedBackSpan
                ? depth / (spanCount + 1)
                : depth
            let cantilever = min(tableCantileverInches, maximumByGeometry)
            guard cantilever > epsilon else { return nil }

            let supported = depth - cantilever
            guard supported > epsilon else { return nil }
            let clearSpan = supported / spanCount
            let offsets = (1...joistRunCount).map { clearSpan * Double($0) }
            return Layout(
                cantileverInches: cantilever,
                clearSpanInches: clearSpan,
                beamOffsetsInches: offsets
            )
        }

        // Free-standing: a beam inboard of each outer edge, plus `joistRunCount - 1`
        // beams between them. Joists cantilever past both outer beams.
        let interiorSpanCount = Double(joistRunCount)
        let maximumByGeometry = cantileverMayNotExceedBackSpan
            ? depth / (interiorSpanCount + 2)
            : depth / 2
        let cantilever = min(tableCantileverInches, maximumByGeometry)
        guard cantilever > epsilon else { return nil }

        let supported = depth - 2 * cantilever
        guard supported > epsilon else { return nil }
        let clearSpan = supported / interiorSpanCount
        let offsets = (0...joistRunCount).map { cantilever + clearSpan * Double($0) }
        return Layout(
            cantileverInches: cantilever,
            clearSpanInches: clearSpan,
            beamOffsetsInches: offsets
        )
    }

    /// Selects a beam for every line in the layout. Returns nil when any line
    /// has no published selection at this post spacing.
    private static func resolveBeams(
        input: Input,
        layout: Layout,
        joistRow: DeckSpanTables.JoistSpanRow,
        postSpacingFeet: Double
    ) -> FramingSolution? {
        let lineCount = layout.beamOffsetsInches.count
        var lines: [BeamLine] = []
        var citations: Set<String> = [joistRow.citation]
        var advisories: [String] = []

        for (index, offset) in layout.beamOffsetsInches.enumerated() {
            let isOutermost = index == lineCount - 1
            let isInnermostFreeStanding = !input.isLedgerAttached && index == 0
            let carriesCantilever = isOutermost || isInnermostFreeStanding

            // Figure 1 note 3: a beam between two joist runs supports two spans.
            let continuity: DeckSpanTables.BeamContinuity = carriesCantilever ? .singleSpan : .twoSpans

            // Figure 1 note 4: the cantilever is added to the joist span before
            // entering the beam tables. A beam with no cantilever enters on the
            // bare span (Table 7b note 6: the larger of two equal runs is the run).
            let enteringInches = layout.clearSpanInches + (carriesCantilever ? layout.cantileverInches : 0)

            let result = DeckSpanTables.beamSelection(
                joistSpanIncludingCantileverFeet: enteringInches / 12,
                postSpacingFeet: postSpacingFeet,
                continuity: continuity
            )
            guard case let .selection(selection) = result else { return nil }

            citations.insert(selection.citation)
            lines.append(BeamLine(
                offsetInches: offset,
                selection: selection,
                postCount: postCount(
                    beamLengthInches: input.beamLengthInches,
                    postSpacingFeet: postSpacingFeet
                )
            ))
        }

        // A layout with more than one joist run per side models joists lapped over
        // the intermediate beam as separate simple spans. That is consistent with
        // Figure 1 note 3, but the guide does not spell it out, so it is not a
        // prescriptive result.
        let runCount = input.isLedgerAttached ? lineCount : lineCount - 1
        let isPrescriptive = runCount <= 1
        if !isPrescriptive {
            advisories.append(
                "Deck is deeper than one published joist span, so the frame uses more than one joist run."
            )
        }

        // The preview has no post-height input, so height enters as zero. Both
        // branches of CWC Note 5 resolve to 6x6 anyway: BCBC 9.17.4.1 requires it
        // absent a structural calculation, and a 3-ply beam requires it for bearing.
        let maximumPly = lines.compactMap { $0.selection?.plyCount }.max() ?? 1
        let postSize: LumberSize
        switch DeckSpanTables.postSelection(beamPlyCount: maximumPly, heightFeet: 0) {
        case let .selection(selection):
            postSize = selection.nominalSize
            citations.insert(selection.citation)
        case .notPrescriptive:
            postSize = DeckSpanTables.defaultPostSize
        }

        return FramingSolution(
            joistSize: joistRow.nominalSize,
            joistSpacingInchesOC: joistRow.maxSpacingInchesOC,
            cantileverInches: layout.cantileverInches,
            joistClearSpanInches: layout.clearSpanInches,
            postSpacingFeet: postSpacingFeet,
            postSize: postSize,
            beamLines: lines,
            isPrescriptive: isPrescriptive,
            advisories: advisories,
            citations: citations.sorted()
        )
    }

    /// The layout drawn when no published combination fits: the deepest joist at
    /// the tightest spacing, enough beam lines to keep every run inside that row,
    /// and no beam selection at all.
    private static func fallbackSolution(for input: Input) -> FramingSolution? {
        let joistSize = LumberSize.twoByTwelve
        let spacing = joistSpacingSearchOrder.last ?? 12
        guard let joistRow = DeckSpanTables.joistRow(nominalSize: joistSize, spacingInchesOC: spacing),
              let cantilever = DeckSpanTables.maxCantileverInches(nominalSize: joistSize)
        else { return nil }

        var joistRunCount = 1
        var resolved: Layout?
        while joistRunCount <= maximumJoistRunCount {
            if let candidate = layout(
                for: input,
                joistRunCount: joistRunCount,
                tableCantileverInches: cantilever
            ), candidate.clearSpanInches <= joistRow.maxSpanInches + epsilon {
                resolved = candidate
                break
            }
            joistRunCount += 1
        }

        let layout = resolved ?? Layout(
            cantileverInches: min(cantilever, input.depthInches / 2),
            clearSpanInches: input.depthInches,
            beamOffsetsInches: [max(input.depthInches - min(cantilever, input.depthInches / 2), epsilon)]
        )

        let postSpacingFeet = postSpacingSearchOrderFeet.last ?? 4
        let lines = layout.beamOffsetsInches.map { offset in
            BeamLine(
                offsetInches: offset,
                selection: nil,
                postCount: postCount(
                    beamLengthInches: input.beamLengthInches,
                    postSpacingFeet: postSpacingFeet
                )
            )
        }

        return FramingSolution(
            joistSize: joistSize,
            joistSpacingInchesOC: spacing,
            cantileverInches: layout.cantileverInches,
            joistClearSpanInches: layout.clearSpanInches,
            postSpacingFeet: postSpacingFeet,
            postSize: DeckSpanTables.defaultPostSize,
            beamLines: lines,
            isPrescriptive: false,
            advisories: ["Deck is outside the published span tables."],
            citations: [joistRow.citation]
        )
    }

    // MARK: - Helpers

    /// Posts along one beam: one at each end plus one at every interval between.
    static func postCount(beamLengthInches: Double, postSpacingFeet: Double) -> Int {
        let spacingInches = postSpacingFeet * 12
        guard spacingInches > epsilon, beamLengthInches > epsilon else { return 1 }
        let intervals = max(1, Int(ceil(beamLengthInches / spacingInches - epsilon)))
        return intervals + 1
    }

    /// Total ordering: fewest posts, then the largest cantilever, then the widest
    /// post spacing, then the smallest joist, then the widest joist spacing.
    private static func isBetter(_ lhs: FramingSolution, _ rhs: FramingSolution) -> Bool {
        if lhs.postCount != rhs.postCount { return lhs.postCount < rhs.postCount }
        if abs(lhs.cantileverInches - rhs.cantileverInches) > epsilon {
            return lhs.cantileverInches > rhs.cantileverInches
        }
        if abs(lhs.postSpacingFeet - rhs.postSpacingFeet) > epsilon {
            return lhs.postSpacingFeet > rhs.postSpacingFeet
        }
        let lhsDepth = DeckSpanTables.nominalDepthInches(lhs.joistSize) ?? 0
        let rhsDepth = DeckSpanTables.nominalDepthInches(rhs.joistSize) ?? 0
        if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
        if abs(lhs.joistSpacingInchesOC - rhs.joistSpacingInchesOC) > epsilon {
            return lhs.joistSpacingInchesOC > rhs.joistSpacingInchesOC
        }
        return lhs.beamCount < rhs.beamCount
    }

    private static func isSmaller(_ lhs: LumberSize, than rhs: LumberSize) -> Bool {
        guard let lhsDepth = DeckSpanTables.nominalDepthInches(lhs),
              let rhsDepth = DeckSpanTables.nominalDepthInches(rhs) else { return false }
        return lhsDepth < rhsDepth
    }
}
