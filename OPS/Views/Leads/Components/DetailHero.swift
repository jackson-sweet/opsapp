//
//  DetailHero.swift
//  OPS
//
//  Top hero block on LeadDetailView — surfaces the deal's identity, stage,
//  and the three numbers a roofing/trades operator decides off (value,
//  weighted, source) without any taps or scrolling.
//
//  Composition (top to bottom, no decorative chrome):
//
//      // L-XXXXXX                               9D IN STAGE
//      [STAGE TAG]   60% WIN PROB
//      Helen Calloway                           ← Cake Mono Light 30
//      Roof tear-off, 28 sq                     ← Mohave Regular 14, text2
//      ┌──────────┬──────────┬──────────┐
//      │ VALUE    │ WEIGHTED │ SOURCE   │      ← L2 nested card, 3 cols
//      │ $14.2K   │ $8.5K    │ MANUAL   │
//      │ ESTIMATED│ @ 60%    │ LEAD ·…  │
//      └──────────┴──────────┴──────────┘
//
//  All values trace to OPSStyle tokens. Stage tag uses the mobile-contrast
//  earth-tone variants (-M) per ops-design-system/project/mobile/MOBILE.md §1.
//

import SwiftUI

struct DetailHero: View {
    let opportunity: Opportunity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            idRow
                .padding(.bottom, 10)

            stageRow
                .padding(.bottom, 12)

            // Hero name — falls back to title if contactName is missing,
            // then to "Unnamed lead". The detail view never renders blank.
            Text(displayName)
                .font(OPSStyle.Typography.display)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let title = opportunity.title, !title.isEmpty {
                Text(title)
                    .font(.custom("Mohave-Regular", size: 14))
                    .foregroundColor(OPSStyle.Colors.text2)
                    .lineLimit(2)
                    .padding(.top, 6)
            }

            kpiStrip
                .padding(.top, 18)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 18)
    }

    // MARK: - ID + days-in-stage row

    private var idRow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(displayId)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .monospacedDigit()
            }
            .font(.custom("JetBrainsMono-Regular", size: 10))
            .kerning(1.4)
            .textCase(.uppercase)

            Spacer(minLength: 12)

            Text("\(opportunity.daysInStage)D IN STAGE")
                .font(.custom("JetBrainsMono-Regular", size: 9.5))
                .kerning(1.3)
                .foregroundColor(OPSStyle.Colors.textMute)
                .textCase(.uppercase)
                .monospacedDigit()
        }
    }

    // MARK: - Stage tag + win prob

    private var stageRow: some View {
        HStack(spacing: 10) {
            StageTag(stage: opportunity.stage)

            Text("\(winProbability)% WIN PROB")
                .font(.custom("JetBrainsMono-Regular", size: 9.5))
                .kerning(1.3)
                .foregroundColor(OPSStyle.Colors.text3)
                .textCase(.uppercase)
                .monospacedDigit()
        }
    }

    // MARK: - 3-col KPI strip

    private var kpiStrip: some View {
        HStack(spacing: 0) {
            KvCell(
                label: "VALUE",
                value: estimatedValue.map(Self.formatMoneyCompact) ?? "—",
                sub: "ESTIMATED",
                useMono: false
            )

            KpiDivider()

            KvCell(
                label: "WEIGHTED",
                value: estimatedValue.map { _ in Self.formatMoneyCompact(opportunity.weightedValue) } ?? "—",
                sub: "@ \(winProbability)%",
                useMono: false
            )

            KpiDivider()

            KvCell(
                label: "SOURCE",
                value: formattedSource,
                sub: "LEAD · \(displayIdShort)",
                useMono: true
            )
        }
        .nestedCard()
    }

    // MARK: - Derived

    private var displayName: String {
        if !opportunity.contactName.isEmpty { return opportunity.contactName }
        if let title = opportunity.title, !title.isEmpty { return title }
        return "Unnamed lead"
    }

    /// "L-AB12CD" — last 6 chars of the UUID, uppercased, with an "L-" prefix
    /// so the operator scanning the screen reads it as a lead identifier.
    private var displayId: String {
        "L-\(displayIdShort)"
    }

    private var displayIdShort: String {
        let raw = opportunity.id.replacingOccurrences(of: "-", with: "")
        return String(raw.suffix(6)).uppercased()
    }

    private var estimatedValue: Double? {
        guard let v = opportunity.estimatedValue, v > 0 else { return nil }
        return v
    }

    private var winProbability: Int {
        opportunity.winProbabilityOverride ?? opportunity.stage.winProbability
    }

    private var formattedSource: String {
        guard let s = opportunity.source, !s.isEmpty else { return "—" }
        return s.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private static func formatMoneyCompact(_ v: Double) -> String {
        if v >= 1_000_000 {
            return "$\((v / 1_000_000).formatted(.number.precision(.fractionLength(1))))M"
        }
        if v >= 10_000 {
            return "$\(Int(v / 1_000))K"
        }
        if v >= 1_000 {
            return "$\((v / 1_000).formatted(.number.precision(.fractionLength(1))))K"
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - StageTag (private)

/// The earth-tone stage chip rendered in the hero. Uses mobile-contrast
/// `-M` token variants for outdoor glare per MOBILE.md §1. Tone selection
/// follows the LEADS Phase 3 spec:
///
///   - .won                                   → olive
///   - .lost                                  → rose
///   - .quoted / .followUp / .negotiation     → tan
///   - .newLead / .qualifying / .quoting      → neutral
///
private struct StageTag: View {
    let stage: PipelineStage

    var body: some View {
        Text(stage.displayName)
            .font(.custom("JetBrainsMono-Regular", size: 9.5))
            .fontWeight(.semibold)
            .kerning(1.4)
            .foregroundColor(textColor)
            .textCase(.uppercase)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }

    private var fillColor: Color {
        switch stage {
        case .won:                                   return OPSStyle.Colors.oliveFillM
        case .lost:                                  return OPSStyle.Colors.roseFillM
        case .quoted, .followUp, .negotiation:       return OPSStyle.Colors.tanFillM
        case .newLead, .qualifying, .quoting:        return OPSStyle.Colors.surfaceHover
        }
    }

    private var borderColor: Color {
        switch stage {
        case .won:                                   return OPSStyle.Colors.oliveLineM
        case .lost:                                  return OPSStyle.Colors.roseLineM
        case .quoted, .followUp, .negotiation:       return OPSStyle.Colors.tanLineM
        case .newLead, .qualifying, .quoting:        return OPSStyle.Colors.line
        }
    }

    private var textColor: Color {
        switch stage {
        case .won:                                   return OPSStyle.Colors.oliveTextM
        case .lost:                                  return OPSStyle.Colors.roseTextM
        case .quoted, .followUp, .negotiation:       return OPSStyle.Colors.tanTextM
        case .newLead, .qualifying, .quoting:        return OPSStyle.Colors.text2
        }
    }
}

// MARK: - KvCell (private)

/// One column in the hero's KPI strip. Three lines:
///   - LABEL  : JBM Mono 9pt 600, kerning 1.26, text3, uppercase
///   - VALUE  : Mohave Light 18pt (non-mono) OR JBM Mono Medium 13pt (mono mode)
///   - SUB    : JBM Mono 8.5pt 600, kerning 1.02, textMute, uppercase
///
/// `useMono` switches the value to monospaced 13pt — used for SOURCE which
/// reads as an enum-y label rather than a numeric value.
private struct KvCell: View {
    let label: String
    let value: String
    let sub: String
    var useMono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.custom("JetBrainsMono-Regular", size: 9))
                .fontWeight(.semibold)
                .kerning(1.26)
                .foregroundColor(OPSStyle.Colors.text3)
                .textCase(.uppercase)

            if useMono {
                Text(value)
                    .font(.custom("JetBrainsMono-Medium", size: 13))
                    .foregroundColor(OPSStyle.Colors.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(value)
                    .font(.custom("Mohave-Light", size: 18))
                    .foregroundColor(OPSStyle.Colors.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(sub)
                .font(.custom("JetBrainsMono-Regular", size: 8.5))
                .fontWeight(.semibold)
                .kerning(1.02)
                .foregroundColor(OPSStyle.Colors.textMute)
                .textCase(.uppercase)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 1pt vertical hairline between KPI cells. 6% white per prototype.
private struct KpiDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("DetailHero / states") {
    ScrollView {
        VStack(spacing: 24) {
            DetailHero(opportunity: .preview(
                title: "Roof tear-off, 28 sq",
                contactName: "Helen Calloway",
                stage: .quoted,
                estimatedValue: 14_200,
                daysInStage: 9
            ))

            DetailHero(opportunity: .preview(
                title: "Storm damage assessment",
                contactName: "Trevor Akinola",
                stage: .negotiation,
                estimatedValue: 86_500,
                daysInStage: 3
            ))

            DetailHero(opportunity: .preview(
                title: "Single skylight install",
                contactName: "Aimee Watari",
                stage: .newLead,
                estimatedValue: nil,
                daysInStage: 0
            ))

            DetailHero(opportunity: {
                let o = Opportunity.preview(
                    title: "Maple Lane porch",
                    contactName: "Tom Liu",
                    stage: .won,
                    estimatedValue: 11_200,
                    daysInStage: 12
                )
                o.source = "referral"
                return o
            }())

            DetailHero(opportunity: {
                let o = Opportunity.preview(
                    title: "Beacon Hill addition",
                    contactName: "Beacon Hill LLC",
                    stage: .lost,
                    estimatedValue: 26_500,
                    daysInStage: 20
                )
                o.source = "web_form"
                return o
            }())
        }
    }
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
