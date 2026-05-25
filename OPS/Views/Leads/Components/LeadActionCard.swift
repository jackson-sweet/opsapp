//
//  LeadActionCard.swift
//  OPS
//
//  Per-lead row in the triage queue. Renders as its own L1 glass mini-card —
//  cards stack with 8pt gaps so the eye can chunk them. Three rows inside:
//
//    Row 1 :  VERB · LEAD NAME                                        $VALUE
//    Row 2 :  job description                              STAGE · NN D
//    Row 3 :  ⏱ DUE CHIP                              [LOG] [···] [→ ADVANCE]
//
//  - Verb is mono 9.5pt, weight 600, semantic tone (rose / tan / steel /
//    neutral). Tone maps to the row's urgency bucket.
//  - Quick glyphs are 34×34pt visual squares with 44×44pt hit areas. ADVANCE gets emphasis
//    (0.06 bg + 0.10 hairline); LOG and MORE are flat.
//  - Tap on card body → open LeadDetailView.
//  - Light haptic on body tap; medium on advance; success on won (driven
//    by sticky action bar, not this row).
//

import SwiftUI

struct LeadActionCard: View {
    let opportunity: Opportunity
    let verb: String
    let tone: PipelineViewModel.UrgencyTone

    var showsLog: Bool = true
    var showsMore: Bool = true
    var showsAdvance: Bool = true
    var onTap:     () -> Void = {}
    var onLog:     () -> Void = {}
    var onMore:    () -> Void = {}
    var onAdvance: () -> Void = {}

    private var toneColor: Color {
        switch tone {
        case .rose:    return OPSStyle.Colors.roseTextM
        case .tan:     return OPSStyle.Colors.tanTextM
        case .steel:   return OPSStyle.Colors.opsAccent
        case .neutral: return OPSStyle.Colors.text2
        }
    }

    private var displayTitle: String {
        if let t = opportunity.title, !t.isEmpty { return t }
        if !opportunity.contactName.isEmpty      { return opportunity.contactName }
        return "Unnamed lead"
    }

    private var displayName: String {
        // Row 1 leads with the contact name; title goes to row 2.
        // Falls back to "Unnamed lead" if contact name is missing.
        opportunity.contactName.isEmpty ? "Unnamed lead" : opportunity.contactName
    }

    private var valueText: String? {
        guard let v = opportunity.estimatedValue, v > 0 else { return nil }
        if v >= 1_000_000 { return "$\((v / 1_000_000).formatted(.number.precision(.fractionLength(1))))M" }
        if v >= 10_000    { return "$\(Int(v / 1_000))K" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v))
    }

    private var dueText: String? {
        guard let due = opportunity.nextFollowUpAt else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: due)).day ?? 0
        if days < 0  { return "\(-days)D OVERDUE" }
        if days == 0 { return "TODAY" }
        if days == 1 { return "TOMORROW" }
        return "IN \(days)D"
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 6) {
                row1
                row2
                row3
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Rows

    private var row1: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verb)
                .font(.custom("JetBrainsMono-Regular", size: 9.5))
                .fontWeight(.semibold)
                .kerning(1.4)
                .foregroundColor(toneColor)
                .textCase(.uppercase)

            Text(displayName)
                .font(.custom("Mohave-Medium", size: 15))
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let valueText {
                Text(valueText)
                    .font(.custom("JetBrainsMono-Regular", size: 12.5))
                    .foregroundColor(OPSStyle.Colors.text)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.custom("JetBrainsMono-Regular", size: 12.5))
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
        }
    }

    private var row2: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(displayTitle)
                .font(.custom("Mohave-Regular", size: 13.5))
                .foregroundColor(OPSStyle.Colors.text3)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(opportunity.stage.shortLabel) · \(opportunity.daysInStage)D")
                .font(.custom("JetBrainsMono-Regular", size: 9.5))
                .foregroundColor(OPSStyle.Colors.textMute)
                .kerning(0.8)
                .textCase(.uppercase)
        }
    }

    private var row3: some View {
        HStack(spacing: 10) {
            if let dueText {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .regular))
                    Text(dueText)
                        .font(.custom("JetBrainsMono-Regular", size: 9.5))
                        .fontWeight(.semibold)
                        .kerning(1.4)
                        .textCase(.uppercase)
                }
                .foregroundColor(toneColor)
            } else if opportunity.source == "referral" {
                Text("REFERRAL")
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .fontWeight(.semibold)
                    .kerning(1.4)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .textCase(.uppercase)
            }

            Spacer(minLength: 0)

            if showsLog || showsMore || showsAdvance {
                HStack(spacing: 4) {
                    if showsLog {
                        QuickGlyph(icon: "note.text", label: "LOG", emphasis: false, action: onLog)
                    }
                    if showsMore {
                        QuickGlyph(icon: "ellipsis", label: "MORE", emphasis: false, action: onMore)
                    }
                    if showsAdvance {
                        QuickGlyph(icon: "arrow.right", label: "ADVANCE", emphasis: true, action: onAdvance)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts: [String] = [verb, displayName, opportunity.stage.displayName]
        if let v = valueText { parts.append(v) }
        if let d = dueText   { parts.append(d) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Quick glyph button

struct QuickGlyph: View {
    let icon: String
    let label: String
    var emphasis: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: emphasis ? .medium : .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(emphasis ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(emphasis ? OPSStyle.Colors.fillNeutralDim : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(emphasis ? OPSStyle.Colors.line : .clear, lineWidth: 1)
                )
                // 34pt visible chip · 44pt hit area — MOBILE.md §1 / audit F1.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - PipelineStage short label helper
//
// `displayName` is the full uppercase name ("NEW LEAD", "QUALIFYING", …).
// Triage rows need a compact 4–7 char variant for the row-2 right caption.
// Kept here as an internal helper to avoid editing the enum file in this phase;
// can be promoted into PipelineStage in Phase 6 cleanup.

extension PipelineStage {
    var shortLabel: String {
        switch self {
        case .newLead:     return "NEW"
        case .qualifying:  return "QUAL"
        case .quoting:     return "QUOTING"
        case .quoted:      return "QUOTED"
        case .followUp:    return "FOLLOW"
        case .negotiation: return "NEGOT"
        case .won:         return "WON"
        case .lost:        return "LOST"
        }
    }
}

#if DEBUG
#Preview("LeadActionCard / states") {
    ScrollView {
        VStack(spacing: 8) {
            LeadActionCard(
                opportunity: .preview(
                    title: "Roof tear-off — 28 sq",
                    contactName: "Helen Calloway",
                    stage: .quoted,
                    estimatedValue: 14_200,
                    daysInStage: 9,
                    lastActivityDaysAgo: 4,
                    nextFollowUpDaysFromNow: -2
                ),
                verb: "CHASE QUOTE",
                tone: .rose
            )
            LeadActionCard(
                opportunity: .preview(
                    title: "Skylight install + flashing",
                    contactName: "Joel Lioudakis",
                    stage: .quoted,
                    estimatedValue: 6_200,
                    daysInStage: 4,
                    lastActivityDaysAgo: 2,
                    nextFollowUpDaysFromNow: 0
                ),
                verb: "CONFIRM",
                tone: .tan
            )
            LeadActionCard(
                opportunity: .preview(
                    title: "Commercial flat roof — phase 2",
                    contactName: "Verity Projects",
                    stage: .qualifying,
                    estimatedValue: 86_000,
                    daysInStage: 3,
                    lastActivityDaysAgo: 0
                ),
                verb: "QUALIFY",
                tone: .steel
            )
            LeadActionCard(
                opportunity: .preview(
                    title: "Single skylight, garage",
                    contactName: "Aimee Watari",
                    stage: .newLead,
                    estimatedValue: 1_800,
                    daysInStage: 0,
                    nextFollowUpDaysFromNow: 1
                ),
                verb: "TRIAGE",
                tone: .neutral
            )
            LeadActionCard(
                opportunity: .preview(
                    title: "Storm-damage assessment",
                    contactName: "Trevor Akinola",
                    stage: .quoted,
                    estimatedValue: 4_400,
                    daysInStage: 5,
                    lastActivityDaysAgo: 3,
                    nextFollowUpDaysFromNow: 4
                ),
                verb: "CHECK IN",
                tone: .neutral
            )
        }
        .padding(20)
    }
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
