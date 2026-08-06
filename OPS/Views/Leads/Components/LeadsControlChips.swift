//
//  LeadsControlChips.swift
//  OPS
//
//  The LEADS console's ONE filter control (console redesign 2026-08-05 §5.2 /
//  §5.3, reworked by the round-2 addendum §15.1). Round 1 put two menu chips —
//  SORT and CREW — beside the search field. Round 2 collapses them into a
//  single trailing control so the field is genuinely full-width in the common
//  case, which is the case that matters: the operator opens LEADS to find
//  somebody, not to reorder a queue that already opens in urgency order.
//
//  At rest the control is a glyph and nothing else. The moment anything is set
//  it names the slice inline — `NEWEST`, `DANA W`, `NEWEST · DANA W` — so the
//  console's state is readable without opening the menu. That is the whole
//  bargain of hiding two controls behind one: the door has to say what is
//  behind it.
//
//  Anatomy is the shipped chip grammar at the search field's 40pt height:
//  `miniLabelBold` at 0.8 tracking, `sidebarHoverRadius`, `text3` on
//  `surfaceInput` at rest, and — holding any NON-DEFAULT value — `text` on a
//  0.10 white fill with a 0.20 white hairline. No accent, ever (DESIGN.md: the
//  accent is the primary CTA and the focus ring, nothing else).
//
//  `Menu` hosts the control; the visible face is fully custom (stock picker /
//  menu styling is banned on this codebase).
//

import SwiftUI

struct LeadsFilterControl: View {
    @Binding var sort: LeadSort
    @Binding var crew: CrewFilter
    let roster: [CrewMember]
    /// Counts for the crew rows, resolved once by the console over every open
    /// lead (addendum §15.2) — never recomputed per row.
    let counts: LeadsCrewCounts
    /// Closed for a solo operator: one nameable operator means assignment
    /// carries no information, so the menu is sort-only and the control still
    /// reads `NEWEST` when the queue is reordered.
    let showsCrew: Bool

    /// Matches `LeadsSearchBar.fieldHeight` — the two controls share a row and
    /// a mismatched pair would read as two systems.
    private static let controlHeight: CGFloat = 40

    var body: some View {
        Menu {
            Section("SORT") {
                ForEach(LeadSort.allCases, id: \.self) { option in
                    Button {
                        select(sort: option)
                    } label: {
                        LeadsControlMenuRow(title: Self.label(for: option),
                                            isCurrent: option == sort)
                    }
                }
            }

            if showsCrew {
                Section("CREW") {
                    Button { select(crew: .all) } label: {
                        LeadsControlMenuRow(title: "ALL CREW · \(counts.all)",
                                            isCurrent: crew == .all)
                    }
                    Button { select(crew: .mine) } label: {
                        LeadsControlMenuRow(title: "MINE · \(counts.mine)",
                                            isCurrent: crew == .mine)
                    }
                    Button { select(crew: .unassigned) } label: {
                        LeadsControlMenuRow(title: "UNASSIGNED · \(counts.unassigned)",
                                            isCurrent: crew == .unassigned)
                    }
                    ForEach(roster) { member in
                        Button { select(crew: .member(member.id)) } label: {
                            LeadsControlMenuRow(
                                title: "\(member.shortLabel) · \(count(for: member))",
                                isCurrent: crew == .member(member.id)
                            )
                        }
                    }
                }
            }
        } label: {
            face
        }
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Face

    private var face: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(isActive ? OPSStyle.Colors.text : OPSStyle.Colors.text3)

            if let activeLabel {
                Text(activeLabel)
                    .font(OPSStyle.Typography.miniLabelBold)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        // At rest the control is square — the glyph alone, centred in a box the
        // width of its own height, so the field owns everything else.
        .padding(.horizontal, activeLabel == nil ? 0 : OPSStyle.Layout.spacing2_5)
        .frame(minWidth: Self.controlHeight)
        .frame(height: Self.controlHeight)
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
        // The visual control is 40pt; the target is the sanctioned 44pt floor.
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .contentShape(Rectangle())
        // The field yields width to the control, not the other way round: a
        // control that truncated its own state while a mostly-empty field sat
        // beside it would hide the thing it exists to say.
        .layoutPriority(1)
    }

    // MARK: State

    /// URGENCY / ALL CREW is the console's answer to "what needs me" — holding
    /// it is not a filter, so the control stays at rest until the operator
    /// deliberately reorders or narrows the queue.
    private var isActive: Bool { activeLabel != nil }

    /// The active selections, joined — `NEWEST`, `DANA W`, `NEWEST · DANA W`.
    /// nil when nothing is set, which is what puts the control at rest.
    private var activeLabel: String? {
        var parts: [String] = []
        if sort != .urgency { parts.append(Self.label(for: sort)) }
        if showsCrew, let crewLabel { parts.append(crewLabel) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// nil for ALL CREW — the default names no slice. A member the roster can
    /// no longer resolve also reads as nothing rather than a stale name.
    private var crewLabel: String? {
        switch crew {
        case .all:        return nil
        case .mine:       return "MINE"
        case .unassigned: return "UNASSIGNED"
        case .member(let id):
            return roster.first(where: { $0.id == id })?.shortLabel
        }
    }

    private var accessibilityLabel: String {
        guard let activeLabel else { return "Filter and sort" }
        return "Filter and sort, currently \(activeLabel.lowercased())"
    }

    private func count(for member: CrewMember) -> Int {
        counts.byMember[member.id.lowercased()] ?? 0
    }

    // MARK: Selection

    private func select(sort option: LeadSort) {
        guard option != sort else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        sort = option
    }

    private func select(crew option: CrewFilter) {
        guard option != crew else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        crew = option
    }

    static func label(for sort: LeadSort) -> String {
        switch sort {
        case .urgency: return "URGENCY"
        case .newest:  return "NEWEST"
        case .value:   return "VALUE"
        }
    }
}

// MARK: - Menu row

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
private struct LeadsFilterControlPreviewHost: View {
    @State private var restingSort: LeadSort = .urgency
    @State private var restingCrew: CrewFilter = .all
    @State private var sortedSort: LeadSort = .newest
    @State private var bothSort: LeadSort = .newest
    @State private var bothCrew: CrewFilter = .member("u-2")

    private let roster: [CrewMember] = [
        CrewMember(id: "u-1", fullName: "Jason Wagner", shortLabel: "JASON W"),
        CrewMember(id: "u-2", fullName: "Dana Whitfield", shortLabel: "DANA W")
    ]

    private let counts = LeadsCrewCounts(
        all: 12, mine: 4, unassigned: 2, byMember: ["u-1": 4, "u-2": 5]
    )

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Rest — glyph only, and the field beside it is full-width.
            LeadsFilterControl(sort: $restingSort, crew: $restingCrew,
                               roster: roster, counts: counts, showsCrew: true)
            // Sorted only.
            LeadsFilterControl(sort: $sortedSort, crew: $restingCrew,
                               roster: roster, counts: counts, showsCrew: true)
            // Sorted AND filtered — the addendum's `NEWEST · DANA W`.
            LeadsFilterControl(sort: $bothSort, crew: $bothCrew,
                               roster: roster, counts: counts, showsCrew: true)
            // Solo operator — sort-only menu, and the crew half never renders.
            LeadsFilterControl(sort: $restingSort, crew: $restingCrew,
                               roster: [], counts: counts, showsCrew: false)
        }
        .padding(OPSStyle.Layout.spacing3_5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OPSStyle.Colors.background)
    }
}

#Preview("LeadsFilterControl / rest · sorted · both · solo") {
    LeadsFilterControlPreviewHost()
        .preferredColorScheme(.dark)
}
#endif
