//
//  TacticalFilterChips.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — the shared single-select filter chip
//  row used by the Money ledger band and the Leads triage queue. A chip reads
//  `LABEL · N`; when active it tints to its semantic tone (rose/tan/olive/steel)
//  or to neutral white when toneless. Horizontal scroll, 36pt chip target
//  (MOBILE.md §4.3 — the one sanctioned sub-44pt control).
//

import SwiftUI

struct TacticalChip: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int
    var tone: Color? = nil   // nil → neutral white active state

    static func == (lhs: TacticalChip, rhs: TacticalChip) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.count == rhs.count
    }
}

struct TacticalChipRow: View {
    let chips: [TacticalChip]
    @Binding var selectedId: String
    /// When true, a chip with a zero count dims and ignores taps.
    var disablesEmpty: Bool = false
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(chips) { chip in
                    chipView(chip)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    @ViewBuilder
    private func chipView(_ chip: TacticalChip) -> some View {
        let isActive = chip.id == selectedId
        let isEmpty = disablesEmpty && chip.count == 0
        let tone = chip.tone ?? OPSStyle.Colors.text

        Button {
            guard !isEmpty else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedId = chip.id
            onSelect?(chip.id)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1 + 2) {
                Text(chip.label)
                Text("·").foregroundColor(isActive ? tone.opacity(0.7) : OPSStyle.Colors.textMute)
                Text("\(chip.count)").monospacedDigit()
            }
            .font(OPSStyle.Typography.miniLabelBold)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundColor(isActive ? tone : OPSStyle.Colors.text3)
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .frame(height: OPSStyle.Layout.chipMinHeight)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous)
                    .fill(isActive ? tone.opacity(chip.tone == nil ? 0.10 : 0.12) : OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous)
                    .strokeBorder(isActive ? tone.opacity(chip.tone == nil ? 0.20 : 0.40) : OPSStyle.Colors.line, lineWidth: 1)
            )
            .opacity(isEmpty ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .accessibilityLabel("\(chip.label), \(chip.count)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
