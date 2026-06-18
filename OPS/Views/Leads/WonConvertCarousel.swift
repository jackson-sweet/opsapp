//
//  WonConvertCarousel.swift
//  OPS
//
//  Horizontal paged carousel of won-but-not-yet-converted leads. Surfaces
//  between the hero widget and the queue chip filter whenever there are
//  open conversion prompts. Each card:
//
//    ┌──────────────────────────────────────────────┐
//    │ [✓] // WON · $14,200 · CONVERT TO PROJECT     │
//    │     Helen Calloway                            │
//    │     Roof tear-off — 28 sq                     │
//    │                                               │
//    │ [ CONVERT → PROJECT ]   [ LATER ]             │
//    └──────────────────────────────────────────────┘
//
//  Per plan §2.1 decision Q6 = (carousel of all unconverted wins).
//  - Page indicator: up to 5 dots (per MOBILE.md § Hero Carousel) — 6pt
//    active (text-3), 4pt inactive (white @ 0.18). Past 5 wins it collapses
//    to a compact `NN / NN` tabular counter (JetBrains Mono) so a long
//    backlog reads as absolute position AND the row can never out-grow the
//    screen. (An uncapped 48-dot row was dragging the shared LEADS column
//    off both edges.)
//  - No accent on the dots or counter.
//  - Light haptic on page snap.
//

import SwiftUI

struct WonConvertCarousel: View {
    let leads: [Opportunity]
    var onConvert: (Opportunity) -> Void = { _ in }
    var onLater:   (Opportunity) -> Void = { _ in }

    @State private var selected: Int = 0

    var body: some View {
        if leads.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 10) {
                TabView(selection: $selected) {
                    ForEach(Array(leads.enumerated()), id: \.element.id) { index, lead in
                        WonConvertCard(
                            lead: lead,
                            onConvert: { onConvert(lead) },
                            onLater:   { onLater(lead) }
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity)
                .frame(height: cardHeight)

                if leads.count > 1 {
                    pageIndicator
                }
            }
            .frame(maxWidth: .infinity)
            .onChange(of: selected) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .onAppear(perform: clampSelection)
            .onChange(of: leadIDs) { _, _ in
                clampSelection()
            }
        }
    }

    /// Cards size themselves; the carousel needs a frame for paging to work.
    /// 152pt accommodates the largest variant (eyebrow + name + title + 2 buttons).
    private var cardHeight: CGFloat { 152 }

    private var leadIDs: [String] {
        leads.map(\.id)
    }

    private func clampSelection() {
        if leads.isEmpty {
            selected = 0
        } else if selected >= leads.count {
            selected = leads.count - 1
        }
    }

    /// Past this many wins the dot row stops being glanceable and starts
    /// out-growing the screen, so we switch to a numeric counter. 5 matches
    /// MOBILE.md § Hero Carousel ("Max 5 dots visible").
    private var maxIndicatorDots: Int { 5 }

    /// 1-based position, clamped — guards the brief window after a lead is
    /// removed and before `clampSelection` runs.
    private var currentPosition: Int { min(max(selected, 0), leads.count - 1) + 1 }

    @ViewBuilder
    private var pageIndicator: some View {
        if leads.count <= maxIndicatorDots {
            dots
        } else {
            positionCounter
        }
    }

    private var dots: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(0..<leads.count, id: \.self) { i in
                Circle()
                    .fill(i == selected ? OPSStyle.Colors.text3 : Color.white.opacity(0.18))  // no exact token
                    .frame(width: i == selected ? 6 : 4, height: i == selected ? 6 : 4)
            }
        }
        .accessibilityHidden(true)
    }

    /// Compact `NN / NN` readout for large backlogs. JetBrains Mono, tabular,
    /// two-digit zero-pad. Current position carries the brighter `text3` (the
    /// active-dot ink); the total dims to `textMute`, echoing the dot
    /// active/inactive contrast. Fixed width — never bleeds the column.
    private var positionCounter: some View {
        HStack(spacing: 0) {
            Text(String(format: "%02d", currentPosition))
                .foregroundColor(OPSStyle.Colors.text3)
            Text(" / \(String(format: "%02d", leads.count))")
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .font(OPSStyle.Typography.metadata.monospacedDigit())
        .accessibilityHidden(true)
    }
}

// MARK: - Individual card

struct WonConvertCard: View {
    let lead: Opportunity
    let onConvert: () -> Void
    let onLater:   () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2_5) {
                wonBadge
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    eyebrow
                    Text(lead.displayContactName)
                        .font(.custom("Mohave-Medium", size: 15))
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)
                    if let title = lead.title, !title.isEmpty {
                        Text(title)
                            .font(.custom("Mohave-Regular", size: 13))
                            .foregroundColor(OPSStyle.Colors.text3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            // Read the card header as one element; CONVERT / LATER remain
            // separate focusable buttons below. (review W-4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Won lead, \(lead.displayContactName), ready to convert to a project")

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onConvert()
                }) {
                    Text("CONVERT → PROJECT")
                        .font(OPSStyle.Typography.buttonLabel)
                        .kerning(0.6)
                        .foregroundColor(OPSStyle.Colors.opsAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .strokeBorder(OPSStyle.Colors.opsAccent, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Convert to project")

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onLater()
                }) {
                    Text("LATER")
                        .font(OPSStyle.Typography.buttonLabel)
                        .kerning(0.6)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .frame(minWidth: 84, minHeight: 44)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("View later")
            }
            .padding(.top, 14)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    private var wonBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(OPSStyle.Colors.oliveTextM)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                    .fill(OPSStyle.Colors.oliveFillM)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.oliveLineM, lineWidth: 1)
            )
    }

    private var eyebrow: some View {
        let valueText: String = {
            guard let v = lead.estimatedValue, v > 0 else { return "—" }
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = "USD"
            f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: v)) ?? "$0"
        }()
        return HStack(spacing: 0) {
            Text("// ")
                .foregroundColor(OPSStyle.Colors.textMute)
            Text("WON · \(valueText) · CONVERT TO PROJECT")
                .foregroundColor(OPSStyle.Colors.oliveTextM)
        }
        .font(OPSStyle.Typography.metadata)
        .kerning(1.4)
        .textCase(.uppercase)
    }
}

#if DEBUG
#Preview("WonConvertCarousel / 3 leads") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack {
            Spacer()
            WonConvertCarousel(
                leads: [
                    .preview(title: "Tear-off + reshingle, 28 sq",
                             contactName: "Calloway Roofing",
                             stage: .won, estimatedValue: 4_820,
                             daysInStage: 1, actualCloseDaysAgo: 1),
                    .preview(title: "Gutter + downspout",
                             contactName: "Martinez Family",
                             stage: .won, estimatedValue: 680,
                             daysInStage: 8, actualCloseDaysAgo: 8),
                    .preview(title: "Insurance claim re-roof",
                             contactName: "Vellmer Estate",
                             stage: .won, estimatedValue: 22_400,
                             daysInStage: 3, actualCloseDaysAgo: 3),
                ]
            )
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("WonConvertCarousel / single") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        WonConvertCarousel(
            leads: [
                .preview(title: "Tear-off + reshingle, 28 sq",
                         contactName: "Calloway Roofing",
                         stage: .won, estimatedValue: 4_820,
                         daysInStage: 1, actualCloseDaysAgo: 1)
            ]
        )
    }
    .preferredColorScheme(.dark)
}

// Reproduces the Canpro Deck & Rail case: 48 won-unconverted leads. Before the
// indicator cap, the 48-dot row forced the carousel ~620pt wide, dragging the
// whole shared LEADS column off both edges. The faux "LEADS" title sits in the
// same leading-aligned column the real tab uses — if the carousel widened the
// column the title would bleed too. Post-fix: the counter stays put, the title
// holds its 20pt margin, nothing exceeds the screen.
#Preview("WonConvertCarousel / 48 leads (overflow guard)") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("LEADS")
                    .font(OPSStyle.Typography.pageTitle)
                    .foregroundColor(OPSStyle.Colors.text)
                    .padding(.horizontal, 20)

                WonConvertCarousel(
                    leads: (1...48).map { i in
                        Opportunity.preview(
                            title: "Roof job #\(i)",
                            contactName: "Customer \(i)",
                            stage: .won,
                            estimatedValue: Double(2_000 + i * 250),
                            daysInStage: (i % 14) + 1,
                            actualCloseDaysAgo: (i % 14) + 1
                        )
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 40)
        }
    }
    .preferredColorScheme(.dark)
}
#endif
