//
//  FilterChipRow.swift
//  OPS
//
//  Horizontal single-select chip strip. The workhorse of triage and any future
//  list-filter surface. Per ops-design-system mobile/MOBILE.md § 4.3 (filter
//  chips) and § 4.1 (segmented control inactive/active treatment):
//
//      [● label · NN]  [● label · NN]  [● label · NN]
//
//  - 4pt earth-tone dot (semantic; never accent unless the chip's id
//    explicitly maps to the accent — none currently do)
//  - JetBrains Mono 10pt 600-weight label, 14% tracking, uppercase
//  - 10pt mono count, two-digit zero-padded
//  - Inactive : 0.04 white bg + 0.10 hairline
//  - Active   : 0.10 white bg + 0.20 hairline (no accent — per spec)
//  - Disabled (count == 0) : 35% opacity, non-tappable
//
//  Single-select. Tap fires a light haptic and onSelect. Horizontal scroll is
//  edge-to-edge with `--m-canvas-x` (20pt) leading and trailing padding.
//

import SwiftUI

/// One row in the strip. `id` is the canonical key (e.g. urgency bucket key).
struct FilterChipModel: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int
    let dotColor: Color

    /// True when count == 0 — chip renders at 35% opacity and is non-tappable.
    var isDisabled: Bool { count == 0 }
}

struct FilterChipRow: View {
    @Binding var selectedId: String
    let chips: [FilterChipModel]

    /// Light haptic fires on a successful select. Override to suppress.
    var fireHaptic: Bool = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips) { chip in
                    chipButton(chip)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func chipButton(_ chip: FilterChipModel) -> some View {
        let isActive = chip.id == selectedId
        Button {
            guard !chip.isDisabled, chip.id != selectedId else { return }
            if fireHaptic {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            selectedId = chip.id
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(chip.dotColor)
                    .frame(width: 5, height: 5)
                Text(chip.label)
                    .font(OPSStyle.Typography.metadata)
                    .fontWeight(.semibold)
                    .kerning(1.4)
                    .foregroundColor(isActive ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
                    .textCase(.uppercase)
                Text(String(format: "%02d", chip.count))
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(isActive ? OPSStyle.Colors.text2 : OPSStyle.Colors.textMute)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.white.opacity(0.20) : OPSStyle.Colors.line,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(chip.isDisabled ? 0.35 : 1)
        .allowsHitTesting(!chip.isDisabled)
        .accessibilityLabel("\(chip.label), \(chip.count) leads")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

#if DEBUG
private struct FilterChipRowPreviewHost: View {
    @State private var selected: String = "overdue"

    private let chips: [FilterChipModel] = [
        .init(id: "all",           label: "ALL",       count: 16, dotColor: OPSStyle.Colors.text),
        .init(id: "overdue",       label: "OVERDUE",   count: 4,  dotColor: OPSStyle.Colors.rose),
        .init(id: "dueToday",      label: "DUE TODAY", count: 3,  dotColor: OPSStyle.Colors.tan),
        .init(id: "waitingOnYou",  label: "REPLY DUE", count: 3,  dotColor: OPSStyle.Colors.opsAccent),
        .init(id: "fresh",         label: "NEW",       count: 3,  dotColor: OPSStyle.Colors.text2),
        .init(id: "waitingOnThem", label: "WAITING",   count: 0,  dotColor: OPSStyle.Colors.textMute),
    ]

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Text("Selected: \(selected)")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .padding(.horizontal, 20)
                FilterChipRow(selectedId: $selected, chips: chips)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("FilterChipRow") {
    FilterChipRowPreviewHost()
}
#endif
