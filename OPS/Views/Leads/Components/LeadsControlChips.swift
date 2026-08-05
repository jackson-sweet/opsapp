//
//  LeadsControlChips.swift
//  OPS
//
//  The LEADS console's two menu chips (console redesign 2026-08-05, spec §5.2
//  / §5.3): SORT and CREW. Both sit beside the search field in the sticky band
//  — visible, never nested behind a "filters" door.
//
//  Anatomy is the shipped `TacticalChip` grammar, verbatim, because these chips
//  share a band with the bucket chip row and a second chip vocabulary in the
//  same 92pt of screen would read as two systems: `miniLabelBold` at 0.8
//  tracking, `chipMinHeight`, `sidebarHoverRadius`, `text3` on `surfaceInput`
//  at rest, and — when the control is holding a NON-DEFAULT value — `text` on a
//  0.10 white fill with a 0.20 white hairline. No accent, ever (DESIGN.md: the
//  accent is the primary CTA and the focus ring, nothing else).
//
//  `Menu` hosts the chip; the visible chip is fully custom (stock picker /
//  menu styling is banned on this codebase).
//

import SwiftUI

// MARK: - Sort

struct LeadsSortChip: View {
    @Binding var sort: LeadSort

    var body: some View {
        Menu {
            ForEach(LeadSort.allCases, id: \.self) { option in
                Button {
                    select(option)
                } label: {
                    LeadsControlMenuRow(title: Self.label(for: option), isCurrent: option == sort)
                }
            }
        } label: {
            // URGENCY is the console's answer to "what needs me" — holding it
            // is not a filter, so the chip stays at rest until the operator
            // deliberately reorders the queue.
            LeadsControlChip(text: Self.label(for: sort), isActive: sort != .urgency)
        }
        .accessibilityLabel("Sort, currently \(Self.label(for: sort).lowercased())")
    }

    private func select(_ option: LeadSort) {
        guard option != sort else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        sort = option
    }

    static func label(for sort: LeadSort) -> String {
        switch sort {
        case .urgency: return "URGENCY"
        case .newest:  return "NEWEST"
        case .value:   return "VALUE"
        }
    }
}

// MARK: - Crew

struct LeadsCrewChip: View {
    @Binding var crew: CrewFilter
    let roster: [CrewMember]

    var body: some View {
        Menu {
            Button { select(.all) } label: {
                LeadsControlMenuRow(title: "ALL CREW", isCurrent: crew == .all)
            }
            Button { select(.mine) } label: {
                LeadsControlMenuRow(title: "MINE", isCurrent: crew == .mine)
            }
            Button { select(.unassigned) } label: {
                LeadsControlMenuRow(title: "UNASSIGNED", isCurrent: crew == .unassigned)
            }
            if !roster.isEmpty {
                Divider()
                ForEach(roster) { member in
                    Button { select(.member(member.id)) } label: {
                        LeadsControlMenuRow(
                            title: member.shortLabel,
                            isCurrent: crew == .member(member.id)
                        )
                    }
                }
            }
        } label: {
            LeadsControlChip(text: label, isActive: crew != .all)
        }
        .accessibilityLabel("Crew filter, currently \(label.lowercased())")
    }

    /// At rest the chip names the control (`CREW`); filtered, it names the
    /// slice — the operator reads WHO they are looking at without opening it.
    private var label: String {
        switch crew {
        case .all:        return "CREW"
        case .mine:       return "MINE"
        case .unassigned: return "UNASSIGNED"
        case .member(let id):
            return roster.first(where: { $0.id == id })?.shortLabel ?? "CREW"
        }
    }

    private func select(_ option: CrewFilter) {
        guard option != crew else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        crew = option
    }
}

// MARK: - Shared chip face

/// The chip both menus wear — `TacticalChip`'s neutral grammar with a trailing
/// affordance instead of a count.
private struct LeadsControlChip: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text(text)
                .foregroundColor(isActive ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
            Text("▾")
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .font(OPSStyle.Typography.miniLabelBold)
        .tracking(0.8)
        .textCase(.uppercase)
        .lineLimit(1)
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .frame(height: OPSStyle.Layout.chipMinHeight)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous)
                .fill(isActive ? OPSStyle.Colors.text.opacity(0.10) : OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous)
                .strokeBorder(
                    isActive ? OPSStyle.Colors.text.opacity(0.20) : OPSStyle.Colors.line,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
    }
}

/// One menu row — the current value carries the system checkmark, matching
/// `LeadStatusMenu`'s grammar.
private struct LeadsControlMenuRow: View {
    let title: String
    let isCurrent: Bool

    var body: some View {
        if isCurrent {
            SwiftUI.Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

// MARK: - Previews

#if DEBUG
private struct LeadsControlChipsPreviewHost: View {
    @State private var restingSort: LeadSort = .urgency
    @State private var activeSort: LeadSort = .newest
    @State private var restingCrew: CrewFilter = .all
    @State private var activeCrew: CrewFilter = .mine

    private let roster: [CrewMember] = [
        CrewMember(id: "u-1", fullName: "Jason Wagner", shortLabel: "JASON W"),
        CrewMember(id: "u-2", fullName: "Dana Whitfield", shortLabel: "DANA W")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Rest — both controls at their defaults.
            HStack(spacing: OPSStyle.Layout.spacing2) {
                LeadsSortChip(sort: $restingSort)
                LeadsCrewChip(crew: $restingCrew, roster: roster)
            }
            // Non-default — active treatment on both.
            HStack(spacing: OPSStyle.Layout.spacing2) {
                LeadsSortChip(sort: $activeSort)
                LeadsCrewChip(crew: $activeCrew, roster: roster)
            }
            // Solo operator — the crew chip is absent entirely (gate closed).
            HStack(spacing: OPSStyle.Layout.spacing2) {
                LeadsSortChip(sort: $restingSort)
            }
        }
        .padding(OPSStyle.Layout.spacing3_5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OPSStyle.Colors.background)
    }
}

#Preview("LeadsControlChips / rest · active · solo") {
    LeadsControlChipsPreviewHost()
        .preferredColorScheme(.dark)
}
#endif
