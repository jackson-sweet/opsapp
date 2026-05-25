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
//  - Page-indicator dots: 6pt active (text-3), 4pt inactive (0.15 white)
//  - No accent on the dots.
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
                        .padding(.horizontal, 20)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: cardHeight)

                if leads.count > 1 {
                    dots
                }
            }
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

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<leads.count, id: \.self) { i in
                Circle()
                    .fill(i == selected ? OPSStyle.Colors.text3 : Color.white.opacity(0.18))  // no exact token
                    .frame(width: i == selected ? 6 : 4, height: i == selected ? 6 : 4)
            }
        }
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
            HStack(alignment: .top, spacing: 12) {
                wonBadge
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow
                    Text(lead.contactName.isEmpty ? "Unnamed lead" : lead.contactName)
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

            HStack(spacing: 8) {
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
#endif
