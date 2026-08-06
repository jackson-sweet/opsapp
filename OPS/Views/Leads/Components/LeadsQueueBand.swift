//
//  LeadsQueueBand.swift
//  OPS
//
//  The LEADS console's sticky control band (console redesign 2026-08-05,
//  spec §5; reworked by the round-2 addendum §15). Two rows and a hairline,
//  pinned under the command band:
//
//      [⌕ Search leads                                        ] [☰]
//      [ALL 12][OVERDUE 2][DUE TODAY 1][YOUR MOVE 1][FRESH …
//      ────────────────────────────────────────────────────
//
//  Round 1 put two menu chips beside the field. Round 2 collapses them into
//  one trailing filter control, so the field is genuinely full-width in the
//  common case — the operator opens LEADS to find somebody, not to reorder a
//  queue that already opens in urgency order.
//
//  The one interaction rule: SEARCH SUSPENDS BROWSE. While a query is live the
//  bucket chips and the filter control neither constrain the results nor
//  accept taps, and they say so by dimming. Sort is suspended with them this
//  round (addendum §15.4) — it now lives INSIDE the filter control, and a
//  control that still worked while visibly standing down would be a worse lie
//  than one that plainly waits. Clearing the query restores the previous chip,
//  sort and crew state untouched, so a search can never dead-end against a
//  filter the operator forgot was set.
//

import SwiftUI

struct LeadsQueueBand: View {
    @Binding var controls: LeadsListControls
    let chips: [TacticalChip]
    @Binding var selectedChipId: String
    let roster: [CrewMember]
    /// Counts for the filter menu's crew rows, resolved once by the console
    /// over every open lead (addendum §15.2).
    let crewCounts: LeadsCrewCounts
    /// Closed for a solo operator — assignment carries no information when
    /// there is only one nameable operator (spec §5.3).
    let showsCrew: Bool
    /// Focus transitions on the search field. The console scrolls this band to
    /// the top on the gained edge (addendum §15.3).
    var onSearchFocusChange: (Bool) -> Void = { _ in }

    /// The dim applied to a control that search has stood down.
    private static let suspendedOpacity: Double = 0.4

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                LeadsSearchBar(query: $controls.query, onFocusChange: onSearchFocusChange)

                LeadsFilterControl(
                    sort: $controls.sort,
                    crew: $controls.crew,
                    roster: roster,
                    counts: crewCounts,
                    showsCrew: showsCrew
                )
                .opacity(controls.isSearching ? Self.suspendedOpacity : 1)
                .allowsHitTesting(!controls.isSearching)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing2)

            TacticalChipRow(chips: chips, selectedId: $selectedChipId)
                .padding(.top, OPSStyle.Layout.spacing2)
                .padding(.bottom, OPSStyle.Layout.spacing2)
                .opacity(controls.isSearching ? Self.suspendedOpacity : 1)
                .allowsHitTesting(!controls.isSearching)

            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: 1)
        }
        .background(OPSStyle.Colors.background)
        .animation(OPSStyle.Animation.standard, value: controls.isSearching)
    }
}

// MARK: - Previews

#if DEBUG
private struct LeadsQueueBandPreviewHost: View {
    @State private var browsing = LeadsListControls()
    @State private var filtered = LeadsListControls(query: "", sort: .newest, crew: .member("u-2"))
    @State private var searching = LeadsListControls(query: "roof", sort: .newest, crew: .all)
    @State private var chipId = PipelineViewModel.TriageBucket.all.rawValue

    private let chips: [TacticalChip] = [
        TacticalChip(id: "all", label: "ALL", count: 12),
        TacticalChip(id: "overdue", label: "OVERDUE", count: 2, tone: OPSStyle.Colors.rose),
        TacticalChip(id: "dueToday", label: "DUE TODAY", count: 1, tone: OPSStyle.Colors.tan),
        TacticalChip(id: "waitingOnYou", label: "YOUR MOVE", count: 1, tone: OPSStyle.Colors.opsAccent)
    ]

    private let roster: [CrewMember] = [
        CrewMember(id: "u-1", fullName: "Jason Wagner", shortLabel: "JASON W"),
        CrewMember(id: "u-2", fullName: "Dana Whitfield", shortLabel: "DANA W")
    ]

    private let counts = LeadsCrewCounts(
        all: 12, mine: 4, unassigned: 2, byMember: ["u-1": 4, "u-2": 5]
    )

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing5) {
            // Browsing at rest — glyph-only control, full-width field.
            LeadsQueueBand(controls: $browsing, chips: chips, selectedChipId: $chipId,
                           roster: roster, crewCounts: counts, showsCrew: true)
            // Sorted and narrowed — the control names the slice.
            LeadsQueueBand(controls: $filtered, chips: chips, selectedChipId: $chipId,
                           roster: roster, crewCounts: counts, showsCrew: true)
            // Searching — chips AND the filter control stood down together.
            LeadsQueueBand(controls: $searching, chips: chips, selectedChipId: $chipId,
                           roster: roster, crewCounts: counts, showsCrew: true)
            // Solo operator — sort-only menu behind the same control.
            LeadsQueueBand(controls: $browsing, chips: chips, selectedChipId: $chipId,
                           roster: [], crewCounts: counts, showsCrew: false)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(OPSStyle.Colors.background)
    }
}

#Preview("LeadsQueueBand / rest · filtered · search · solo") {
    LeadsQueueBandPreviewHost()
        .preferredColorScheme(.dark)
}
#endif
