//
//  LeadsQueueBand.swift
//  OPS
//
//  The LEADS console's sticky control band (console redesign 2026-08-05,
//  spec §5). Two rows and a hairline, pinned under the command band:
//
//      [⌕ Search leads              ] [URGENCY ▾] [CREW ▾]
//      [ALL 12][OVERDUE 2][DUE TODAY 1][YOUR MOVE 1][FRESH …
//      ────────────────────────────────────────────────────
//
//  Every control the operator has is visible here — nothing behind a
//  "filters" door. The one interaction rule: SEARCH SUSPENDS BROWSE. While a
//  query is live the bucket chips and the crew filter neither constrain the
//  results nor accept taps, and they say so by dimming; sort keeps working,
//  because reordering matches is still a sane thing to want. Clearing the
//  query restores the previous chip and crew state untouched — so a search can
//  never dead-end against a filter the operator forgot was set.
//

import SwiftUI

struct LeadsQueueBand: View {
    @Binding var controls: LeadsListControls
    let chips: [TacticalChip]
    @Binding var selectedChipId: String
    let roster: [CrewMember]
    /// Closed for a solo operator — assignment carries no information when
    /// there is only one nameable operator (spec §5.3).
    let showsCrew: Bool

    /// The dim applied to a control that search has stood down.
    private static let suspendedOpacity: Double = 0.4

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                LeadsSearchBar(query: $controls.query)
                LeadsSortChip(sort: $controls.sort)
                if showsCrew {
                    LeadsCrewChip(crew: $controls.crew, roster: roster)
                        .opacity(controls.isSearching ? Self.suspendedOpacity : 1)
                        .allowsHitTesting(!controls.isSearching)
                }
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

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing5) {
            // Browsing — everything live.
            LeadsQueueBand(controls: $browsing, chips: chips,
                           selectedChipId: $chipId, roster: roster, showsCrew: true)
            // Searching — chips and crew stood down; sort still live.
            LeadsQueueBand(controls: $searching, chips: chips,
                           selectedChipId: $chipId, roster: roster, showsCrew: true)
            // Solo operator — no crew chip at all.
            LeadsQueueBand(controls: $browsing, chips: chips,
                           selectedChipId: $chipId, roster: [], showsCrew: false)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(OPSStyle.Colors.background)
    }
}

#Preview("LeadsQueueBand / browse · search · solo") {
    LeadsQueueBandPreviewHost()
        .preferredColorScheme(.dark)
}
#endif
